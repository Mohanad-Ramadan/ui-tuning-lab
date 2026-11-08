# Flutter overlay

The feature and the lab share one `CardStyle` held by the screen's state. The
baseline is the declared default, `CardStyle.appDefault`. All lab code lives in
`feature_screen.ui-tuning-lab.dart`; the host references it only inside
`if (kDebugMode)`, a compile-time constant, so release AOT builds tree-shake it.
The host wraps only the feature, but the pill and panel live in the app's
`Overlay` through an `OverlayPortal`, the declarative form of an
`OverlayEntry`, so they pin to the screen corner even when the feature sits
inside a scroll view. The overlay child is built as part of the host's own
build, so it follows every draft change without `markNeedsBuild` calls. While
the lab is closed it builds only the pill; the panel is not built at all (the
`maintainState: false` behavior). It is not opaque, so the feature outside the
panel stays visible and touchable.

Activation (`references/activation.md`):

- **Agent:** `flutter run --dart-define=UITUNINGLAB_OPEN=true`. The flag is a
  `const bool.fromEnvironment` read inside the lab file and consumed the first
  time the host mounts in this Dart isolate.
- **Human and visible fallback:** a **Card Lab** pill in a free corner. If the app
  has a debug drawer or developer menu, add an entry that calls the same open
  method, and keep the pill.

The host's lab state owns the pins, so pins, `basedOn`, and the stashed draft
survive closing the overlay. The default lab is ephemeral: pins live in memory
and the log only, and a name is never reused within an isolate. The chip row
under the header shows Shipped, each pin, and, last, the draft chip ("Shipped +
edits", "compact + edits"), which appears only while the draft holds unpinned
changes; tapping a chip shows it in the real feature, and the draft is stashed
meanwhile and restored when its chip is tapped or the panel closes. While
Shipped is shown the presets and sliders are disabled; moving one while a pin
is shown copies that pin into the draft first. **Pin** pins the draft and is
disabled while the draft matches Shipped or a pin, **Choose** picks the shown
chip and collapses the panel to the result bar, and the **⋯** menu holds Reset
and Copy values. The hint sits below the scrolling controls.

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

class UITuningLabHost extends StatefulWidget {
  const UITuningLabHost({super.key, required this.style, required this.onChanged, required this.child});
  final CardStyle style;
  final ValueChanged<CardStyle> onChanged;
  final Widget child;
  @override
  State<UITuningLabHost> createState() => _UITuningLabHostState();
}

class _UITuningLabHostState extends State<UITuningLabHost> {
  // Pins the lab opens with. Empty by default; a later session seeds the
  // finalists kept in the project here (references/candidates.md).
  final List<_Candidate> candidates = [];
  // Every name issued, removed ones included, plus the names a pin never takes.
  final Set<String> issued = {'draft', 'now', 'original', 'baseline'};
  final Set<String> logged = {};
  String basedOn = 'baseline';
  String? lastPreset;
  String shown = 'draft'; // the shown chip: "draft", "original" (Shipped), or a pin's name
  CardStyle? stash; // the draft, while another chip is shown
  String? status;
  String? result; // the last pick; while set, the panel is the result bar
  // Hidden means the panel is not built: nothing of it stays in the tree.
  final portal = OverlayPortalController();
  bool isOpen = false;

  CardStyle get draft => widget.style;

  // The chip the draft matches ('original' for Shipped, or a pin), or null while
  // it holds unpinned changes and shows its own chip, last, as "<source> + edits".
  String? get draftMatch {
    final values = _changed(stash ?? draft);
    if (values.isEmpty) return 'original';
    return candidates.where((c) => _sortedJson(c.values) == _sortedJson(values)).firstOrNull?.name;
  }

  // The highlighted chip: the one shown, or the one the draft matches.
  String get current => shown == 'draft' ? draftMatch ?? 'draft' : shown;

  String get draftTitle => '${basedOn == 'baseline' ? 'Shipped' : basedOn} + edits';

  @override
  void initState() {
    super.initState();
    issued.addAll(candidates.map((c) => c.name));
    final requested = uiTuningLabConsumeRequest();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      portal.show(); // the pill; the panel is built only while isOpen
      if (requested) open();
    });
  }

  // The panel is built by this state's build, so setState alone redraws it,
  // and a new widget.style from the parent reaches it the same way.
  void update(VoidCallback change) => setState(change);

  void open() {
    if (isOpen) return;
    for (final c in candidates) { if (logged.add(c.name)) _log('UITUNINGLAB_CANDIDATE', c.toJson()); }
    update(() { isOpen = true; status = null; });
  }

  void close() {
    show('draft');
    update(() => isOpen = false);
  }

  // Tapping a chip shows it in the real feature; the draft is stashed meanwhile.
  // The chip the draft matches shows the draft itself.
  void show(String chip) {
    final target = chip == draftMatch ? 'draft' : chip;
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

  // Every control edits the draft. Moved while a pin is shown, it copies that pin
  // into the draft first; the pin itself does not change. Editing a draft that
  // matches Shipped or a pin starts from that look.
  void edit(CardStyle next, [String? from]) {
    final match = shown == 'draft' ? draftMatch : shown;
    final source = from ?? (match == null ? basedOn : match == 'original' ? 'baseline' : match);
    stash = null;
    widget.onChanged(next);
    update(() { basedOn = source; shown = 'draft'; });
  }

  void applyPreset(String name) { lastPreset = name; edit(_presets[name]!, name); }
  void reset() { lastPreset = null; edit(_baseline, 'baseline'); }

  // Always reports the draft, whichever chip is shown.
  Future<void> copyValues() async {
    final values = _changed(stash ?? draft);
    final json = _sortedJson(values);
    _log('UITUNINGLAB_VALUES', values);
    await Clipboard.setData(ClipboardData(text: json));
    update(() => status = json == '{}' ? 'No changes from Shipped' : 'Copied $json');
  }

  // Returns the new pin, or null with a status. Pin is enabled only while the
  // draft holds unpinned changes. The persist variant writes the pin before
  // calling commit().
  _Candidate? prepareKeep() {
    final values = _changed(stash ?? draft);
    if (values.isEmpty) { update(() => status = 'Same as Shipped'); return null; }
    final same = candidates.where((c) => _sortedJson(c.values) == _sortedJson(values)).firstOrNull;
    if (same != null) { update(() => status = 'Same as ${same.name}'); return null; }
    final stem = lastPreset ?? 'tweak';
    var name = stem;
    for (var i = 2; issued.contains(name); i++) { name = '$stem-$i'; }
    return _Candidate(name, basedOn, values);
  }

  void commit(_Candidate c) {
    issued.add(c.name);
    logged.add(c.name);
    _log('UITUNINGLAB_CANDIDATE', c.toJson());
    update(() { candidates.add(c); status = 'Pinned ${c.name}'; });
  }

  void keep() { final c = prepareKeep(); if (c != null) commit(c); }

  void remove(String name) {
    if (shown == name) show('draft');
    _log('UITUNINGLAB_CANDIDATE_REMOVED', {'name': name});
    update(() => candidates.removeWhere((c) => c.name == name));
  }

  // Choose picks the highlighted chip and finishes. Picking again replaces the
  // result.
  Future<void> useThis() async {
    final chip = current;
    final picked = candidates.where((c) => c.name == chip).firstOrNull;
    final winner = picked?.name ?? (chip == 'original' ? 'original' : 'draft');
    final values = picked?.values ?? (chip == 'original' ? <String, double>{} : _changed(draft));
    final done = <String, Object?>{
      'candidates': [for (final c in candidates) c.toJson()],
      'values': values,
      'winner': winner,
    };
    _log('UITUNINGLAB_DONE', done);
    // The result file needs path_provider; without it the log and the
    // clipboard code carry the pick ("The result file", below).
    await Clipboard.setData(ClipboardData(text: 'land $winner'));
    update(() => result = winner);
  }

  @override
  Widget build(BuildContext context) {
    // The host wraps only the feature; the overlay pins the pill and panel to
    // the screen. TickerMode is off while the screen is an offstage tab
    // (IndexedStack) or a covered route, so the lab hides with it.
    return OverlayPortal(controller: portal, child: widget.child, overlayChildBuilder: (overlayContext) {
      if (!TickerMode.of(overlayContext)) return const SizedBox.shrink();
      if (isOpen) return result == null ? panel(overlayContext) : resultBar(result!);
      return Positioned(right: 16, bottom: 16, child: SafeArea(child: Semantics(
          label: 'Open UI tuning lab', button: true, excludeSemantics: true,
          child: FilledButton(onPressed: open, child: const Text('Card Lab')))));
    });
  }

  Widget resultBar(String name) {
    return Positioned(right: 16, bottom: 16, child: SafeArea(child: Material(
      elevation: 8,
      // The outline keeps the bar distinct when the screen behind it has the
      // same background, where a shadow alone vanishes.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Theme.of(context).colorScheme.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Semantics(liveRegion: true, child: Text('Chosen: $name')),
          TextButton(onPressed: () => update(() => result = null), child: const Text('Change')),
        ]),
      ),
    )));
  }

  Widget slider(String label, double value, double max, bool editable, ValueChanged<double> onChanged) {
    return Row(children: [
      SizedBox(width: 96, child: Text(label)),
      Expanded(child: Slider(value: value, max: max, divisions: max.toInt(), label: label,
          onChanged: editable ? (v) => onChanged(v.roundToDouble()) : null)),
      ExcludeSemantics(child: Text('${value.round()}')),
    ]);
  }

  Widget panel(BuildContext overlayContext) {
    final editable = shown != 'original'; // never edit the baseline
    final size = MediaQuery.sizeOf(overlayContext);
    // Phones: a full-width panel docked to the bottom, at most 45% tall, so the
    // feature stays visible above it. Wider screens: a 320-wide corner panel.
    final compact = size.width < 600;
    return Positioned(
      left: compact ? 0 : null, right: compact ? 0 : 16, bottom: compact ? 0 : 72,
      width: compact ? null : 320,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: compact ? size.height * 0.45 : size.height - 120),
        child: Material(
          elevation: 8,
          // The outline keeps the panel distinct when the screen behind it has
          // the same background, where a shadow alone vanishes. Material takes
          // either borderRadius or shape, never both.
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Theme.of(overlayContext).colorScheme.outline),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Semantics(header: true, child: const Text('UI tuning lab'))),
                PopupMenuButton<String>(
                  tooltip: 'More', icon: const Icon(Icons.more_horiz),
                  onSelected: (choice) { if (choice == 'reset') { reset(); } else { copyValues(); } },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'reset', child: Text('Reset')),
                    PopupMenuItem(value: 'copy', child: Text('Copy values')),
                  ],
                ),
                TextButton(onPressed: close, child: const Text('Close')),
              ]),
              // The chips: Shipped, each pin, then the draft chip while the draft
              // holds unpinned changes. Highlighted = shown.
              Wrap(spacing: 8, runSpacing: 4, children: [
                ChoiceChip(label: const Text('Shipped'), selected: current == 'original',
                    onSelected: (_) => show('original')),
                for (final c in candidates)
                  InputChip(label: Text(c.name), selected: current == c.name,
                      onSelected: (_) => show(c.name),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      deleteButtonTooltipMessage: 'Remove ${c.name}',
                      onDeleted: () => remove(c.name)),
                if (draftMatch == null)
                  ChoiceChip(label: Text(draftTitle), selected: current == 'draft',
                      onSelected: (_) => show('draft')),
              ]),
              Flexible(child: SingleChildScrollView(child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Wrap(spacing: 8, children: [
                  for (final name in _presets.keys)
                    OutlinedButton(onPressed: editable ? () => applyPreset(name) : null,
                        child: Text(name[0].toUpperCase() + name.substring(1))),
                ]),
                slider('Radius', draft.cornerRadius, 32, editable,
                    (v) => edit(draft.copyWith(cornerRadius: v))),
                slider('Spacing', draft.spacing, 24, editable,
                    (v) => edit(draft.copyWith(spacing: v))),
                if (status != null) Semantics(liveRegion: true, child: Text(status!)),
              ]))),
              Wrap(spacing: 8, children: [
                OutlinedButton(onPressed: draftMatch == null ? keep : null, child: const Text('Pin')),
                FilledButton(onPressed: useThis, child: const Text('Choose')),
              ]),
              // Pinned below the controls, visible however long the panel grows.
              const Padding(padding: EdgeInsets.only(top: 8), child: Text('Pin looks to compare · Choose to finish')),
            ]),
          ),
        ),
      ),
    );
  }
}
```

## Design variants, when the user asks for alternative designs

`references/design-variants.md` is the rule; this is the Flutter shape. The
variants are builders in the lab file that take the same real inputs as the
feature, so `feature_screen.dart` does not change beyond the host change above.
For a feature fed by a bloc or provider, give the lab host a `variantInputs`
parameter (the state and callbacks the feature already reads) and build the
variants from it, still inside the host's `kDebugMode` branch.

Changes to `lib/feature_screen.ui-tuning-lab.dart`:

```dart
// Each variant renders the feature's real data with the draft style. The
// original stays the production widget, so it has no entry here. The titles
// below stand in for the feature's real inputs (variantInputs, bloc state).
typedef _DesignBuilder = Widget Function(BuildContext context, CardStyle style);
final Map<String, _DesignBuilder> _designs = {
  'grid': (context, style) => GridView.count(
        crossAxisCount: 2, shrinkWrap: true, padding: const EdgeInsets.all(16),
        mainAxisSpacing: style.spacing, crossAxisSpacing: style.spacing,
        children: [
          for (final title in const ['First card', 'Second card'])
            Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(style.cornerRadius)),
                child: Center(child: Text(title))),
        ]),
};
const _designLabels = {'original': 'Shipped', 'grid': 'Grid'};

// The design joins the values: present only when it differs from 'original'.
Map<String, Object> _changedWith(String design, CardStyle draft) =>
    {if (design != 'original') 'design': design, ..._changed(draft)};
String _designOf(Map<String, Object> v) => v['design'] as String? ?? 'original';
CardStyle _styleOf(Map<String, Object> v) => _apply({
      for (final e in v.entries) if (e.value is num) e.key: (e.value as num).toDouble(),
    });
```

In the host state:

- Add `String design = 'original';` and `String? stashDesign;` beside `stash`.
- `_Candidate.values` becomes `Map<String, Object>`. `prepareKeep` and
  `draftMatch` use `_changedWith(stashDesign ?? design, stash ?? draft)`, and
  `copyValues` reports the draft the same way.
- A pin is named after its design when that is not `original`, so
  `prepareKeep` takes `final stem = design != 'original' ? design : lastPreset ?? 'tweak';`.
- Presets carry a design: `Map<String, ({String design, CardStyle style})>`,
  and `applyPreset` passes both to `edit`.
- Fields that are not numbers (a bool toggle, a string choice) go in the same
  map: `_changed` compares with `!=`, `_sortedJson` already prints them, and
  `_styleOf` reads them back with `v['goldAccent'] as bool?`.
- A variant reads the feature's real state the way the feature does: for a
  bloc, `context.watch<HomeBloc>().state` inside the builder works, since a
  variant renders where the feature did. The panel, in the overlay, inherits
  from the host's location too.
- `reset()` becomes `lastPreset = null; edit(_baseline, from: 'baseline', design: 'original');`.

`show`, `edit`, and `useThis` move the design with the style:

```dart
void show(String chip) {
  final target = chip == draftMatch ? 'draft' : chip;
  if (target == 'draft') {
    if (stash != null) widget.onChanged(stash!);
    design = stashDesign ?? design;
    stash = null;
    stashDesign = null;
  } else {
    stash ??= draft;
    stashDesign ??= design;
    final c = candidates.where((c) => c.name == target).firstOrNull;
    design = c == null ? 'original' : _designOf(c.values);
    widget.onChanged(c == null ? _baseline : _styleOf(c.values));
  }
  update(() => shown = target);
}

// While a pin is shown, design already holds its design, so copying it into
// the draft keeps it unless the control changes the design itself.
void edit(CardStyle next, {String? from, String? design}) {
  final match = shown == 'draft' ? draftMatch : shown;
  final source = from ?? (match == null ? basedOn : match == 'original' ? 'baseline' : match);
  stash = null;
  stashDesign = null;
  if (design != null) this.design = design;
  widget.onChanged(next);
  update(() { basedOn = source; shown = 'draft'; });
}

void applyPreset(String name) {
  final p = _presets[name]!;
  lastPreset = name;
  edit(p.style, from: name, design: p.design);
}

// In useThis(): a pin's values come from the pin itself, never from
// widget.style, which updates only after the parent rebuilds.
final values = picked?.values ??
    (chip == 'original' ? <String, Object>{} : _changedWith(design, draft));
```

The sliders call `edit(draft.copyWith(...))` as before.

- `build` renders the variant in place of the feature:
  `final body = _designs[design]?.call(context, draft) ?? widget.child;` and
  uses `body` where it used `widget.child`.
- The panel's first row under the chips is the Design picker, disabled while
  Shipped is shown like every other control:

```dart
const Text('Design'),
Wrap(spacing: 8, children: [
  for (final key in _designLabels.keys)
    ChoiceChip(label: Text(_designLabels[key]!), selected: design == key,
        onSelected: editable ? (_) => edit(draft, design: key) : null),
]),
```

Landing a design other than `original` moves its builder's body into
`CardFeature.build` with the winning values in `CardStyle.appDefault`, then
removes the lab as usual.

## Reading the lines and waiting for the pick

`debugPrint` lines reach `flutter run` / `flutter logs`, logcat under the
`flutter` tag on Android, and the unified log on the iOS Simulator. Use the
commands in `references/platform-handoff.md`: `adb logcat -d -s flutter:I` and
the Android wait loop with `TAG=flutter`, or the Simulator `log show` command
without the subsystem clause. When the agent started `flutter run` itself with
its output redirected to a file, polling that file with
`grep -m1 UITUNINGLAB_DONE <file>` in the same `until` loop works on every
platform. Logcat truncates a line near 4 KB; a Done line with many pins
can exceed it, so ask the user to press Choose again or read `flutter run`
output.

When the app builds only in CI or a cloud device service and `flutter` is not
installed here, follow "No local toolchain" in `references/platform-handoff.md`:
the lab is the same, the pick reaches the agent as the pasted `land <name>` line, and
the release search runs in the pipeline or is reported as not run.

## Teardown

Close sets `isOpen` to false, which stops building the panel, so nothing of it
stays in the tree; only the pill remains. If the screen goes away, the
`OverlayPortal` leaves the tree with the host and takes the pill and panel with
it. The lab registers no
listeners, timers, or streams. Confirm in Flutter DevTools' widget inspector
that no `UI tuning lab` subtree remains after closing.

Removal at landing: delete `feature_screen.ui-tuning-lab.dart`, its import, and
the `kDebugMode` branch, and point the screen back at
`CardFeature(style: CardStyle.appDefault)`, which now holds the winner.

## The result file, only when the app has `path_provider`

Choose also writes the Done object plus `savedAt` to
`getApplicationSupportDirectory()/.ui-tuning-lab/result.json`, replacing the
last pick atomically. When the app does not depend on `path_provider`, skip
this section; never add the package for it. Add to the lab file:

```dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';

// Temporary file, then rename: a reader never sees half a pick.
Future<void> _uiTuningLabWriteResult(Map<String, Object?> done) async {
  final dir = await Directory('${(await getApplicationSupportDirectory()).path}/.ui-tuning-lab')
      .create(recursive: true);
  final temp = File('${dir.path}/result.json.tmp');
  await temp.writeAsString(
      _sortedJson({...done, 'savedAt': DateTime.now().toUtc().toIso8601String()}), flush: true);
  await temp.rename('${dir.path}/result.json');
}
```

In `useThis()`, right after `_log('UITUNINGLAB_DONE', done)`:
`try { await _uiTuningLabWriteResult(done); } catch (e) { status = 'Result file failed: $e'; }`.
The pick still goes through the log and the clipboard, and the status shows
after Change. Read it with
`adb exec-out run-as <package> cat files/.ui-tuning-lab/result.json` on Android
or the iOS Simulator command in `references/platform-handoff.md`.

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
    await target.delete(); // release the claimed name; the Pin is refused
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

Wiring: `keep()` becomes `Future<void> keep() async { final c = prepareKeep(); if (c == null) return; try { await _uiTuningLabWrite(c, stash ?? draft); commit(c); } catch (e) { update(() => status = 'Pin failed: $e'); } }`,
so a failed write refuses the Pin. In a design-variant lab, write
`{..._asMap(overrides), 'design': design}` as `overrides` and read `design`
back with `_designOf`, so a saved candidate reopens on its design. `remove()` deletes
`<dir>/<name>.json` first and stops with a status on failure. `open()` awaits
`_uiTuningLabReadAll(issued)`, adds found candidates not already listed, shows
the problems in `status`, then logs unlogged candidates. Pull a file with
`adb exec-out run-as <pkg> cat files/.ui-tuning-lab/candidates/tweak.json` (the
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

## Version notes

- Needs Flutter 3.10+ (`OverlayPortal`) and Dart 3 (`firstOrNull`, records in
  the persistence variant).
- If the release search finds lab strings, move the import behind a
  conditional import or a separate debug entry point (`lib/main_debug.dart`).
- A hot restart re-runs `main`, so the lab reopens while the `--dart-define` is
  set; hot reload does not.
- If `debugPrint` lines do not reach the iOS Simulator unified log, read
  `flutter logs`.
