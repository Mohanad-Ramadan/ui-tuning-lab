# Flutter overlay

The feature and the lab share one `CardStyle` held by the screen's state. The
baseline is the declared default, `CardStyle.appDefault`. All lab code lives in
`feature_screen.ui-tuning-lab.dart`; the host references it only inside
`if (kDebugMode)`, a compile-time constant, so release AOT builds tree-shake it.
The host wraps only the feature, but the pill and panel live in the app's
`Overlay` through an `OverlayPortal`, the declarative form of an
`OverlayEntry`, so they pin to the screen corner even when the feature sits
inside a scroll view. The overlay child is built as part of the host's own
build, so it follows every change to the shown look without `markNeedsBuild`
calls. While the lab is closed it builds only the pill; the panel is not built
at all (the `maintainState: false` behavior). It is not opaque, so the feature outside the
panel stays visible and touchable.

Activation (`references/activation.md`):

- **Agent:** `flutter run --dart-define=UITUNINGLAB_OPEN=true`. The flag is a
  `const bool.fromEnvironment` read inside the lab file and consumed the first
  time the host mounts in this Dart isolate.
- **Human and visible fallback:** a **Card Lab** pill in a free corner. If the app
  has a debug drawer or developer menu, add an entry that calls the same open
  method, and keep the pill.

The host's lab state owns the pins and the selection, so both survive closing
the overlay. The default lab is ephemeral: pins live in memory and the log only,
and a name is never reused within an isolate. The panel follows
`references/candidates.md`. The chip row under the header shows **Shipped** and
each pin; the selected chip is outlined, and the feature always shows it.
Switching chips is the comparison: there is no draft and nothing is stashed.
The presets and sliders edit the selected pin in place; on Shipped, which is
read-only, they start a new pin named after the preset or `tweak`.
**Duplicate** branches the selected pin, **Apply** picks the selected chip and
collapses the panel to the result bar (**Change** restores it), and the **⋯**
menu holds **Copy values** for the selected look. Closing keeps the selected
look in the feature. The hint sits below the scrolling controls.

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
import 'dart:io';
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
// Preset keys are kebab-case: the key is what a pin records as basedOn and is
// named after.
const _presets = {
  'compact': CardStyle(cornerRadius: 4, spacing: 4),
  'relaxed': CardStyle(cornerRadius: 24, spacing: 16),
};

Map<String, double> _asMap(CardStyle s) => {'cornerRadius': s.cornerRadius, 'spacing': s.spacing};
Map<String, double> _changed(CardStyle look) {
  final base = _asMap(_baseline);
  return Map.fromEntries(_asMap(look).entries.where((e) => base[e.key] != e.value));
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

// Hands the pick to the agent's waiter (scripts/wait-for-pick.py) at once, so it
// resumes without a message. Fire and forget: where the app cannot reach the
// host (Android blocks cleartext HTTP by default), the log carries the pick.
Future<void> _sendPick(Object? done) async {
  if (!kDebugMode) return;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client.postUrl(Uri.parse('http://localhost:47321/pick'));
    request.write('UITUNINGLAB_DONE ${_sortedJson(done)}');
    await (await request.close()).drain<void>();
  } catch (_) {
  } finally {
    client.close();
  }
}

// `stem`, or `stem-2`, `stem-3`, ... when taken. Removed names stay in `issued`,
// so a name is never reused in this isolate.
String _nextName(String stem, Set<String> issued) {
  var name = stem;
  for (var i = 2; issued.contains(name); i++) { name = '$stem-$i'; }
  return name;
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
  // The line each pin last logged, so a pin logs again only after it changed.
  final Map<String, String> logged = {};
  // The selected chip: 'original' (Shipped) or a pin's name. The feature always
  // shows it; there is no draft and nothing is stashed.
  String selected = 'original';
  String? status;
  String? result; // the last pick; while set, the panel is the result bar
  // How many times Apply ran. The first reaches the agent's waiter; after it the
  // agent no longer listens, so the button becomes Save and copy and the next pick goes
  // through chat as a pasted `land <name>`. Change does not reset it.
  int applies = 0;
  // The result bar's second line: where Apply saved the pick. Only the
  // path_provider result file below saves one; without it the line stays empty.
  String? saved;
  // Hidden means the panel is not built: nothing of it stays in the tree.
  final portal = OverlayPortalController();
  bool isOpen = false;

  CardStyle get look => widget.style;
  _Candidate? get selectedPin => candidates.where((c) => c.name == selected).firstOrNull;

  // The selected chip is outlined, so it reads as selected without a label.
  BorderSide? outline(bool on) =>
      on ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2) : null;

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

  // Logs a pin's line when it is new or changed since it last logged. The
  // persist variant also writes the pin here.
  void logPin(_Candidate c) {
    final line = _sortedJson(c.toJson());
    if (logged[c.name] == line) return;
    logged[c.name] = line;
    _log('UITUNINGLAB_CANDIDATE', c.toJson());
  }

  // A pin edited in place logs its new values once it is left: another chip is
  // selected, the lab closes, or Apply.
  void leave() {
    final pin = selectedPin;
    if (pin != null) logPin(pin);
  }

  void open() {
    if (isOpen) return;
    for (final c in candidates) { if (!logged.containsKey(c.name)) logPin(c); }
    update(() { isOpen = true; status = null; });
  }

  // Closing keeps the selected look in the feature; reopening keeps the chips.
  void close() {
    leave();
    update(() => isOpen = false);
  }

  // Tapping a chip shows its look in the real feature. Switching chips is the
  // comparison.
  void select(String chip) {
    if (chip == selected) return;
    leave();
    final c = candidates.where((c) => c.name == chip).firstOrNull;
    widget.onChanged(c == null ? _baseline : _apply(c.values));
    update(() => selected = chip);
  }

  // Adds a pin, selects it, and shows it.
  void add(String stem, String basedOn, CardStyle next) {
    leave();
    final name = _nextName(stem, issued);
    final c = _Candidate(name, basedOn, _changed(next));
    issued.add(name);
    logPin(c);
    widget.onChanged(next);
    update(() { candidates.add(c); selected = name; status = 'New look $name'; });
  }

  // Every control edits the selected look. Shipped is read-only, so an edit on it
  // starts a new pin; a pin changes in place.
  void edit(CardStyle next, [String? preset]) {
    final i = candidates.indexWhere((c) => c.name == selected);
    if (i < 0) { add(preset ?? 'tweak', preset ?? 'baseline', next); return; }
    final old = candidates[i];
    widget.onChanged(next);
    update(() => candidates[i] = _Candidate(old.name, preset ?? old.basedOn, _changed(next)));
  }

  void applyPreset(String name) => edit(_presets[name]!, name);

  // Duplicate branches the selected pin, so the two can be compared. It copies
  // the pin's own values, never widget.style, which updates only after the
  // parent rebuilds.
  void duplicate() {
    final pin = selectedPin;
    if (pin == null) return;
    add(pin.name.replaceFirst(RegExp(r'-[0-9]+$'), ''), pin.name, _apply(pin.values));
  }

  // Reports the selected look.
  Future<void> copyValues() async {
    final values = selectedPin?.values ?? <String, double>{};
    final json = _sortedJson(values);
    _log('UITUNINGLAB_VALUES', values);
    await Clipboard.setData(ClipboardData(text: json));
    update(() => status = json == '{}' ? 'Same as Shipped' : 'Copied $json');
  }

  void remove(String name) {
    _log('UITUNINGLAB_CANDIDATE_REMOVED', {'name': name});
    logged.remove(name);
    final wasSelected = selected == name;
    if (wasSelected) widget.onChanged(_baseline);
    update(() {
      candidates.removeWhere((c) => c.name == name);
      if (wasSelected) selected = 'original';
    });
  }

  // Apply picks the selected chip and finishes. Picking again replaces the
  // result.
  Future<void> choose() async {
    leave();
    final pin = selectedPin;
    final winner = pin?.name ?? 'original';
    final done = <String, Object?>{
      'candidates': [for (final c in candidates) c.toJson()],
      'values': pin?.values ?? <String, double>{},
      'winner': winner,
    };
    _log('UITUNINGLAB_DONE', done);
    _sendPick(done).ignore();
    saved = null;
    // The result file needs path_provider; without it the log and the
    // clipboard code carry the pick ("The result file", below).
    await Clipboard.setData(ClipboardData(text: 'land $winner'));
    update(() {
      applies++;
      result = winner;
    });
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
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Semantics(liveRegion: true, child: Text(applies > 1
                ? 'Copied land $name: paste it in chat so the agent applies it'
                : 'Applied: $name')),
            TextButton(onPressed: () => update(() => result = null), child: const Text('Change')),
          ]),
          if ((saved ?? status) != null)
            Padding(padding: const EdgeInsets.only(bottom: 8),
                child: Text((saved ?? status)!, style: Theme.of(context).textTheme.bodySmall)),
        ]),
      ),
    )));
  }

  Widget slider(String label, double value, double max, ValueChanged<double> onChanged) {
    return Row(children: [
      SizedBox(width: 96, child: Text(label)),
      Expanded(child: Slider(value: value, max: max, divisions: max.toInt(), label: label,
          onChanged: (v) => onChanged(v.roundToDouble()))),
      ExcludeSemantics(child: Text('${value.round()}')),
    ]);
  }

  Widget panel(BuildContext overlayContext) {
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
                  tooltip: 'More actions', icon: const Icon(Icons.more_horiz),
                  onSelected: (_) => copyValues(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'copy', child: Text('Copy values')),
                  ],
                ),
                TextButton(onPressed: close, child: const Text('Close')),
              ]),
              // The chips: Shipped, then each pin. The selected chip is outlined.
              Wrap(spacing: 8, runSpacing: 4, children: [
                ChoiceChip(label: const Text('Shipped'), selected: selected == 'original',
                    side: outline(selected == 'original'), showCheckmark: false,
                    onSelected: (_) => select('original')),
                for (final c in candidates)
                  InputChip(label: Text(c.name), selected: selected == c.name,
                      side: outline(selected == c.name), showCheckmark: false,
                      onSelected: (_) => select(c.name),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      deleteButtonTooltipMessage: 'Remove ${c.name}',
                      onDeleted: () => remove(c.name)),
              ]),
              Flexible(child: SingleChildScrollView(child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // Presets are actions, never outlined.
                Wrap(spacing: 8, children: [
                  for (final name in _presets.keys)
                    OutlinedButton(onPressed: () => applyPreset(name),
                        child: Text(name[0].toUpperCase() + name.substring(1))),
                ]),
                slider('Radius', look.cornerRadius, 32,
                    (v) => edit(look.copyWith(cornerRadius: v))),
                slider('Spacing', look.spacing, 24,
                    (v) => edit(look.copyWith(spacing: v))),
                if (status != null) Semantics(liveRegion: true, child: Text(status!)),
              ]))),
              Wrap(spacing: 8, children: [
                OutlinedButton(onPressed: selectedPin == null ? null : duplicate, child: const Text('Duplicate')),
                FilledButton(onPressed: choose, child: Text(applies > 0 ? 'Save and copy' : 'Apply')),
              ]),
              // Pinned below the controls, visible however long the panel grows.
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(applies > 0
                  ? 'Duplicate to compare · Save and copy, then paste it in chat'
                  : 'Duplicate to compare · Apply to finish')),
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
// Each variant renders the feature's real data with the shown style. The
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
Map<String, Object> _changedWith(String design, CardStyle look) =>
    {if (design != 'original') 'design': design, ..._changed(look)};
String _designOf(Map<String, Object> v) => v['design'] as String? ?? 'original';
CardStyle _styleOf(Map<String, Object> v) => _apply({
      for (final e in v.entries) if (e.value is num) e.key: (e.value as num).toDouble(),
    });
```

In the host state:

- Add `String design = 'original';`, the selected look's design.
- `_Candidate.values` becomes `Map<String, Object>`, and `copyValues` and
  `choose` fall back to `<String, Object>{}` for Shipped.
- A new pin is named after its design when that is not `original`, else after
  the preset, else `tweak`.
- Presets carry a design: `Map<String, ({String design, CardStyle style})>`,
  and `applyPreset` passes both to `edit`.
- Fields that are not numbers (a bool toggle, a string choice) go in the same
  map: `_changed` compares with `!=`, `_sortedJson` already prints them, and
  `_styleOf` reads them back with `v['goldAccent'] as bool?`.
- A variant reads the feature's real state the way the feature does: for a
  bloc, `context.watch<HomeBloc>().state` inside the builder works, since a
  variant renders where the feature did. The panel, in the overlay, inherits
  from the host's location too.
- `remove` also sets `design = 'original'` when it removes the selected pin.

`select`, `add`, `edit`, and `duplicate` move the design with the style:

```dart
void select(String chip) {
  if (chip == selected) return;
  leave();
  final c = candidates.where((c) => c.name == chip).firstOrNull;
  widget.onChanged(c == null ? _baseline : _styleOf(c.values));
  update(() { selected = chip; design = c == null ? 'original' : _designOf(c.values); });
}

void add(String stem, String basedOn, CardStyle next, String nextDesign) {
  leave();
  final name = _nextName(stem, issued);
  final c = _Candidate(name, basedOn, _changedWith(nextDesign, next));
  issued.add(name);
  logPin(c);
  widget.onChanged(next);
  update(() { candidates.add(c); selected = name; design = nextDesign; status = 'New look $name'; });
}

// A control that does not change the design keeps the selected look's design.
void edit(CardStyle next, {String? preset, String? design}) {
  final nextDesign = design ?? this.design;
  final i = candidates.indexWhere((c) => c.name == selected);
  if (i < 0) {
    add(nextDesign != 'original' ? nextDesign : preset ?? 'tweak', preset ?? 'baseline', next, nextDesign);
    return;
  }
  final old = candidates[i];
  widget.onChanged(next);
  update(() {
    this.design = nextDesign;
    candidates[i] = _Candidate(old.name, preset ?? old.basedOn, _changedWith(nextDesign, next));
  });
}

void applyPreset(String name) {
  final p = _presets[name]!;
  edit(p.style, preset: name, design: p.design);
}

// The pin's own values, never widget.style, which updates only after the
// parent rebuilds.
void duplicate() {
  final pin = selectedPin;
  if (pin == null) return;
  add(pin.name.replaceFirst(RegExp(r'-[0-9]+$'), ''), pin.name, _styleOf(pin.values), _designOf(pin.values));
}
```

The sliders call `edit(look.copyWith(...))` as before.

- `build` renders the variant in place of the feature:
  `final body = _designs[design]?.call(context, look) ?? widget.child;` and
  uses `body` where it used `widget.child`.
- The panel's first row under the chips is the Design picker. Like every other
  control it is always enabled: on Shipped it starts a new pin named after the
  design.

```dart
const Text('Design'),
Wrap(spacing: 8, children: [
  for (final key in _designLabels.keys)
    ChoiceChip(label: Text(_designLabels[key]!), selected: design == key,
        side: outline(design == key), showCheckmark: false,
        onSelected: (_) => edit(look, design: key)),
]),
```

Landing a design other than `original` moves its builder's body into
`CardFeature.build` with the winning values in `CardStyle.appDefault`, then
removes the lab as usual.

## Reading the lines and waiting for the pick

`debugPrint` lines reach `flutter run` / `flutter logs`, logcat under the
`flutter` tag on Android, and the unified log on the iOS Simulator. Use the
commands in `references/platform-handoff.md`: `adb logcat -d -s flutter:I`, or
the Simulator `log show` command without the subsystem clause. Wait for the
pick with `python3 <skill-dir>/scripts/wait-for-pick.py` in the background and
`--log android` or `--log ios-sim` (`references/platform-handoff.md`, "Wait for
Done"); when the agent started `flutter run` itself with its output redirected
to a file, `--log-file <file>` works on every platform. Logcat truncates a line near 4 KB; a Done line with many pins
can exceed it, so ask the user to press Apply again or read `flutter run`
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

Apply also writes the Done object plus `savedAt` to
`getApplicationSupportDirectory()/.ui-tuning-lab/result.json`, replacing the
last pick atomically. When the app does not depend on `path_provider`, skip
this section; never add the package for it. Add to the lab file:

```dart
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

In `choose()`, right after `_log('UITUNINGLAB_DONE', done)`:
`try { await _uiTuningLabWriteResult(done); saved = 'Saved $winner in .ui-tuning-lab/result.json'; } catch (e) { status = 'Result file failed: $e'; }`.
The pick still goes through the log and the clipboard, and either line shows
under the result bar. Read it with
`adb exec-out run-as <package> cat files/.ui-tuning-lab/result.json` on Android
or the iOS Simulator command in `references/platform-handoff.md`.

## Persistence variant, only when requested

Writes one `schemaVersion: 2` profile per pin to
`getApplicationSupportDirectory()/.ui-tuning-lab/candidates/<name>.json`
when the pin is created and again whenever it logs new values
(`references/platform-handoff.md`). Ask before adding `path_provider` if the
app lacks it. On Android that directory is the app's `files` directory, which
Android Auto Backup includes by default: exclude `.ui-tuning-lab/` in the app's
backup rules (`fullBackupContent` / `dataExtractionRules`), ideally from a
debug-only manifest overlay, or say in the report that lab files may be backed up. Add these functions to the lab file and wire them as described
below; everything else stays the same.

```dart
import 'package:path_provider/path_provider.dart';

Future<Directory> _uiTuningLabDir() async =>
    Directory('${(await getApplicationSupportDirectory()).path}/.ui-tuning-lab/candidates');

// Writes the pin's own file: temporary file, then rename, so a reader never
// sees half a profile. Stored names are reserved, so a new pin never lands on
// another pin's file.
Future<void> _uiTuningLabWrite(_Candidate c) async {
  final dir = await (await _uiTuningLabDir()).create(recursive: true);
  final temp = File('${dir.path}/${c.name}.json.tmp');
  await temp.writeAsString(_sortedJson({
    'basedOn': c.basedOn, 'container': 'FeatureScreen.OverlayPortal', 'name': c.name, 'notes': '',
    'overrides': _asMap(_apply(c.values)), 'platform': 'flutter',
    'savedAt': DateTime.now().toUtc().toIso8601String(), 'schemaVersion': 2,
    'scope': ['appearance', 'layout'],
  }), flush: true);
  await temp.rename('${dir.path}/${c.name}.json');
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

Wiring: `logPin()`, right after its log line, calls
`_uiTuningLabWrite(c).catchError((Object e) { if (mounted) update(() => status = '${c.name} not saved: $e'); });`,
so a pin is written when it is created and whenever it logs new values; a
failed write leaves the pin in the panel. In a design-variant lab, write
`{..._asMap(_styleOf(c.values)), 'design': _designOf(c.values)}` as `overrides` and read `design`
back with `_designOf`, so a saved pin reopens on its design. `remove()` becomes
async, deletes `<dir>/<name>.json` first, and on failure stops with a status and
keeps the chip. `open()` awaits
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
