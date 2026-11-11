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
  await page.getByRole("slider", { name: label }).evaluate((input, v) => {
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

    const button = name => page.getByRole("button", { name, exact: true });
    const pinButton = () => button("Save & pin");
    const saveButton = () => button("Save");
    const removeCount = () => page.getByRole("button", { name: /^Remove / }).count();
    const enabled = async (...names) => {
      for (const name of names) if (await button(name).isDisabled()) return false;
      return true;
    };
    const disabled = async (...names) => {
      for (const name of names) if (!(await button(name).isDisabled())) return false;
      return true;
    };
    record(scope, "Save & pin is there from the first open and disabled on plain Shipped",
      (await pinButton().isVisible()) && (await pinButton().isDisabled()));
    record(scope, "Undo, Redo, and Reset start disabled", await disabled("Undo", "Redo", "Reset"));
    record(scope, "there is no Duplicate", (await page.getByRole("button", { name: "Duplicate" }).count()) === 0);

    // An edit on Shipped is unsaved: it shows live, no chip is outlined, and no
    // chip appears until Save & pin.
    await button("Compact").click();
    const compact = await cardStyles(page);
    record(scope, "preset changes the real feature", !same(compact, before), JSON.stringify(compact));
    record(scope, "an edit on Shipped outlines no chip and adds none",
      same(await pressed(), []) && (await outline("Shipped")) === "none" &&
      (await page.locator("[aria-label=Looks] button[aria-pressed]").count()) === 1);
    record(scope, "an edit enables Save & pin, Undo, and Reset",
      (await enabled("Save & pin", "Undo", "Reset")) && (await disabled("Redo")));

    // One slider drag is one Undo step.
    for (const value of [10, 14, 20]) await setRange(page, /Radius/, value);
    record(scope, "radius slider edits the shown look", (await cardStyles(page)).radius === "20px");
    record(scope, "unsaved edits have no chip of their own",
      (await page.getByRole("button", { name: /\+ edits$/ }).count()) === 0);
    await button("Undo").click();
    record(scope, "Undo takes back a whole slider drag in one step", same(await cardStyles(page), compact),
      JSON.stringify(await cardStyles(page)));
    await button("Redo").click();
    record(scope, "Redo brings the drag back", (await cardStyles(page)).radius === "20px");
    // Undo and Redo on the keyboard, with focus in the panel.
    await page.getByRole("slider", { name: /Radius/ }).focus();
    await page.keyboard.press("Control+z");
    const undone = (await cardStyles(page)).radius;
    await page.keyboard.press("Control+Shift+z");
    record(scope, "Ctrl-Z and Ctrl-Shift-Z in the panel run Undo and Redo",
      undone === compact.radius && (await cardStyles(page)).radius === "20px", `after Ctrl-Z: ${undone}`);

    // Save & pin keeps the look, named after its preset, and selects it, without a Done line.
    logs.length = 0;
    await pinButton().click();
    await page.waitForTimeout(300);
    record(scope, "Save & pin keeps the look as Compact-1 and selects it", same(await pressed(), ["Compact-1"]));
    record(scope, "Save & pin logs the look, not a Done line before Apply",
      logs.some(text => text.startsWith("UITUNINGLAB_CANDIDATE ") && text.includes('"name":"compact-1"')) &&
      !logs.some(text => text.startsWith("UITUNINGLAB_DONE ")), logs.join(" | "));
    const savedStatus = await page.getByRole("status").allInnerTexts();
    record(scope, "Save & pin says what it pinned and copied",
      savedStatus.some(text => /Pinned Compact-1/.test(text) && /land compact-1/.test(text)), savedStatus.join(" | "));
    record(scope, "on a pinned look the button is Save, disabled with no edits",
      (await pinButton().count()) === 0 && (await saveButton().isDisabled()));
    record(scope, "a save starts a fresh history", await disabled("Undo", "Redo", "Reset"));

    // A real click: it fails if the panel covers the feature.
    await page.locator("article").last().click({ timeout: 3000 });
    record(scope, "clicking the feature keeps the lab open", await dialog.isVisible());

    // Switching chips is the comparison; × shows only on the selected look.
    const tuned = await cardStyles(page);
    record(scope, "× shows on the selected look", (await removeCount()) === 1);
    await button("Shipped").click();
    record(scope, "the Shipped chip renders the baseline", same(before, await cardStyles(page)));
    record(scope, "× is hidden when no look is selected", (await removeCount()) === 0);
    await button("Compact-1").click();
    record(scope, "the look's chip renders its look", same(tuned, await cardStyles(page)));

    // Edits on a pinned look enable Save, Undo, and Reset, and stay with it when
    // the user switches away; switching logs nothing.
    logs.length = 0;
    await setRange(page, /Radius/, 6);
    record(scope, "an edit on a pinned look enables Save, Undo, and Reset", await enabled("Save", "Undo", "Reset"));
    await button("Shipped").click();
    await button("Compact-1").click();
    record(scope, "a pinned look keeps its edits after switching away",
      (await cardStyles(page)).radius === "6px" && same(await pressed(), ["Compact-1"]) && (await enabled("Save")));
    record(scope, "editing and switching log nothing", !logs.some(text => text.startsWith("UITUNINGLAB_")), logs.join(" | "));
    await button("Reset").click();
    record(scope, "Reset goes back to the last save", same(tuned, await cardStyles(page)) && (await disabled("Save", "Reset")));
    await button("Undo").click();
    record(scope, "Undo takes Reset back", (await cardStyles(page)).radius === "6px");
    // ↺ puts one control back to Shipped's value, not the look's last save,
    // as one step that Undo takes back.
    const radiusReset = page.getByRole("button", { name: "Reset Radius to default, 12 px", exact: true });
    const readouts = await page.locator("output").allInnerTexts();
    record(scope, "a changed slider shows ↺ and names the default",
      (await radiusReset.count()) === 1 && readouts.includes("6 px · default 12"), readouts.join(" | "));
    await radiusReset.click();
    const shippedRadius = await cardStyles(page);
    record(scope, "↺ on a pinned look puts the control back to Shipped's value",
      shippedRadius.radius === before.radius && shippedRadius.gap === tuned.gap &&
      (await radiusReset.count()) === 0 && (await enabled("Save")), JSON.stringify(shippedRadius));
    await button("Undo").click();
    record(scope, "Undo takes ↺ back in one step", (await cardStyles(page)).radius === "6px");
    // ↺ goes away once the value is Shipped's, so it hands focus to its slider:
    // the panel's Ctrl-Z still reaches Undo.
    await radiusReset.click();
    const focusedName = await page.evaluate(() =>
      document.activeElement?.closest("[role=dialog]") ? document.activeElement.getAttribute("type") : null);
    await page.keyboard.press("Control+z");
    record(scope, "↺ keeps focus in the panel, on its slider, so Ctrl-Z undoes it",
      focusedName === "range" && (await cardStyles(page)).radius === "6px", `focused: ${focusedName}`);
    // A real drag that ends near the tick lands exactly on Shipped; an arrow
    // key then moves past it.
    const radiusSlider = page.getByRole("slider", { name: /Radius/ });
    const track = await radiusSlider.boundingBox();
    const xAt = value => track.x + 8 + (track.width - 16) * value / 32;
    await page.mouse.move(xAt(20), track.y + track.height / 2);
    await page.mouse.down();
    await page.mouse.move(xAt(12.3), track.y + track.height / 2, { steps: 8 });
    await page.mouse.up();
    record(scope, "a drag that ends near the tick lands exactly on Shipped",
      (await cardStyles(page)).radius === before.radius, JSON.stringify(await cardStyles(page)));
    await radiusSlider.focus();
    await page.keyboard.press("ArrowRight");
    record(scope, "an arrow key moves past the tick without snapping", (await cardStyles(page)).radius === "13px",
      JSON.stringify(await cardStyles(page)));
    await button("Undo").click();
    record(scope, "Undo takes the drag and the arrow back as one run", (await cardStyles(page)).radius === "6px",
      JSON.stringify(await cardStyles(page)));
    await saveButton().click();
    await page.waitForTimeout(300);
    const resaved = await page.getByRole("status").allInnerTexts();
    record(scope, "Save keeps the edits and logs the look",
      resaved.some(text => /Saved Compact-1/.test(text) && /land compact-1/.test(text)) &&
      logs.some(text => text.startsWith("UITUNINGLAB_CANDIDATE ") && text.includes('"radius":6')) &&
      (await saveButton().isDisabled()), `${resaved.join(" | ")} || ${logs.join(" | ")}`);

    // Change exactly one field so an over-reporting Copy cannot pass.
    await button("Shipped").click();
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
    record(scope, "closing keeps the shown look", (await cardStyles(page)).gap === "20px");

    // Reopening keeps the looks and the unsaved edits; Apply pins those edits
    // (no preset, so Custom-1) and hands it over; Change brings the whole panel
    // back without Apply.
    await page.getByRole("button", { name: "Card Lab" }).click();
    await dialog.waitFor();
    record(scope, "reopening keeps the looks and the unsaved edits",
      same(await pressed(), []) &&
      (await page.locator("[aria-label=Looks] button[aria-pressed]").count()) === 2 &&
      (await cardStyles(page)).gap === "20px");
    logs.length = 0;
    await page.getByRole("button", { name: "Apply" }).click();
    await page.waitForTimeout(300);
    const done = logs.find(text => text.startsWith("UITUNINGLAB_DONE "));
    record(scope, "Apply pins unsaved edits as Custom-1 and logs it as winner",
      !!done && done.includes('"winner":"custom-1"') && done.includes('"name":"compact-1"'), done ?? "no DONE line");
    const applied = await page.locator("[role=dialog]").innerText();
    record(scope, "the result bar names the applied look", applied.includes("Applied: Custom-1"), applied);
    await page.getByRole("button", { name: "Change" }).click();
    record(scope, "Change brings back the controls",
      (await dialog.getByRole("slider").count()) === 2 && (await saveButton().isVisible()));
    record(scope, "Apply is hidden after the first Apply",
      (await page.getByRole("button", { name: "Apply", exact: true }).count()) === 0);
    const hint = await page.locator("[role=dialog]").innerText();
    record(scope, "after Apply the hint asks to save and paste", hint.includes("Save, then paste it in chat"), hint);
    // After the first Apply the agent stops listening: Save stays enabled and
    // hands the pick over, and the result bar asks for the land line in chat.
    record(scope, "after Apply Save stays enabled with no edits", !(await saveButton().isDisabled()));
    await saveButton().click();
    await page.waitForTimeout(300);
    // The dialog is named by its title, which is now the result text.
    const bar = await page.locator("[role=dialog]").innerText();
    record(scope, "Save asks to paste the land line in chat",
      /Copied land custom-1: paste it in chat so the agent applies it|Tell the agent: land custom-1/.test(bar), bar);
    record(scope, "the result bar says where the pick was saved",
      bar.includes("Saved Custom-1 in localStorage uiTuningLab.result"), bar);
    await page.getByRole("button", { name: "Change" }).click();
    await page.getByRole("button", { name: "Close" }).click();
    await page.waitForTimeout(200);

    // Keyboard-only path: every control is reachable by Tab.
    await page.getByRole("button", { name: "Card Lab" }).click();
    await dialog.waitFor();
    const reachable = new Set();
    // Forward, then back: headless Firefox does not wrap Tab past the end of
    // the page, so the controls before the first focus are reached with Shift-Tab.
    for (let i = 0; i < 40; i++) {
      await page.keyboard.press(i < 20 ? "Tab" : "Shift+Tab");
      const name = await page.evaluate(() => {
        const el = document.activeElement;
        if (!el || !el.closest("[role=dialog]")) return null;
        return el.getAttribute("aria-label") || el.closest("label")?.textContent?.trim().split(/\s+/)[0] || el.textContent?.trim();
      });
      if (name) reachable.add(name);
    }
    const sliders = await dialog.getByRole("slider").evaluateAll(inputs =>
      inputs.map(input => input.closest("label")?.textContent?.trim().split(/\s+/)[0]));
    // Undo, Redo, and Reset are disabled here (no edits), so Tab skips them.
    const expected = ["Close", "More actions", "Shipped", "Compact-1", "Custom-1", "Remove Custom-1", "Compact", "Relaxed", "Save", ...sliders];
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
