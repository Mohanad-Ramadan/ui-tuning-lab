# Android — Jetpack Compose panel

The feature and the lab share one `CardStyle` held by the screen. The baseline is
the declared default, `CardStyle.appDefault`, never the value on screen when the
lab opens. All lab code lives in the `debug` source set (`app/src/debug/`), which
the release variant cannot compile; main code reaches it through one call,
`TuningLabHost(...)`, which a pass-through file in `app/src/release/` satisfies
for Release. The panel is a non-modal `Surface` overlaid in a screen-level `Box`
and anchored to a corner, composed only while open: touches outside it reach
the feature, so the feature stays usable while the lab is open, and closing
removes the panel from composition. A `ModalBottomSheet` is not used because
its scrim captures every touch outside the sheet.

Activation (`references/activation.md`):

- **Agent:** the boolean intent extra `UITuningLabOpen`, consumed the first time
  the screen composes in this process, so recreation does not reopen the lab.
- **Human and visible fallback:** a **Card Lab** pill pinned to a free corner of the
  screen. If the app has a developer menu or drawer, add a menu entry that sets
  the same `showUITuningLab` state, and keep the pill.

The host owns the `UITuningLabCandidates` store, so pins, `basedOn`, and the
selection survive closing the panel. The default lab is ephemeral: pins live in
memory and in logcat only, and a name is never reused within a process. The
panel follows `references/candidates.md`. The chip row under the header shows
**Shipped** and each pin; the selected chip is outlined, and the feature always
shows it. Switching chips is the comparison: there is no draft and nothing is
stashed. Moving a slider or applying a preset edits the selected pin in place;
on Shipped, which is read-only, it starts a new pin named after the preset or
`tweak` and selects it. **Duplicate** branches the selected pin (it is disabled
on Shipped), **Choose** picks the selected chip and shrinks the panel to the
result bar, and the **⋯** menu holds Copy values. Closing keeps the selected
look on screen. The panel's height is capped and the hint sits below the
scrolling controls, so it is visible at any panel or screen size.

## Host change (main source set)

The feature took `CardStyle.appDefault` directly; it now reads screen state so
the lab can edit it. This is the only production-side change, and it is undone
at landing (`references/landing-protocol.md`, step 3).

`app/src/main/java/com/example/cards/CardFeature.kt`

```kotlin
package com.example.cards

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

data class CardStyle(val cornerRadius: Int, val spacing: Int) {
    companion object {
        val appDefault = CardStyle(cornerRadius = 12, spacing = 8)
    }
}

@Composable
fun CardFeature(style: CardStyle, modifier: Modifier = Modifier) {
    Column(modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(style.spacing.dp)) {
        for (title in listOf("First card", "Second card")) {
            Surface(shape = RoundedCornerShape(style.cornerRadius.dp), tonalElevation = 2.dp,
                modifier = Modifier.fillMaxWidth()) {
                Text(title, Modifier.padding(16.dp))
            }
        }
    }
}
```

`app/src/main/java/com/example/cards/FeatureScreen.kt`

```kotlin
package com.example.cards

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue

@Composable
fun FeatureScreen() {
    var style by remember { mutableStateOf(CardStyle.appDefault) }
    // The one main-source hook. Debug resolves it to the lab in src/debug/;
    // Release resolves it to the pass-through in src/release/.
    TuningLabHost(style = style, onStyleChange = { style = it }) { CardFeature(it) }
}
```

`app/src/release/java/com/example/cards/TuningLabHost.kt`

```kotlin
package com.example.cards

import androidx.compose.runtime.Composable

// Release pass-through: no lab code, strings, or intent handling. Like the web
// example's TuningLabHost, it is deliberately unmarked so a Release search for
// UITuningLab stays clean. Every non-debug build type needs this file (or a
// shared source directory holding it).
@Composable
fun TuningLabHost(
    style: CardStyle,
    onStyleChange: (CardStyle) -> Unit,
    content: @Composable (CardStyle) -> Unit,
) = content(style)
```

## Lab code (debug source set only)

`app/src/debug/java/com/example/cards/UITuningLabHost.kt`

```kotlin
package com.example.cards

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

// The agent path: `adb shell am start -S -n <pkg>/<activity> --ez UITuningLabOpen true`.
// Honored once per process: the flag stops recreation or a second screen from
// reopening the lab, and the extra is removed from the intent.
object UITuningLabLaunch {
    private var handled = false

    fun consumeRequest(activity: Activity?): Boolean {
        if (handled || activity == null) return false
        handled = true
        val requested = activity.intent.getBooleanExtra("UITuningLabOpen", false)
        activity.intent.removeExtra("UITuningLabOpen")
        return requested
    }
}

private tailrec fun Context.uiTuningLabActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.uiTuningLabActivity()
    else -> null
}

// Debug half of the main-source hook. Same signature as the release pass-through.
@Composable
fun TuningLabHost(
    style: CardStyle,
    onStyleChange: (CardStyle) -> Unit,
    content: @Composable (CardStyle) -> Unit,
) {
    val activity = LocalContext.current.uiTuningLabActivity()
    // Candidates the lab opens with. Empty by default; a later session seeds the
    // finalists kept in the project here (references/candidates.md).
    val lab = remember { UITuningLabCandidates(initial = emptyList()) }
    var showUITuningLab by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { if (UITuningLabLaunch.consumeRequest(activity)) showUITuningLab = true }

    // fillMaxSize pins the pill to the screen corner; call the hook at screen
    // level so it does not change the feature's own layout.
    Box(Modifier.fillMaxSize()) {
        content(style)
        // The visible fallback. Pick the corner inspection found free.
        if (!showUITuningLab) {
            Button(onClick = { showUITuningLab = true },
                modifier = Modifier.align(Alignment.BottomEnd).padding(16.dp)
                    .semantics { contentDescription = "Open UI tuning lab" }) { Text("Card Lab") }
        }
        if (showUITuningLab) {
            // Closing keeps the selected look on screen: it is real state, so
            // there is nothing to restore. An edited pin logs its new values.
            UITuningLabPanel(style = style, setStyle = onStyleChange, lab = lab,
                modifier = Modifier.align(Alignment.BottomEnd), onClose = {
                    lab.leave()
                    showUITuningLab = false
                })
        }
    }
}
```

`app/src/debug/java/com/example/cards/UITuningLabCandidates.kt`

```kotlin
package com.example.cards

import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.time.Instant

// The declared default, never the value on screen when the lab opens.
private val baseline = CardStyle.appDefault

// Preset keys are kebab-case: the key is what a candidate records as basedOn.
val uiTuningLabPresets = linkedMapOf(
    "compact" to CardStyle(cornerRadius = 4, spacing = 4),
    "relaxed" to CardStyle(cornerRadius = 24, spacing = 16),
)

fun CardStyle.uiTuningLabMap(): Map<String, Any> =
    mapOf("cornerRadius" to cornerRadius, "spacing" to spacing)

// The fields of a look that differ from the baseline.
fun uiTuningLabChanged(look: CardStyle): Map<String, Any> {
    val base = baseline.uiTuningLabMap()
    return look.uiTuningLabMap().filter { (key, value) -> base[key] != value }
}

fun uiTuningLabApply(values: Map<String, Any>) = CardStyle(
    cornerRadius = values["cornerRadius"] as? Int ?: baseline.cornerRadius,
    spacing = values["spacing"] as? Int ?: baseline.spacing,
)

// JSON with sorted keys and two-decimal rounding, so every line has one shape.
fun uiTuningLabJson(value: Any?): String = when (value) {
    null -> "null"
    is Map<*, *> -> value.entries.sortedBy { it.key as String }
        .joinToString(",", "{", "}") { "${JSONObject.quote(it.key as String)}:${uiTuningLabJson(it.value)}" }
    is List<*> -> value.joinToString(",", "[", "]") { uiTuningLabJson(it) }
    is String -> JSONObject.quote(value)
    is Double -> (Math.round(value * 100) / 100.0)
        .let { if (it % 1.0 == 0.0) it.toLong().toString() else it.toString() }
    else -> value.toString()
}

fun uiTuningLabLog(tag: String, json: String) {
    if (BuildConfig.DEBUG) Log.i("ui-tuning-lab", "$tag $json")
}

class UITuningLabCandidate(val name: String, val basedOn: String, val values: Map<String, Any>) {
    fun asMap() = mapOf("basedOn" to basedOn, "name" to name, "values" to values)
}

// Temporary file, then rename over the last pick: a reader never sees half a file.
private fun writeResult(file: File, done: Map<String, Any>) {
    val dir = file.parentFile ?: throw IOException("no directory for $file")
    if (!dir.isDirectory && !dir.mkdirs()) throw IOException("cannot create $dir")
    val temp = File(dir, "result.json.tmp")
    temp.writeText(uiTuningLabJson(done + ("savedAt" to Instant.now().toString())))
    if (!temp.renameTo(file)) { temp.delete(); throw IOException("cannot replace $file") }
}

class UITuningLabCandidates(initial: List<UITuningLabCandidate>) {
    val list = mutableStateListOf<UITuningLabCandidate>().apply { addAll(initial) }
    // Every name issued in this process, removed ones included, plus the names a
    // pin never takes. The persist variant adds every stored name.
    internal val issued = (initial.map { it.name } + listOf("draft", "now", "original", "baseline")).toMutableSet()
    // The line each pin last logged, so a pin logs again only after it changed.
    private val logged = mutableMapOf<String, String>()
    // The selected chip: "original" (Shipped) or a pin's name. The feature always
    // shows it; there is no draft and nothing is stashed.
    var selected by mutableStateOf("original")
    var status by mutableStateOf<String?>(null)
    // The last pick; while set, the panel is the result bar.
    var result by mutableStateOf<String?>(null)
    // The persist variant sets these; the default lab writes only the result file.
    var store: ((UITuningLabCandidate) -> Unit)? = null
    var unstore: ((String) -> Unit)? = null

    val selectedPin: UITuningLabCandidate? get() = list.firstOrNull { it.name == selected }

    // Logs a pin's line when it is new or changed since it last logged, and
    // stores it in the persist variant. A failed write shows in the status line;
    // the pin stays in the panel.
    private fun log(candidate: UITuningLabCandidate, storing: Boolean = true) {
        val line = uiTuningLabJson(candidate.asMap())
        if (logged[candidate.name] == line) return
        logged[candidate.name] = line
        uiTuningLabLog("UITUNINGLAB_CANDIDATE", line)
        if (!storing) return
        try { store?.invoke(candidate) } catch (e: Exception) { status = "${candidate.name} not saved: ${e.message}" }
    }

    // Seeded or stored pins log their own line the first time the lab shows them.
    fun logUnlogged() {
        for (c in list.toList()) if (c.name !in logged) log(c, storing = false)
    }

    // A pin edited in place logs its new values once it is left: another chip is
    // selected, the lab closes, or Choose.
    fun leave() { selectedPin?.let { log(it) } }

    // Tapping a chip shows its look in the real feature. Switching chips is the
    // comparison.
    fun select(chip: String, setStyle: (CardStyle) -> Unit) {
        if (chip == selected) return
        leave()
        val pin = list.firstOrNull { it.name == chip }
        setStyle(if (pin == null) baseline else uiTuningLabApply(pin.values))
        selected = chip
    }

    // Adds a pin, selects it, and shows it. `stem`, or `stem-2`, `stem-3`, ...
    // when taken.
    private fun add(stem: String, basedOn: String, look: CardStyle, setStyle: (CardStyle) -> Unit) {
        leave()
        val name = generateSequence(1) { it + 1 }.map { if (it == 1) stem else "$stem-$it" }.first { it !in issued }
        val candidate = UITuningLabCandidate(name, basedOn, uiTuningLabChanged(look))
        issued.add(name)
        list.add(candidate)
        status = "New look $name"
        log(candidate)
        setStyle(look)
        selected = name
    }

    // Every control edits the selected look. Shipped is read-only, so an edit on
    // it starts a new pin; a pin changes in place, and a preset becomes its basedOn.
    fun edit(next: CardStyle, setStyle: (CardStyle) -> Unit, preset: String? = null) {
        val index = list.indexOfFirst { it.name == selected }
        if (index < 0) { add(preset ?: "tweak", preset ?: "baseline", next, setStyle); return }
        val pin = list[index]
        list[index] = UITuningLabCandidate(pin.name, preset ?: pin.basedOn, uiTuningLabChanged(next))
        setStyle(next)
    }

    fun applyPreset(name: String, setStyle: (CardStyle) -> Unit) =
        edit(uiTuningLabPresets.getValue(name), setStyle, name)

    // Duplicate branches the selected pin, so the two can be compared.
    fun duplicate(setStyle: (CardStyle) -> Unit) {
        val pin = selectedPin ?: return
        add(pin.name.replace(Regex("-[0-9]+$"), ""), pin.name, uiTuningLabApply(pin.values), setStyle)
    }

    // Reports the selected look: {} for Shipped.
    fun copyValues(): String {
        val json = uiTuningLabJson(selectedPin?.values ?: emptyMap<String, Any>())
        uiTuningLabLog("UITUNINGLAB_VALUES", json)
        status = if (json == "{}") "Same as Shipped" else "Copied $json"
        return json
    }

    // Removing the selected pin selects Shipped.
    fun remove(name: String, setStyle: (CardStyle) -> Unit) {
        try { unstore?.invoke(name) } catch (e: Exception) { status = "$name not removed: ${e.message}"; return }
        list.removeAll { it.name == name }
        logged.remove(name)
        uiTuningLabLog("UITUNINGLAB_CANDIDATE_REMOVED", uiTuningLabJson(mapOf("name" to name)))
        if (selected == name) { selected = "original"; setStyle(baseline) }
    }

    // Choose picks the selected chip ("original" for Shipped) and finishes;
    // returns the code for the clipboard. Picking again replaces the result: the
    // newest pick wins.
    fun choose(resultFile: File): String {
        leave()
        val pin = selectedPin
        val winner = pin?.name ?: "original"
        val values = pin?.values ?: emptyMap<String, Any>()
        val done = mapOf("candidates" to list.map { it.asMap() }, "values" to values, "winner" to winner)
        val line = uiTuningLabJson(done)
        // Logcat cuts entries near 4 KB. When the Done line may be cut, repeat each
        // pin on its own line first, so the agent can rebuild the list.
        if (line.length > 3500) list.forEach { uiTuningLabLog("UITUNINGLAB_CANDIDATE", uiTuningLabJson(it.asMap())) }
        uiTuningLabLog("UITUNINGLAB_DONE", line)
        status = try { writeResult(resultFile, done); null } catch (e: Exception) { "Result file failed: ${e.message}" }
        result = winner
        return "land $winner"
    }
}
```

`app/src/debug/java/com/example/cards/UITuningLabPanel.kt`

```kotlin
package com.example.cards

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp
import java.io.File
import kotlin.math.roundToInt

// A non-modal panel: it consumes touches only inside its own bounds, so the
// feature around it stays usable. Composed only while the lab is open.
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UITuningLabPanel(
    style: CardStyle,
    setStyle: (CardStyle) -> Unit,
    lab: UITuningLabCandidates,
    modifier: Modifier = Modifier,
    onClose: () -> Unit,
) {
    val clipboard = LocalClipboardManager.current
    val resultFile = File(LocalContext.current.noBackupFilesDir, ".ui-tuning-lab/result.json")
    val maxHeight = (LocalConfiguration.current.screenHeightDp * 0.6f).dp
    var menuOpen by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { lab.logUnlogged() }
    // System back closes the lab first, like Escape on the web.
    BackHandler(onBack = onClose)

    // After Choose the panel is one bar; Change restores the whole panel.
    lab.result?.let { name ->
        Surface(modifier.padding(16.dp), shape = MaterialTheme.shapes.extraLarge,
            tonalElevation = 3.dp, shadowElevation = 8.dp,
            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)) {
            Row(Modifier.padding(start = 16.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Chosen: $name", Modifier.semantics { liveRegion = LiveRegionMode.Polite })
                TextButton(onClick = { lab.result = null }) { Text("Change") }
            }
        }
        return
    }

    // The outline keeps the panel distinct when the screen behind it has the
    // same background, where a shadow alone vanishes.
    Surface(modifier.padding(16.dp).widthIn(max = 360.dp).heightIn(max = maxHeight),
        shape = MaterialTheme.shapes.large, tonalElevation = 3.dp, shadowElevation = 8.dp,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)) {
        Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("UI tuning lab", style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f).semantics { heading() })
                Box {
                    IconButton(onClick = { menuOpen = true },
                        modifier = Modifier.semantics { contentDescription = "More" }) {
                        Text("⋯", Modifier.clearAndSetSemantics { })
                    }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        DropdownMenuItem(text = { Text("Copy values") }, onClick = {
                            menuOpen = false
                            clipboard.setText(AnnotatedString(lab.copyValues()))
                        })
                    }
                }
                TextButton(onClick = onClose) { Text("Close") }
            }
            // The chips: Shipped, then each pin. The selected chip is outlined and
            // is what the feature shows; exactly one is selected at a time.
            val selected = lab.selected
            val outline = MaterialTheme.colorScheme.primary
            Row(Modifier.horizontalScroll(rememberScrollState()), verticalAlignment = Alignment.CenterVertically) {
                FilterChip(selected = selected == "original", onClick = { lab.select("original", setStyle) },
                    label = { Text("Shipped") }, modifier = Modifier.padding(end = 8.dp),
                    border = FilterChipDefaults.filterChipBorder(enabled = true, selected = selected == "original",
                        selectedBorderColor = outline, selectedBorderWidth = 2.dp))
                for (c in lab.list) {
                    InputChip(selected = selected == c.name, onClick = { lab.select(c.name, setStyle) },
                        label = { Text(c.name) }, modifier = Modifier.padding(end = 8.dp),
                        border = InputChipDefaults.inputChipBorder(enabled = true, selected = selected == c.name,
                            selectedBorderColor = outline, selectedBorderWidth = 2.dp),
                        trailingIcon = {
                            IconButton(onClick = { lab.remove(c.name, setStyle) },
                                modifier = Modifier.size(24.dp).semantics { contentDescription = "Remove ${c.name}" }) {
                                Text("×", Modifier.clearAndSetSemantics { })
                            }
                        })
                }
            }
            // Always enabled: they show the selected look and edit it. On Shipped,
            // the first change starts a new pin.
            Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState())) {
                Row {
                    // Presets are actions, not states, so they are never outlined.
                    for (name in uiTuningLabPresets.keys) {
                        OutlinedButton(onClick = { lab.applyPreset(name, setStyle) },
                            modifier = Modifier.padding(end = 8.dp)) { Text(name.replaceFirstChar(Char::uppercase)) }
                    }
                }
                UITuningLabSlider("Corner radius", style.cornerRadius, 32) {
                    lab.edit(style.copy(cornerRadius = it), setStyle)
                }
                UITuningLabSlider("Spacing", style.spacing, 24) {
                    lab.edit(style.copy(spacing = it), setStyle)
                }
                lab.status?.let { Text(it, Modifier.semantics { liveRegion = LiveRegionMode.Polite }) }
            }
            Row(Modifier.padding(top = 8.dp)) {
                OutlinedButton(enabled = lab.selectedPin != null, onClick = { lab.duplicate(setStyle) },
                    modifier = Modifier.padding(end = 8.dp)) { Text("Duplicate") }
                Button(onClick = { clipboard.setText(AnnotatedString(lab.choose(resultFile))) }) {
                    Text("Choose")
                }
            }
            // Pinned below the controls, visible however long the panel grows.
            Text("Duplicate to compare · Choose to finish",
                style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(vertical = 12.dp))
        }
    }
}

@Composable
private fun UITuningLabSlider(label: String, value: Int, max: Int, onChange: (Int) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f))
        // The slider already reports its value to TalkBack; hide the readout.
        Text("$value dp", Modifier.clearAndSetSemantics { })
    }
    Slider(value = value.toFloat(), onValueChange = { onChange(it.roundToInt()) },
        valueRange = 0f..max.toFloat(), steps = max - 1,
        modifier = Modifier.semantics { contentDescription = label })
}
```

## Reading the lines and waiting for the pick

Lines go to logcat under the `ui-tuning-lab` tag. Read them with
`adb logcat -d -s ui-tuning-lab:I`, and wait for `UITUNINGLAB_DONE` with the
Android loop in `references/platform-handoff.md` ("Wait for Done") with
`TAG=ui-tuning-lab`. Start the wait right after the `am start` command, and stop
it if the user writes first. A busy device can rotate the logcat buffer; then
read the result file, which Choose writes to
`noBackupFilesDir/.ui-tuning-lab/result.json`:
`adb exec-out run-as <pkg> cat no_backup/.ui-tuning-lab/result.json`.

Logcat truncates an entry near 4 KB, so a Done line with many pins can be
cut. When its JSON exceeds about 3,500 characters, the lab logs every pin
on its own `UITUNINGLAB_CANDIDATE` line right before Done; if the Done line does
not parse, read the result file or rebuild the list from those lines
(`references/candidates.md`, "Log lines").

`-S` force-stops the app first. Without it, a running process has already used
its one launch request and the extra is ignored.

## Teardown

Closing (Close or system back) sets `showUITuningLab` to false, which removes
the panel, its `BackHandler`, and its state from composition. The feature keeps
the selected look, and reopening shows the same chips and selection. The lab
registers no listeners,
sensors, or timers; `LaunchedEffect` scopes are cancelled with the composition.
Confirm with Layout Inspector that no panel node remains after closing.

Removal at landing: delete `app/src/debug/java/.../UITuningLab*.kt` and
`app/src/release/java/.../TuningLabHost.kt`, and point `FeatureScreen` back at
`CardFeature(CardStyle.appDefault)`, which now holds the winner. Then run the
`grep` in `references/landing-protocol.md` (step 3) over `app/src/` and build
both variants.

## Persistence variant, only when requested

Add this file and hand it to the store; everything else stays the same. It
writes one `schemaVersion: 2` profile per pin to
`context.noBackupFilesDir/.ui-tuning-lab/candidates/<name>.json`
(`references/platform-handoff.md`) when the pin is created and again whenever it
logs new values, and × deletes it. A failed write shows in the status line; the
pin stays in the panel. Unreadable or incompatible files are reported, skipped,
and left untouched, and their names stay reserved.

`app/src/debug/java/com/example/cards/UITuningLabStorage.kt`

```kotlin
package com.example.cards

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.time.Instant

class UITuningLabStorage(context: Context) {
    private val dir = File(context.noBackupFilesDir, ".ui-tuning-lab/candidates")

    // Atomic: write a temporary file, then move it over the pin's last profile,
    // so a reader never sees half a file.
    fun write(candidate: UITuningLabCandidate) {
        if (!dir.isDirectory && !dir.mkdirs()) throw IOException("cannot create $dir")
        val target = File(dir, "${candidate.name}.json")
        val profile = mapOf(
            "basedOn" to candidate.basedOn, "container" to "FeatureScreen.panel",
            "name" to candidate.name, "notes" to "",
            "overrides" to uiTuningLabApply(candidate.values).uiTuningLabMap(),
            "platform" to "android", "savedAt" to Instant.now().toString(), "schemaVersion" to 2,
            "scope" to listOf("appearance", "layout"),
        )
        val temp = File(dir, ".${candidate.name}.json.tmp")
        temp.writeText(uiTuningLabJson(profile))
        try {
            Files.move(temp.toPath(), target.toPath(),
                StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
        } finally { temp.delete() }
    }

    fun delete(name: String) {
        val file = File(dir, "$name.json")
        if (file.exists() && !file.delete()) throw IOException("cannot delete $file")
    }

    // Every stored name goes into `reserved`, readable or not, so a new pin never
    // reuses it.
    fun readAll(reserved: MutableSet<String>): Pair<List<UITuningLabCandidate>, List<String>> {
        val found = mutableListOf<Pair<Instant, UITuningLabCandidate>>()
        val problems = mutableListOf<String>()
        for (file in dir.listFiles { f -> f.name.endsWith(".json") }.orEmpty()) {
            val name = file.name.removeSuffix(".json")
            reserved.add(name)
            try {
                val p = JSONObject(file.readText())
                val o = p.getJSONObject("overrides")
                if (p.getInt("schemaVersion") != 2 || p.getString("platform") != "android" ||
                    p.getString("name") != name) throw IOException("incompatible schema, platform, or name")
                val values = uiTuningLabChanged(CardStyle(o.getInt("cornerRadius"), o.getInt("spacing")))
                if (values.isEmpty()) throw IOException("matches the baseline")
                // Sort by instant, not by string: "…24Z" and "…24.5Z" do not compare as text.
                val savedAt = runCatching { Instant.parse(p.optString("savedAt")) }.getOrDefault(Instant.EPOCH)
                found += savedAt to UITuningLabCandidate(name, p.optString("basedOn", "baseline"), values)
            } catch (e: Exception) {
                problems += "$name (${e.message})"
            }
        }
        return found.sortedBy { it.first }.map { it.second } to problems
    }
}
```

Wiring, in `TuningLabHost`: add `val context = LocalContext.current` and
`val storage = remember { UITuningLabStorage(context) }` before the store, and
create the store with
`remember { UITuningLabCandidates(initial = emptyList()).apply { store = storage::write; unstore = storage::delete } }`.
The store already calls them: `store` whenever a pin logs its
`UITUNINGLAB_CANDIDATE` line (creation, and leaving it after an edit), with a
failure shown in `status`; `unstore` before × removes a pin, which stays if the
delete fails. The panel's `LaunchedEffect` calls `storage.readAll(lab.issued)`,
adds the found candidates that are not already in `lab.list`, shows the
problems in `lab.status`, then calls `logUnlogged()`, which logs loaded pins
without writing them again. Do file work off the main thread in a real app
(`withContext(Dispatchers.IO)`). Validate a pulled file with
`sh <skill-dir>/scripts/verify.sh profile <file>` after
`adb exec-out run-as <pkg> cat no_backup/.ui-tuning-lab/candidates/tweak.json > tweak.json`.

## Manual gate check

`verify.sh source-gates` does not read Kotlin and reports `N/A`, which is never a
pass. Check by hand and record the evidence (`references/platform-handoff.md`,
"Gates the source linter cannot see"):

1. Every `UITuningLab` file is under `app/src/debug/`; main code references only
   `TuningLabHost`, and `app/src/release/` holds only the pass-through.
2. `./gradlew assembleRelease`, then
   `unzip -p app/build/outputs/apk/release/app-release*.apk 'classes*.dex' | grep -acE 'UITuningLab|UITUNINGLAB_|ui-tuning-lab'`
   prints `0`. R8 renames classes, so the string literals (`UITUNINGLAB_`, the
   `ui-tuning-lab` log tag, the `UITuningLabOpen` extra key) are the evidence
   that matters, not the class marker alone.
3. `adb shell am start -S -n <pkg>/<activity> --ez UITuningLabOpen true` on a
   Release install opens nothing.

## Version notes

- Height cap: `LocalConfiguration.screenHeightDp`; on Compose 1.7+ use the
  window size from `LocalWindowInfo`.
- Recent Compose deprecates `LocalClipboardManager`; there, use
  `LocalClipboard` and its suspend `setClipEntry`.
- `BuildConfig.DEBUG` needs `buildFeatures { buildConfig = true }` on AGP 8+.
- `Files.move` and `Instant` need API 26, or core library desugaring.
- `FilterChip` and `InputChip` are stable from Material 3 1.2; the panel's
  `@OptIn(ExperimentalMaterial3Api::class)` covers older versions.
