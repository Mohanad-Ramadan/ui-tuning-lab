# Unvalidated adaptation — Flutter overlay

> **Unvalidated adaptation — not compiled in this repository.** No Flutter or
> Dart toolchain runs here, so none of this code has been analyzed, run, or
> inspected in a release build. Treat it as a starting point and complete the
> full protocol (`references/verify-protocol.md`) in the target app before
> relying on it. Places where an API was assumed rather than checked are listed
> under "Assumptions to validate".

The feature and the lab share one `CardStyle` held by the screen's state. The
baseline is the declared default, `CardStyle.appDefault`. All lab code lives in
`feature_screen.ui-tuning-lab.dart`; the host references it only inside
`if (kDebugMode)`, a compile-time constant, so release AOT builds tree-shake it.
The panel is shown in the app's `Overlay` through an `OverlayPortal`, the
declarative form of an `OverlayEntry`: its child is built as part of the host's
own build, so it follows every draft change without `markNeedsBuild` calls, and
while hidden it is not built at all (the `maintainState: false` behavior). It is
not opaque, so the feature outside the panel stays visible and touchable.

Activation (`references/activation.md`):

- **Agent:** `flutter run --dart-define=UITUNINGLAB_OPEN=true`. The flag is a
  `const bool.fromEnvironment` read inside the lab file and consumed the first
  time the host mounts in this Dart isolate.
- **Human and visible fallback:** a **Tune** pill in a free corner. If the app
  has a debug drawer or developer menu, add an entry that calls the same open
  method, and keep the pill.

The host's lab state owns the candidates store, so candidates, `basedOn`, and
the Compare stash survive closing the overlay. The default lab is ephemeral:
candidates live in memory and the log only, and a name is never reused within an
isolate. Show baseline and Compare share one stash and are exclusive; while
either shows something other than the draft, presets, sliders, Reset, Copy
values, Keep, and Load are disabled. Done is disabled only while Show baseline
is on; while Compare shows a candidate, Done loads it first. Closing restores
the draft. The finish hint sits below the scrolling controls.

## Host change

The feature took `CardStyle.appDefault` directly; it now reads screen state so
the lab can edit it. Undo this at landing (`references/landing-protocol.md`).

`lib/card_feature.dart`

```dart
import 'package:flutter/material.dart';

@immutable
class CardStyle {
  const CardStyle({required this.cornerRadius, required this.spacing});
  final double cornerRadius;
  final double spacing;

  static const appDefault = CardStyle(cornerRadius: 12, spacing: 8);

  CardStyle copyWith({double? cornerRadius, double? spacing}) => CardStyle(
      cornerRadius: cornerRadius ?? this.cornerRadius, spacing: spacing ?? this.spacing);
}

class CardFeature extends StatelessWidget {
  const CardFeature({super.key, required this.style});
  final CardStyle style;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(style.cornerRadius));
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        for (final title in const ['First card', 'Second card']) ...[
          Card(shape: shape, child: ListTile(title: Text(title))),
          SizedBox(height: style.spacing),
        ],
      ]),
    );
  }
}
```

`lib/feature_screen.dart`

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'card_feature.dart';
import 'feature_screen.ui-tuning-lab.dart';

class FeatureScreen extends StatefulWidget {
  const FeatureScreen({super.key});
  @override
  State<FeatureScreen> createState() => _FeatureScreenState();
}

class _FeatureScreenState extends State<FeatureScreen> {
  CardStyle style = CardStyle.appDefault;

  @override
  Widget build(BuildContext context) {
    final feature = CardFeature(style: style);
    // kDebugMode is a const: release builds drop this branch and the lab file.
    if (kDebugMode) {
      return UITuningLabHost(
          style: style, onChanged: (next) => setState(() => style = next), child: feature);
    }
    return feature;
  }
}
```

## Lab code

`lib/feature_screen.ui-tuning-lab.dart`

```dart
// The marker in the file name is what the skill's naming rule requires.
// ignore_for_file: file_names
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'card_feature.dart';

// Agent path: flutter run --dart-define=UITUNINGLAB_OPEN=true. Honored once per
// isolate, so a rebuild, a second screen, or a hot reload does not reopen it.
const bool _uiTuningLabOpenRequested = bool.fromEnvironment('UITUNINGLAB_OPEN');
bool _uiTuningLabLaunchConsumed = false;

bool uiTuningLabConsumeRequest() {
  if (_uiTuningLabLaunchConsumed) return false;
  _uiTuningLabLaunchConsumed = true;
  return _uiTuningLabOpenRequested;
}

// The declared default, never the value on screen when the lab opens.
const _baseline = CardStyle.appDefault;
// Preset keys are kebab-case: the key is what a candidate records as basedOn.
const _presets = {
  'compact': CardStyle(cornerRadius: 4, spacing: 4),
  'relaxed': CardStyle(cornerRadius: 24, spacing: 16),
};

Map<String, double> _asMap(CardStyle s) => {'cornerRadius': s.cornerRadius, 'spacing': s.spacing};
Map<String, double> _changed(CardStyle draft) {
  final base = _asMap(_baseline);
  return Map.fromEntries(_asMap(draft).entries.where((e) => base[e.key] != e.value));
}
CardStyle _apply(Map<String, double> v) => CardStyle(
    cornerRadius: v['cornerRadius'] ?? _baseline.cornerRadius, spacing: v['spacing'] ?? _baseline.spacing);

// JSON with sorted keys and two-decimal rounding; whole numbers print as 12, not 12.0.
String _sortedJson(Object? v) {
  if (v is Map) {
    final keys = v.keys.cast<String>().toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${_sortedJson(v[k])}').join(',')}}';
  }
  if (v is List) return '[${v.map(_sortedJson).join(',')}]';
  if (v is double) {
    final r = (v * 100).round() / 100;
    return r == r.truncateToDouble() ? r.toInt().toString() : r.toString();
  }
  return jsonEncode(v);
}

void _log(String tag, Object? payload) {
  if (kDebugMode) debugPrint('$tag ${_sortedJson(payload)}');
}

class _Candidate {
  const _Candidate(this.name, this.basedOn, this.values);
  final String name;
  final String basedOn;
  final Map<String, double> values;
  Map<String, Object> toJson() => {'basedOn': basedOn, 'name': name, 'values': values};
}

// 1 -> a, 26 -> z, 27 -> aa (bijective base 26).
String _candidateName(int index) {
  var name = '';
  for (var n = index; n > 0; n ~/= 26) {
    n -= 1;
    name = String.fromCharCode(97 + n % 26) + name;
  }
  return name;
}

class UITuningLabHost extends StatefulWidget {
  const UITuningLabHost({super.key, required this.style, required this.onChanged, required this.child});
  final CardStyle style;
  final ValueChanged<CardStyle> onChanged;
  final Widget child;
  @override
  State<UITuningLabHost> createState() => _UITuningLabHostState();
}

class _UITuningLabHostState extends State<UITuningLabHost> {
  // Candidates the lab opens with. Empty by default; a later session seeds the
  // finalists kept in the project here (references/candidates.md).
  final List<_Candidate> candidates = [];
  final Set<String> issued = {}; // every name issued, removed ones included
  final Set<String> logged = {};
  String basedOn = 'baseline';
  String shown = 'draft'; // "draft", "baseline", or a candidate's name
  CardStyle? stash; // the draft while the baseline or a candidate is shown
  String? status;
  // Hidden means the panel is not built: nothing of it stays in the tree.
  final portal = OverlayPortalController();

  CardStyle get draft => widget.style;

  @override
  void initState() {
    super.initState();
    issued.addAll(candidates.map((c) => c.name));
    if (uiTuningLabConsumeRequest()) {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) open(); });
    }
  }

  // The panel is built by this state's build, so setState alone redraws it,
  // and a new widget.style from the parent reaches it the same way.
  void update(VoidCallback change) => setState(change);

  void open() {
    if (portal.isShowing) return;
    for (final c in candidates) { if (logged.add(c.name)) _log('UITUNINGLAB_CANDIDATE', c.toJson()); }
    portal.show();
    update(() => status = null);
  }

  void close() {
    show('draft');
    portal.hide();
    update(() {});
  }

  void show(String target) {
    if (target == 'draft') {
      if (stash != null) widget.onChanged(stash!);
      stash = null;
    } else {
      stash ??= draft;
      final c = candidates.where((c) => c.name == target).firstOrNull;
      widget.onChanged(c == null ? _baseline : _apply(c.values));
    }
    update(() => shown = target);
  }

  void applyPreset(String name) { widget.onChanged(_presets[name]!); update(() => basedOn = name); }
  void reset() { widget.onChanged(_baseline); update(() => basedOn = 'baseline'); }

  Future<void> copyValues() async {
    final json = _sortedJson(_changed(draft));
    _log('UITUNINGLAB_VALUES', _changed(draft));
    await Clipboard.setData(ClipboardData(text: json));
    update(() => status = json == '{}' ? 'No changes from baseline' : 'Copied $json');
  }

  // Returns the new candidate, or null with a status. The persist variant writes
  // the candidate before calling commit().
  _Candidate? prepareKeep() {
    final values = _changed(draft);
    if (values.isEmpty) { update(() => status = 'Matches the baseline; nothing to keep'); return null; }
    final same = candidates.where((c) => _sortedJson(c.values) == _sortedJson(values)).firstOrNull;
    if (same != null) { update(() => status = 'Same as ${same.name}'); return null; }
    var i = 1;
    while (issued.contains(_candidateName(i))) { i++; }
    return _Candidate(_candidateName(i), basedOn, values);
  }

  void commit(_Candidate c) {
    issued.add(c.name);
    logged.add(c.name);
    _log('UITUNINGLAB_CANDIDATE', c.toJson());
    update(() { candidates.add(c); status = 'Kept as ${c.name}'; });
  }

  void keep() { final c = prepareKeep(); if (c != null) commit(c); }

  void load(_Candidate c) {
    stash = null;
    widget.onChanged(_apply(c.values));
    update(() { basedOn = c.name; shown = 'draft'; });
  }

  void remove(String name) {
    _log('UITUNINGLAB_CANDIDATE_REMOVED', {'name': name});
    update(() => candidates.removeWhere((c) => c.name == name));
    if (shown == name) show('draft');
  }

  // Like Copy values, and it tells the agent the session is over. While Compare
  // shows a candidate, that candidate becomes the draft first: it is the winner.
  Future<void> done() async {
    final picked = candidates.where((c) => c.name == shown).firstOrNull;
    if (picked != null) load(picked);
    final values = _changed(picked != null ? _apply(picked.values) : draft);
    final winner = candidates.where((c) => _sortedJson(c.values) == _sortedJson(values)).firstOrNull;
    _log('UITUNINGLAB_DONE', {
      'candidates': [for (final c in candidates) c.toJson()],
      'values': values,
      'winner': winner?.name,
    });
    final json = _sortedJson(values);
    await Clipboard.setData(ClipboardData(text: json));
    update(() => status = 'Done. Copied $json');
  }

  @override
  Widget build(BuildContext context) {
    // Wrap the screen body, not a content-sized widget, so the pill sits in the
    // screen corner inspection found free.
    return OverlayPortal(controller: portal, overlayChildBuilder: panel, child: Stack(fit: StackFit.expand, children: [
      widget.child,
      if (!portal.isShowing)
        Positioned(right: 16, bottom: 16, child: Semantics(
          label: 'Open UI tuning lab', button: true, excludeSemantics: true,
          child: FilledButton(onPressed: open, child: const Text('Tune')))),
    ]));
  }

  Widget slider(String label, double value, double max, bool editing, ValueChanged<double> onChanged) {
    return Row(children: [
      SizedBox(width: 96, child: Text(label)),
      Expanded(child: Slider(value: value, max: max, divisions: max.toInt(), label: label,
          onChanged: editing ? (v) => onChanged(v.roundToDouble()) : null)),
      ExcludeSemantics(child: Text('${value.round()}')),
    ]);
  }

  Widget panel(BuildContext overlayContext) {
    final editing = shown == 'draft';
    return Positioned(
      right: 16, bottom: 72, width: 320,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(overlayContext).height - 120),
        child: Material(
          elevation: 8, borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Flexible(child: SingleChildScrollView(child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Semantics(header: true, child: const Text('UI tuning lab'))),
                  TextButton(onPressed: close, child: const Text('Close')),
                ]),
                SwitchListTile(title: const Text('Show baseline'), value: shown == 'baseline',
                    onChanged: (on) => show(on ? 'baseline' : 'draft')),
                Wrap(spacing: 8, children: [
                  for (final name in _presets.keys)
                    OutlinedButton(onPressed: editing ? () => applyPreset(name) : null,
                        child: Text(name[0].toUpperCase() + name.substring(1))),
                ]),
                slider('Radius', draft.cornerRadius, 32, editing,
                    (v) => widget.onChanged(draft.copyWith(cornerRadius: v))),
                slider('Spacing', draft.spacing, 24, editing,
                    (v) => widget.onChanged(draft.copyWith(spacing: v))),
                Wrap(spacing: 8, children: [
                  TextButton(onPressed: editing ? reset : null, child: const Text('Reset')),
                  TextButton(onPressed: editing ? copyValues : null, child: const Text('Copy values')),
                  TextButton(onPressed: editing ? keep : null, child: const Text('Keep as candidate')),
                ]),
                if (candidates.isNotEmpty) ...[
                  for (final c in candidates)
                    Row(children: [
                      Expanded(child: Text('${c.name} from ${c.basedOn}')),
                      TextButton(onPressed: editing ? () => load(c) : null,
                          child: Text('Load', semanticsLabel: 'Load ${c.name}')),
                      TextButton(onPressed: () => remove(c.name),
                          child: Text('Remove', semanticsLabel: 'Remove ${c.name}')),
                    ]),
                  const Text('Compare'),
                  Wrap(spacing: 8, children: [
                    for (final target in ['draft', ...candidates.map((c) => c.name)])
                      ChoiceChip(label: Text(target == 'draft' ? 'Draft' : target),
                          selected: shown == target, onSelected: (_) => show(target)),
                  ]),
                ],
                FilledButton(onPressed: shown == 'baseline' ? null : done, child: const Text('Done')),
                if (status != null) Semantics(liveRegion: true, child: Text(status!)),
              ]))),
              // Pinned below the scrolling controls, visible however long the panel grows.
              const Padding(padding: EdgeInsets.only(top: 8), child: Text(
                  'Finished? Keep the ones you like, then press Done, or tell the agent "land b".')),
            ]),
          ),
        ),
      ),
    );
  }
}
```

## Reading the lines and waiting for Done

`debugPrint` lines reach `flutter run` / `flutter logs`, logcat under the
`flutter` tag on Android, and the unified log on the iOS Simulator. Use the
commands in `references/platform-handoff.md`: `adb logcat -d -s flutter:I` and
the Android wait loop with `TAG=flutter`, or the Simulator `log show` command
without the subsystem clause. When the agent started `flutter run` itself with
its output redirected to a file, polling that file with
`grep -m1 UITUNINGLAB_DONE <file>` in the same `until` loop works on every
platform. Logcat truncates a line near 4 KB; a Done line with many candidates
can exceed it, so ask the user to press Done again or read `flutter run` output.

## Teardown

Close calls `portal.hide()`, which stops building the panel, so nothing of it
stays in the tree. If the screen goes away with the lab open, the
`OverlayPortal` leaves the tree with the host and takes the panel with it. The lab registers no
listeners, timers, or streams. Confirm in Flutter DevTools' widget inspector
that no `UI tuning lab` subtree remains after closing.

Removal at landing: delete `feature_screen.ui-tuning-lab.dart`, its import, and
the `kDebugMode` branch, and point the screen back at
`CardFeature(style: CardStyle.appDefault)`, which now holds the winner.

## Persistence variant, only when requested

Writes one `schemaVersion: 2` profile per candidate to
`getApplicationSupportDirectory()/.ui-tuning-lab/candidates/<name>.json`
(`references/platform-handoff.md`). Ask before adding `path_provider` if the
app lacks it. On Android that directory is the app's `files` directory, which
Android Auto Backup includes by default: exclude `.ui-tuning-lab/` in the app's
backup rules (`fullBackupContent` / `dataExtractionRules`), ideally from a
debug-only manifest overlay, or say in the report that lab files may be backed up. Add these functions to the lab file and wire them as described
below; everything else stays the same.

```dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<Directory> _uiTuningLabDir() async =>
    Directory('${(await getApplicationSupportDirectory()).path}/.ui-tuning-lab/candidates');

// Never over an existing file. File.rename replaces its target on POSIX, so the
// name is first claimed with an exclusive create, which fails if the file
// exists; the rename then replaces only that empty placeholder.
Future<void> _uiTuningLabWrite(_Candidate c, CardStyle overrides) async {
  final dir = await (await _uiTuningLabDir()).create(recursive: true);
  final target = File('${dir.path}/${c.name}.json');
  try {
    await target.create(exclusive: true);
  } on FileSystemException {
    throw FileSystemException('${c.name} already exists in storage');
  }
  final temp = File('${target.path}.tmp');
  try {
    await temp.writeAsString(_sortedJson({
      'basedOn': c.basedOn, 'container': 'FeatureScreen.OverlayPortal', 'name': c.name, 'notes': '',
      'overrides': _asMap(overrides), 'platform': 'flutter',
      'savedAt': DateTime.now().toUtc().toIso8601String(), 'schemaVersion': 2,
      'scope': ['appearance', 'layout'],
    }), flush: true);
    await temp.rename(target.path);
  } catch (_) {
    await target.delete(); // release the claimed name; the Keep is refused
    rethrow;
  }
}

// Every stored name is reserved, readable or not. Unusable files are reported and left alone.
Future<(List<_Candidate>, List<String>)> _uiTuningLabReadAll(Set<String> reserved) async {
  final dir = await _uiTuningLabDir();
  if (!await dir.exists()) return (<_Candidate>[], <String>[]);
  final found = <(DateTime, _Candidate)>[];
  final problems = <String>[];
  await for (final f in dir.list()) {
    if (f is! File || !f.path.endsWith('.json')) continue;
    final name = f.uri.pathSegments.last.replaceAll('.json', '');
    reserved.add(name);
    try {
      final p = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final o = p['overrides'] as Map<String, dynamic>;
      if (p['schemaVersion'] != 2 || p['platform'] != 'flutter' || p['name'] != name) {
        throw const FormatException('incompatible schema, platform, or name');
      }
      final values = _changed(CardStyle(cornerRadius: (o['cornerRadius'] as num).toDouble(),
          spacing: (o['spacing'] as num).toDouble()));
      if (values.isEmpty) throw const FormatException('matches the baseline');
      // Sort by instant, not by string: "…24Z" and "…24.5Z" do not compare as text.
      final savedAt = DateTime.tryParse(p['savedAt'] as String? ?? '') ?? DateTime.utc(1970);
      found.add((savedAt, _Candidate(name, p['basedOn'] as String? ?? 'baseline', values)));
    } catch (e) {
      problems.add('$name ($e)');
    }
  }
  found.sort((a, b) => a.$1.compareTo(b.$1));
  return ([for (final f in found) f.$2], problems);
}
```

Wiring: `keep()` becomes `final c = prepareKeep(); if (c == null) return; try { await _uiTuningLabWrite(c, draft); commit(c); } catch (e) { update(() => status = 'Keep failed: $e'); }`,
so a failed write refuses the Keep. `remove()` deletes
`<dir>/<name>.json` first and stops with a status on failure. `open()` awaits
`_uiTuningLabReadAll(issued)`, adds found candidates not already listed, shows
the problems in `status`, then logs unlogged candidates. Pull a file with
`adb exec-out run-as <pkg> cat files/.ui-tuning-lab/candidates/b.json` (the
Android support directory) and validate it with
`sh <skill-dir>/scripts/verify.sh profile <file>`.

## Manual gate check

`verify.sh source-gates` does not read Dart and reports `N/A`, which is never a
pass (`references/platform-handoff.md`, "Gates the source linter cannot see"):

1. Every reference to `UITuningLabHost` or the lab file's symbols sits inside
   `if (kDebugMode)`.
2. `flutter build apk --release`, then
   `unzip -p build/app/outputs/flutter-apk/app-release.apk 'lib/*/libapp.so' | grep -acE 'UITuningLab|UITUNINGLAB_|ui-tuning-lab'`
   prints `0`. Release builds made with `--obfuscate` rename identifiers, so
   the string literals (`UITUNINGLAB_`, `UITUNINGLAB_OPEN`, `ui-tuning-lab`)
   are the evidence that matters, not the class marker alone. For iOS,
   `flutter build ios --release` and search `App.framework/App` the same way.
3. A release build made with `--dart-define=UITUNINGLAB_OPEN=true` opens nothing.

## Assumptions to validate

- That the AOT compiler tree-shakes the statically imported lab file when its
  only reference is under `if (kDebugMode)`. The release search above is the
  evidence; if it finds strings, move the import behind a conditional import or
  a separate debug entry point (`lib/main_debug.dart`).
- A hot restart re-runs `main` and resets `_uiTuningLabLaunchConsumed`, so the
  lab reopens while the `--dart-define` is set; hot reload does not.
- `OverlayPortal` (Flutter 3.10+) and a `Positioned` overlay child,
  `Iterable.firstOrNull` (Dart 3), records in the persistence variant (Dart 3),
  and `File.create(exclusive: true)` (Dart 2.19+).
- Whether `debugPrint` output appears in the iOS Simulator unified log for the
  app's Flutter version; `flutter logs` is the fallback.
