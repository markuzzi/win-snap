#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn
#ErrorStdOut 'CP0'

SendMode "Input"
SetWinDelay 0

; =========================
; Konfiguration
; =========================
global DefaultSplitX := 0.50      ; Default vertikal (links/rechts)
global DefaultSplitY := 0.50      ; Default horizontal (oben/unten)
global SplitStep     := 0.05      ; Schrittweite für Alt+Shift+Pfeile
global MinFrac       := 0.15
global MaxFrac       := 0.85
global SnapGap       := 24        ; Abstand zwischen Snap-Areas (Pixel gesamt)

global HighlightEnabled := true    ; roten Rahmen anzeigen?
global BorderPx         := 3

; =========================
; Globale States
; =========================
global WinHistory  := Map()       ; hwnd -> {x,y,w,h}
global LastDir     := Map()       ; hwnd -> "left"|"right"|"top"|"bottom"|"up"
global WinToLeaf   := Map()       ; hwnd -> {mon: idx, leaf: id}
global LeafWindows := Map()       ; (mon:leaf) -> [hwnd,...]

; Layout pro Monitor:
; Layouts[mon] = { root: id, next: id, nodes: Map() }
; Node: {id, parent, split: ""|"v"|"h", frac: float, a: id, b: id}
global Layouts := Map()

; Highlight-GUIs (vier Ränder)
global HL := {init:false, top:"", bot:"", left:"", right:""}
global CurrentHighlight := {mon:0, leaf:0}
global CurrentLeafSelection := Map()    ; mon -> {leaf, source:"manual"|"auto"}
global ManualNav := {mon:0, leaf:0}
global SnapOverlay := {edges:[]}
global OverlayDuration := 1200
global SelectionFlashDuration := 350
global OverlayColor := "Navy"
global OverlayOpacity := 160
global SelectionFlashColor := "Teal"
global WindowSearch := {gui:"", edit:"", list:"", items:[], filtered:[], ctx:{}, active:false}
global FrameComp := Map()    ; Klassenname -> {L,T,R,B} Offsets fr Extended Frame Bounds-Kompensation
global FrameCompDebug := true
global FrameCompLogPath := A_ScriptDir "\WinSnap.log"
global ActivateOnAreaSwitch := true    ; Beim Snap-Area-Wechsel Fenster fokussieren? (false = nur Auswahl/Highlight)
global LoggingEnabled := true          ; Logging ein/aus
global LoggingLevel := 2               ; 0=aus, 1=INFO, 2=DEBUG, 3=TRACE
global LoggingPath := FrameCompLogPath ; Pfad zur Logdatei
global ScriptPaused := false           ; eigener Pause-Status (Hotkeys + Timer)

; =========================
; Module-Includes
; =========================
#Include ".\modules\_JXON.ahk"
#Include ".\modules\WinSnap_Utils.ahk"
#Include ".\modules\WinSnap_Highlight.ahk"
#Include ".\modules\WinSnap_Overlays.ahk"
#Include ".\modules\WinSnap_WindowSearch.ahk"
#Include ".\modules\WinSnap_Layout.ahk"
#Include ".\modules\WinSnap_LeafWindows.ahk"
#Include ".\modules\WinSnap_Selection.ahk"
#Include ".\modules\WinSnap_Grid.ahk"
#Include ".\modules\WinSnap_HotkeyOverlay.ahk"

InitTrayIcon()
TrayTip "WinSnap", "WinSnap geladen - Layouts bereit", 1500

; =========================
; Hotkeys
; =========================

#HotIf WindowSearch.active
Up:: {
    WindowSearch_MoveSelection(-1)
    return
}
Down:: {
    WindowSearch_MoveSelection(1)
    return
}
Enter:: {
    WindowSearch_Confirm()
    return
}
Esc:: {
    WindowSearch_Close()
    return
}
#HotIf

; Win+Left/Right/Up/Down: durch Grid bewegen (inkl. Auto-Split beim ersten Snap)
#Left::  GridMove("left")
#Right:: GridMove("right")
#Up::    GridMove("up")
#Down::  GridMove("down")

; Win+Ctrl+Up/Down: vertikal bewegen (Legacy)
#^Up::   GridMove("up")
#^Down:: GridMove("down")

; Win+Shift+Up: Fullscreen (erneut: UnSnap)
#+Up:: {
    win := GetActiveWindow()
    if (!win)
        return
    hwnd := win.hwnd
    if (LastDir.Has(hwnd) && (LastDir[hwnd] = "up"))
        UnSnapWindow(hwnd)
    else {
        mon := GetMonitorIndexAndArea(hwnd)
        EnsureHistory(hwnd)
        MoveWindow(hwnd, mon.left, mon.top, mon.right - mon.left, mon.bottom - mon.top)
        LastDir[hwnd] := "up"
    }
}

; Win+Shift+Down: minimieren
#+Down:: {
    win := GetActiveWindow()
    if (!win)
        return
    hwnd := win.hwnd
    HideHighlight()
    WinMinimize "ahk_id " hwnd
}

; Alt+Pfeile: Snap-Area wechseln (oberstes Fenster aktivieren)
!Left::  SwitchSnapArea("left")
!Right:: SwitchSnapArea("right")
!Up::    SwitchSnapArea("up")
!Down::  SwitchSnapArea("down")

; Alt+Space: Fenster-Suche f�r aktuelle Snap-Area
!Space:: WindowSearch_Open()

; Alt+Backspace/Delete: aktuelle Snap-Area entfernen
!Backspace::DeleteCurrentSnapArea()
!Delete::    DeleteCurrentSnapArea()

; Alt+Shift+O: alle Snap-Areas kurz hervorheben
!+o::ShowAllSnapAreasHotkey()

; Alt+Shift+A: alle Fenster in der aktiven Snap-Area einsammeln
!+a::CollectWindowsInActiveLeaf()

; Strg+Shift+Up/Down: Fenster innerhalb einer Area wechseln
^+Up::   CycleWindowInLeaf("prev")
^+Down:: CycleWindowInLeaf("next")

; ALT+SHIFT + PLUS → vertikal teilen (Top-Row + Numpad)
!+vkBB::      SplitCurrentLeaf("v")  ; VK_OEM_PLUS
!+NumpadAdd:: SplitCurrentLeaf("v")

; ALT+SHIFT + MINUS → horizontal teilen (Top-Row + Numpad)
!+vkBD::       SplitCurrentLeaf("h") ; VK_OEM_MINUS
!+NumpadSub::  SplitCurrentLeaf("h")

; ALT+SHIFT + Pfeile → NUR die Grenze der aktuellen Split-Gruppe verschieben
!+Left::  AdjustBoundaryForActive("Left")
!+Right:: AdjustBoundaryForActive("Right")
!+Up::    AdjustBoundaryForActive("Up")
!+Down::  AdjustBoundaryForActive("Down")

; Highlight toggeln
^!h:: {
    global HighlightEnabled, CurrentLeafSelection
    HighlightEnabled := !HighlightEnabled
    if (!HighlightEnabled)
        HideHighlight()
    else {
        for mon, state in CurrentLeafSelection {
            if (state.leaf) {
                ApplyLeafHighlight(mon, state.leaf)
                break
            }
        }
    }
}

; Reload-Hotkey
^!r::Reload()

; Hotkey Overlay (anzeigen solange gedrückt) – Ctrl+Alt+/? (vkBF)
^!vkBF:: {
    HotkeyOverlay_Toggle()
}

; Pause/Resume (Hotkeys und relevante Timer)
^!p:: {
    TogglePause()
}

; Script beenden
^!q:: {
    LogInfo("ExitApp via hotkey")
    ExitApp()
}

TogglePause() {
    global ScriptPaused
    newState := !ScriptPaused
    ScriptPaused := newState
    try {
        Suspend(newState)
    }
    ; Timer steuern: Active-Highlight und AutoSnap-NewWindows
    try {
        SetTimer(UpdateActiveHighlight, newState ? 0 : 150)
    }
    try {
        SetTimer(AutoSnap_NewlyStartedWindows, newState ? 0 : 2000)
    }
    if (newState)
        HideHighlight()
    TrayTip "WinSnap", newState ? "Pausiert" : "Aktiv", 1000
    LogInfo(Format("TogglePause: {}", newState ? "paused" : "resumed"))
    UpdateTrayTooltip()
}

; =========================
; Layout Preset Hotkeys (pro aktueller Monitor)
; =========================

; Helper to get current monitor index
GetCurrentMonitorIndex() {
    win := GetActiveWindow()
    if (win) {
        mi := GetMonitorIndexAndArea(win.hwnd)
        return mi.index
    }
    return 1
}

; Alt+Ctrl+Win+1: Fullscreen (ein Leaf)
^#!1:: {
    mon := GetCurrentMonitorIndex()
    Layout_ResetMonitor(mon)
    LogInfo(Format("Preset: Fullscreen on mon={}", mon))
}

; Alt+Ctrl+Win+2: 50/50 vertikal
^#!2:: {
    mon := GetCurrentMonitorIndex()
    Layout_SetMonitorColumns(mon, [1, 1])
    LogInfo(Format("Preset: 50/50 on mon={}", mon))
}

; Alt+Ctrl+Win+3: 33/33/33 vertikal
^#!3:: {
    mon := GetCurrentMonitorIndex()
    Layout_SetMonitorColumns(mon, [1, 1, 1])
    LogInfo(Format("Preset: 33/33/33 on mon={}", mon))
}

; Alt+Ctrl+Win+4: 2x2 Quadranten
^#!4:: {
    mon := GetCurrentMonitorIndex()
    Layout_SetMonitorQuadrants(mon)
    LogInfo(Format("Preset: Quadrants on mon={}", mon))
}

; Alt+Ctrl+Win+5: 25/50/25 vertikal
^#!5:: {
    mon := GetCurrentMonitorIndex()
    Layout_SetMonitorColumns(mon, [1, 2, 1])
    LogInfo(Format("Preset: 25/50/25 on mon={}", mon))
}

; Alt+Ctrl+Win+6: 70/30 vertikal
^#!6:: {
    mon := GetCurrentMonitorIndex()
    Layout_SetMonitorColumns(mon, [7, 3])
    LogInfo(Format("Preset: 70/30 on mon={}", mon))
}

; Alt+Ctrl+Win+0: alle Monitore 50/50
^#!0:: {
    count := MonitorGetCount()
    Loop count {
        Layout_SetMonitorColumns(A_Index, [1, 1])
    }
    LogInfo("Preset: 50/50 on all monitors")
}

; --------------------
; Tray Icon utilities
; --------------------
InitTrayIcon() {
    ico := A_ScriptDir "\WinSnap.ico"
    try {
        if (FileExist(ico))
            TraySetIcon(ico)
        else
            TraySetIcon("imageres.dll", 202)
    }
    catch {
        try TraySetIcon("shell32.dll", 44)
    }
    UpdateTrayTooltip()
}

UpdateTrayTooltip() {
    global ScriptPaused
    tip := ScriptPaused ? "WinSnap — Pausiert" : "WinSnap — Aktiv"
    try A_IconTip := tip
}
