# Example — macOS panel (minimal tier)

Borderless nonactivating `NSPanel` hosting the lab. `orderOut` on hide
removes it from compositing. Smoke-tested: open, toggle one variant,
close, confirm no timers survive.

Key points: `isFloatingPanel = true`, `animationBehavior = .none`,
lazy `ensurePanel()`, `NSHostingView` root, DEBUG-only menu item plus
hotkey. Never a modal sheet over the tuned window.
