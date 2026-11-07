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

The host owns the `UITuningLabCandidates` store beside the draft, so pins,
`basedOn`, and the stashed draft survive closing the panel. The default lab is
ephemeral: pins live in memory and in logcat only, and a name is never reused
within a process. The chip row under the header shows Shipped, each pin, and,
last, the draft chip ("Shipped + edits", "compact + edits"), which appears only
while the draft holds unpinned changes; tapping a chip shows it in the real
feature, and the draft is stashed meanwhile and restored when its chip is
tapped or the panel closes. While Shipped is shown the presets and sliders are
disabled; moving one while a pin is shown copies that pin into the draft first.
**Pin** pins the draft and is disabled while the draft matches Shipped or a
pin, **Choose** picks the shown chip and shrinks the panel to the result bar,
and the **⋯** menu holds Reset and Copy values. The panel's height is capped and the hint sits below the scrolling
controls, so it is visible at any panel or screen size.

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
            UITuningLabPanel(draft = style, setDraft = onStyleChange, lab = lab,
                modifier = Modifier.align(Alignment.BottomEnd), onClose = {
                    lab.restoreDraft(onStyleChange)
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

// The draft fields that differ from the baseline.
fun uiTuningLabChanged(draft: CardStyle): Map<String, Any> {
    val base = baseline.uiTuningLabMap()
    return draft.uiTuningLabMap().filter { (key, value) -> base[key] != value }
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
    // pin never takes.
    private val issued = (initial.map { it.name } + listOf("draft", "now", "original", "baseline")).toMutableSet()
    private val logged = mutableSetOf<String>()
    // Where the draft came from: a preset, "baseline", or a pin's name.
    var basedOn by mutableStateOf("baseline")
    private var lastPreset: String? = null
    // The shown chip: "draft", "original" (Shipped), or a pin's name.
    var shown by mutableStateOf("draft")
    var status by mutableStateOf<String?>(null)
    // The last pick; while set, the panel is the result bar.
    var result by mutableStateOf<String?>(null)
    // Holds the draft while another chip is shown.
    private var stash: CardStyle? = null

    // The chip the draft matches ("original" for Shipped, or a pin), or null while
    // it holds unpinned changes and shows its own chip, last, as "<source> + edits".
    fun draftMatch(onScreen: CardStyle): String? {
        val values = uiTuningLabChanged(stash ?: onScreen)
        if (values.isEmpty()) return "original"
        return list.firstOrNull { it.values == values }?.name
    }

    // The highlighted chip: the one shown, or the one the draft matches.
    fun current(onScreen: CardStyle) = if (shown == "draft") draftMatch(onScreen) ?: "draft" else shown

    val draftTitle get() = "${if (basedOn == "baseline") "Shipped" else basedOn} + edits"

    // Seeded or stored pins log their own line the first time the lab shows them.
    fun logUnlogged() {
        for (c in list) if (logged.add(c.name)) uiTuningLabLog("UITUNINGLAB_CANDIDATE", uiTuningLabJson(c.asMap()))
    }

    // Tapping a chip shows it in the real feature; the chip the draft matches
    // shows the draft itself.
    fun show(chip: String, draft: CardStyle, setDraft: (CardStyle) -> Unit) {
        val target = if (chip == draftMatch(draft)) "draft" else chip
        if (target == "draft") {
            stash?.let(setDraft)
            stash = null
        } else {
            if (stash == null) stash = draft
            val candidate = list.firstOrNull { it.name == target }
            setDraft(if (candidate == null) baseline else uiTuningLabApply(candidate.values))
        }
        shown = target
    }

    fun restoreDraft(setDraft: (CardStyle) -> Unit) = show("draft", baseline, setDraft)

    // Every control edits the draft. Moved while a pin is shown, it copies that
    // pin into the draft first; the pin itself does not change. Editing a draft
    // that matches Shipped or a pin starts from that look.
    fun edit(next: CardStyle, setDraft: (CardStyle) -> Unit, from: String? = null, before: CardStyle = next) {
        val match = if (shown == "draft") draftMatch(before) else shown
        val source = from ?: when (match) { null -> basedOn; "original" -> "baseline"; else -> match }
        stash = null
        setDraft(next)
        basedOn = source
        shown = "draft"
    }

    fun reset(setDraft: (CardStyle) -> Unit) { lastPreset = null; edit(baseline, setDraft, "baseline") }

    fun applyPreset(name: String, setDraft: (CardStyle) -> Unit) {
        lastPreset = name
        edit(uiTuningLabPresets.getValue(name), setDraft, name)
    }

    // Always reports the draft, whichever chip is shown.
    fun copyValues(draft: CardStyle): String {
        val json = uiTuningLabJson(uiTuningLabChanged(stash ?: draft))
        uiTuningLabLog("UITUNINGLAB_VALUES", json)
        status = if (json == "{}") "No changes from Shipped" else "Copied $json"
        return json
    }

    // Returns the new pin, or null with a status. Pin is enabled only while the
    // draft holds unpinned changes. The persist variant writes it before commit().
    fun prepareKeep(draft: CardStyle): UITuningLabCandidate? {
        val values = uiTuningLabChanged(draft)
        if (values.isEmpty()) { status = "Same as Shipped"; return null }
        list.firstOrNull { it.values == values }?.let { status = "Same as ${it.name}"; return null }
        val stem = lastPreset ?: "tweak"
        val name = generateSequence(1) { it + 1 }.map { if (it == 1) stem else "$stem-$it" }.first { it !in issued }
        return UITuningLabCandidate(name, basedOn, values)
    }

    fun commit(candidate: UITuningLabCandidate) {
        list.add(candidate)
        issued.add(candidate.name)
        logged.add(candidate.name)
        uiTuningLabLog("UITUNINGLAB_CANDIDATE", uiTuningLabJson(candidate.asMap()))
        status = "Pinned ${candidate.name}"
    }

    // Pins the draft, stashed or on screen.
    fun keep(draft: CardStyle) { prepareKeep(stash ?: draft)?.let(::commit) }

    fun remove(name: String, draft: CardStyle, setDraft: (CardStyle) -> Unit) {
        if (shown == name) show("draft", draft, setDraft)
        list.removeAll { it.name == name }
        uiTuningLabLog("UITUNINGLAB_CANDIDATE_REMOVED", uiTuningLabJson(mapOf("name" to name)))
    }

    // Choose picks the highlighted chip and finishes; returns the code for the
    // clipboard. Picking again replaces the result: the newest pick wins.
    fun useThis(draft: CardStyle, resultFile: File): String {
        val chip = current(draft)
        val picked = list.firstOrNull { it.name == chip }
        val winner = picked?.name ?: if (chip == "original") "original" else "draft"
        val values = picked?.values ?: if (chip == "original") emptyMap<String, Any>() else uiTuningLabChanged(draft)
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
    draft: CardStyle,
    setDraft: (CardStyle) -> Unit,
    lab: UITuningLabCandidates,
    modifier: Modifier = Modifier,
    onClose: () -> Unit,
) {
    val clipboard = LocalClipboardManager.current
    val resultFile = File(LocalContext.current.noBackupFilesDir, ".ui-tuning-lab/result.json")
    val editable = lab.shown != "original" // never edit the baseline
    val maxHeight = (LocalConfiguration.current.screenHeightDp * 0.6f).dp
    var menuOpen by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { lab.logUnlogged() }
    // System back closes the lab first, like Escape on the web.
    BackHandler(onBack = onClose)

    // After Choose the panel is one bar; Change reopens it.
    lab.result?.let { name ->
        Surface(modifier.padding(16.dp), shape = MaterialTheme.shapes.extraLarge,
            tonalElevation = 3.dp, shadowElevation = 8.dp) {
            Row(Modifier.padding(start = 16.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Chosen: $name", Modifier.semantics { liveRegion = LiveRegionMode.Polite })
                TextButton(onClick = { lab.result = null }) { Text("Change") }
            }
        }
        return
    }

    Surface(modifier.padding(16.dp).widthIn(max = 360.dp).heightIn(max = maxHeight),
        shape = MaterialTheme.shapes.large, tonalElevation = 3.dp, shadowElevation = 8.dp) {
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
                        DropdownMenuItem(text = { Text("Reset") },
                            onClick = { menuOpen = false; lab.reset(setDraft) })
                        DropdownMenuItem(text = { Text("Copy values") }, onClick = {
                            menuOpen = false
                            clipboard.setText(AnnotatedString(lab.copyValues(draft)))
                        })
                    }
                }
                TextButton(onClick = onClose) { Text("Close") }
            }
            // The chips: Shipped, each pin, then the draft chip while the draft holds
            // unpinned changes. Highlighted = shown.
            val current = lab.current(draft)
            val unpinned = lab.draftMatch(draft) == null
            Row(Modifier.horizontalScroll(rememberScrollState()), verticalAlignment = Alignment.CenterVertically) {
                FilterChip(selected = current == "original", onClick = { lab.show("original", draft, setDraft) },
                    label = { Text("Shipped") }, modifier = Modifier.padding(end = 8.dp))
                for (c in lab.list) {
                    InputChip(selected = current == c.name, onClick = { lab.show(c.name, draft, setDraft) },
                        label = { Text(c.name) }, modifier = Modifier.padding(end = 8.dp),
                        trailingIcon = {
                            IconButton(onClick = { lab.remove(c.name, draft, setDraft) },
                                modifier = Modifier.size(24.dp).semantics { contentDescription = "Remove ${c.name}" }) {
                                Text("×", Modifier.clearAndSetSemantics { })
                            }
                        })
                }
                if (unpinned) {
                    FilterChip(selected = current == "draft", onClick = { lab.show("draft", draft, setDraft) },
                        label = { Text(lab.draftTitle) }, modifier = Modifier.padding(end = 8.dp))
                }
            }
            Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState())) {
                Row {
                    for (name in uiTuningLabPresets.keys) {
                        OutlinedButton(enabled = editable, onClick = { lab.applyPreset(name, setDraft) },
                            modifier = Modifier.padding(end = 8.dp)) { Text(name.replaceFirstChar(Char::uppercase)) }
                    }
                }
                UITuningLabSlider("Corner radius", draft.cornerRadius, 32, editable) {
                    lab.edit(draft.copy(cornerRadius = it), setDraft, before = draft)
                }
                UITuningLabSlider("Spacing", draft.spacing, 24, editable) {
                    lab.edit(draft.copy(spacing = it), setDraft, before = draft)
                }
                lab.status?.let { Text(it, Modifier.semantics { liveRegion = LiveRegionMode.Polite }) }
            }
            Row(Modifier.padding(top = 8.dp)) {
                OutlinedButton(enabled = unpinned, onClick = { lab.keep(draft) },
                    modifier = Modifier.padding(end = 8.dp)) { Text("Pin") }
                Button(onClick = { clipboard.setText(AnnotatedString(lab.useThis(draft, resultFile))) }) {
                    Text("Choose")
                }
            }
            // Pinned below the controls, visible however long the panel grows.
            Text("Pin looks to compare · Choose to finish",
                style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(vertical = 12.dp))
        }
    }
}

@Composable
private fun UITuningLabSlider(label: String, value: Int, max: Int, enabled: Boolean, onChange: (Int) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f))
        // The slider already reports its value to TalkBack; hide the readout.
        Text("$value dp", Modifier.clearAndSetSemantics { })
    }
    Slider(value = value.toFloat(), onValueChange = { onChange(it.roundToInt()) }, enabled = enabled,
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
the panel, its `BackHandler`, and its state from composition and restores any
stashed draft. The lab registers no listeners,
sensors, or timers; `LaunchedEffect` scopes are cancelled with the composition.
Confirm with Layout Inspector that no panel node remains after closing.

Removal at landing: delete `app/src/debug/java/.../UITuningLab*.kt` and
`app/src/release/java/.../TuningLabHost.kt`, and point `FeatureScreen` back at
`CardFeature(CardStyle.appDefault)`, which now holds the winner. Then run the
`grep` in `references/landing-protocol.md` (step 3) over `app/src/` and build
both variants.

## Persistence variant, only when requested

Add this file and call it from the store; everything else stays the same. It
writes one `schemaVersion: 2` profile per candidate to
`context.noBackupFilesDir/.ui-tuning-lab/candidates/<name>.json`
(`references/platform-handoff.md`), never over an existing file. A failed write
refuses the Pin. Unreadable or incompatible files are reported, skipped, and
left untouched, and their names stay reserved.

`app/src/debug/java/com/example/cards/UITuningLabStorage.kt`

```kotlin
package com.example.cards

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.time.Instant

class UITuningLabStorage(context: Context) {
    private val dir = File(context.noBackupFilesDir, ".ui-tuning-lab/candidates")

    // Atomic: write a temporary file, then move it into place. Files.move without
    // REPLACE_EXISTING fails if the target exists, so nothing is overwritten.
    fun write(candidate: UITuningLabCandidate, overrides: CardStyle) {
        if (!dir.isDirectory && !dir.mkdirs()) throw IOException("cannot create $dir")
        val target = File(dir, "${candidate.name}.json")
        if (target.exists()) throw IOException("${candidate.name} already exists in storage")
        val profile = mapOf(
            "basedOn" to candidate.basedOn, "container" to "FeatureScreen.panel",
            "name" to candidate.name, "notes" to "", "overrides" to overrides.uiTuningLabMap(),
            "platform" to "android", "savedAt" to Instant.now().toString(), "schemaVersion" to 2,
            "scope" to listOf("appearance", "layout"),
        )
        val temp = File(dir, ".${candidate.name}.json.tmp")
        temp.writeText(uiTuningLabJson(profile))
        try { Files.move(temp.toPath(), target.toPath()) } finally { temp.delete() }
    }

    fun delete(name: String) { File(dir, "$name.json").delete() }

    // Every stored name goes into `reserved`, readable or not, so Pin never reuses it.
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

Wiring, in the store: give `UITuningLabCandidates` a `storage` parameter.
`keep` becomes `val pinned = stash ?: draft; prepareKeep(pinned)?.let { c -> try { storage.write(c, pinned); commit(c) } catch (e: Exception) { status = "Pin failed: ${e.message}" } }`;
`remove` calls `storage.delete(name)` first; and the panel's `LaunchedEffect`
calls `readAll(issued)` (make `issued` internal), adds the found candidates
that are not already listed, shows the problems in `status`, then calls
`logUnlogged()`. Do file work off the main thread in a real app
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
