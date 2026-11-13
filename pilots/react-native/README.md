# Card list (React Native pilot)

Typecheck-only fixture. It mirrors `pilots/web-vite`: a list of cards whose corner
radius, gap, and padding come from one declared default, `cardDefaults` in
`src/cards.ts`.

It has no `ios/` or `android/` folders and is never run. The machine that builds this
repo has no CocoaPods, Android SDK, or Java, so a device or simulator build is not
possible. Its job is to give `tests/compile.sh` a React Native type environment to
check `skills/ui-tuning-lab/examples/react-native-overlay.md` against.

    npm install
    npx tsc --noEmit
