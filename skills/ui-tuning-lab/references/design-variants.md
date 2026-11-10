# Design Variants

Use this when the user asks for alternative designs of a feature ("make three
better versions of this list", "try a card layout and a timeline") rather than
new values for the existing one. The variants are different widget or view
trees, so they cannot be reached by sliders alone, but they still go through
the same lab: the same panel, chips, Duplicate, Apply,
and landing. A row of chips or tabs dropped into the screen is not a lab.

## Where ideas come from

Draft the designs yourself or with a design skill the user named (for example
`ui-ux-pro-max`). The design skill proposes; this skill hosts. Keep the app's
own tokens, fonts, and brand colors: a design skill's generic palette or
landing-page template does not replace them. Each variant must render the
feature's real data and keep its real behavior (taps, toggles, navigation,
accessibility, right-to-left, light and dark).

## Build

1. **The shipped design is the baseline.** The feature's current widget stays exactly as
   it is and is what renders when the lab opens. Its design key is `original`.
2. **Variants live in the lab file.** Each variant is one builder or view in the
   `*.ui-tuning-lab.*` file (or files), named with a kebab-case key such as
   `timeline`, `strip`, `focus`. Production files gain no variant code before
   landing; the host only lets the lab replace the feature's subtree.
3. **The design is a field in each look.** Add `design` (a string, baseline
   `original`) to the lab's configuration, next to any values being tuned. The
   lab renders the variant whose key matches the selected look's `design` in place of the
   feature, and the original otherwise.
4. **The picker lives in the panel.** Put a **Design** picker (segmented
   control or choice chips, one option per key, Shipped first) at the top of
   the panel, per the target picker rule in `references/control-mapping.md`.
   Never put it in the feature's layout: opening the lab changes nothing on
   screen, and the screen must look the same with the lab closed.
5. **Each design gets presets and direct controls.** At least two presets
   across the lab (a preset may set `design` and its values together, such as
   `timeline-compact`), plus the few knobs that matter for each design
   (spacing, radius, emphasis color, row height). Controls that do not apply to
   the selected design are hidden or disabled. Each design's knobs start from
   that design's own defaults, declared next to it in the lab file; the
   original's knobs start from its real defaults, which means lifting its
   constants into state as usual. When the original hard-codes values and the
   user asked only for new designs, leave the shipped design untunable (its knobs
   disabled) rather than editing production code. Copy values reports each
   knob against the selected design's defaults, and landing writes the winning
   design with those defaults plus the changed values.
6. **Everything else is unchanged.** The Shipped chip renders `original`
   with the baseline values; Copy values reports only what differs
   (`{"design":"strip","cardRadius":16}`); a pin records the design in
   `values`, and one started from Shipped is named after it (`strip`); the chips flip the real
   screen between pins of different designs; Apply hands the pick
   over (`references/candidates.md`). A saved profile
   keeps `design` inside `overrides` like any other field, so a persisted or
   seeded candidate reopens on its design.

## Land

1. Take the winner exactly as `references/landing-protocol.md`, step 1 says.
2. If `design` is `original`, land the values only.
3. Otherwise move the winning variant's code out of the lab file into the
   feature's production widget or view (replace its body, or replace the file
   when the user agrees), with the winning values as its defaults. Reuse the
   feature's existing name and call sites, so nothing else in the app changes.
4. Delete the other variants with the lab, unless the user asks to keep them
   for later; then follow "Keeping finalists for later" in
   `references/candidates.md`, and move their source to
   `.ui-tuning-lab/variants/` (outside the app's source tree, so it never
   compiles or ships). A later session copies it back into the lab file
   before seeding those candidates.
5. Show the baseline-to-winner table with `design` as its first row, and list
   the production files changed.

## Report

Name each design in one line (what it is and what it optimises for), then the
usual short **How to try it**, with "pick a design" as the start of its flow
line.
