# Windows (WinUI 3) flyout

The feature and the lab share one `CardConfig` held by the page. The baseline is
the declared default, `CardConfig.AppDefault`. All lab code lives in
`UITuningLabFlyout.cs`, wrapped in `#if DEBUG`; the page creates it inside
`#if DEBUG`, so Release compiles none of it. The panel is a `Flyout` attached to
a debug-only **Card Lab** button on the page's `CommandBar` (or on a bar the lab
creates in code when the page has none), created when it opens
and released when it closes. Never a `ContentDialog`: it is modal.

Activation (`references/activation.md`):

- **Agent:** the command-line argument `--ui-tuning-lab-open`, consumed the
  first time the page loads in this process.
- **Human:** `Ctrl+Shift+L`, a keyboard accelerator on the Card Lab button. Check
  during inspection that the app does not already use it.
- **Visible fallback:** the Card Lab button itself, with an accessible name.

The page owns the `UITuningLabFlyout` instance, so looks, `basedOn`, and the
selection survive closing the flyout. The default lab is ephemeral: looks live in
memory and the debug output only, and a name is never reused within a process.
The panel follows `references/candidates.md`. The chip row under the header
shows **Shipped** and each saved look (**Look 1**, **Look 2**, …); the selected chip is checked and outlined, and
the feature always shows it. Switching chips is the comparison. Moving a slider or applying a preset edits the
selected look in place, and a saved look keeps its edits when you switch away;
on Shipped, which is read-only, it makes unsaved changes, with no chip
outlined, until **Save & copy** keeps them as the next Look N. **Apply** (hidden after its first use) picks the selected chip and shrinks
the flyout to the result bar, and the **⋯** menu holds Copy values. Closing
keeps the selected look on screen. The hint is a grid row below the
`ScrollViewer`, so it stays visible.

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
using System.Text.RegularExpressions;
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

    private readonly Func<CardConfig> getLook;
    private readonly Action<CardConfig> setLook;
    private readonly AppBarButton tuneButton;
    // Saved looks the lab opens with. Empty by default; a later session seeds the
    // finalists kept in the project here (references/candidates.md).
    private readonly List<UITuningLabCandidate> candidates = new();
    // Every name issued, removed ones included, so a look number is never reused.
    private readonly HashSet<string> issued = new();
    // The line each look last logged, so a look logs again only after it changed.
    private readonly Dictionary<string, string> logged = new();
    // The selected chip: "original" (Shipped) or a look's name. The feature always
    // shows it.
    private string selected = "original";
    // Edits made on Shipped and not saved yet; while set, no chip is outlined.
    private SortedDictionary<string, double>? unsaved;
    private string unsavedBasedOn = "baseline";
    private string? result; // the last pick; while set, the flyout is the result bar
    // How many picks reached the agent. The first Apply reaches its waiter; after
    // it the agent no longer listens, so Apply hides and Save & copy hands the
    // pick over for the user to paste as `land <name>`. Change does not reset it.
    private int applies;
    // The result bar's second line: where Apply saved the pick, or why it could not.
    private string? saved;
    private Flyout? flyout;
    private bool allowClose;
    private bool refreshing;
    // Controls exist only while the flyout is open.
    private Grid? panel;
    private StackPanel? resultBar, chips;
    private TextBlock? resultText, savedText, status, hint;
    private Slider? radiusSlider, spacingSlider;
    private Button? saveButton, applyButton;

    public UITuningLabFlyout(Page page, Grid root, CommandBar? toolbar, Func<CardConfig> getLook, Action<CardConfig> setLook)
    {
        this.getLook = getLook;
        this.setLook = setLook;
        issued.UnionWith(candidates.Select(c => c.Name));
        tuneButton = new AppBarButton { Label = "Card Lab", Icon = new SymbolIcon(Symbol.Setting) };
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
            // of it exists in Release markup. Place it in a corner inspection found free.
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

    // The fields of a look that differ from the baseline.
    private static SortedDictionary<string, double> Changed(CardConfig look)
    {
        var base_ = AsMap(Baseline);
        return new(AsMap(look).Where(e => base_[e.Key] != e.Value).ToDictionary(e => e.Key, e => e.Value));
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

    // Hands the pick to the agent's waiter (scripts/wait-for-pick.py) at once, so
    // it resumes without a message. Fire and forget: a packaged app's loopback
    // isolation blocks it, and then the debug output carries the pick.
    private static readonly System.Net.Http.HttpClient PickClient = new() { Timeout = TimeSpan.FromSeconds(2) };
    private static async void SendPick(object payload)
    {
        try
        {
            using var body = new System.Net.Http.StringContent($"UITUNINGLAB_DONE {Json(payload)}");
            using var _ = await PickClient.PostAsync("http://localhost:47321/pick", body);
        }
        catch (Exception) { }
    }

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
        // Seeded looks log their own line the first time the lab shows them.
        foreach (var c in candidates.Where(c => !logged.ContainsKey(c.Name)).ToList()) LogPin(c);
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

    // The feature keeps the selected look: it is real state, so nothing is
    // restored. An edited look logs its new values; then the flyout and every
    // control it held are released.
    private void OnClosed(object? sender, object e)
    {
        Leave();
        if (flyout != null) { flyout.Closed -= OnClosed; flyout.Content = null; }
        flyout = null;
        panel = null; resultBar = chips = null; resultText = savedText = status = null;
        radiusSlider = spacingSlider = null; saveButton = applyButton = null;
        tuneButton.Focus(FocusState.Programmatic);
    }

    private UIElement BuildContent()
    {
        refreshing = true; // Refresh clears it once the controls hold the selected look
        var closeButton = new Button { Content = "Close" };
        closeButton.Click += (_, _) => Close();
        var more = new Button { Content = "⋯" };
        AutomationProperties.SetName(more, "More");
        var copyItem = new MenuFlyoutItem { Text = "Copy values" };
        copyItem.Click += (_, _) => CopyValues();
        more.Flyout = new MenuFlyout { Items = { copyItem } };
        var title = new TextBlock { Text = "UI tuning lab", Style = (Style)Application.Current.Resources["SubtitleTextBlockStyle"] };
        AutomationProperties.SetHeadingLevel(title, AutomationHeadingLevel.Level1);
        var header = new Grid { ColumnDefinitions = { new() { Width = new(1, GridUnitType.Star) }, new() { Width = GridLength.Auto }, new() { Width = GridLength.Auto } } };
        header.Children.Add(title);
        Grid.SetColumn(more, 1);
        header.Children.Add(more);
        Grid.SetColumn(closeButton, 2);
        header.Children.Add(closeButton);

        // The chips: Shipped, then each look. Refresh fills them and outlines the
        // selected one.
        chips = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
        var chipScroller = new ScrollViewer
        {
            Content = chips, HorizontalScrollMode = ScrollMode.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
            VerticalScrollMode = ScrollMode.Disabled, VerticalScrollBarVisibility = ScrollBarVisibility.Disabled,
        };

        // Always enabled: the controls show the selected look and edit it. On
        // Shipped, a change stays unsaved until Save & copy.
        var body = new StackPanel { Spacing = 8 };
        // Presets are actions, not states, so they are never outlined.
        var presetRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        foreach (var (key, label, value) in Presets)
        {
            var b = new Button { Content = label };
            b.Click += (_, _) => Edit(value, key);
            presetRow.Children.Add(b);
        }
        body.Children.Add(presetRow);
        radiusSlider = AddSlider(body, "Corner radius", 32, v => getLook() with { CornerRadius = v });
        spacingSlider = AddSlider(body, "Spacing", 24, v => getLook() with { Spacing = v });
        status = new TextBlock { TextWrapping = TextWrapping.Wrap };
        AutomationProperties.SetLiveSetting(status, AutomationLiveSetting.Polite);
        body.Children.Add(status);

        var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, Margin = new Thickness(0, 8, 0, 0) };
        saveButton = MakeButton("Save & copy", SaveAndCopy);
        actions.Children.Add(saveButton);
        applyButton = MakeButton("Apply", Apply);
        actions.Children.Add(applyButton);
        // Pinned below the scrolling controls, visible however long the panel grows.
        hint = new TextBlock
        {
            Text = "Save & copy to keep a look · Apply to finish",
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

        // After Apply the flyout is one bar; Change restores the whole panel.
        resultText = new TextBlock { VerticalAlignment = VerticalAlignment.Center };
        AutomationProperties.SetLiveSetting(resultText, AutomationLiveSetting.Polite);
        var resultRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        resultRow.Children.Add(resultText);
        resultRow.Children.Add(MakeButton("Change", () => result = null));
        savedText = new TextBlock { FontSize = 12, Opacity = 0.8 };
        resultBar = new StackPanel { Spacing = 4 };
        resultBar.Children.Add(resultRow);
        resultBar.Children.Add(savedText);

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
            if (!refreshing) Edit(edit(Math.Round(e.NewValue)));
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

    private UITuningLabCandidate? SelectedPin() => candidates.Find(c => c.Name == selected);

    // The selected chip is outlined, so it reads as selected without a label.
    private static void Outline(Control control, bool on)
    {
        control.BorderThickness = new Thickness(on ? 2 : 1);
        if (on) control.BorderBrush = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["AccentFillColorDefaultBrush"];
        else control.ClearValue(Control.BorderBrushProperty);
    }

    // Brings every control in line with the selected look and the looks.
    private void Refresh()
    {
        if (flyout == null) return;
        refreshing = true;
        var look = getLook();
        panel!.Visibility = result == null ? Visibility.Visible : Visibility.Collapsed;
        resultBar!.Visibility = result == null ? Visibility.Collapsed : Visibility.Visible;
        resultText!.Text = applies > 1
            ? $"Copied land {result}: paste it in chat so the agent applies it"
            : $"Applied: {ChipLabel(result!)}";
        savedText!.Text = saved ?? "";
        savedText.Visibility = saved == null ? Visibility.Collapsed : Visibility.Visible;
        // Apply reaches the agent once; after that it is hidden for good.
        applyButton!.Visibility = applies > 0 ? Visibility.Collapsed : Visibility.Visible;
        hint!.Text = applies > 0
            ? "Save & copy, then paste it in chat"
            : "Save & copy to keep a look · Apply to finish";
        radiusSlider!.Value = look.CornerRadius;
        spacingSlider!.Value = look.Spacing;
        // Shipped with no edits has nothing to keep.
        saveButton!.IsEnabled = SelectedPin() != null || unsaved != null;
        chips!.Children.Clear();
        AddChip("Shipped", "original");
        foreach (var c in candidates)
        {
            var name = c.Name;
            AddChip(ChipLabel(name), name);
            // × only on the selected look, so nothing is removed by accident.
            if (selected != name) continue;
            var remove = new Button { Content = "×" };
            AutomationProperties.SetName(remove, $"Remove {ChipLabel(name)}");
            remove.Click += (_, _) => Later(() => Remove(name));
            chips.Children.Add(remove);
        }
        refreshing = false;
    }

    // A chip's label: `Look 2` for `look-2`, Shipped for `original`, else the name.
    private static string ChipLabel(string name)
    {
        if (name == "original") return "Shipped";
        var m = Regex.Match(name, "^look-([0-9]+)$");
        return m.Success ? $"Look {m.Groups[1].Value}" : name;
    }

    // At most one chip is checked and outlined: the selected one, and none while
    // Shipped has unsaved edits.
    private void AddChip(string label, string target)
    {
        var on = selected == target && (target != "original" || unsaved == null);
        var chip = new ToggleButton { Content = label, IsChecked = on };
        Outline(chip, on);
        chip.Click += (_, _) => Later(() => Select(target));
        chips!.Children.Add(chip);
    }

    // The chips are rebuilt by Refresh; do that after the click, not inside it.
    private void Later(Action action) => tuneButton.DispatcherQueue.TryEnqueue(() => { if (flyout != null) action(); });

    // Logs a look's line when it is new or changed since it last logged.
    private void LogPin(UITuningLabCandidate c)
    {
        var line = Json(c.AsJson());
        if (logged.TryGetValue(c.Name, out var last) && last == line) return;
        logged[c.Name] = line;
        Debug.WriteLine($"UITUNINGLAB_CANDIDATE {line}");
    }

    // A look edited in place logs its new values once it is left: another chip is
    // selected, the lab closes, or Apply.
    private void Leave() { if (SelectedPin() is { } pin) LogPin(pin); }

    // Clicking a chip shows its look in the real feature. Switching chips is the
    // comparison. Clicking the selected chip only re-checks it.
    private void Select(string chip)
    {
        if (chip != selected || unsaved != null)
        {
            Leave();
            unsaved = null; // unsaved edits on Shipped are dropped
            var pin = candidates.Find(c => c.Name == chip);
            setLook(pin == null ? Baseline : ApplyValues(pin.Values));
            selected = chip;
        }
        Refresh();
    }

    // Every control edits the selected look. Shipped is read-only, so an edit on
    // it shows live as unsaved changes until Save & copy; a saved look changes in
    // place, keeps its edits when the user switches away, and a preset becomes
    // its basedOn.
    private void Edit(CardConfig next, string? preset = null)
    {
        var index = candidates.FindIndex(c => c.Name == selected);
        var wasUnsaved = unsaved != null;
        setLook(next);
        if (index < 0)
        {
            unsaved = Changed(next);
            if (preset != null) unsavedBasedOn = preset;
            // The first unsaved edit drops Shipped's outline; a preset moves the sliders.
            if (preset != null || !wasUnsaved) Refresh();
            return;
        }
        var pin = candidates[index];
        candidates[index] = pin with { BasedOn = preset ?? pin.BasedOn, Values = Changed(next) };
        // A preset moves the sliders; a slider tick needs no refresh.
        if (preset != null) Refresh();
    }

    // Keeps the current look: unsaved edits on Shipped become the next Look N,
    // selected; a selected look is logged as it is. Returns the look, or null on
    // plain Shipped.
    private UITuningLabCandidate? Keep()
    {
        if (SelectedPin() is { } pin) { LogPin(pin); return pin; }
        if (unsaved == null) return null;
        var number = issued.Select(n => Regex.Match(n, "^look-([0-9]+)$"))
            .Where(m => m.Success).Select(m => int.Parse(m.Groups[1].Value)).DefaultIfEmpty(0).Max() + 1;
        var candidate = new UITuningLabCandidate($"look-{number}", unsavedBasedOn, unsaved);
        issued.Add(candidate.Name);
        candidates.Add(candidate);
        selected = candidate.Name;
        unsaved = null;
        unsavedBasedOn = "baseline";
        LogPin(candidate);
        return candidate;
    }

    // Save & copy keeps the current look as a chip to compare and copies its land
    // code. Before the first Apply the agent is listening for Apply, so nothing
    // more happens; after it, the pick is handed over for pasting.
    private void SaveAndCopy()
    {
        if (Keep() is not { } look) return;
        if (applies > 0) { HandOver(look); return; }
        CopyText($"land {look.Name}");
        SetStatus($"Saved {ChipLabel(look.Name)} · copied land {look.Name}");
    }

    private void SetStatus(string text) { if (status != null) status.Text = text; }

    // Reports the selected look: {} for Shipped.
    private void CopyValues()
    {
        var values = SelectedPin()?.Values ?? unsaved ?? new SortedDictionary<string, double>();
        var json = Json(values);
        Log("UITUNINGLAB_VALUES", values);
        CopyText(json);
        SetStatus(json == "{}" ? "Same as Shipped" : $"Copied {json}");
    }

    // Removing the selected look selects Shipped.
    private void Remove(string name)
    {
        candidates.RemoveAll(c => c.Name == name);
        logged.Remove(name);
        Log("UITUNINGLAB_CANDIDATE_REMOVED", new SortedDictionary<string, object?> { ["name"] = name });
        if (selected == name) { selected = "original"; setLook(Baseline); }
        Refresh();
    }

    // Apply keeps unsaved edits as a look first, then hands the pick over.
    private void Apply() => HandOver(Keep());

    // Hands a pick ("original" for Shipped) to the agent and finishes. Picking
    // again replaces the result.
    private void HandOver(UITuningLabCandidate? pin)
    {
        var winner = pin?.Name ?? "original";
        var values = pin?.Values ?? new SortedDictionary<string, double>();
        var done = new SortedDictionary<string, object?>
        {
            ["candidates"] = candidates.Select(c => c.AsJson()).ToList(),
            ["values"] = values,
            ["winner"] = winner,
        };
        Log("UITUNINGLAB_DONE", done);
        SendPick(done);
        try
        {
            WriteResult(done);
            saved = $"Saved {ChipLabel(winner)} in .ui-tuning-lab/result.json";
        }
        catch (Exception e)
        {
            saved = $"Result file failed: {e.Message}";
            SetStatus(saved);
        }
        CopyText($"land {winner}");
        applies++;
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
`Select-String -Path <file> -Pattern UITUNINGLAB_`, and wait for the pick
with `python3 <skill-dir>/scripts/wait-for-pick.py --log-file <file>` in the
background, which also catches Apply's beacon in an unpackaged app. Without
Python, wait for `UITUNINGLAB_DONE` by polling the same file. Anchor the wait to this session: record how many lines
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

When no log was captured, read the result file Apply writes:
`Get-Content "$env:LOCALAPPDATA\Packages\<package-family-name>\LocalState\.ui-tuning-lab\result.json"`
for a packaged app (its `LocalFolder`), or
`Get-Content "$env:LOCALAPPDATA\<app-name>\.ui-tuning-lab\result.json"` unpackaged.
The `ExampleApp` folder name in `LabDirectory()` stands for the app's name.

Launch for the agent path: an unpackaged app with
`.\App.exe --ui-tuning-lab-open`; a packaged app through its execution alias
with the same argument.

## Teardown

Close and Escape set `allowClose` and hide the flyout; `Closed` logs an edited
look's new values (the feature keeps the selected look), detaches its handler, drops the content, and returns focus to
Card Lab. The page's `Unloaded` handler calls `Release()`, which does the same when
the user navigates away with the lab open. The lab owns no timers or app-level event subscriptions; the page's
`Loaded` handler removes itself after the first load. The Card Lab button and its
accelerator remain while the page lives, which is the human path.

Removal at landing: delete `UITuningLabFlyout.cs` and both `#if DEBUG` blocks in
`FeaturePage.xaml.cs`, and pass `CardConfig.AppDefault`, which now holds the
winner, straight to `Feature.Apply`. Build Debug and Release.

## Persistence variant, only when requested

One `schemaVersion: 2` profile per look (`references/platform-handoff.md`),
written on Save & copy and again whenever it logs new values (leaving it after an edit), and
deleted by ×:
packaged apps use `ApplicationData.Current.LocalFolder\.ui-tuning-lab\candidates\<name>.json`,
unpackaged apps `%LOCALAPPDATA%\<app-name>\.ui-tuning-lab\candidates\<name>.json`.
Add to the class, inside `#if DEBUG`:

```csharp
private static string CandidateDirectory() => System.IO.Path.Combine(LabDirectory(), "candidates");

// Atomic: a temporary file, then a replacing move over the look's last profile.
private static void WriteCandidate(UITuningLabCandidate c)
{
    var overrides = ApplyValues(c.Values);
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
    try { System.IO.File.Move(temp, target, overwrite: true); } finally { System.IO.File.Delete(temp); }
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

Wiring: `LogPin` gains a `bool store = true` parameter and ends with
`if (store) { try { WriteCandidate(c); } catch (Exception e) { SetStatus($"{c.Name} not saved: {e.Message}"); } }`,
so every `UITUNINGLAB_CANDIDATE` line (creation, and leaving a look after an
edit) writes the profile, and a failed write shows in the status line while the
look stays in the panel. `Remove` deletes `<dir>\<name>.json` first and stops
with a status on failure. `Open` calls `ReadStored()`, adds found candidates not
already listed, and shows the problems in the status line before logging
unlogged candidates with `LogPin(c, store: false)`, so loaded looks are not
written again. Validate a file with
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
   Card Lab button, and ignores `Ctrl+Shift+L`.

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
