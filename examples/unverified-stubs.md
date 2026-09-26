# Unvalidated adaptations — Windows, Flutter, React Native

These notes are not validation claims. Complete the full protocol on the target
stack before relying on them.

- Windows (WinUI 3): `Flyout` on a debug toolbar button. Never
  `ContentDialog` for the lab. Gate `_DEBUG`, `Ctrl+Shift+L`.
- Flutter: `OverlayEntry` inserted and `remove()`d, `maintainState: false`.
  Gate `kDebugMode`. Never an always-mounted `Opacity(0)` stack.
- React Native: `DevSettings.addMenuItem` plus a `__DEV__`-gated overlay.
  Reuse the shake dev menu. Never a custom release shake listener.
