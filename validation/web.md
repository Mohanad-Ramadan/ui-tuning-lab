# Web Validation Receipt

- Status: **PENDING**: automated pilot passed on Chromium and WebKit; Firefox, real Safari, real mobile devices, and a screen reader are not yet tested
- Commit: `ed31122` (skill), package fingerprint `696f02b7321ca66a` from `tools/package.sh`. Earlier runs against `3d23b79` and `b06291f` gave the same results before the baseline fix; this receipt covers `ed31122` only.
- Build/bundle identifier: `pilots/web-vite`, Vite 5.4.11, React 18.3.1, `dist/assets/index-C6CsTkpE.js` (lab in place), `index-E4v3X97q.js` (after landing)
- Browsers/devices: Playwright 1.63.0 Chromium and WebKit 26.6, headless, at 1280×800, 375×812, and 812×375. Firefox: not run (see Limitations). No physical devices.
- Tester: Claude (agent). The lab was built and landed by separate Claude Sonnet 5.5 agents that had only the packaged skill.
- Date: 2026-10-21

## Required checks

- [x] Baseline equivalence; compact and relaxed variants; exact reset. `cross-engine.txt`: "opening leaves the feature at its baseline", "preset changes the real feature", "Reset restores the baseline exactly", and after a close and reopen with the draft kept, "Copy values reports exactly the kept draft" and "Show baseline shows the declared default".
- [ ] Activation paths: `?ui-tuning-lab=1` opens the lab (agent), the visible Tune button opens it (human and fallback), and the Tune button works again after close; the production build ignores the query parameter. **Not run:** added for 1.1.0 after the `ed31122` pilot; the pilot lab predates the default query-parameter path. Re-record the pilot at 1.1.0 before changing the status.
- [x] Copy values copies and logs only changed fields; landing writes them into the feature defaults; removal leaves `source-gates` at N/A. `cross-engine.txt` ("Copy values logs only the changed fields" asserts exactly `{"radius":20}`), `landing.diff`, `landing-checks.txt`.
- [ ] Candidates, Compare, and Done (`references/candidates.md`): Keep as candidate logs `UITUNINGLAB_CANDIDATE` and skips duplicates; Compare renders each candidate and Draft restores the draft; Done logs a `UITUNINGLAB_DONE` line carrying the winner and every candidate; the finish hint is visible. **Not run:** added for 1.2.0.
- N/A: persistence not requested. The pilot lab has no Save or Load saved action; `pilot-lab.diff` contains no `localStorage`, `sessionStorage`, or `indexedDB` call.
- [ ] Desktop/mobile layout, pointer/touch, keyboard, focus, and Close/Escape dismissal; clicking the feature keeps the lab open. **Partly done:** passing in Chromium and WebKit at three viewports (panel fits, Close visible, focus in and back to Tune, keyboard reaches every control, Escape with focus on the page, real click on the feature). Touch on a physical phone and Firefox are not run.
- [ ] Screen-reader behavior and reduced-motion behavior where applicable. **Partly done:** the accessibility tree shows a named dialog, a named control group, labelled sliders, and readouts hidden from assistive technology (`accessibility-tree.txt`). VoiceOver and NVDA were not run. Reduced motion is not applicable: the pilot lab has no motion.
- [x] Conditional unmount removes UI and listeners. `cross-engine.txt` ("Escape closes and unmounts the panel"), `teardown-chromium.txt` (listener sets on window, document, and body unchanged after 3 open/close cycles; 0 lab nodes).
- [x] Production assets contain no lab code, and query, storage, keyboard, and menu activation paths fail. The pilot agent's grep of `dist` for markers and lab labels returned nothing (no source maps emitted); `cross-engine.txt` "[chromium|webkit/production] query, storage, and keyboard activation open nothing".

## Evidence

All files are in `validation/evidence/web/`.

- Static checks: the pilot agent's `source-gates` PASS (exit 0), `npm run build` exit 0, and an empty grep of `dist`; recorded in the final pilot report and reproducible from `pilot-lab.diff` with `scripts/verify.sh`.
- Hands-on: `cross-engine.txt` (116 passed; the 4 failures are Firefox launches), `teardown-chromium.txt`, `accessibility-tree.txt`, `lab-{chromium,webkit}-{desktop,mobile}.png`.
- Landing: `landing.diff` (only `cardDefaults` changed: radius 12→20, gap 8→12, padding untouched) and `landing-checks.txt` (`N/A: supported sources contain no lab references`; grep empty). The build after landing passed and the bundle carries `radius:20,gap:12,padding:16`.
- Commands: `sh tools/package.sh`, `node tests/pilot-web/check.mjs http://localhost:5199 http://localhost:5299` against `vite` and `vite preview`, plus the teardown script recorded in `teardown-chromium.txt`.

## Limitations and result

- **Firefox:** not run. Playwright's Firefox (1.48 and 1.63 builds) fails to start on this macOS 27 machine ("Could not find profile folder" / launch timeout), inside and outside the sandbox.
- **Safari:** WebKit through Playwright is the same engine but not Safari itself; real Safari is not run.
- **Devices and assistive technology:** no physical phone or tablet, no VoiceOver or NVDA session.
- **Pilot scope:** one ephemeral lab with three numeric fields, no motion, no persistence.

PENDING blocks verified status and publication. To finish: run `tests/pilot-web/check.mjs` where Firefox launches, open the pilot lab in Safari on macOS and iOS, and complete one VoiceOver pass over the panel.
