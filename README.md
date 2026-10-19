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
- `!Space`: Window search for the current snap area
- `!Backspace` or `!Delete`: Remove current snap area
- `!+o`: Briefly show all snap areas
- `!+a`: Collect all windows into the active snap area
- `^#!a`: Collect windows across all snap areas (assign by intersection)
- `^+Up` / `^+Down`: Cycle windows within the current leaf (prev/next)
- `!+Plus` (top row or numpad): Split current leaf vertically
- `!+Minus` (top row or numpad): Split current leaf horizontally
- `!+ArrowKeys`: Adjust boundary of the current split group
- `^!h`: Toggle highlight overlay
- `^!r`: Reload script
- `^!/?`: Toggle hotkey overlay while held (vkBF)
- `^!w`: Toggle window pills overlay
- `^!b`: Open AutoSnap blacklist menu for the active window (process+class, class, title RegEx, class+title RegEx)
- `^!p`: Pause/resume hotkeys and timers
- `^!q`: Quit script

### Alt Mouse/Scroll Gestures

- `Alt + Left‑Drag`: Move window under mouse
- `Alt + Right‑Drag`: Resize window under mouse (corner based on start)
- `Alt + WheelDown` or `Alt + XButton2`: Minimize window under mouse
- `Alt + Ctrl + Win + +/-`: Adjust active window transparency by ±15
- `Alt + Win + WheelUp/Down`: Adjust active window transparency by ±15

### Layout Presets (per current monitor)

- `^#!1`: Fullscreen (single leaf)
- `^#!2`: 50/50 vertical split
- `^#!3`: 33/33/33 vertical split
- `^#!4`: 2x2 quadrants
- `^#!5`: 25/50/25 vertical split
- `^#!6`: 70/30 vertical split
- `^#!0`: Set all monitors to 50/50

## Configuration

Most defaults live near the top of `WinSnap.ahk` and control split behavior, overlay appearance, logging, and more. Notable options:

- `DefaultSplitX`, `DefaultSplitY`, `SplitStep`, `MinFrac`, `MaxFrac`, `SnapGap`
- Highlight: `HighlightEnabled`, `BorderPx`
- Window pills: `WindowPillsEnabled`, `WindowPillsMaxTitle`, `WindowPillsOpacity`, `WindowPillsFont`, `WindowPillsFontSize`, `WindowPillsShowIcons`, etc.
- Logging: `LoggingEnabled`, `LoggingLevel`, `LoggingPath`

Adjust these to taste and reload the script (`^!r`).

## Multi-Monitor Behaviour

AutoHotkey addresses monitors by a volatile index (1..N). WinSnap therefore maps each monitor to a stable key (the display device interface ID, falling back to device name + resolution) in `modules/WinSnap_Monitors.ahk`.

- Layouts are persisted per stable key (file format v2: `{"version": 2, "monitors": {"<key>": {...}}}`). Old index-based files are migrated on first load.
- On `WM_DISPLAYCHANGE` / work-area changes (debounced ~700 ms) all index-based state (layouts, window↔area mapping, selection, pill reserves, frame caches) is re-keyed to the new indices.
- Layouts of unplugged monitors are parked in memory and in the layout file; they are restored when the monitor returns. Windows that were on the unplugged monitor are assigned to the snap area Windows moved them into, and moved back to their old area when the monitor reappears.
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
