#Requires AutoHotkey v2.0
#SingleInstance Force
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
global SnapGap       := 12        ; Abstand zwischen Snap-Areas (Pixel gesamt)

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

TrayTip "WinSnap", "WinSnap geladen – Layouts bereit", 1500

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
    if !win
        return
    hwnd := win.hwnd
    if LastDir.Has(hwnd) && (LastDir[hwnd] = "up")
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
    if !win
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
    if !HighlightEnabled
        HideHighlight()
    else {
        for mon, state in CurrentLeafSelection {
            if state.leaf {
                ApplyLeafHighlight(mon, state.leaf)
                break
            }
        }
    }
}

; Reload-Hotkey
^!r::Reload()
