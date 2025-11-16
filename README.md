# WinSnap (AutoHotkey v2)

WinSnap is a Windows window-tiling and snapping script built with AutoHotkey v2. It brings flexible, keyboard‑driven layouts, fast window movement, adjustable splits, overlays, and handy power‑user gestures (drag/resize with Alt, quick transparency, window search, and more).

The script organizes each monitor into “leaves” (snap areas) that you can split horizontally/vertically, navigate with arrows, and expand across neighbors. Layouts persist between runs and can be customized on the fly.

## Features

- Grid/snapping per monitor with adjustable splits
- Keyboard navigation and expand/shrink across neighbors
- Layout presets (e.g., 50/50, 2x2, 70/30)
- Highlight overlay for current snap area and optional window pills overlay
- Window search within the active snap area
- Drag-move and drag-resize using Alt mouse gestures
- Quick transparency controls for the active window
- Persistent layouts stored in `WinSnap_layouts.json`
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
- `#+Up`: Toggle fullscreen (press again to unsnap)
- `#+Down`: Minimize active window
- `#+Right` / `#+Left`: Expand across right/left neighbor (and reduce back)
- `#^+Up` / `#^+Down`: Expand across up/down neighbor
- `!Left` / `!Right` / `!Up` / `!Down`: Switch active snap area (focus top window)
- `!Space`: Window search for the current snap area
- `!Backspace` or `!Delete`: Remove current snap area
- `!+o`: Briefly show all snap areas
- `!+a`: Collect all windows into the active snap area
- `^+Up` / `^+Down`: Cycle windows within the current leaf (prev/next)
- `!+Plus` (top row or numpad): Split current leaf vertically
- `!+Minus` (top row or numpad): Split current leaf horizontally
- `!+ArrowKeys`: Adjust boundary of the current split group
- `^!h`: Toggle highlight overlay
- `^!r`: Reload script
- `^!/?`: Toggle hotkey overlay while held (vkBF)
- `^!w`: Toggle window pills overlay
- `^!b`: Toggle AutoSnap blacklist for the active window (by process)
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

## Persistence and Logs

- Layouts persist in `WinSnap_layouts.json` in the repo folder. Delete that file to reset layouts.
- Logs go to `WinSnap.log` (ignored by git). You can turn logging off via `LoggingEnabled := false`.

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
- `modules/` – modular features (layout, selection, overlays, window search, drag‑resize, pills overlay, utils, and JSON parser `_JXON.ahk`)
- `WinSnap_layouts.json` – persisted layouts (git‑ignored)
- `WinSnap.log` – log output (git‑ignored)

## Contributing

Issues and PRs are welcome. Please keep changes minimal and focused, follow the existing code style (AutoHotkey v2), and include a short rationale in your PR description. For feature work, consider adding a brief demo or screenshots.

## Contributors

- <github@mluckey.de>

## License

MIT — see [LICENSE](./LICENSE) for details.
