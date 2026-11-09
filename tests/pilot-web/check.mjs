// Hands-on checks for the web pilot lab, run in Chromium, Firefox, and WebKit at
// desktop and mobile sizes, plus production-bundle activation checks.
// Usage: sh run.sh (builds the web example into the pilot and runs this), or
// node check.mjs <dev-url> <preview-url>
import { chromium, firefox, webkit } from "playwright";

const [devUrl, previewUrl] = process.argv.slice(2);
if (!devUrl || !previewUrl) {
  console.error("usage: node check.mjs <dev-url> <preview-url>");
  process.exit(2);
}

const engines = { chromium, firefox, webkit };
const viewports = {
  desktop: { width: 1280, height: 800 },
  mobile: { width: 375, height: 812 },
  landscape: { width: 812, height: 375 },
};
const results = [];
function record(scope, name, passed, detail = "") {
  results.push({ scope, name, passed, detail });
  console.log(`${passed ? "ok" : "not ok"} - [${scope}] ${name}${detail ? `: ${detail}` : ""}`);
}

// Computed card styles: what the user actually sees.
async function cardStyles(page) {
  return page.evaluate(() => {
    // The web example's cards are articles in one grid.
    const card = document.querySelector("article");
    const list = card.parentElement;
    const cs = getComputedStyle(card);
    return {
      radius: cs.borderTopLeftRadius,
      padding: cs.paddingTop,
      gap: getComputedStyle(list).rowGap,
    };
  });
}

async function setRange(page, label, value) {
  await page.getByLabel(label).evaluate((input, v) => {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
    setter.call(input, String(v));
    input.dispatchEvent(new Event("input", { bubbles: true }));
    input.dispatchEvent(new Event("change", { bubbles: true }));
  }, value);
}

const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// Copy values lives in the ⋯ menu, which closes after each action.
async function menuItem(page, name) {
  const item = page.getByRole("button", { name, exact: true });
  if (!(await item.isVisible())) await page.getByRole("button", { name: "More actions" }).click();
  await item.click();
}

async function devChecks(engineName, engine, viewportName) {
  const scope = `${engineName}/${viewportName}`;
  let browser;
  try {
    browser = await engine.launch();
  } catch (error) {
    record(scope, "browser launched", false, String(error).split("\n")[0]);
    return;
  }
  const context = await browser.newContext({ viewport: viewports[viewportName] });
  const page = await context.newPage();
  const logs = [];
  page.on("console", message => logs.push(message.text()));
  try {
    await page.goto(devUrl);
    await page.getByRole("button", { name: "Card Lab" }).waitFor();
    const before = await cardStyles(page);

    await page.getByRole("button", { name: "Card Lab" }).click();
    const dialog = page.getByRole("dialog", { name: /tuning lab/i });
    await dialog.waitFor();
    record(scope, "opening leaves the feature at its baseline", same(before, await cardStyles(page)), JSON.stringify(before));

    const box = await dialog.boundingBox();
    const viewport = viewports[viewportName];
    record(scope, "Close is visible without scrolling the page", await page.getByRole("button", { name: "Close" }).isVisible());
    record(scope, "panel fits inside the viewport",
      box && box.x >= 0 && box.y >= 0 && box.x + box.width <= viewport.width + 1 && box.y + box.height <= viewport.height + 1,
      JSON.stringify(box));

    // The lab moves focus in on the next animation frame.
    const focused = await page.waitForFunction(
      () => !!document.activeElement?.closest("[role=dialog]"), null, { timeout: 2000 },
    ).then(() => true, () => false);
    record(scope, "focus moves into the panel", focused);

    const pressed = async () => page.locator("[aria-label=Looks] button[aria-pressed=true]").allInnerTexts();
    const outline = name => page.getByRole("button", { name, exact: true })
      .evaluate(el => getComputedStyle(el).outlineStyle);
    record(scope, "Shipped starts selected and outlined",
      same(await pressed(), ["Shipped"]) && (await outline("Shipped")) === "solid");

    // An edit on Shipped starts a new pin; Shipped is never edited.
    await page.getByRole("button", { name: "Compact" }).click();
    const compact = await cardStyles(page);
    record(scope, "preset changes the real feature", !same(compact, before), JSON.stringify(compact));
    record(scope, "a preset on Shipped starts a new selected pin",
      same(await pressed(), ["compact"]) && (await outline("Shipped")) === "none");

    await setRange(page, /Radius/, 20);
    record(scope, "radius slider edits the selected pin", (await cardStyles(page)).radius === "20px");
    record(scope, "unpinned edits have no chip of their own",
      (await page.getByRole("button", { name: /\+ edits$/ }).count()) === 0);

    // A real click: it fails if the panel covers the feature.
    await page.locator("article").last().click({ timeout: 3000 });
    record(scope, "clicking the feature keeps the lab open", await dialog.isVisible());

    // Switching chips is the comparison.
    const tuned = await cardStyles(page);
    await page.getByRole("button", { name: "Shipped", exact: true }).click();
    record(scope, "the Shipped chip renders the baseline", same(before, await cardStyles(page)));
    await page.getByRole("button", { name: "compact", exact: true }).click();
    record(scope, "the pin chip renders its look", same(tuned, await cardStyles(page)));

    // Duplicate branches the selected pin; editing the copy leaves the source.
    await page.getByRole("button", { name: "Duplicate" }).click();
    await setRange(page, /Radius/, 6);
    record(scope, "Duplicate selects a new pin", same(await pressed(), ["compact-2"]));
    await page.getByRole("button", { name: "compact", exact: true }).click();
    record(scope, "editing a duplicate leaves its source", same(tuned, await cardStyles(page)));

    // Change exactly one field so an over-reporting Copy cannot pass.
    await page.getByRole("button", { name: "Shipped", exact: true }).click();
    record(scope, "Duplicate is disabled on Shipped",
      await page.getByRole("button", { name: "Duplicate" }).isDisabled());
    await setRange(page, /Gap/, 20);
    logs.length = 0;
    await menuItem(page, "Copy values");
    await page.waitForTimeout(300);
    const line = logs.find(text => text.startsWith("UITUNINGLAB_VALUES "));
    let copied = null;
    try { copied = line && JSON.parse(line.slice("UITUNINGLAB_VALUES ".length)); } catch { /* reported below */ }
    record(scope, "Copy values logs only the changed fields",
      copied !== null && JSON.stringify(copied) === JSON.stringify({ gap: 20 }),
      line ?? "no UITUNINGLAB_VALUES line");

    // Escape must close the lab even when focus is on the page, not the panel.
    await page.evaluate(() => document.activeElement?.blur());
    await page.keyboard.press("Escape");
    await page.waitForTimeout(200);
    record(scope, "Escape closes and unmounts the panel",
      (await page.locator("[role=dialog]").count()) === 0 && (await page.locator("[popover]").count()) === 0);
    record(scope, "focus returns to Card Lab after Escape",
      await page.evaluate(() => document.activeElement?.textContent?.trim() === "Card Lab"));
    record(scope, "closing keeps the selected look", (await cardStyles(page)).gap === "20px");

    // Reopening keeps the pins and the selection; Choose then Change brings the
    // whole panel back.
    await page.getByRole("button", { name: "Card Lab" }).click();
    await dialog.waitFor();
    record(scope, "reopening keeps the pins and the selection",
      same(await pressed(), ["tweak"]) &&
      (await page.locator("[aria-label=Looks] button[aria-pressed]").count()) === 4);
    logs.length = 0;
    await page.getByRole("button", { name: "Choose" }).click();
    await page.waitForTimeout(300);
    const done = logs.find(text => text.startsWith("UITUNINGLAB_DONE "));
    record(scope, "Choose logs the selected chip as winner", !!done && done.includes('"winner":"tweak"'), done ?? "no DONE line");
    await page.getByRole("button", { name: "Change" }).click();
    record(scope, "Change brings back the controls",
      (await dialog.getByRole("slider").count()) === 2 &&
      (await page.getByRole("button", { name: "Duplicate" }).isVisible()));
    await page.getByRole("button", { name: "Close" }).click();
    await page.waitForTimeout(200);

    // Keyboard-only path: every control is reachable by Tab.
    await page.getByRole("button", { name: "Card Lab" }).click();
    await dialog.waitFor();
    const reachable = new Set();
    for (let i = 0; i < 30; i++) {
      await page.keyboard.press("Tab");
      const name = await page.evaluate(() => {
        const el = document.activeElement;
        if (!el || !el.closest("[role=dialog]")) return null;
        return el.getAttribute("aria-label") || el.closest("label")?.textContent?.trim().split(/\s+/)[0] || el.textContent?.trim();
      });
      if (name) reachable.add(name);
    }
    const sliders = await dialog.getByRole("slider").evaluateAll(inputs =>
      inputs.map(input => input.closest("label")?.textContent?.trim().split(/\s+/)[0]));
    const expected = ["Close", "More actions", "Shipped", "Compact", "Relaxed", "Duplicate", "Choose", ...sliders];
    const missing = expected.filter(name => !reachable.has(name));
    record(scope, "keyboard reaches every control", missing.length === 0, missing.length ? `missing ${missing.join(", ")}` : "");
  } catch (error) {
    record(scope, "dev checks completed", false, String(error).split("\n")[0]);
  } finally {
    await browser.close();
  }
}

async function productionChecks(engineName, engine) {
  const scope = `${engineName}/production`;
  let browser;
  try {
    browser = await engine.launch();
  } catch (error) {
    record(scope, "browser launched", false, String(error).split("\n")[0]);
    return;
  }
  const page = await browser.newPage();
  try {
    await page.addInitScript(() => {
      try { localStorage.setItem("uiTuningLab.open", "1"); localStorage.setItem("uiTuningLab.default", "{}"); } catch { /* storage blocked */ }
    });
    await page.goto(`${previewUrl}/?ui-tuning-lab=1&uiTuningLab=1&tune=1`);
    await page.locator("article").first().waitFor();
    await page.keyboard.press("Control+Shift+L");
    await page.keyboard.press("Meta+Shift+L");
    await page.keyboard.press("Escape");
    await page.waitForTimeout(300);
    const tune = await page.getByRole("button", { name: "Card Lab" }).count();
    const dialogs = await page.locator("[role=dialog], [popover]").count();
    record(scope, "query, storage, and keyboard activation open nothing", tune === 0 && dialogs === 0, `tune=${tune} dialogs=${dialogs}`);
  } catch (error) {
    record(scope, "production checks completed", false, String(error).split("\n")[0]);
  } finally {
    await browser.close();
  }
}

for (const [engineName, engine] of Object.entries(engines)) {
  for (const viewportName of Object.keys(viewports)) await devChecks(engineName, engine, viewportName);
  await productionChecks(engineName, engine);
}
const failed = results.filter(result => !result.passed);
console.log(`\n${results.length - failed.length} passed; ${failed.length} failed`);
process.exit(failed.length ? 1 : 0);
