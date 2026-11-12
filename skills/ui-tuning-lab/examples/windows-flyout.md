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

The page owns the `UITuningLabFlyout` instance, so looks, the unsaved edits
with their history, and the selection survive closing the flyout. The default
lab is ephemeral: looks live in memory and the debug output only, and a name is
never reused within a process. The panel follows `references/candidates.md`.
The chip row under the header shows **Shipped** and each pinned look, named
after its preset (**Compact-1**, **Relaxed-1**, **Custom-1**); the selected chip
is checked and outlined, and the feature always shows it. Switching chips is
the comparison. Every chip is read-only, a pinned look included: moving a
slider or applying a preset forks the selected chip into unsaved changes that
start from its values, with no chip outlined, until **Save & pin** keeps them as
a new look (an edit on **Compact-1** pins as **Compact-2**); the chip it came
from never changes, and clicking a chip drops the unsaved changes. The edit row
under the controls holds **Undo**, **Redo**, and **Reset**, each disabled when
it cannot act. They work on the unsaved changes, back to the chip they were
forked from, which is outlined again, and a slider drag is one step. Each slider marks the Shipped value with a tick under its
track, on every chip (WinUI draws only evenly spaced ticks, so the lab overlays
it); a drag near it snaps to it exactly, the arrow keys still reach the values
beside it, and the readout reads `14 · default 12` while the value differs.
**↺** beside a changed slider, or a double-click on its label, puts that one
control back to Shipped as one Undo step (`references/control-mapping.md`, "Default marker and per-control reset"). `Ctrl+Z` and `Ctrl+Y` run Undo and Redo as keyboard
accelerators whose scope is the flyout content, so they work only while focus is
inside the panel and never reach the app. **Apply** (hidden after its first use)
pins unsaved changes first, picks the selected chip, and shrinks the flyout to the result bar.
The **⋯** menu holds Copy values. Closing keeps the selected look on screen. The
hint is a grid row below the `ScrollViewer`, so it stays visible.

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
    // One point in the unsaved edits' history: what it showed, and where it came from.
    private sealed record Step(CardConfig Value, string BasedOn);
    // Undo and Redo steps of the unsaved edits, back to the chip they were forked from.
    private readonly List<Step> undoSteps = new(), redoSteps = new();
    // The control of the newest step, so a drag stays one step.
    private string? lastControl;
    // Every name issued, removed ones included, so a look number is never reused.
    private readonly HashSet<string> issued = new();
    // The line each look last logged, so a look logs once.
    private readonly Dictionary<string, string> logged = new();
    // The selected chip: "original" (Shipped) or a look's name. The feature shows
    // it, or the unsaved edits forked from it.
    private string selected = "original";
    // Edits not pinned yet, forked from the selected chip; while set, no chip is
    // outlined. The chip itself never changes.
    private CardConfig? unsaved;
    private string unsavedBasedOn = "baseline";
    private string? result; // the last pick; while set, the flyout is the result bar
    // How many picks reached the agent. The first Apply reaches its waiter; after
    // it the agent no longer listens, so Apply hides and Save & pin also hands
    // the pick over for the user to paste as `land <name>`. Change does not reset
    // it.
    private int applies;
    // The result bar's second line: where the pick was saved, or why it could not.
    private string? saved;
    // Whether the last pick's land code reached the clipboard.
    private bool copied;
    // A failed profile write during the current pin, so the next status keeps it.
    private string? storeError;
    private Flyout? flyout;
    private bool allowClose;
    private bool refreshing;
    // Controls exist only while the flyout is open.
    private Grid? panel;
    private StackPanel? resultBar, chips;
    private TextBlock? resultText, savedText, status, hint;
    // Each slider's refresh: shows a look's value, readout, and ↺.
    private readonly List<Action<CardConfig>> sliders = new();
    private Button? saveButton, applyButton, undoButton, redoButton, resetButton;

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

    // The clipboard can be held by another app (COMException); false then.
    private static bool CopyText(string text)
    {
        try
        {
            var package = new DataPackage();
            package.SetText(text);
            Clipboard.SetContent(package);
            return true;
        }
        catch (Exception) { return false; }
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
    // restored. The flyout and every control it held are released.
    private void OnClosed(object? sender, object e)
    {
        if (flyout != null) { flyout.Closed -= OnClosed; flyout.Content = null; }
        flyout = null;
        panel = null; resultBar = chips = null; resultText = savedText = status = null;
        sliders.Clear(); saveButton = applyButton = undoButton = redoButton = resetButton = null;
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

        // Always enabled: the controls show the selected look; a change forks it
        // into unsaved edits until Save & pin. Sliders pass their key, so a drag
        // is one Undo step; presets pass none.
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
        AddSlider(body, "Corner radius", "cornerRadius", 32, c => c.CornerRadius, (c, v) => c with { CornerRadius = v });
        AddSlider(body, "Spacing", "spacing", 24, c => c.Spacing, (c, v) => c with { Spacing = v });
        status = new TextBlock { TextWrapping = TextWrapping.Wrap };
        AutomationProperties.SetLiveSetting(status, AutomationLiveSetting.Polite);
        body.Children.Add(status);

        // Each button is disabled when it has nothing to do.
        var edits = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, Margin = new Thickness(0, 8, 0, 0) };
        undoButton = MakeButton("Undo", Undo);
        redoButton = MakeButton("Redo", Redo);
        resetButton = MakeButton("Reset", Reset);
        edits.Children.Add(undoButton);
        edits.Children.Add(redoButton);
        edits.Children.Add(resetButton);

        var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, Margin = new Thickness(0, 8, 0, 0) };
        // Save & pin, the one save button: pins the unsaved edits.
        saveButton = MakeButton("Save & pin", Save);
        actions.Children.Add(saveButton);
        applyButton = MakeButton("Apply", Apply);
        actions.Children.Add(applyButton);
        // Pinned below the scrolling controls, visible however long the panel grows.
        hint = new TextBlock
        {
            Text = "Save & pin to keep a look · Apply to finish",
            TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 0),
        };

        panel = new Grid
        {
            Width = 320, MaxHeight = 560,
            RowDefinitions = { new() { Height = GridLength.Auto }, new() { Height = GridLength.Auto },
                new() { Height = new(1, GridUnitType.Star) }, new() { Height = GridLength.Auto },
                new() { Height = GridLength.Auto }, new() { Height = GridLength.Auto } },
        };
        var scroller = new ScrollViewer { Content = body };
        FrameworkElement[] rows = { header, chipScroller, scroller, edits, actions, hint };
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
        // Ctrl+Z and Ctrl+Y act only while focus is inside the panel.
        AddAccelerator(undoButton, VirtualKey.Z, Undo, content);
        AddAccelerator(redoButton, VirtualKey.Y, Redo, content);
        return content;
    }

    // The accelerator's scope is the flyout content, so the app's own Undo wins
    // everywhere else, and a focused text box keeps its own.
    private void AddAccelerator(Button button, VirtualKey key, Action action, UIElement scope)
    {
        var accelerator = new KeyboardAccelerator { Key = key, Modifiers = VirtualKeyModifiers.Control, ScopeOwner = scope };
        accelerator.Invoked += (_, e) =>
        {
            if (FocusManager.GetFocusedElement(scope.XamlRoot) is TextBox) return;
            action();
            Refresh();
            e.Handled = true;
        };
        button.KeyboardAccelerators.Add(accelerator);
    }

    // A slider with the Shipped value marked: a tick under the track, on every
    // chip. WinUI draws only evenly spaced ticks (TickFrequency), so the tick is
    // a Rectangle laid over the track, inset by half the thumb (ThumbInset) so
    // it sits under the thumb's center at that value. A pointer drag (never the
    // arrow keys) within 1.5% of the range, or less than half a step, snaps to
    // Shipped exactly; there is no haptic on the desktop. The readout adds
    // "· default 12" while the value differs. ↺, and double-clicking the label,
    // put this control back to Shipped as one Undo step. All of it is display
    // only. ThumbInset is half the default WinUI thumb; measure it again on
    // your WinUI version or when the app restyles the slider.
    private const double ThumbInset = 10;

    private void AddSlider(Panel parent, string label, string control, double max,
        Func<CardConfig, double> read, Func<CardConfig, double, CardConfig> write)
    {
        var shipped = read(Baseline);
        var slider = new Slider { Minimum = 0, Maximum = max, StepFrequency = 1 };
        // ↺ hides once the value is Shipped's, so focus moves to the slider and
        // stays inside the panel, where Ctrl+Z still reaches Undo.
        void Reset()
        {
            ResetControl((look, original) => write(look, read(original)));
            slider.Focus(FocusState.Programmatic);
        }
        var title = new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center };
        // The label is a shortcut only: ↺ is the path Narrator and the keyboard use.
        title.DoubleTapped += (_, _) => Reset();
        // Narrator names the slider from the label, so it is not announced twice.
        AutomationProperties.SetLabeledBy(slider, title);
        var readout = new TextBlock { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 0, 0) };
        // The slider already reports its value to Narrator; keep the readout out of the tree.
        AutomationProperties.SetAccessibilityView(readout, AccessibilityView.Raw);
        var reset = MakeButton("↺", Reset);
        AutomationProperties.SetName(reset, $"Reset {label} to default, {shipped:0.##}");
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
        row.Children.Add(title);
        row.Children.Add(readout);
        row.Children.Add(reset);

        var dragging = false;
        // The slider handles pointer events itself, so listen to handled ones too.
        slider.AddHandler(UIElement.PointerPressedEvent, new PointerEventHandler((_, _) => dragging = true), true);
        slider.AddHandler(UIElement.PointerReleasedEvent, new PointerEventHandler((_, _) => dragging = false), true);
        slider.AddHandler(UIElement.PointerCaptureLostEvent, new PointerEventHandler((_, _) => dragging = false), true);
        slider.ValueChanged += (_, e) =>
        {
            if (refreshing) return;
            var distance = Math.Abs(e.NewValue - shipped);
            var snap = dragging && (distance <= max * 0.015 || distance < 0.5);
            Edit(write(getLook(), snap ? shipped : Math.Round(e.NewValue)), control: control);
        };
        var tick = new Microsoft.UI.Xaml.Shapes.Rectangle
        {
            Width = 2, Height = 6, HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 18, 0, 0), IsHitTestVisible = false,
            Fill = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
        };
        AutomationProperties.SetAccessibilityView(tick, AccessibilityView.Raw);
        var track = new Grid();
        track.Children.Add(slider);
        track.Children.Add(tick);
        track.SizeChanged += (_, e) =>
            tick.Margin = new Thickness(ThumbInset + (e.NewSize.Width - 2 * ThumbInset) * shipped / max - 1, 18, 0, 0);

        sliders.Add(look =>
        {
            var value = read(look);
            slider.Value = value;
            readout.Text = value == shipped ? $"{value:0.##}" : $"{value:0.##} · default {shipped:0.##}";
            reset.Visibility = value == shipped ? Visibility.Collapsed : Visibility.Visible;
        });
        parent.Children.Add(row);
        parent.Children.Add(track);
    }

    private Button MakeButton(string label, Action action)
    {
        var button = new Button { Content = label };
        button.Click += (_, _) => { action(); Refresh(); };
        return button;
    }

    private UITuningLabCandidate? SelectedPin() => candidates.Find(c => c.Name == selected);

    // The selected chip's look, which unsaved edits fork from.
    private Step Source() => SelectedPin() is { } pin
        ? new Step(ApplyValues(pin.Values), pin.BasedOn) : new Step(Baseline, "baseline");

    // The look the feature shows: the unsaved edits, else the selected chip.
    private CardConfig SelectedLook() => unsaved ?? Source().Value;

    // Save & pin, the one save button, and Reset need unsaved edits.
    private bool HasEdits => unsaved != null;
    private bool CanUndo => undoSteps.Count > 0;
    private bool CanRedo => redoSteps.Count > 0;

    // What the feature shows now, as a history step.
    private Step CurrentStep() => unsaved is { } value ? new Step(value, unsavedBasedOn) : Source();

    private static Step? Pop(List<Step> steps)
    {
        if (steps.Count == 0) return null;
        var step = steps[^1];
        steps.RemoveAt(steps.Count - 1);
        return step;
    }

    private void ClearHistory()
    {
        undoSteps.Clear();
        redoSteps.Clear();
        lastControl = null;
    }

    // Shows a step. Matching the chip the edits were forked from leaves no
    // unsaved edits, and that chip is outlined again.
    private void Show(Step next)
    {
        if (next.Value == Source().Value)
        {
            unsaved = null;
            unsavedBasedOn = "baseline";
        }
        else
        {
            unsaved = next.Value;
            unsavedBasedOn = next.BasedOn;
        }
    }

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
        resultText!.Text = result == null ? ""
            : applies > 1 ? (copied ? $"Copied land {result}: paste it in chat so the agent applies it"
                : $"Tell the agent: land {result}")
            : $"Applied: {ChipLabel(result)}";
        savedText!.Text = saved ?? "";
        savedText.Visibility = saved == null ? Visibility.Collapsed : Visibility.Visible;
        // Apply reaches the agent once; after that it is hidden for good.
        applyButton!.Visibility = applies == 0 ? Visibility.Visible : Visibility.Collapsed;
        hint!.Text = applies > 0
            ? "Save & pin, then paste it in chat"
            : "Save & pin to keep a look · Apply to finish";
        foreach (var show in sliders) show(look);
        saveButton!.IsEnabled = HasEdits;
        undoButton!.IsEnabled = CanUndo;
        redoButton!.IsEnabled = CanRedo;
        resetButton!.IsEnabled = HasEdits;
        chips!.Children.Clear();
        AddChip("Shipped", "original");
        foreach (var c in candidates)
        {
            var name = c.Name;
            AddChip(ChipLabel(name), name);
            // × only on the selected look, outlined, so nothing is removed by accident.
            if (selected != name || unsaved != null) continue;
            var remove = new Button { Content = "×" };
            AutomationProperties.SetName(remove, $"Remove {ChipLabel(name)}");
            remove.Click += (_, _) => Later(() => Remove(name));
            chips.Children.Add(remove);
        }
        refreshing = false;
    }

    // A chip's label: `Brass-2` for `brass-2`, `Warm Glow-1` for `warm-glow-1`,
    // Shipped for `original`; a name that does not end in `-N` shows as it is.
    private static string ChipLabel(string name)
    {
        if (name == "original") return "Shipped";
        var m = Regex.Match(name, "^(.+)-([0-9]+)$");
        if (!m.Success) return name;
        var words = m.Groups[1].Value.Split('-', StringSplitOptions.RemoveEmptyEntries)
            .Select(w => char.ToUpperInvariant(w[0]) + w[1..]);
        return $"{string.Join(" ", words)}-{m.Groups[2].Value}";
    }

    // At most one chip is checked and outlined: the selected one, and none while
    // there are unsaved edits.
    private void AddChip(string label, string target)
    {
        var on = selected == target && unsaved == null;
        var chip = new ToggleButton { Content = label, IsChecked = on };
        Outline(chip, on);
        chip.Click += (_, _) => Later(() => Select(target));
        chips!.Children.Add(chip);
    }

    // The chips are rebuilt by Refresh; do that after the click, not inside it.
    private void Later(Action action) => tuneButton.DispatcherQueue.TryEnqueue(() => { if (flyout != null) action(); });

    // Logs a look's line the first time. Only a pin logs.
    private void LogPin(UITuningLabCandidate c)
    {
        var line = Json(c.AsJson());
        if (logged.TryGetValue(c.Name, out var last) && last == line) return;
        logged[c.Name] = line;
        Debug.WriteLine($"UITUNINGLAB_CANDIDATE {line}");
    }

    // Clicking a chip shows its look in the real feature. Switching chips is the
    // comparison. Unsaved edits are dropped, so a chip always shows its look
    // exactly, the one they were forked from included. Clicking the outlined
    // chip only re-checks it.
    private void Select(string chip)
    {
        if (chip != selected || unsaved != null)
        {
            ClearHistory();
            unsaved = null;
            unsavedBasedOn = "baseline";
            selected = candidates.Exists(c => c.Name == chip) ? chip : "original";
            setLook(SelectedLook());
        }
        Refresh();
    }

    // Every control makes unsaved edits. On an outlined chip the first edit forks
    // it: the edits start from its values and basedOn, and the chip itself never
    // changes. A preset becomes their basedOn. Sliders pass `control`, their key:
    // a run of edits from the same control in a row is one Undo step. Presets
    // pass none, so each is a step.
    private void Edit(CardConfig next, string? preset = null, string? control = null)
    {
        var current = CurrentStep();
        if (next == current.Value && (preset == null || preset == current.BasedOn)) return;
        if (control == null || control != lastControl || !CanUndo) undoSteps.Add(current);
        redoSteps.Clear();
        lastControl = control;
        Show(new Step(next, preset ?? current.BasedOn));
        setLook(SelectedLook());
        Refresh();
    }

    // ↺ on one control: `restore` copies that control's fields from Shipped (a
    // spring's two sliders together). An ordinary edit: one Undo step that ends
    // the current slider run, so it never merges with a drag. On a pinned look it
    // forks unsaved edits; edits that match the chip they were forked from again
    // are dropped, and that chip is outlined.
    private void ResetControl(Func<CardConfig, CardConfig, CardConfig> restore) =>
        Edit(restore(SelectedLook(), Baseline));

    // Undo steps the unsaved edits back one, never past the chip they were forked
    // from, which is outlined again when they reach it.
    private void Undo()
    {
        if (Pop(undoSteps) is not { } previous) return;
        redoSteps.Add(CurrentStep());
        lastControl = null;
        Show(previous);
        setLook(SelectedLook());
    }

    // Redo brings back the edit Undo last took away.
    private void Redo()
    {
        if (Pop(redoSteps) is not { } next) return;
        undoSteps.Add(CurrentStep());
        lastControl = null;
        Show(next);
        setLook(SelectedLook());
    }

    // Reset drops the unsaved edits back to the chip they were forked from,
    // outlined again, in one step that Undo can take back.
    private void Reset()
    {
        if (!HasEdits) return;
        undoSteps.Add(CurrentStep());
        redoSteps.Clear();
        lastControl = null;
        Show(Source());
        setLook(SelectedLook());
    }

    // Pins the unsaved edits as a new look, named `<prefix>-N` after their
    // basedOn (`custom` for baseline), selected and outlined; the history starts
    // fresh and the look logs. Returns false with no unsaved edits.
    private bool Commit()
    {
        storeError = null;
        if (unsaved is not { } value) return false;
        var prefix = unsavedBasedOn == "baseline" ? "custom" : unsavedBasedOn;
        var number = issued.Select(n => Regex.Match(n, $"^{Regex.Escape(prefix)}-([0-9]+)$"))
            .Where(m => m.Success).Select(m => int.Parse(m.Groups[1].Value)).DefaultIfEmpty(0).Max() + 1;
        var candidate = new UITuningLabCandidate($"{prefix}-{number}", unsavedBasedOn, Changed(value));
        issued.Add(candidate.Name);
        candidates.Add(candidate);
        selected = candidate.Name;
        unsaved = null;
        unsavedBasedOn = "baseline";
        ClearHistory();
        LogPin(candidate);
        return true;
    }

    // Save & pin, the one save button: pins the unsaved edits and copies the new
    // look's land code. Before the first Apply the agent is listening for Apply,
    // so nothing more happens; after it, the pick is handed over for pasting.
    private void Save()
    {
        if (!Commit() || SelectedPin() is not { } look) return;
        if (applies > 0) { HandOver(look); return; }
        saved = null;
        var kept = $"Pinned {ChipLabel(look.Name)}";
        var line = CopyText($"land {look.Name}") ? $"{kept} · copied land {look.Name}" : $"{kept} · Tell the agent: land {look.Name}";
        SetStatus(storeError ?? line);
    }

    private void SetStatus(string text) { if (status != null) status.Text = text; }

    // Reports the selected look as shown, edits included: {} for Shipped.
    private void CopyValues()
    {
        var values = Changed(SelectedLook());
        var json = Json(values);
        Log("UITUNINGLAB_VALUES", values);
        if (!CopyText(json)) SetStatus($"Clipboard unavailable; values logged: {json}");
        else SetStatus(json == "{}" ? "Same as Shipped" : $"Copied {json}");
    }

    // Removing the selected look selects Shipped.
    private void Remove(string name)
    {
        candidates.RemoveAll(c => c.Name == name);
        logged.Remove(name);
        Log("UITUNINGLAB_CANDIDATE_REMOVED", new SortedDictionary<string, object?> { ["name"] = name });
        if (selected == name) { selected = "original"; ClearHistory(); }
        setLook(SelectedLook());
        SetStatus($"Removed {ChipLabel(name)}");
        Refresh();
    }

    // Apply pins unsaved edits first, like Save & pin, then hands the selected
    // chip over.
    private void Apply()
    {
        Commit();
        HandOver(SelectedPin());
    }

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
            if (storeError != null) SetStatus(storeError);
        }
        catch (Exception e)
        {
            saved = $"Result file failed: {e.Message}";
            SetStatus(saved);
        }
        copied = CopyText($"land {winner}");
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

Close and Escape set `allowClose` and hide the flyout; `Closed` detaches its
handler, drops the content (the feature keeps the selected look), and returns
focus to Card Lab. The Undo and Redo accelerators go with the content. The page's `Unloaded` handler calls `Release()`, which does the same when
the user navigates away with the lab open. The lab owns no timers or app-level event subscriptions; the page's
`Loaded` handler removes itself after the first load. The Card Lab button and its
accelerator remain while the page lives, which is the human path.

Removal at landing: delete `UITuningLabFlyout.cs` and both `#if DEBUG` blocks in
`FeaturePage.xaml.cs`, and pass `CardConfig.AppDefault`, which now holds the
winner, straight to `Feature.Apply`. Build Debug and Release.

## Persistence variant, only when requested

One `schemaVersion: 2` profile per look (`references/platform-handoff.md`),
written once, when a look is pinned (Save & pin, or Apply with unsaved edits), never for unsaved
edits and never again after that, and deleted by ×:
packaged apps use `ApplicationData.Current.LocalFolder\.ui-tuning-lab\candidates\<name>.json`,
unpackaged apps `%LOCALAPPDATA%\<app-name>\.ui-tuning-lab\candidates\<name>.json`.
Add to the class, inside `#if DEBUG`:

```csharp
private static string CandidateDirectory() => System.IO.Path.Combine(LabDirectory(), "candidates");

// Atomic: a temporary file, then a move into place. A pinned look never changes,
// so it is written once, when it is pinned; savedAt orders the looks when they load.
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
`if (store) { try { WriteCandidate(c); } catch (Exception e) { storeError = $"{ChipLabel(c.Name)} not saved: {e.Message}"; SetStatus(storeError); } }`,
so every `UITUNINGLAB_CANDIDATE` line (a new pin) writes the profile, and a failed write shows in the status line while the
look stays in the panel; `Save` and `HandOver` keep that line instead of their own. `Remove` deletes `<dir>\<name>.json` first and stops
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
