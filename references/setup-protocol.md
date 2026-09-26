# Inspect-First Setup Protocol

Inspect before asking. Read the app entry point, build configuration, feature
configuration model, presentation conventions, persistence layer, and nearby
tests. Record these working choices:

- target: feature unless the request explicitly names the container;
- scope: only the animation, layout, appearance, or visible logic requested;
- container: the existing platform-native transient surface nearest the feature;
- gate: the project's development, DEBUG, internal, or tester mechanism;
- persistence: none unless the user asks to save or reuse profiles;
- profiles: one working draft unless named profiles were requested;
- baseline: a copy of the configuration currently rendered by the feature.

Proceed without an interview when those choices are observable and safe. If one
material ambiguity remains, ask one focused question with concrete options and a
recommended default. Do not batch a questionnaire.

An ephemeral lab can live entirely in development-only state. Create
`.ui-tuning-lab/lab.json` only when the user wants a reusable profile or saved
configuration. A reusable configuration must pass `scripts/verify.sh config`.

Stop only when the development gate cannot be established, the baseline cannot
be captured without changing production data, or the requested persistence would
overwrite a production key. Report the exact blocker and smallest decision needed.
