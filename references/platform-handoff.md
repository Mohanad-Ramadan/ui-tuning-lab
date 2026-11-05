# Platform Handoff

How each platform emits the lab's log lines, where the agent reads them, how it
waits for Done, and where a persisted lab keeps its candidates. The lines
themselves are the same everywhere (`references/candidates.md`): one tag, a
space, then one sorted-key JSON object, on a single line.

Status follows `references/surface-matrix.md`: Web, iOS, and macOS rows are
candidates exercised by this skill's examples; every other row is an
unvalidated adaptation until a receipt in the target app proves it.

## Emit and read

| Platform | Emit (development builds only) | Agent reads |
|---|---|---|
| Web | `console.info(line)` | the browser console, for example the built-in browser's console messages filtered by `UITUNINGLAB_` |
| iOS, iPadOS, visionOS | `Logger(subsystem: "ui-tuning-lab", category: "values").notice("\(line, privacy: .public)")` | `xcrun simctl spawn booted log show --last 1h --style compact --predicate 'subsystem == "ui-tuning-lab" AND eventMessage CONTAINS "UITUNINGLAB_"'` |
| macOS | the same `Logger` call | `/usr/bin/log show --last 1h --style compact --predicate 'subsystem == "ui-tuning-lab" AND eventMessage CONTAINS "UITUNINGLAB_"'` (a bare `log` is a zsh builtin) |
| Android (Compose, Views) | `Log.i("ui-tuning-lab", line)` inside `if (BuildConfig.DEBUG)` | `adb logcat -d -s ui-tuning-lab:I` |
| Flutter | `debugPrint(line)` inside `if (kDebugMode)` | Android: `adb logcat -d -s flutter:I`; iOS Simulator: `xcrun simctl spawn booted log show --last 1h --style compact --predicate 'eventMessage CONTAINS "UITUNINGLAB_"'`; or the `flutter run` / `flutter logs` output |
| React Native | `console.info(line)` inside `if (__DEV__)` | Android: `adb logcat -d -s ReactNativeJS:I`; iOS Simulator: the Simulator `log show` command above without the subsystem clause; or React Native DevTools' console |
| Windows (WinUI 3, WPF) | `System.Diagnostics.Debug.WriteLine(line)` inside `#if DEBUG` | the Visual Studio Output window, or Sysinternals DebugView logging to a file (`Dbgview.exe /accepteula /l <file>`), read with `Select-String UITUNINGLAB_ <file>` |
| Linux, HarmonyOS | the platform's debug logger with a `ui-tuning-lab` tag, or stderr | the matching log reader (`journalctl`, `hdc hilog`) filtered by `UITUNINGLAB_` |

Read with a window that covers the whole session. `adb logcat -d` dumps the
current buffer and exits; a busy device can rotate the buffer, so read soon
after Done, or ask the user to press Done again. Logcat also cuts a line at
about 4 KB, so a Done line with many candidates can arrive truncated: rebuild
the list from the `UITUNINGLAB_CANDIDATE` lines instead, which each lab logs as
candidates are kept, loaded, or seeded.

## Wait for Done

Poll a dump; never pipe a live stream (`log stream`, `adb logcat` without
`-d`) into `grep -m1`, because the stream keeps the pipeline alive after grep
exits. Start the wait right after opening the lab, in the background, and stop
it when the user writes first.

```sh
# Android, React Native on Android, Flutter on Android: set TAG to
# ui-tuning-lab, ReactNativeJS, or flutter.
# adb shell joins its arguments unquoted, so quote the whole remote command.
start=$(adb shell "date '+%m-%d %H:%M:%S.000'" | tr -d '\r')
[ -n "$start" ] || { echo "could not read the device clock" >&2; exit 1; }
until line=$(adb logcat -d -T "$start" -s "$TAG:I" | grep -m1 UITUNINGLAB_DONE); do sleep 3; done
printf '%s\n' "$line"
```

```sh
# macOS. For the iOS Simulator, replace `/usr/bin/log show` with
# `xcrun simctl spawn booted log show` (and drop the subsystem clause for
# Flutter and React Native).
start=$(date '+%Y-%m-%d %H:%M:%S')
until line=$(/usr/bin/log show --start "$start" --style compact \
    --predicate 'subsystem == "ui-tuning-lab" AND eventMessage CONTAINS "UITUNINGLAB_DONE"' |
    grep -m1 UITUNINGLAB_DONE); do sleep 3; done
printf '%s\n' "$line"
```

Windows with DebugView logging to a file: record the file's line count when the
lab opens, then poll for a Done line after it, so a log left from an earlier
session cannot answer:

```powershell
$start = (Get-Content $log).Count
do { Start-Sleep 3; $line = Select-String -Path $log -Pattern UITUNINGLAB_DONE |
  Where-Object LineNumber -gt $start | Select-Object -First 1 } until ($line)
$line.Line
``` The
web has nothing to poll from outside the browser: read the console when the
user next writes.

## Where persisted candidates live

Only when persistence was requested. One `schemaVersion: 2` profile per
candidate, written atomically (temporary file, then rename) and never over an
existing entry (`references/candidates.md`, "Persistence").

| Platform | `platform` value | Location |
|---|---|---|
| Web | `web` | `localStorage` key `uiTuningLab.candidates.<name>` |
| iOS, iPadOS | `ios` | Application Support `.ui-tuning-lab/candidates/<name>.json` in the app container |
| visionOS | `visionos` | as iOS |
| macOS | `macos` | Application Support `<bundle-id>/.ui-tuning-lab/candidates/<name>.json` |
| Android | `android` | `context.noBackupFilesDir/.ui-tuning-lab/candidates/<name>.json`, so device backup never copies lab data |
| Flutter | `flutter` | `getApplicationSupportDirectory()` (`path_provider`) `/.ui-tuning-lab/candidates/<name>.json`; ask before adding `path_provider` if the app lacks it. On Android this maps to `files/`, which Auto Backup includes |
| React Native | `react-native` | `@react-native-async-storage/async-storage` key `uiTuningLab.candidates.<name>`, only when the app already depends on it; otherwise ask, and never add a native module for the lab alone |
| Windows | `windows` | packaged: `ApplicationData.Current.LocalFolder\.ui-tuning-lab\candidates\<name>.json`; unpackaged: `%LOCALAPPDATA%\<app-name>\.ui-tuning-lab\candidates\<name>.json` |
| Linux | `linux` | `$XDG_DATA_HOME/<app-name>/.ui-tuning-lab/candidates/<name>.json` |
| HarmonyOS | `harmonyos` | the ability context's `filesDir/.ui-tuning-lab/candidates/<name>.json` |

A Flutter or React Native candidate uses the framework value, not the device's
OS, so a candidate kept on an Android device loads on iOS too. Order loaded
candidates by parsing `savedAt` to an instant, never by comparing the strings:
Kotlin and Dart print a varying number of fractional digits.

## Gates the source linter cannot see

`verify.sh source-gates` reads Swift and JavaScript or TypeScript only (React
Native included: it accepts `require()` inside `if (__DEV__) {`, never
`import()`, and fails a file that defines `__DEV__`). A PASS is lint, not
validation. For Kotlin, Dart, C#, and other languages it reports `N/A`, which
is never a pass: check those gates by hand and record the evidence in the
report.

Release searches look for the log tag and the subsystem string, not only the
class marker: R8, Metro minification, Hermes, and Flutter `--obfuscate` rename
identifiers, but string literals survive. Search every artifact for
`UITUNINGLAB_`, `ui-tuning-lab`, and `UITuningLab`, and fail the check when no
artifact file was found to search.

| Platform | Gate | Manual check |
|---|---|---|
| Android | lab files in `src/debug/` (preferred), or `BuildConfig.DEBUG` | the release variant cannot compile `src/debug/`; otherwise every reference sits inside `if (BuildConfig.DEBUG)`. `./gradlew assembleRelease`, then search every `classes*.dex` in the APK (`unzip -p app-release.apk 'classes*.dex' \| strings`) for the three strings |
| Flutter | `kDebugMode` | every lab reference sits inside `if (kDebugMode)`; `flutter build apk --release` (or `ios --release`), then search `libapp.so` (or the iOS `App.framework`) with `strings` for the three strings |
| React Native | `__DEV__` | run `source-gates` on the host; then `npx react-native bundle --entry-file index.js --platform android --dev false --minify true --bundle-output /tmp/release.bundle` and search it for the three strings |
| Windows | `#if DEBUG` | every lab file is wrapped in `#if DEBUG`; build Release, then `Get-ChildItem bin -Recurse -Filter <App>.dll` piped to `Select-String -SimpleMatch` for the three strings, once more with `-Encoding Unicode` for UTF-16 literals |
