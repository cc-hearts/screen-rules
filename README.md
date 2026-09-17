<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/logo-dark.png">
    <img src="docs/logo.png" width="160" alt="ScreenRules logo">
  </picture>
</p>

<h1 align="center">ScreenRules</h1>

<p align="center">
  A tiny macOS menu bar app that forces each app's windows onto <b>the display you choose</b>, at <b>the size you choose</b>.<br>
  <a href="README.zh-CN.md">简体中文文档</a>
</p>

## Why

macOS opens almost every new window on the **main display**. With two (or more) monitors, that means constantly dragging windows to the other screen. The built-in Dock → "Assign to Desktop on Display N" option is tied to Spaces and behaves inconsistently.

ScreenRules fixes this with per-app rules:

- **Display rule** — an app's new windows open on the main or the secondary display
- **Size rule** — optionally resize windows to a percentage (50–100%) of the target display, centered
- **Force mode for stubborn apps** — apps that reposition their own window (e.g. on Dock click) get re-corrected by multi-pass enforcement after activation: 0.3s / 1.2s / 3s
- Only standard main windows are managed — IME candidate popups, dialogs, drawers and floating panels are never touched

## Install & Run

Requires macOS 13+ and the Swift toolchain (Xcode Command Line Tools are enough — no Xcode project involved).

```sh
git clone https://github.com/cc-hearts/screen-rules.git
cd screen-rules
./run.sh        # build + (re)launch
```

Then grant **Accessibility permission** when prompted (System Settings → Privacy & Security → Accessibility). The app detects the grant automatically within ~1.5s — no restart needed.

## Usage

1. Bring the app you want to tame to the foreground
2. Click the ScreenRules icon in the menu bar → the "Current App: xxx" submenu
3. Pick a display (Main / Secondary) and/or a window size (50%–100% of the target display's visible area, centered)
4. Rules apply instantly to already-open windows; every new window follows from then on

Other menu items: "Apply all rules now" snaps every ruled app's windows into place, "Open rules file…" reveals the JSON config, "Open debug log…" shows every observed event and move result.

> [!NOTE]
> The menu bar UI is currently Chinese-only; the item names above are translations.

Rules are stored in `~/Library/Application Support/ScreenRules/rules.json`.

## How it works

- Observes `kAXWindowCreatedNotification` via `AXObserver` on every regular app, plus `NSWorkspace` launch / activate / terminate events
- On window creation: apply the rule after 0.25s and 1s (many apps reposition themselves right after creating a window — the second pass wins)
- On app activation (covers Dock-click reopens, which don't create windows): three enforcement passes at 0.3s / 1.2s / 3s
- Moving preserves window size and relative position; size rules scale to the target display's visible frame and center
- Displays are matched by **main / secondary semantics**, not hardware IDs — replugging monitors or swapping cables never breaks rules
- Signed with a stable self-signed certificate (`.signing/`, git-ignored), so Accessibility permission survives rebuilds

Pure SwiftPM / AppKit, ~500 lines, zero dependencies.

## Known limitations

- Windows of apps running as another user (or with different privileges) can't be touched
- Fullscreen windows are ignored by design
- A few apps create non-standard windows that reject repositioning; check the debug log if one misbehaves

## License

[MIT](LICENSE)
