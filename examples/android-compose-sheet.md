# Unvalidated adaptation — Android Jetpack Compose panel

> **Unvalidated adaptation — not compiled in this repository.** No Kotlin or
> Android toolchain runs here, so none of this code has been built, run, or
> inspected in a Release APK. Treat it as a starting point and complete the full
> protocol (`references/verify-protocol.md`) in the target app before relying
> on it. Places where an API was assumed rather than checked are listed under
> "Assumptions to validate".

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
- **Human and visible fallback:** a **Tune** pill pinned to a free corner of the
  screen. If the app has a developer menu or drawer, add a menu entry that sets
  the same `showUITuningLab` state, and keep the pill.

The host owns the `UITuningLabCandidates` store beside the draft, so candidates,
`basedOn`, and the Compare stash survive closing the panel. The default lab is
ephemeral: candidates live in memory and in logcat only, and a name is never
reused within a process. Show baseline and Compare share one stash and are
exclusive; while either shows something other than the draft, presets, sliders,
Reset, Copy values, Keep, and Load are disabled. Done is disabled only while
Show baseline is on; while Compare shows a candidate, Done loads it first, so it
is the winner. Closing restores the draft. The panel's height is capped and the
finish hint sits below the scrolling controls, so the hint is visible at any
panel or screen size.

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
                    .semantics { contentDescription = "Open UI tuning lab" }) { Text("Tune") }
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

// 1 -> a, 26 -> z, 27 -> aa (bijective base 26).
private fun candidateName(index: Int): String {
    var name = ""
    var n = index
    while (n > 0) { n -= 1; name = ('a' + n % 26) + name; n /= 26 }
    return name
}

class UITuningLabCandidates(initial: List<UITuningLabCandidate>) {
    val list = mutableStateListOf<UITuningLabCandidate>().apply { addAll(initial) }
    // Every name issued in this process, removed ones included: never reused.
    private val issued = initial.map { it.name }.toMutableSet()
    private val logged = mutableSetOf<String>()
    // Where the draft came from: a preset, "baseline", or a candidate's name.
    var basedOn by mutableStateOf("baseline")
    // What the real feature shows: "draft", "baseline", or a candidate's name.
    var shown by mutableStateOf("draft")
    var status by mutableStateOf<String?>(null)
    // Holds the draft while the baseline or a candidate is shown.
    private var stash: CardStyle? = null

    // Seeded or stored candidates log their own line the first time the lab shows them.
    fun logUnlogged() {
        for (c in list) if (logged.add(c.name)) uiTuningLabLog("UITUNINGLAB_CANDIDATE", uiTuningLabJson(c.asMap()))
    }

    fun show(target: String, draft: CardStyle, setDraft: (CardStyle) -> Unit) {
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

    fun reset(setDraft: (CardStyle) -> Unit) { setDraft(baseline); basedOn = "baseline" }

    fun applyPreset(name: String, setDraft: (CardStyle) -> Unit) { setDraft(uiTuningLabPresets.getValue(name)); basedOn = name }

    fun copyValues(draft: CardStyle): String {
        val json = uiTuningLabJson(uiTuningLabChanged(draft))
        uiTuningLabLog("UITUNINGLAB_VALUES", json)
        status = if (json == "{}") "No changes from baseline" else "Copied $json"
        return json
    }

    // Returns the new candidate, or null when the draft matches the baseline or a
    // candidate. The persist variant writes it before calling commit().
    fun prepareKeep(draft: CardStyle): UITuningLabCandidate? {
        val values = uiTuningLabChanged(draft)
        if (values.isEmpty()) { status = "Matches the baseline; nothing to keep"; return null }
        list.firstOrNull { it.values == values }?.let { status = "Same as ${it.name}"; return null }
        val name = generateSequence(1) { it + 1 }.map(::candidateName).first { it !in issued }
        return UITuningLabCandidate(name, basedOn, values)
    }

    fun commit(candidate: UITuningLabCandidate) {
        list.add(candidate)
        issued.add(candidate.name)
        logged.add(candidate.name)
        uiTuningLabLog("UITUNINGLAB_CANDIDATE", uiTuningLabJson(candidate.asMap()))
        status = "Kept as ${candidate.name}"
    }

    fun keep(draft: CardStyle) { prepareKeep(draft)?.let(::commit) }

    fun load(candidate: UITuningLabCandidate, setDraft: (CardStyle) -> Unit) {
        stash = null
        setDraft(uiTuningLabApply(candidate.values))
        basedOn = candidate.name
        shown = "draft"
    }

    fun remove(name: String, draft: CardStyle, setDraft: (CardStyle) -> Unit) {
        list.removeAll { it.name == name }
        uiTuningLabLog("UITUNINGLAB_CANDIDATE_REMOVED", uiTuningLabJson(mapOf("name" to name)))
        if (shown == name) show("draft", draft, setDraft)
    }

    // Like Copy values, and it tells the agent the session is over. While Compare
    // shows a candidate, that candidate becomes the draft first: it is the winner.
    fun done(draft: CardStyle, setDraft: (CardStyle) -> Unit): String {
        val picked = list.firstOrNull { it.name == shown }
        picked?.let { load(it, setDraft) }
        val values = uiTuningLabChanged(picked?.let { uiTuningLabApply(it.values) } ?: draft)
        val winner = list.firstOrNull { it.values == values }?.name
        val line = uiTuningLabJson(
            mapOf("candidates" to list.map { it.asMap() }, "values" to values, "winner" to winner))
        // Logcat cuts entries near 4 KB. When the Done line may be cut, repeat each
        // candidate on its own line first, so the agent can rebuild the list.
        if (line.length > 3500) list.forEach { uiTuningLabLog("UITUNINGLAB_CANDIDATE", uiTuningLabJson(it.asMap())) }
        uiTuningLabLog("UITUNINGLAB_DONE", line)
        return uiTuningLabJson(values).also { status = "Done. Copied $it" }
    }
}
```

`app/src/debug/java/com/example/cards/UITuningLabPanel.kt`

```kotlin
package com.example.cards

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt

// A non-modal panel: it consumes touches only inside its own bounds, so the
// feature around it stays usable. Composed only while the lab is open.
@Composable
fun UITuningLabPanel(
    draft: CardStyle,
    setDraft: (CardStyle) -> Unit,
    lab: UITuningLabCandidates,
    modifier: Modifier = Modifier,
    onClose: () -> Unit,
) {
    val clipboard = LocalClipboardManager.current
    val editing = lab.shown == "draft"
    val maxHeight = (LocalConfiguration.current.screenHeightDp * 0.6f).dp
    LaunchedEffect(Unit) { lab.logUnlogged() }
    fun close() = onClose()
    // System back closes the lab first, like Escape on the web.
    BackHandler(onBack = onClose)

    Surface(modifier.padding(16.dp).widthIn(max = 360.dp).heightIn(max = maxHeight),
        shape = MaterialTheme.shapes.large, tonalElevation = 3.dp, shadowElevation = 8.dp) {
        Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
            Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState())) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("UI tuning lab", style = MaterialTheme.typography.titleMedium,
                        modifier = Modifier.weight(1f).semantics { heading() })
                    TextButton(onClick = { close() }) { Text("Close") }
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Show baseline", Modifier.weight(1f))
                    Switch(checked = lab.shown == "baseline",
                        onCheckedChange = { lab.show(if (it) "baseline" else "draft", draft, setDraft) })
                }
                Row {
                    for (name in uiTuningLabPresets.keys) {
                        OutlinedButton(enabled = editing, onClick = { lab.applyPreset(name, setDraft) },
                            modifier = Modifier.padding(end = 8.dp)) { Text(name.replaceFirstChar(Char::uppercase)) }
                    }
                }
                UITuningLabSlider("Corner radius", draft.cornerRadius, 32, editing) { setDraft(draft.copy(cornerRadius = it)) }
                UITuningLabSlider("Spacing", draft.spacing, 24, editing) { setDraft(draft.copy(spacing = it)) }
                Row {
                    TextButton(enabled = editing, onClick = { lab.reset(setDraft) }) { Text("Reset") }
                    TextButton(enabled = editing, onClick = {
                        clipboard.setText(AnnotatedString(lab.copyValues(draft)))
                    }) { Text("Copy values") }
                    TextButton(enabled = editing, onClick = { lab.keep(draft) }) { Text("Keep as candidate") }
                }
                if (lab.list.isNotEmpty()) {
                    Text("Candidates", style = MaterialTheme.typography.titleSmall)
                    for (c in lab.list) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("${c.name} from ${c.basedOn}", Modifier.weight(1f))
                            TextButton(enabled = editing, onClick = { lab.load(c, setDraft) },
                                modifier = Modifier.semantics { contentDescription = "Load ${c.name}" }) { Text("Load") }
                            TextButton(onClick = { lab.remove(c.name, draft, setDraft) },
                                modifier = Modifier.semantics { contentDescription = "Remove ${c.name}" }) { Text("Remove") }
                        }
                    }
                    Text("Compare", style = MaterialTheme.typography.titleSmall)
                    Column(Modifier.selectableGroup()) {
                        for (target in listOf("draft") + lab.list.map { it.name }) {
                            Row(Modifier.fillMaxWidth().selectable(selected = lab.shown == target, role = Role.RadioButton,
                                onClick = { lab.show(target, draft, setDraft) }),
                                verticalAlignment = Alignment.CenterVertically) {
                                RadioButton(selected = lab.shown == target, onClick = null)
                                Text(if (target == "draft") "Draft" else target)
                            }
                        }
                    }
                }
                Button(enabled = lab.shown != "baseline", onClick = {
                    clipboard.setText(AnnotatedString(lab.done(draft, setDraft)))
                }) { Text("Done") }
                lab.status?.let { Text(it, Modifier.semantics { liveRegion = LiveRegionMode.Polite }) }
            }
            // Pinned below the scrolling controls, visible however long the panel grows.
            Text("Finished? Keep the ones you like, then press Done, or tell the agent \"land b\".",
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

## Reading the lines and waiting for Done

Lines go to logcat under the `ui-tuning-lab` tag. Read them with
`adb logcat -d -s ui-tuning-lab:I`, and wait for Done with the Android loop in
`references/platform-handoff.md` ("Wait for Done") with `TAG=ui-tuning-lab`.
Start the wait right after the `am start` command, and stop it if the user
writes first. A busy device can rotate the logcat buffer, so read soon after
Done or ask the user to press Done again.

Logcat truncates an entry near 4 KB, so a Done line with many candidates can be
cut. When its JSON exceeds about 3,500 characters, the lab logs every
candidate on its own `UITUNINGLAB_CANDIDATE` line right before Done; if the Done
line does not parse, rebuild the list from those lines
(`references/candidates.md`, "Log lines") and take the draft's values from a
fresh Copy values.

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
refuses the Keep. Unreadable or incompatible files are reported, skipped, and
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

    // Every stored name goes into `reserved`, readable or not, so Keep never reuses it.
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
`keep` becomes `prepareKeep(draft)?.let { c -> try { storage.write(c, draft); commit(c) } catch (e: Exception) { status = "Keep failed: ${e.message}" } }`;
`remove` calls `storage.delete(name)` first; and the panel's `LaunchedEffect`
calls `readAll(issued)` (make `issued` internal), adds the found candidates
that are not already listed, shows the problems in `status`, then calls
`logUnlogged()`. Do file work off the main thread in a real app
(`withContext(Dispatchers.IO)`). Validate a pulled file with
`sh <skill-dir>/scripts/verify.sh profile <file>` after
`adb exec-out run-as <pkg> cat no_backup/.ui-tuning-lab/candidates/b.json > b.json`.

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

## Assumptions to validate

- `LocalConfiguration.screenHeightDp` for the height cap; on Compose 1.7+ the
  window size from `LocalWindowInfo` is the newer equivalent.
- `LocalClipboardManager` is deprecated in recent Compose releases in favour of
  `LocalClipboard` (suspend `setClipEntry`); adapt to the app's Compose version.
- `BuildConfig.DEBUG` requires `buildFeatures { buildConfig = true }` on AGP 8+.
- `Files.move` and `Instant` need API 26, or core library desugaring.
- `Intent.removeExtra` on `activity.intent` is assumed not to survive into a
  recreated activity's intent; the process-level `handled` flag covers that
  case either way.
