# Windows (WinUI 3) flyout

The feature and the lab share one `CardConfig` held by the page. The baseline is
the declared default, `CardConfig.AppDefault`. All lab code lives in
`UITuningLabFlyout.cs`, wrapped in `#if DEBUG`; the page creates it inside
`#if DEBUG`, so Release compiles none of it. The panel is a `Flyout` attached to
a debug-only **Tune** button on the page's `CommandBar` (or on a bar the lab
creates in code when the page has none), created when it opens
and released when it closes. Never a `ContentDialog`: it is modal.

Activation (`references/activation.md`):

- **Agent:** the command-line argument `--ui-tuning-lab-open`, consumed the
  first time the page loads in this process.
- **Human:** `Ctrl+Shift+L`, a keyboard accelerator on the Tune button. Check
  during inspection that the app does not already use it.
- **Visible fallback:** the Tune button itself, with an accessible name.

The page owns the `UITuningLabFlyout` instance, so favorites, `basedOn`, and
the stashed Now survive closing the flyout. The default lab is ephemeral:
favorites live in memory and the debug output only, and a name is never reused
within a process. The chip row under the header shows Original, Now, or a
favorite in the real feature; Now is stashed meanwhile and restored when Now is
clicked or the flyout closes. While Original is shown the presets and sliders
are disabled; moving one while a favorite is shown loads that favorite into Now
first. **★ Keep** adds Now to the favorites, **✓ Use this** picks the shown chip
and shrinks the flyout to the result bar, and the **⋯** menu holds Reset and
Copy values. The hint is a grid row below the `ScrollViewer`, so it stays
visible.

## Host change

The page passed `CardConfig.AppDefault` straight to the feature; it now keeps a
`config` field so the lab can edit it. Undo this at landing
(`references/landing-protocol.md`).

`CardFeature.cs`

```csharp
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace App;

public sealed record CardConfig(double CornerRadius, double Spacing)
{
    public static readonly CardConfig AppDefault = new(CornerRadius: 12, Spacing: 8);
}

public sealed class CardFeature : StackPanel
{
    public void Apply(CardConfig config)
    {
        Children.Clear();
        Spacing = config.Spacing;
        Padding = new Thickness(16);
        foreach (var title in new[] { "First card", "Second card" })
        {
            Children.Add(new Border
            {
                CornerRadius = new CornerRadius(config.CornerRadius),
                Padding = new Thickness(16),
                Background = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"],
                Child = new TextBlock { Text = title },
            });
        }
    }
}
```

`FeaturePage.xaml`: this page already has a `CommandBar`, so the lab adds its
button there. When the page has none, pass `null` for the toolbar and the lab
creates one in code inside `#if DEBUG`. Never add XAML for the lab: markup is
not behind `#if DEBUG` and ships in Release.

```xml
<Page x:Class="App.FeaturePage"
      xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
      xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
      xmlns:local="using:App">
    <Grid x:Name="Root" RowDefinitions="Auto,*">
        <CommandBar x:Name="Toolbar" DefaultLabelPosition="Right" />
        <local:CardFeature x:Name="Feature" Grid.Row="1" />
    </Grid>
</Page>
```

`FeaturePage.xaml.cs`

```csharp
using Microsoft.UI.Xaml.Controls;

namespace App;

public sealed partial class FeaturePage : Page
{
    private CardConfig config = CardConfig.AppDefault;

    public FeaturePage()
    {
        InitializeComponent();
        Feature.Apply(config);
#if DEBUG
        uiTuningLab = new UITuningLabFlyout(this, Root, Toolbar, () => config, next =>
        {
            config = next;
            Feature.Apply(next);
        });
        // Leaving the page closes the flyout and releases its content.
        Unloaded += (_, _) => uiTuningLab.Release();
#endif
    }

#if DEBUG
    private readonly UITuningLabFlyout uiTuningLab;
#endif
}
```

## Lab code

`UITuningLabFlyout.cs`

```csharp
#if DEBUG
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Linq;
using System.Text.Json;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Windows.ApplicationModel.DataTransfer;
using Windows.System;

namespace App;

// Agent path: launch with --ui-tuning-lab-open. Honored once per process, so
// navigating back to the page does not reopen the lab.
internal static class UITuningLabLaunch
{
    private static bool handled;

    public static bool ConsumeRequest()
    {
        if (handled) return false;
        handled = true;
        return Environment.GetCommandLineArgs().Contains("--ui-tuning-lab-open");
    }
}

internal sealed record UITuningLabCandidate(string Name, string BasedOn, SortedDictionary<string, double> Values)
{
    public SortedDictionary<string, object?> AsJson() =>
        new() { ["basedOn"] = BasedOn, ["name"] = Name, ["values"] = Values };
}

internal sealed class UITuningLabFlyout
{
    // The declared default, never the value on screen when the lab opens.
    private static readonly CardConfig Baseline = CardConfig.AppDefault;
    // Preset keys are kebab-case: the key is what a candidate records as basedOn.
    private static readonly (string Key, string Title, CardConfig Value)[] Presets =
    {
        ("compact", "Compact", new CardConfig(4, 4)),
        ("relaxed", "Relaxed", new CardConfig(24, 16)),
    };

    private readonly Func<CardConfig> getDraft;
    private readonly Action<CardConfig> setDraft;
    private readonly AppBarButton tuneButton;
    // Favorites the lab opens with. Empty by default; a later session seeds the
    // finalists kept in the project here (references/candidates.md).
    private readonly List<UITuningLabCandidate> candidates = new();
    // Every name issued, removed ones included, plus the names a favorite never takes.
    private readonly HashSet<string> issued = new() { "draft", "now", "original", "baseline" };
    private readonly HashSet<string> logged = new();
    private string basedOn = "baseline";
    private string? lastPreset;
    private string shown = "draft"; // the shown chip: "draft" (Now), "original", or a favorite's name
    private CardConfig? stash; // Now, while another chip is shown
    private string? result; // the last pick; while set, the flyout is the result bar
    private Flyout? flyout;
    private bool allowClose;
    private bool refreshing;
    // Controls exist only while the flyout is open.
    private Grid? panel;
    private StackPanel? resultBar, chips, draftControls;
    private TextBlock? resultText, status;
    private Slider? radiusSlider, spacingSlider;
    private Button? keepButton;

    public UITuningLabFlyout(Page page, Grid root, CommandBar? toolbar, Func<CardConfig> getDraft, Action<CardConfig> setDraft)
    {
        this.getDraft = getDraft;
        this.setDraft = setDraft;
        issued.UnionWith(candidates.Select(c => c.Name));
        tuneButton = new AppBarButton { Label = "Tune", Icon = new SymbolIcon(Symbol.Setting) };
        AutomationProperties.SetName(tuneButton, "Open UI tuning lab");
        tuneButton.KeyboardAccelerators.Add(new KeyboardAccelerator
        {
            Key = VirtualKey.L,
            Modifiers = VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift,
        });
        tuneButton.Click += (_, _) => Open();
        if (toolbar == null)
        {
            // No toolbar on the page: a debug-only bar, created in code so nothing
            // of it exists in Release markup. Pin it to a corner inspection found free.
            toolbar = new CommandBar
            {
                DefaultLabelPosition = CommandBarDefaultLabelPosition.Right,
                HorizontalAlignment = HorizontalAlignment.Right,
                VerticalAlignment = VerticalAlignment.Bottom,
                Margin = new Thickness(16),
            };
            Grid.SetRowSpan(toolbar, Math.Max(1, root.RowDefinitions.Count));
            Grid.SetColumnSpan(toolbar, Math.Max(1, root.ColumnDefinitions.Count));
            root.Children.Add(toolbar);
        }
        toolbar.PrimaryCommands.Add(tuneButton);
        page.Loaded += OnFirstLoaded;

        void OnFirstLoaded(object sender, RoutedEventArgs e)
        {
            page.Loaded -= OnFirstLoaded;
            if (UITuningLabLaunch.ConsumeRequest()) Open();
        }
    }

    private static Dictionary<string, double> AsMap(CardConfig c) =>
        new() { ["cornerRadius"] = c.CornerRadius, ["spacing"] = c.Spacing };

    private static SortedDictionary<string, double> Changed(CardConfig draft)
    {
        var base_ = AsMap(Baseline);
        return new(AsMap(draft).Where(e => base_[e.Key] != e.Value).ToDictionary(e => e.Key, e => e.Value));
    }

    private static CardConfig ApplyValues(IDictionary<string, double> v) => new(
        v.TryGetValue("cornerRadius", out var r) ? r : Baseline.CornerRadius,
        v.TryGetValue("spacing", out var s) ? s : Baseline.Spacing);

    // JSON with sorted keys and two-decimal rounding, so every line has one shape.
    private static string Json(object? value) => value switch
    {
        null => "null",
        string s => JsonSerializer.Serialize(s),
        double d => Math.Round(d, 2).ToString("R", CultureInfo.InvariantCulture),
        int i => i.ToString(CultureInfo.InvariantCulture),
        IDictionary map => "{" + string.Join(",", map.Keys.Cast<string>().OrderBy(k => k, StringComparer.Ordinal)
            .Select(k => JsonSerializer.Serialize(k) + ":" + Json(map[k]))) + "}",
        IEnumerable list => "[" + string.Join(",", list.Cast<object?>().Select(Json)) + "]",
        _ => throw new ArgumentException($"unsupported value {value}"),
    };

    private static void Log(string tag, object payload) => Debug.WriteLine($"{tag} {Json(payload)}");

    private static void CopyText(string text)
    {
        var package = new DataPackage();
        package.SetText(text);
        Clipboard.SetContent(package);
    }

    // Packaged: the app's LocalFolder. Unpackaged: %LOCALAPPDATA%\<app-name>.
    private static string LabDirectory()
    {
        string root;
        try { root = Windows.Storage.ApplicationData.Current.LocalFolder.Path; }
        catch (Exception) // unpackaged: no package identity (InvalidOperationException or COMException)
        {
            root = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ExampleApp");
        }
        return System.IO.Path.Combine(root, ".ui-tuning-lab");
    }

    // Temporary file, then a replacing move: a reader never sees half a pick.
    private static void WriteResult(SortedDictionary<string, object?> done)
    {
        var dir = System.IO.Directory.CreateDirectory(LabDirectory()).FullName;
        var target = System.IO.Path.Combine(dir, "result.json");
        var temp = target + ".tmp";
        System.IO.File.WriteAllText(temp, Json(new SortedDictionary<string, object?>(done)
        {
            ["savedAt"] = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture),
        }));
        System.IO.File.Move(temp, target, overwrite: true);
    }

    public void Open()
    {
        if (flyout != null) return;
        foreach (var c in candidates.Where(c => logged.Add(c.Name))) Log("UITUNINGLAB_CANDIDATE", c.AsJson());
        allowClose = false;
        flyout = new Flyout
        {
            Content = BuildContent(),
            Placement = FlyoutPlacementMode.BottomEdgeAlignedRight,
            // Pointer input on the page reaches the feature while the lab is open.
            OverlayInputPassThroughElement = tuneButton.XamlRoot?.Content as UIElement,
        };
        // The flyout stays open while the feature is used; only Close and Escape dismiss it.
        flyout.Closing += (_, e) => { if (!allowClose) e.Cancel = true; };
        flyout.Closed += OnClosed;
        flyout.ShowAt(tuneButton);
        Refresh();
    }

    private void Close()
    {
        allowClose = true;
        flyout?.Hide();
    }

    // Called when the page unloads: close, and release the content even if the
    // flyout raises no Closed event once its page has left the tree.
    public void Release()
    {
        Close();
        if (flyout != null) OnClosed(null, EventArgs.Empty);
    }

    // Restores Now and releases the flyout and every control it held.
    private void OnClosed(object? sender, object e)
    {
        Show("draft");
        if (flyout != null) { flyout.Closed -= OnClosed; flyout.Content = null; }
        flyout = null;
        panel = null; resultBar = chips = draftControls = null; resultText = status = null;
        radiusSlider = spacingSlider = null; keepButton = null;
        tuneButton.Focus(FocusState.Programmatic);
    }

    private UIElement BuildContent()
    {
        refreshing = true; // Refresh clears it once the controls hold the draft
        var closeButton = new Button { Content = "Close" };
        closeButton.Click += (_, _) => Close();
        var more = new Button { Content = "⋯" };
        AutomationProperties.SetName(more, "More");
        var resetItem = new MenuFlyoutItem { Text = "Reset" };
        resetItem.Click += (_, _) => { lastPreset = null; Edit(Baseline, "baseline"); };
        var copyItem = new MenuFlyoutItem { Text = "Copy values" };
        copyItem.Click += (_, _) => CopyValues();
        more.Flyout = new MenuFlyout { Items = { resetItem, copyItem } };
        var title = new TextBlock { Text = "UI tuning lab", Style = (Style)Application.Current.Resources["SubtitleTextBlockStyle"] };
        AutomationProperties.SetHeadingLevel(title, AutomationHeadingLevel.Level1);
        var header = new Grid { ColumnDefinitions = { new() { Width = new(1, GridUnitType.Star) }, new() { Width = GridLength.Auto }, new() { Width = GridLength.Auto } } };
        header.Children.Add(title);
        Grid.SetColumn(more, 1);
        header.Children.Add(more);
        Grid.SetColumn(closeButton, 2);
        header.Children.Add(closeButton);

        // The chips: Original, Now, then each favorite. Refresh fills them.
        chips = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
        var chipScroller = new ScrollViewer
        {
            Content = chips, HorizontalScrollMode = ScrollMode.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
            VerticalScrollMode = ScrollMode.Disabled, VerticalScrollBarVisibility = ScrollBarVisibility.Disabled,
        };

        var body = new StackPanel { Spacing = 8 };
        draftControls = new StackPanel { Spacing = 8 };
        var presetRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        foreach (var (key, label, value) in Presets)
        {
            var b = new Button { Content = label };
            b.Click += (_, _) => { lastPreset = key; Edit(value, key); };
            presetRow.Children.Add(b);
        }
        draftControls.Children.Add(presetRow);
        radiusSlider = AddSlider(draftControls, "Corner radius", 32, v => getDraft() with { CornerRadius = v });
        spacingSlider = AddSlider(draftControls, "Spacing", 24, v => getDraft() with { Spacing = v });
        body.Children.Add(draftControls);
        status = new TextBlock { TextWrapping = TextWrapping.Wrap };
        AutomationProperties.SetLiveSetting(status, AutomationLiveSetting.Polite);
        body.Children.Add(status);

        var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, Margin = new Thickness(0, 8, 0, 0) };
        keepButton = MakeButton("★ Keep", Keep);
        actions.Children.Add(keepButton);
        actions.Children.Add(MakeButton("✓ Use this", UseThis));
        // Pinned below the scrolling controls, visible however long the panel grows.
        var hint = new TextBlock
        {
            Text = "Keep favorites · Use this to finish",
            TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 0),
        };

        panel = new Grid
        {
            Width = 320, MaxHeight = 560,
            RowDefinitions = { new() { Height = GridLength.Auto }, new() { Height = GridLength.Auto },
                new() { Height = new(1, GridUnitType.Star) }, new() { Height = GridLength.Auto }, new() { Height = GridLength.Auto } },
        };
        var scroller = new ScrollViewer { Content = body };
        FrameworkElement[] rows = { header, chipScroller, scroller, actions, hint };
        for (var i = 0; i < rows.Length; i++) { Grid.SetRow(rows[i], i); panel.Children.Add(rows[i]); }

        // After ✓ Use this the flyout is one bar; Change reopens the panel.
        resultText = new TextBlock { VerticalAlignment = VerticalAlignment.Center };
        AutomationProperties.SetLiveSetting(resultText, AutomationLiveSetting.Polite);
        resultBar = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        resultBar.Children.Add(resultText);
        resultBar.Children.Add(MakeButton("Change", () => result = null));

        var content = new Grid();
        content.Children.Add(panel);
        content.Children.Add(resultBar);
        content.PreviewKeyDown += (_, e) => { if (e.Key == VirtualKey.Escape) { e.Handled = true; Close(); } };
        return content;
    }

    private Slider AddSlider(Panel parent, string label, double max, Func<double, CardConfig> edit)
    {
        var readout = new TextBlock();
        // The slider already reports its value to Narrator; keep the readout out of the tree.
        AutomationProperties.SetAccessibilityView(readout, AccessibilityView.Raw);
        var slider = new Slider { Header = label, Minimum = 0, Maximum = max, StepFrequency = 1, Tag = readout };
        slider.ValueChanged += (_, e) =>
        {
            readout.Text = $"{e.NewValue:0}";
            if (!refreshing && shown != "original") Edit(edit(Math.Round(e.NewValue)));
        };
        parent.Children.Add(slider);
        parent.Children.Add(readout);
        return slider;
    }

    private Button MakeButton(string label, Action action)
    {
        var button = new Button { Content = label };
        button.Click += (_, _) => { action(); Refresh(); };
        return button;
    }

    // Brings every control in line with Now, the favorites, and the shown chip.
    private void Refresh()
    {
        if (flyout == null) return;
        refreshing = true;
        var draft = getDraft();
        var editable = shown != "original"; // never edit the baseline
        panel!.Visibility = result == null ? Visibility.Visible : Visibility.Collapsed;
        resultBar!.Visibility = result == null ? Visibility.Collapsed : Visibility.Visible;
        resultText!.Text = $"✓ Sent: {result}";
        radiusSlider!.Value = draft.CornerRadius;
        spacingSlider!.Value = draft.Spacing;
        foreach (var control in draftControls!.Children.OfType<Control>()) control.IsEnabled = editable;
        foreach (var row in draftControls.Children.OfType<StackPanel>())
            foreach (var control in row.Children.OfType<Control>()) control.IsEnabled = editable;
        keepButton!.IsEnabled = shown == "draft";
        chips!.Children.Clear();
        AddChip("Original", "original");
        AddChip("Now", "draft");
        foreach (var c in candidates)
        {
            var name = c.Name;
            AddChip(name, name);
            var remove = new Button { Content = "×" };
            AutomationProperties.SetName(remove, $"Remove {name}");
            remove.Click += (_, _) => Later(() => Remove(name));
            chips.Children.Add(remove);
        }
        refreshing = false;
    }

    private void AddChip(string label, string target)
    {
        var chip = new ToggleButton { Content = label, IsChecked = shown == target };
        chip.Click += (_, _) => Later(() => Show(target));
        chips!.Children.Add(chip);
    }

    // The chips are rebuilt by Refresh; do that after the click, not inside it.
    private void Later(Action action) => tuneButton.DispatcherQueue.TryEnqueue(() => { if (flyout != null) action(); });

    // Clicking a chip shows it in the real feature.
    private void Show(string target)
    {
        if (target == "draft")
        {
            if (stash != null) setDraft(stash);
            stash = null;
        }
        else
        {
            stash ??= getDraft();
            var candidate = candidates.Find(c => c.Name == target);
            setDraft(candidate == null ? Baseline : ApplyValues(candidate.Values));
        }
        shown = target;
        Refresh();
    }

    // Every control edits Now. Moved while a favorite is shown, it loads that
    // favorite into Now first; the favorite itself does not change.
    private void Edit(CardConfig next, string? from = null)
    {
        var chipChanged = shown != "draft";
        basedOn = from ?? (shown == "draft" ? basedOn : shown);
        stash = null;
        shown = "draft";
        setDraft(next);
        if (chipChanged || from != null) Refresh();
    }

    private void SetStatus(string text) { if (status != null) status.Text = text; }

    // Always reports Now, whichever chip is shown.
    private void CopyValues()
    {
        var values = Changed(stash ?? getDraft());
        var json = Json(values);
        Log("UITUNINGLAB_VALUES", values);
        CopyText(json);
        SetStatus(json == "{}" ? "No changes from Original" : $"Copied {json}");
    }

    // Returns the new favorite, or null with a status. Keep is enabled only while
    // Now is shown, so getDraft() is Now. The persist variant writes the favorite
    // before calling Commit.
    private UITuningLabCandidate? PrepareKeep()
    {
        var values = Changed(getDraft());
        if (values.Count == 0) { SetStatus("Same as Original"); return null; }
        var same = candidates.Find(c => Json(c.Values) == Json(values));
        if (same != null) { SetStatus($"Same as {same.Name}"); return null; }
        var stem = lastPreset ?? "tweak";
        var name = stem;
        for (var i = 2; issued.Contains(name); i++) name = $"{stem}-{i}";
        return new UITuningLabCandidate(name, basedOn, values);
    }

    private void Commit(UITuningLabCandidate candidate)
    {
        candidates.Add(candidate);
        issued.Add(candidate.Name);
        logged.Add(candidate.Name);
        Log("UITUNINGLAB_CANDIDATE", candidate.AsJson());
        SetStatus($"Kept as {candidate.Name}");
    }

    private void Keep() { if (PrepareKeep() is { } c) Commit(c); }

    private void Remove(string name)
    {
        if (shown == name) Show("draft");
        candidates.RemoveAll(c => c.Name == name);
        Log("UITUNINGLAB_CANDIDATE_REMOVED", new SortedDictionary<string, object?> { ["name"] = name });
        Refresh();
    }

    // Picks the shown chip and finishes. Picking again replaces the result.
    private void UseThis()
    {
        var picked = candidates.Find(c => c.Name == shown);
        var winner = picked?.Name ?? (shown == "original" ? "original" : "draft");
        var values = picked?.Values ?? (shown == "original" ? new SortedDictionary<string, double>() : Changed(getDraft()));
        var done = new SortedDictionary<string, object?>
        {
            ["candidates"] = candidates.Select(c => c.AsJson()).ToList(),
            ["values"] = values,
            ["winner"] = winner,
        };
        Log("UITUNINGLAB_DONE", done);
        try { WriteResult(done); } catch (Exception e) { SetStatus($"Result file failed: {e.Message}"); }
        CopyText($"land {winner}");
        result = winner;
    }
}
#endif
```

## Reading the lines and waiting for the pick

`Debug.WriteLine` goes to the Visual Studio Output window when a debugger is
attached, and to `OutputDebugString`, which Sysinternals DebugView captures.
Follow `references/platform-handoff.md`: start
`Dbgview.exe /accepteula /l <file>` before launching the app, read with
`Select-String -Path <file> -Pattern UITUNINGLAB_`, and wait for
`UITUNINGLAB_DONE` by polling the same file. Anchor the wait to this session: record how many lines
the log holds when the lab opens and match only lines after that, so a Done
from an earlier session never ends the wait. (Starting a fresh DebugView log
file per session works too.)

```powershell
$file = "<log-file>"                       # the file DebugView writes with /l
$start = @(Get-Content $file).Count         # lines already there when the lab opens
while (-not ($line = Get-Content $file | Select-Object -Skip $start |
        Select-String -SimpleMatch UITUNINGLAB_DONE | Select-Object -First 1)) { Start-Sleep 3 }
$line.Line
```

When no log was captured, read the result file ✓ Use this writes:
`Get-Content "$env:LOCALAPPDATA\Packages\<package-family-name>\LocalState\.ui-tuning-lab\result.json"`
for a packaged app (its `LocalFolder`), or
`Get-Content "$env:LOCALAPPDATA\<app-name>\.ui-tuning-lab\result.json"` unpackaged.
The `ExampleApp` folder name in `LabDirectory()` stands for the app's name.

Launch for the agent path: an unpackaged app with
`.\App.exe --ui-tuning-lab-open`; a packaged app through its execution alias
with the same argument.

## Teardown

Close and Escape set `allowClose` and hide the flyout; `Closed` restores the
stashed draft, detaches its handler, drops the content, and returns focus to
Tune. The page's `Unloaded` handler calls `Release()`, which does the same when
the user navigates away with the lab open. The lab owns no timers or app-level event subscriptions; the page's
`Loaded` handler removes itself after the first load. The Tune button and its
accelerator remain while the page lives, which is the human path.

Removal at landing: delete `UITuningLabFlyout.cs` and both `#if DEBUG` blocks in
`FeaturePage.xaml.cs`, and pass `CardConfig.AppDefault`, which now holds the
winner, straight to `Feature.Apply`. Build Debug and Release.

## Persistence variant, only when requested

One `schemaVersion: 2` profile per candidate (`references/platform-handoff.md`):
packaged apps use `ApplicationData.Current.LocalFolder\.ui-tuning-lab\candidates\<name>.json`,
unpackaged apps `%LOCALAPPDATA%\<app-name>\.ui-tuning-lab\candidates\<name>.json`.
Add to the class, inside `#if DEBUG`:

```csharp
private static string CandidateDirectory() => System.IO.Path.Combine(LabDirectory(), "candidates");

// Atomic and never over an existing file: File.Move without overwrite throws if the target exists.
private static void WriteCandidate(UITuningLabCandidate c, CardConfig overrides)
{
    var dir = System.IO.Directory.CreateDirectory(CandidateDirectory()).FullName;
    var target = System.IO.Path.Combine(dir, c.Name + ".json");
    var temp = target + ".tmp";
    System.IO.File.WriteAllText(temp, Json(new SortedDictionary<string, object?>
    {
        ["basedOn"] = c.BasedOn, ["container"] = "FeaturePage.Flyout", ["name"] = c.Name, ["notes"] = "",
        ["overrides"] = new SortedDictionary<string, double>(AsMap(overrides)), ["platform"] = "windows",
        ["savedAt"] = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture), ["schemaVersion"] = 2,
        ["scope"] = new List<object?> { "appearance", "layout" },
    }));
    try { System.IO.File.Move(temp, target); } finally { System.IO.File.Delete(temp); }
}

// Every stored name is reserved, readable or not; unusable files are reported and left alone.
private (List<UITuningLabCandidate> Found, List<string> Problems) ReadStored()
{
    var found = new List<(DateTimeOffset SavedAt, UITuningLabCandidate Candidate)>();
    var problems = new List<string>();
    var dir = CandidateDirectory();
    if (!System.IO.Directory.Exists(dir)) return (new(), problems);
    foreach (var file in System.IO.Directory.GetFiles(dir, "*.json"))
    {
        var name = System.IO.Path.GetFileNameWithoutExtension(file);
        issued.Add(name);
        try
        {
            using var doc = JsonDocument.Parse(System.IO.File.ReadAllText(file));
            var p = doc.RootElement;
            var o = p.GetProperty("overrides");
            if (p.GetProperty("schemaVersion").GetInt32() != 2 || p.GetProperty("platform").GetString() != "windows"
                || p.GetProperty("name").GetString() != name)
                throw new FormatException("incompatible schema, platform, or name");
            var values = Changed(new CardConfig(o.GetProperty("cornerRadius").GetDouble(), o.GetProperty("spacing").GetDouble()));
            if (values.Count == 0) throw new FormatException("matches the baseline");
            // Sort by instant, not by string: "…24Z" and "…24.5Z" do not compare as text.
            var savedAt = p.TryGetProperty("savedAt", out var s) && DateTimeOffset.TryParse(s.GetString(),
                CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var t) ? t : DateTimeOffset.MinValue;
            var from = p.TryGetProperty("basedOn", out var b) ? b.GetString() ?? "baseline" : "baseline";
            found.Add((savedAt, new UITuningLabCandidate(name, from, values)));
        }
        catch (Exception e) { problems.Add($"{name} ({e.Message})"); }
    }
    return (found.OrderBy(f => f.SavedAt).Select(f => f.Candidate).ToList(), problems);
}
```

Wiring: `Keep` becomes
`if (PrepareKeep() is { } c) { try { WriteCandidate(c, getDraft()); Commit(c); } catch (Exception e) { SetStatus($"Keep failed: {e.Message}"); } }`,
so a failed write refuses the Keep. `Remove` deletes `<dir>\<name>.json` first
and stops with a status on failure. `Open` calls `ReadStored()`, adds found
candidates not already listed, and shows the problems in the status line before
logging unlogged candidates. Validate a file with
`sh <skill-dir>/scripts/verify.sh profile <file>` (from WSL or Git Bash).

## Manual gate check

`verify.sh source-gates` does not read C# and reports `N/A`, which is never a
pass (`references/platform-handoff.md`, "Gates the source linter cannot see"):

1. `UITuningLabFlyout.cs` starts with `#if DEBUG` and ends with `#endif`, and
   every page reference to it sits inside `#if DEBUG`.
2. `dotnet build -c Release`, then search every Release copy of the app
   assembly. `-Path` with `**` does not recurse, so enumerate the files
   first, and fail when none is found: an empty search is not a pass. Type
   names are UTF-8 in the assembly and string literals are UTF-16, so search
   both encodings, and include the literals (`UITUNINGLAB_`, `ui-tuning-lab`),
   not just the type marker:

   ```powershell
   $assembly = "App.dll"                    # the app's assembly name
   $patterns = "UITuningLab", "UITUNINGLAB_", "ui-tuning-lab"
   $files = @(Get-ChildItem bin -Recurse -Filter $assembly | Where-Object FullName -like "*\Release\*")
   if ($files.Count -eq 0) { throw "No Release $assembly under bin: the check did not run" }
   $hits = @($files | Select-String -SimpleMatch -Pattern $patterns) +
           @($files | Select-String -SimpleMatch -Encoding Unicode -Pattern $patterns)
   if ($hits.Count -gt 0) { $hits | ForEach-Object Line; throw "Lab strings found in Release" }
   "clean: $($files.Count) assemblies searched"
   ```
3. A Release build launched with `--ui-tuning-lab-open` opens nothing, shows no
   Tune button, and ignores `Ctrl+Shift+L`.

## Version notes

- If light dismiss still swallows the first click on the feature, use a `Popup`
  with `IsLightDismissEnabled = false` anchored to the button, with the same
  content and teardown.
- A packaged app launched through its execution alias may receive arguments
  through `AppInstance.GetCurrent().GetActivatedEventArgs()` rather than
  `Environment.GetCommandLineArgs()`; read both.
- If DebugView shows nothing without a debugger attached, attach the Visual
  Studio debugger and read the Output window.
- For the release search, Sysinternals `strings` works too.
