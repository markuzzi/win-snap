# WinSnap (AutoHotkey v2)

WinSnap is a Windows window-tiling and snapping script built with AutoHotkey v2. It brings flexible, keyboard‑driven layouts, fast window movement, adjustable splits, overlays, and handy power‑user gestures (drag/resize with Alt, quick transparency, window search, and more).

The script organizes each monitor into “leaves” (snap areas) that you can split horizontally/vertically, navigate with arrows, and expand across neighbors. Layouts persist between runs and can be customized on the fly.

## Features

- Grid/snapping per monitor with adjustable splits
- Keyboard navigation and expand/shrink across neighbors
- Layout presets (e.g., 50/50, 2x2, 70/30)
- Highlight overlay for current snap area and optional window pills overlay (left-click activate, right-click blacklist)
- Window search within the active snap area
- Drag-move and drag-resize using Alt mouse gestures
- Quick transparency controls for the active window
- Persistent layouts stored in `WinSnap_layouts.json`, keyed by a stable monitor ID (survives index changes)
- Multi-monitor hotplug handling: unplugging/replugging monitors re-keys all state, parks the layout of the missing monitor and restores it (including displaced windows) when it returns
- Logging to `WinSnap.log` for troubleshooting

## Versioning

Releases are tagged in git (`v1.0.0` and up). The running version is shown in the tray tooltip and in the hotkey overlay (`WinSnapVersion` in `WinSnap.ahk`).

## Requirements

- Windows 10/11
- AutoHotkey v2 (2.0+)

## Getting Started

1. Install AutoHotkey v2 from the official site.
2. Clone or download this repository.
3. Double‑click `WinSnap.ahk` to run, or launch it via AutoHotkey v2.

Optional: Compile to a standalone `.exe` with Ahk2Exe (bundled with AHK v2) if you prefer a single binary.

## Core Hotkeys

Legend: `#` = Win, `!` = Alt, `^` = Ctrl, `+` = Shift

- `#Left` / `#Right` / `#Up` / `#Down`: Move active window through the grid
- `#^Up` / `#^Down`: Alternate vertical move
- `#+Up`: Maximize active window and place window pills behind it
- `#+Down`: Restore active window (if previously snapped, return it to its previous snap area)
- `#+Right` / `#+Left`: Expand across right/left neighbor (and reduce back)
- `#^+Up` / `#^+Down`: Expand across up/down neighbor
- `!Left` / `!Right` / `!Up` / `!Down`: Switch active snap area (focus top window)
- `#Space`: Window search for the current snap area
- `!Backspace` or `!Delete`: Remove current snap area
- `!+o`: Briefly show all snap areas
- `!+a`: Collect all windows into the active snap area
- `^#!a`: Collect windows across all snap areas (assign by intersection)
- `^+Up` / `^+Down`: Cycle windows within the current leaf (prev/next)
- `#1` .. `#9` (top row or numpad): Activate the n-th window of the current leaf (same order as the pills); only intercepted while the leaf holds more than one window, otherwise Win+number reaches the Windows taskbar as usual
- `!+Plus` (top row or numpad): Split current leaf vertically (active window moves into the new right half)
- `!+Minus` (top row or numpad): Split current leaf horizontally (active window moves into the new bottom half)
- `!+ArrowKeys`: Adjust boundary of the current split group
- `^!h`: Toggle highlight overlay
- `^!r`: Reload script
- `^!#` (vkBF, `/?` on US layouts): Toggle the hotkey overlay. Rows marked with `>` run the function directly (maximize/restore, split, collect, toggles, presets, ...): click them, or move the selection with `Up`/`Down` (`Left`/`Right` switches the column) and confirm with `Enter`; `Esc` closes
- `^#!#` (vkBF): Toggle the layout overlay: shows the current layout of the active monitor with its area numbers plus a preview of every preset. While it is open, the bare preset key (`1`..`7`, `0`), a click on a tile, or arrow keys + `Enter` applies the preset; `Esc` closes
- `^!w`: Toggle window pills overlay
- `^!f`: Toggle focus mode (dims all windows except the active one and its popups; WinSnap overlays stay undimmed)
- `^!z`: Toggle zen mode (same as focus mode, but inactive windows are hidden completely; pressing the other hotkey switches modes)
- `^!b`: Open AutoSnap blacklist menu for the active window (process+class, class, title RegEx, class+title RegEx)
- `^!p`: Pause/resume hotkeys and timers
- `^#!q`: Quit script

### Alt Mouse/Scroll Gestures

- `Alt + Left‑Drag`: Move window under mouse
- `Alt + Right‑Drag`: Resize window under mouse (corner based on start)
- `Alt + WheelDown` or `Alt + XButton2`: Minimize window under mouse
- `Alt + Ctrl + Win + +/-`: Adjust active window transparency by ±15
- `Alt + Win + WheelUp/Down`: Adjust active window transparency by ±15

### Layout Presets (per current monitor)

Defined in `modules/WinSnap_LayoutPresets.ahk`; preview them with `^#!#` (layout overlay).

- `^#!1`: Fullscreen (single leaf)
- `^#!2`: 50/50 vertical split
- `^#!3`: 33/33/33 vertical split
- `^#!4`: 2x2 quadrants
- `^#!5`: 25/50/25 vertical split
- `^#!6`: 20/60/20 vertical split
- `^#!7`: 70/30 vertical split
- `^#!0`: Set all monitors to 50/50

Each monitor remembers which window sat in which area per preset: switching from preset A to B stores A's window assignment, and applying A again restores it (windows are matched by handle, falling back to process/class/title after a restart). Adjusting split boundaries keeps the preset identity; splitting or deleting an area turns the layout into a free layout without preset memory. Assignments persist in `WinSnap_PresetAssignments.json`, the active preset per monitor in `WinSnap_layouts.json`.

## Configuration

Most defaults live near the top of `WinSnap.ahk` and control split behavior, overlay appearance, logging, and more. Notable options:

- `DefaultSplitX`, `DefaultSplitY`, `SplitStep`, `MinFrac`, `MaxFrac`, `SnapGap`
- Highlight: `HighlightEnabled`, `BorderPx`
- Focus mode: `FocusModeEnabled`, `FocusModeOpacity`, `FocusModeColor`, `FocusModeInterval`
- Zen mode: `ZenModeEnabled`, `ZenModeOpacity`, `ZenModeColor`
- Window pills: `WindowPillsEnabled`, `WindowPillsMaxTitle`, `WindowPillsOpacity`, `WindowPillsFont`, `WindowPillsFontSize`, `WindowPillsShowIcons`, etc.
- Logging: `LoggingEnabled`, `LoggingLevel`, `LoggingPath`

Adjust these to taste and reload the script (`^!r`).

## Multi-Monitor Behaviour

AutoHotkey addresses monitors by a volatile index (1..N). WinSnap therefore maps each monitor to a stable key (the display device interface ID, falling back to adapter name + physical resolution) in `modules/WinSnap_Monitors.ahk`.

- Layouts are persisted per stable key (file format v2: `{"version": 2, "monitors": {"<key>": {...}}, "aliases": {...}}`). Old index-based files are migrated on first load.
- Right after a hotplug or a wake from sleep, Windows often does not report the device interface ID yet. WinSnap then waits (up to 3 × 1 s) before applying the change, and otherwise resolves the monitor through a learned alias (`aliases`: fallback key → last known device ID) so that the correct layout is restored instead of a fresh one.
- On `WM_DISPLAYCHANGE` / work-area changes (debounced ~700 ms) all index-based state (layouts, window↔area mapping, selection, pill reserves, frame caches) is re-keyed to the new indices. The monitor registry is only rebuilt inside this handler; a change detected elsewhere just schedules it. Changes arriving while the handler runs are applied in a second pass.
- Layouts of unplugged monitors are parked in memory and in the layout file; they are restored when the monitor returns. Windows that were on the unplugged monitor wait 5 s (grace period) before they are assigned to the snap area Windows moved them into; if the monitor comes back earlier (typical for wake/dock), they move straight back to their old area.
- Monitor lookup for windows and points uses `MonitorFromWindow` / `MonitorFromPoint`, so windows overlapping the taskbar or partially off-screen resolve to the correct monitor.

## Persistence and Logs

- Layouts persist in `WinSnap_layouts.json` in the repo folder. Delete that file to reset layouts.
- AutoSnap blacklist rules persist in `WinSnap_BlackList.json`.
- Logs go to `WinSnap.log` (ignored by git). You can turn logging off via `LoggingEnabled := false`. The log is rotated to `WinSnap.log.1` once it exceeds `LoggingMaxBytes` (default 10 MB).

## Run at Startup (optional)

- Create a shortcut to `WinSnap.ahk` (or your compiled `.exe`).
- Place the shortcut in `shell:startup` or create a Task Scheduler entry (run with highest privileges if needed).

## Build a Standalone EXE

Using Ahk2Exe (installed with AutoHotkey v2):

- Open Ahk2Exe, select `WinSnap.ahk` as the script, choose an output file, and compile.
- Or from command line (adjust paths):
  - `"C:\\Program Files\\AutoHotkey\\Compiler\\Ahk2Exe.exe" /in WinSnap.ahk /out WinSnap.exe`

## Repository Structure

- `WinSnap.ahk` – main entry script
- `modules/` – modular features (layout, monitors/hotplug, selection, overlays, window search, drag‑resize, pills overlay, utils, and JSON parser `_JXON.ahk`)
- `WinSnap_layouts.json` – persisted layouts (git‑ignored)
- `WinSnap.log` – log output (git‑ignored)

## Contributing

Issues and PRs are welcome. Please keep changes minimal and focused, follow the existing code style (AutoHotkey v2), and include a short rationale in your PR description. For feature work, consider adding a brief demo or screenshots.

## Contributors

- <github@mluckey.de>

## License

MIT — see [LICENSE](./LICENSE) for details.
