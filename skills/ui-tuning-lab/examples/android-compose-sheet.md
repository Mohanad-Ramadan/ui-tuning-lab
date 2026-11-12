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

The host owns the `UITuningLabCandidates` store, so looks, the unsaved edits
with their history, and the selection survive closing the panel. The default
lab is ephemeral: looks live in memory and in logcat only, and a name is never
reused within a process. The panel follows `references/candidates.md`. The chip
row under the header shows **Shipped** and each pinned look, named after its
preset (**Compact-1**, **Relaxed-1**, **Custom-1**); the selected chip is
outlined, and the feature always shows it. Switching chips is the comparison.
Every chip is read-only, a pinned look included: moving a slider or applying a
preset forks the selected chip into unsaved changes that start from its values,
with no chip outlined, until **Save & pin** keeps them as a new look (an edit on
**Compact-1** pins as **Compact-2**); the chip it came from never changes, and
tapping a chip drops the unsaved changes. The edit row under the controls holds
**Undo**, **Redo**, and **Reset**, each disabled when it cannot act. They work
on the unsaved changes, back to the chip they were forked from, which is
outlined again, and a slider drag is one step. Each slider marks the Shipped value with a tick under its
track, on every chip; a drag near it snaps to it exactly with a light haptic
tick, TalkBack's adjust action still reaches the values beside it, and the
readout reads `14 dp · default 12` while the value differs. **↺** beside a
changed slider puts that one control back to Shipped as one Undo step
(`references/control-mapping.md`, "Default marker and per-control reset"). There are no keyboard shortcuts: the panel uses buttons only.
**Apply** (hidden after its first use) pins unsaved changes first, picks the selected chip, and
shrinks the panel to the result bar. The **⋯** menu holds Copy values. Closing
keeps the selected look on screen. The panel's height is capped and the hint
sits below the scrolling controls, so it is visible at any panel or screen size.

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

    // fillMaxSize looks the pill to the screen corner; call the hook at screen
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
            // there is nothing to restore.
            UITuningLabPanel(style = style, setStyle = onStyleChange, lab = lab,
                modifier = Modifier.align(Alignment.BottomEnd), onClose = { showUITuningLab = false })
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

// Hands the pick to the agent's waiter (scripts/wait-for-pick.py) at once, so it
// resumes without a message; the waiter's `adb reverse` makes the host
// reachable as localhost. Fire and forget: without INTERNET or cleartext to
// localhost, logcat carries the pick.
fun uiTuningLabSendPick(json: String) {
    if (!BuildConfig.DEBUG) return
    Thread {
        try {
            val connection = java.net.URL("http://localhost:47321/pick").openConnection() as java.net.HttpURLConnection
            connection.connectTimeout = 2000
            connection.readTimeout = 2000
            connection.requestMethod = "POST"
            connection.doOutput = true
            connection.outputStream.use { it.write("UITUNINGLAB_DONE $json".toByteArray()) }
            connection.responseCode
            connection.disconnect()
        } catch (_: Throwable) {
        }
    }.start()
}

class UITuningLabCandidate(val name: String, val basedOn: String, val values: Map<String, Any>) {
    fun asMap() = mapOf("basedOn" to basedOn, "name" to name, "values" to values)
}

// A chip's label: `Brass-2` for `brass-2`, `Warm Glow-1` for `warm-glow-1`, Shipped
// for `original`; a name that does not end in `-N` shows as it is.
fun uiTuningLabChipLabel(name: String): String {
    if (name == "original") return "Shipped"
    val dash = name.lastIndexOf('-')
    val number = if (dash > 0) name.substring(dash + 1).toIntOrNull() else null
    if (number == null) return name
    val words = name.substring(0, dash).split('-').filter { it.isNotEmpty() }
        .joinToString(" ") { it.replaceFirstChar(Char::uppercase) }
    return "$words-$number"
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
    // The pinned looks, oldest first, each with its values. A pinned look never
    // changes: an edit on it forks `unsaved`.
    val list = mutableStateListOf<UITuningLabCandidate>().apply { addAll(initial) }
    // Every name issued in this process, removed ones included, so a look number
    // is never reused. The persist variant adds every stored name.
    internal val issued = initial.map { it.name }.toMutableSet()
    // The line each look last logged, so a look logs once.
    private val logged = mutableMapOf<String, String>()
    // The selected chip: "original" (Shipped) or a look's name. The feature shows
    // it, or the unsaved edits forked from it.
    var selected by mutableStateOf("original")
        private set
    // Edits not pinned yet, forked from the selected chip; while set, no chip is
    // outlined. The chip itself never changes.
    var unsaved by mutableStateOf<CardStyle?>(null)
        private set
    private var unsavedBasedOn = "baseline"
    // One point in the unsaved edits' history: what it showed, and where it came from.
    private class Step(val value: CardStyle, val basedOn: String)
    // Undo and Redo steps of the unsaved edits, back to the chip they were forked from.
    private var undoSteps by mutableStateOf(listOf<Step>())
    private var redoSteps by mutableStateOf(listOf<Step>())
    // The control of the newest step, so a drag stays one step.
    private var lastControl: String? = null
    // A failed profile write during the current pin, so the next status keeps it.
    private var storeError: String? = null
    var status by mutableStateOf<String?>(null)
    // The last pick; while set, the panel is the result bar.
    var result by mutableStateOf<String?>(null)
    // How many picks reached the agent. The first Apply reaches its waiter; after
    // it the agent no longer listens, so Apply hides and Save & pin also hands
    // the pick over for the user to paste as `land <name>`. Change does not reset
    // it.
    var applies by mutableStateOf(0)
        private set
    // The result bar's second line: where the pick was saved, or null when the
    // write failed (then `status` says why).
    var saved by mutableStateOf<String?>(null)
        private set
    // The persist variant sets these; the default lab writes only the result file.
    var store: ((UITuningLabCandidate) -> Unit)? = null
    var unstore: ((String) -> Unit)? = null

    val selectedPin: UITuningLabCandidate? get() = list.firstOrNull { it.name == selected }
    // The selected chip's look, which unsaved edits fork from.
    private val source: Step
        get() = selectedPin?.let { Step(uiTuningLabApply(it.values), it.basedOn) } ?: Step(baseline, "baseline")
    // The look the feature shows: the unsaved edits, else the selected chip.
    val selectedLook: CardStyle get() = unsaved ?: source.value
    // Only the selected chip is outlined, and none while there are unsaved edits.
    fun isOutlined(chip: String): Boolean = chip == selected && unsaved == null
    // Save & pin, the one save button, and Reset need unsaved edits.
    val hasEdits: Boolean get() = unsaved != null
    val canUndo: Boolean get() = undoSteps.isNotEmpty()
    val canRedo: Boolean get() = redoSteps.isNotEmpty()
    val canReset: Boolean get() = hasEdits

    // What the feature shows now, as a history step.
    private val currentStep: Step get() = unsaved?.let { Step(it, unsavedBasedOn) } ?: source

    // Shows a step. Matching the chip the edits were forked from leaves no
    // unsaved edits, and that chip is outlined again.
    private fun show(next: Step) {
        if (next.value == source.value) {
            unsaved = null
            unsavedBasedOn = "baseline"
        } else {
            unsaved = next.value
            unsavedBasedOn = next.basedOn
        }
    }

    private fun clearHistory() {
        undoSteps = emptyList()
        redoSteps = emptyList()
        lastControl = null
    }

    // Logs a look's line the first time, and stores it in the persist variant.
    // Only a new pin logs and stores. A failed write shows in
    // the status line; the look stays in the panel.
    private fun log(candidate: UITuningLabCandidate, storing: Boolean = true) {
        val line = uiTuningLabJson(candidate.asMap())
        if (logged[candidate.name] == line) return
        logged[candidate.name] = line
        uiTuningLabLog("UITUNINGLAB_CANDIDATE", line)
        if (!storing) return
        try { store?.invoke(candidate) } catch (e: Exception) {
            storeError = "${uiTuningLabChipLabel(candidate.name)} not saved: ${e.message}"
            status = storeError
        }
    }

    // Seeded or stored looks log their own line the first time the lab shows them.
    fun logUnlogged() {
        for (c in list.toList()) if (c.name !in logged) log(c, storing = false)
    }

    // Tapping a chip shows its look in the real feature. Switching chips is the
    // comparison. Unsaved edits are dropped, so a chip always shows its look
    // exactly, the one they were forked from included.
    fun select(chip: String, setStyle: (CardStyle) -> Unit) {
        if (chip == selected && unsaved == null) return
        clearHistory()
        unsaved = null
        unsavedBasedOn = "baseline"
        selected = if (list.any { it.name == chip }) chip else "original"
        setStyle(selectedLook)
    }

    // Every control makes unsaved edits. On an outlined chip the first edit forks
    // it: the edits start from its values and basedOn, and the chip itself never
    // changes. A preset becomes their basedOn. Sliders pass `control`, their key:
    // a run of edits from the same control in a row is one Undo step. Presets
    // pass none, so each is a step.
    fun edit(next: CardStyle, setStyle: (CardStyle) -> Unit, preset: String? = null, control: String? = null) {
        val current = currentStep
        if (next == current.value && (preset == null || preset == current.basedOn)) return
        if (control == null || control != lastControl || !canUndo) undoSteps = undoSteps + current
        redoSteps = emptyList()
        lastControl = control
        show(Step(next, preset ?: current.basedOn))
        setStyle(selectedLook)
    }

    fun applyPreset(name: String, setStyle: (CardStyle) -> Unit) =
        edit(uiTuningLabPresets.getValue(name), setStyle, preset = name)

    // The Shipped look: what each control's default marker shows, on every chip.
    val shipped: CardStyle get() = baseline

    // ↺ on one control: `restore` copies that control's fields from Shipped (a
    // spring's two sliders together). An ordinary edit: one Undo step that ends
    // the current slider run, so it never merges with a drag. On a pinned look it
    // forks unsaved edits; edits that match the chip they were forked from again
    // are dropped, and that chip is outlined.
    fun resetControl(setStyle: (CardStyle) -> Unit, restore: (look: CardStyle, shipped: CardStyle) -> CardStyle) =
        edit(restore(selectedLook, baseline), setStyle)

    // Undo steps the unsaved edits back one, never past the chip they were forked
    // from, which is outlined again when they reach it.
    fun undo(setStyle: (CardStyle) -> Unit) {
        val previous = undoSteps.lastOrNull() ?: return
        undoSteps = undoSteps.dropLast(1)
        redoSteps = redoSteps + currentStep
        lastControl = null
        show(previous)
        setStyle(selectedLook)
    }

    // Redo brings back the edit Undo last took away.
    fun redo(setStyle: (CardStyle) -> Unit) {
        val next = redoSteps.lastOrNull() ?: return
        redoSteps = redoSteps.dropLast(1)
        undoSteps = undoSteps + currentStep
        lastControl = null
        show(next)
        setStyle(selectedLook)
    }

    // Reset drops the unsaved edits back to the chip they were forked from,
    // outlined again, in one step that Undo can take back.
    fun reset(setStyle: (CardStyle) -> Unit) {
        if (!hasEdits) return
        undoSteps = undoSteps + currentStep
        redoSteps = emptyList()
        lastControl = null
        show(source)
        setStyle(selectedLook)
    }

    // Pins the unsaved edits as a new look, named `<prefix>-N` after their basedOn
    // (`custom` for baseline), selected and outlined; the history starts fresh and
    // the look logs. Returns false with no unsaved edits.
    private fun commit(): Boolean {
        storeError = null
        val value = unsaved ?: return false
        val prefix = if (unsavedBasedOn == "baseline") "custom" else unsavedBasedOn
        val used = issued.mapNotNull { if (it.startsWith("$prefix-")) it.removePrefix("$prefix-").toIntOrNull() else null }
        val candidate = UITuningLabCandidate("$prefix-${(used.maxOrNull() ?: 0) + 1}", unsavedBasedOn, uiTuningLabChanged(value))
        issued.add(candidate.name)
        list.add(candidate)
        selected = candidate.name
        unsaved = null
        unsavedBasedOn = "baseline"
        clearHistory()
        log(candidate)
        return true
    }

    // Save & pin, the one save button: the unsaved edits become a new look,
    // selected; returns the land code for the clipboard, or null when there is
    // nothing to pin. Before the first Apply the agent is listening for Apply, so
    // nothing more happens; after it, the pick is handed over for pasting.
    fun save(resultFile: File): String? {
        if (!commit()) return null
        val look = selectedPin ?: return null
        if (applies > 0) return handOver(look, resultFile)
        saved = null
        status = storeError ?: "Pinned ${uiTuningLabChipLabel(look.name)} · copied land ${look.name}"
        return "land ${look.name}"
    }

    // Reports the selected look as shown, edits included: {} for Shipped.
    fun copyValues(): String {
        val json = uiTuningLabJson(uiTuningLabChanged(selectedLook))
        uiTuningLabLog("UITUNINGLAB_VALUES", json)
        status = if (json == "{}") "Same as Shipped" else "Copied $json"
        return json
    }

    // Removing the selected look selects Shipped.
    fun remove(name: String, setStyle: (CardStyle) -> Unit) {
        val label = uiTuningLabChipLabel(name)
        try { unstore?.invoke(name) } catch (e: Exception) { status = "$label not removed: ${e.message}"; return }
        list.removeAll { it.name == name }
        logged.remove(name)
        uiTuningLabLog("UITUNINGLAB_CANDIDATE_REMOVED", uiTuningLabJson(mapOf("name" to name)))
        if (selected == name) { selected = "original"; clearHistory() }
        status = "Removed $label"
        setStyle(selectedLook)
    }

    // Apply pins unsaved edits first, like Save & pin, then hands the selected
    // chip over; returns the code for the clipboard.
    fun choose(resultFile: File): String {
        commit()
        return handOver(selectedPin, resultFile)
    }

    // Hands a pick ("original" for Shipped) to the agent and finishes; returns the
    // code for the clipboard. Picking again replaces the result: the newest pick wins.
    private fun handOver(pin: UITuningLabCandidate?, resultFile: File): String {
        val winner = pin?.name ?: "original"
        val values = pin?.values ?: emptyMap<String, Any>()
        val done = mapOf("candidates" to list.map { it.asMap() }, "values" to values, "winner" to winner)
        val line = uiTuningLabJson(done)
        // Logcat cuts entries near 4 KB. When the Done line may be cut, repeat each
        // look on its own line first, so the agent can rebuild the list.
        if (line.length > 3500) list.forEach { uiTuningLabLog("UITUNINGLAB_CANDIDATE", uiTuningLabJson(it.asMap())) }
        uiTuningLabLog("UITUNINGLAB_DONE", line)
        uiTuningLabSendPick(line)
        try {
            writeResult(resultFile, done)
            status = storeError
            saved = "Saved ${uiTuningLabChipLabel(winner)} in .ui-tuning-lab/result.json"
        } catch (e: Exception) {
            saved = null
            status = "Result file failed: ${e.message}"
        }
        applies++
        result = winner
        return "land $winner"
    }
}
```

`app/src/debug/java/com/example/cards/UITuningLabPanel.kt`

```kotlin
package com.example.cards

import androidx.activity.compose.BackHandler
import android.view.HapticFeedbackConstants
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsDraggedAsState
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
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp
import java.io.File
import kotlin.math.abs
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

    // After Apply the panel is one bar; Change restores the whole panel.
    lab.result?.let { name ->
        Surface(modifier.padding(16.dp), shape = MaterialTheme.shapes.extraLarge,
            tonalElevation = 3.dp, shadowElevation = 8.dp,
            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)) {
            Column(Modifier.padding(start = 16.dp, end = 4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(if (lab.applies > 1) "Copied land $name: paste it in chat so the agent applies it"
                        else "Applied: ${uiTuningLabChipLabel(name)}",
                        Modifier.semantics { liveRegion = LiveRegionMode.Polite })
                    TextButton(onClick = { lab.result = null }) { Text("Change") }
                }
                (lab.saved ?: lab.status)?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(bottom = 8.dp))
                }
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
            // The chips: Shipped, then each look. The selected chip is outlined and
            // is what the feature shows; exactly one is selected at a time.
            val outline = MaterialTheme.colorScheme.primary
            Row(Modifier.horizontalScroll(rememberScrollState()), verticalAlignment = Alignment.CenterVertically) {
                FilterChip(selected = lab.isOutlined("original"), onClick = { lab.select("original", setStyle) },
                    label = { Text("Shipped") }, modifier = Modifier.padding(end = 8.dp),
                    border = FilterChipDefaults.filterChipBorder(enabled = true, selected = lab.isOutlined("original"),
                        selectedBorderColor = outline, selectedBorderWidth = 2.dp))
                for (c in lab.list) {
                    val on = lab.isOutlined(c.name)
                    InputChip(selected = on, onClick = { lab.select(c.name, setStyle) },
                        label = { Text(uiTuningLabChipLabel(c.name)) }, modifier = Modifier.padding(end = 8.dp),
                        border = InputChipDefaults.inputChipBorder(enabled = true, selected = on,
                            selectedBorderColor = outline, selectedBorderWidth = 2.dp),
                        // × only on the selected look, outlined, so nothing is removed by accident.
                        trailingIcon = if (!on) null else {
                            {
                                IconButton(onClick = { lab.remove(c.name, setStyle) },
                                    modifier = Modifier.size(24.dp).semantics {
                                        contentDescription = "Remove ${uiTuningLabChipLabel(c.name)}"
                                    }) {
                                    Text("×", Modifier.clearAndSetSemantics { })
                                }
                            }
                        })
                }
            }
            // Always enabled: they show the selected look; a change forks it into
            // unsaved edits until Save & pin. Sliders pass their key, so a drag is
            // one Undo step; presets pass none.
            Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState())) {
                Row {
                    // Presets are actions, not states, so they are never outlined.
                    for (name in uiTuningLabPresets.keys) {
                        OutlinedButton(onClick = { lab.applyPreset(name, setStyle) },
                            modifier = Modifier.padding(end = 8.dp)) { Text(name.replaceFirstChar(Char::uppercase)) }
                    }
                }
                UITuningLabSlider("Corner radius", style.cornerRadius, lab.shipped.cornerRadius, 32,
                    onReset = { lab.resetControl(setStyle) { look, shipped -> look.copy(cornerRadius = shipped.cornerRadius) } }) {
                    lab.edit(style.copy(cornerRadius = it), setStyle, control = "cornerRadius")
                }
                UITuningLabSlider("Spacing", style.spacing, lab.shipped.spacing, 24,
                    onReset = { lab.resetControl(setStyle) { look, shipped -> look.copy(spacing = shipped.spacing) } }) {
                    lab.edit(style.copy(spacing = it), setStyle, control = "spacing")
                }
                lab.status?.let { Text(it, Modifier.semantics { liveRegion = LiveRegionMode.Polite }) }
            }
            // Each button is disabled when it has nothing to do. Buttons only: no
            // keyboard shortcuts on Android.
            Row {
                TextButton(enabled = lab.canUndo, onClick = { lab.undo(setStyle) }) { Text("Undo") }
                TextButton(enabled = lab.canRedo, onClick = { lab.redo(setStyle) }) { Text("Redo") }
                TextButton(enabled = lab.canReset, onClick = { lab.reset(setStyle) }) { Text("Reset") }
            }
            Row(Modifier.padding(top = 8.dp)) {
                // Save & pin, the one save button: pins the unsaved edits.
                OutlinedButton(enabled = lab.hasEdits, modifier = Modifier.padding(end = 8.dp), onClick = {
                    lab.save(resultFile)?.let { clipboard.setText(AnnotatedString(it)) }
                }) { Text("Save & pin") }
                // Apply reaches the agent once; after that it is hidden for good.
                if (lab.applies == 0) {
                    Button(onClick = { clipboard.setText(AnnotatedString(lab.choose(resultFile))) }) { Text("Apply") }
                }
            }
            // Pinned below the controls, visible however long the panel grows.
            Text(if (lab.applies > 0) "Save & pin, then paste it in chat"
                else "Save & pin to keep a look · Apply to finish",
                style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(vertical = 12.dp))
        }
    }
}

// A slider with the Shipped value marked: a tick under the track, on every chip.
// Slider has no API for one tick at an arbitrary value, so it is drawn over the
// track; THUMB_INSET, half the thumb's width, keeps it under the thumb's center
// at that value. 10.dp fits the Material 3 slider this was written against;
// measure it again on your Material 3 version or a restyled thumb. A drag
// (never TalkBack's adjust action) within 1.5% of the range, or less than half
// a step, snaps to Shipped exactly, with one light haptic tick as it lands.
// The readout adds "· default 12" while the value differs, and ↺ puts this
// control back to Shipped as one Undo step, then focuses the slider, so focus
// stays in the panel as the ↺ goes away. All of it is display only.
private val THUMB_INSET = 10.dp

@Composable
private fun UITuningLabSlider(
    label: String, value: Int, shipped: Int, max: Int, onReset: () -> Unit, onChange: (Int) -> Unit,
) {
    val view = LocalView.current
    val interaction = remember { MutableInteractionSource() }
    val dragging by interaction.collectIsDraggedAsState()
    val focus = remember { FocusRequester() }
    // The last value this slider sent, so the haptic fires once, on the move onto Shipped.
    val lastSent = remember { intArrayOf(value) }
    if (!dragging) lastSent[0] = value  // a drag starts from the value shown
    val tick = MaterialTheme.colorScheme.outline
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f))
        // The slider already reports its value to TalkBack; hide the readout.
        Text(if (value == shipped) "$value dp" else "$value dp · default $shipped", Modifier.clearAndSetSemantics { })
        if (value != shipped) {
            IconButton(onClick = { onReset(); focus.requestFocus() }, modifier = Modifier.size(32.dp).semantics {
                contentDescription = "Reset $label to default, $shipped dp"
            }) { Text("↺", Modifier.clearAndSetSemantics { }) }
        }
    }
    Slider(value = value.toFloat(), onValueChange = { raw ->
            val distance = abs(raw - shipped)
            val snap = dragging && (distance <= max * 0.015f || distance < 0.5f)
            val next = if (snap) shipped else raw.roundToInt()
            if (snap && lastSent[0] != shipped) view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
            lastSent[0] = next
            onChange(next)
        },
        valueRange = 0f..max.toFloat(), steps = max - 1, interactionSource = interaction,
        modifier = Modifier.focusRequester(focus).semantics { contentDescription = label }.drawWithContent {
            drawContent()
            val inset = THUMB_INSET.toPx()
            val x = inset + (size.width - 2 * inset) * shipped / max
            drawRect(tick, topLeft = Offset(x - 1.dp.toPx(), size.height / 2 + 6.dp.toPx()),
                size = Size(2.dp.toPx(), 6.dp.toPx()))
        })
}
```

## Reading the lines and waiting for the pick

Lines go to logcat under the `ui-tuning-lab` tag. Read them with
`adb logcat -d -s ui-tuning-lab:I`. Wait for the pick with
`python3 <skill-dir>/scripts/wait-for-pick.py --log android` in the background
(`references/platform-handoff.md`, "Wait for Done"), started right after the
`am start` command; stop it if the user writes first. Its `adb reverse` lets
Apply's beacon reach it when the debug build has INTERNET and allows cleartext
to localhost; otherwise it reads the Done line from logcat. A busy device can rotate the logcat buffer; then
read the result file, which Apply writes to
`noBackupFilesDir/.ui-tuning-lab/result.json`:
`adb exec-out run-as <pkg> cat no_backup/.ui-tuning-lab/result.json`.

Logcat truncates an entry near 4 KB, so a Done line with many looks can be
cut. When its JSON exceeds about 3,500 characters, the lab logs every look
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
writes one `schemaVersion: 2` profile per look to
`context.noBackupFilesDir/.ui-tuning-lab/candidates/<name>.json`
(`references/platform-handoff.md`) once, when a look is pinned (Save & pin, or
Apply with unsaved edits), never for unsaved edits and never again after that,
and × deletes it. A failed write shows in the status line; the
look stays in the panel. Unreadable or incompatible files are reported, skipped,
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

    // Atomic: write a temporary file, then move it into place, so a reader never
    // sees half a file. A pinned look never changes, so it is written once;
    // `savedAt` orders the looks when they load.
    fun write(candidate: UITuningLabCandidate) {
        if (!dir.isDirectory && !dir.mkdirs()) throw IOException("cannot create $dir")
        val target = File(dir, "${candidate.name}.json")
        val savedAt = Instant.now().toString()
        val profile = mapOf(
            "basedOn" to candidate.basedOn, "container" to "FeatureScreen.panel",
            "name" to candidate.name, "notes" to "",
            "overrides" to uiTuningLabApply(candidate.values).uiTuningLabMap(),
            "platform" to "android", "savedAt" to savedAt, "schemaVersion" to 2,
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

    // Every stored name goes into `reserved`, readable or not, so a new look never
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
The store already calls them: `store` whenever a look logs its
`UITUNINGLAB_CANDIDATE` line (a new pin), with a
failure shown in `status`; `unstore` before × removes a look, which stays if the
delete fails. The panel's `LaunchedEffect` calls `storage.readAll(lab.issued)`,
adds the found candidates that are not already in `lab.list`, shows the
problems in `lab.status`, then calls `logUnlogged()`, which logs loaded looks
without writing them again. Do file work off the main thread in a real app
(`withContext(Dispatchers.IO)`). Validate a pulled file with
`sh <skill-dir>/scripts/verify.sh profile <file>` after
`adb exec-out run-as <pkg> cat no_backup/.ui-tuning-lab/candidates/compact-1.json > compact-1.json`.

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
