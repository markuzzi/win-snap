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

global BorderPx         := 3

; =========================
; Globale States
; =========================
global AppState := {
    WinHistory: Map(),            ; hwnd -> {x,y,w,h}
    LastDir: Map(),               ; hwnd -> "left"|"right"|"top"|"bottom"|"up"
    WinToLeaf: Map(),             ; hwnd -> {mon: idx, leaf: id}
    MaximizeRestoreState: Map(),  ; hwnd -> {snapped:bool, mon:idx, leaf:id}
    LeafWindows: Map(),           ; (mon:leaf) -> [hwnd,...]
    AutoSnapBlackList: Map(),     ; exe/class -> true
    ; Layout pro Monitor:
    ; Layouts[mon] = { root: id, next: id, nodes: Map() }
    ; Node: {id, parent, split: ""|"v"|"h", frac: float, a: id, b: id}
    Layouts: Map(),
    ; Highlight-GUIs (vier Ränder)
    HL: {init:false, top:"", bot:"", left:"", right:""},
    CurrentHighlight: {mon:0, leaf:0},
    CurrentLeafSelection: Map(),  ; mon -> {leaf, source:"manual"|"auto"}
    ManualNav: {mon:0, leaf:0},
    SnapOverlay: {edges:[]},
    WindowSearch: {gui:"", edit:"", list:"", items:[], filtered:[], ctx:{}, active:false},
    FrameComp: Map(),             ; Klassenname -> {L,T,R,B} Offsets fuer EFB-Kompensation
    EfbSkip: { classes: Map(), processes: Map() },      ; EFB-Korrektur komplett ueberspringen
    EfbShrinkOnly: { classes: Map(), processes: Map() }, ; EFB nur schrumpfen, nicht vergroessern
    WindowPillsReserve: Map(),    ; (mon:leaf) -> reservierte Hoehe oberhalb Area
    ; Primitive State-Flags (vorher als einzelne Globals)
    HighlightEnabled: false,
    ShellHookMsg: 0,
    OverlayDuration: 1200,
    SelectionFlashDuration: 350,
    OverlayColor: "Navy",
    OverlayOpacity: 160,
    SelectionFlashColor: "Teal",
    FrameCompDebug: true,
    FrameCompLogPath: A_ScriptDir "\WinSnap.log",
    ActivateOnAreaSwitch: true,
    LoggingEnabled: true,
    LoggingLevel: 1,
    LoggingPath: A_ScriptDir "\WinSnap.log",
    ScriptPaused: false,
    SnappedWindowsStatusPath: A_ScriptDir "\WinSnap_SnappedWindows.json",
    SnappedWindowsWritePending: false,
    LayoutSavePending: false,
    LayoutSaveDelayMs: 500,
    SuppressMoveHighlight: false
}

; Kompatibilitaets-Aliase: bestehender Modulcode kann weiter mit den bisherigen
; Globalnamen arbeiten, waehrend die Struktur zentral in AppState lebt.
global WinHistory := AppState.WinHistory
global LastDir := AppState.LastDir
global WinToLeaf := AppState.WinToLeaf
global MaximizeRestoreState := AppState.MaximizeRestoreState
global LeafWindows := AppState.LeafWindows
global AutoSnapBlackList := AppState.AutoSnapBlackList
global Layouts := AppState.Layouts
global HL := AppState.HL
global CurrentHighlight := AppState.CurrentHighlight
global CurrentLeafSelection := AppState.CurrentLeafSelection
global ManualNav := AppState.ManualNav
global SnapOverlay := AppState.SnapOverlay
global WindowSearch := AppState.WindowSearch
global FrameComp := AppState.FrameComp
global EfbSkip := AppState.EfbSkip
global EfbShrinkOnly := AppState.EfbShrinkOnly
global WindowPillsReserve := AppState.WindowPillsReserve

; Window Pills Overlay (config)
global WindowPillsEnabled := true      ; Anzeige der Fenster-Pills über SnapAreas
global WindowPillsMaxTitle := 20       ; Max. Zeichen pro Titel (abschneiden mit …)
global WindowPillsOpacity := 220       ; 0..255
global WindowPillsRadius := 10         ; Rundung der Ecken
global WindowPillsPaddingX := 8
global WindowPillsPaddingY := 4
global WindowPillsGap := 6             ; Abstand zwischen Pills
global WindowPillsMarginX := 8         ; Abstand vom Area-Rand (links/rechts)
global WindowPillsMarginY := 8         ; Abstand vom Area-Rand (oben)
global WindowPillsFont := "Segoe UI"
global WindowPillsFontSize := 9
global WindowPillsTextColor := "cBlack"
global WindowPillsActiveTextColor := "cWhite"
global WindowPillColor := "Silver"
global WindowPillColorActive := "Gray"
global WindowPillsActiveBorderColor := "Teal"
global WindowPillsActiveBorderPx := 3
global WindowPillsShowIcons := true    ; Icons in Pills anzeigen
global WindowPillsIconSize := 16       ; Icon-Größe (px)
global WindowPillsIconGap := 6         ; Abstand Icon↔Text
global WindowPillsReserveAllLeaves := true
global WindowPillsReserveDefaultPx := (2*WindowPillsMarginY) + (2*WindowPillsPaddingY) + Ceil(WindowPillsFontSize*1.6)

; Window Pills Update/Refresh behavior (reduces flicker)
global WindowPillsUpdateInterval := 300       ; ms; 0 = disable periodic updates (invalidate-only)
global WindowPillsOnDemandOnly := false       ; true = update only when layout/selection changes
global WindowPillsMinRebuildInterval := 250   ; ms guard between full rebuilds
global WindowPillsReserveChangeTolerance := 2  ; px; only reapply if change >= tolerance

; --- AppState Helper --------------------------------------------------------
StateGet(key, default := "") {
    global AppState
    try {
        if (IsObject(AppState) && AppState.HasOwnProp(key))
            return AppState.%key%
    }
    catch Error as e {
    }
    return default
}

StateSet(key, value) {
    global AppState
    if (!IsObject(AppState))
        AppState := {}
    AppState.%key% := value
    return value
}

StateToggle(key, default := false) {
    val := !!StateGet(key, default)
    val := !val
    StateSet(key, val)
    return val
}

; Drag-Snap (RButton while LButton dragging)
; Drag-Snap moved to module

; =========================
; Module-Includes
; =========================
#Include ".\modules\_JXON.ahk"
#Include ".\modules\WinSnap_Utils.ahk"
#Include ".\modules\WinSnap_Layout.ahk"        ; Load layouts BEFORE anything triggers highlights
#Include ".\modules\WinSnap_LeafWindows.ahk"
#Include ".\modules\WinSnap_Selection.ahk"
#Include ".\modules\WinSnap_Highlight.ahk"
#Include ".\modules\WinSnap_Overlays.ahk"
#Include ".\modules\WinSnap_WindowSearch.ahk"
#Include ".\modules\WinSnap_Grid.ahk"
#Include ".\modules\WinSnap_HotkeyOverlay.ahk"
#Include ".\modules\WinSnap_DragSnap.ahk"
#Include ".\modules\WinSnap_WindowPills.ahk"
#Include ".\modules\WinSnap_DragResize.ahk"
#Include ".\modules\WinSnap_App.ahk"

App_Startup()

; =========================
; Hotkeys
; =========================

; Pause/Resume (always active)
^!p:: {
    TogglePause()
}

#HotIf !StateGet("ScriptPaused", false) && WindowSearch.active
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

#HotIf !StateGet("ScriptPaused", false)

; Win+Left/Right/Up/Down: durch Grid bewegen (inkl. Auto-Split beim ersten Snap)
#Left::  GridMove("left")
#Right:: GridMove("right")
#Up::    GridMove("up")
#Down::  GridMove("down")

; Win+Ctrl+Up/Down: vertikal bewegen (Legacy)
#^Up::   GridMove("up")
#^Down:: GridMove("down")

; Win+Shift+Up: maximieren + Pills hinter das Fenster legen
#+Up:: {
    global MaximizeRestoreState, WinToLeaf
    win := GetActiveWindow()
    if (!win)
        return
    hwnd := win.hwnd

    snapped := false
    mon := 0
    leaf := 0
    if (WinToLeaf.Has(hwnd)) {
        info := WinToLeaf[hwnd]
        snapped := true
        mon := info.mon
        leaf := info.leaf
    }
    MaximizeRestoreState[hwnd] := { snapped:snapped, mon:mon, leaf:leaf }

    try {
        WindowPills_SendBehindWindow(hwnd)
    }
    catch Error as e {
        LogException(e, "Hotkey #+Up: WindowPills_SendBehindWindow failed")
    }

    try {
        WinMaximize "ahk_id " hwnd
    }
    catch Error as e {
        ; Fallback fuer Fenster/Apps, die WinMaximize ignorieren.
        monInfo := GetMonitorIndexAndArea(hwnd)
        MoveWindow(hwnd, monInfo.left, monInfo.top, monInfo.right - monInfo.left, monInfo.bottom - monInfo.top)
    }
}

; Win+Shift+Down: restore; bei gesnappten Fenstern zur alten Snap-Area zurueck
#+Down:: {
    global MaximizeRestoreState
    win := GetActiveWindow()
    if (!win)
        return
    hwnd := win.hwnd
    restoredToLeaf := false

    if (MaximizeRestoreState.Has(hwnd)) {
        st := MaximizeRestoreState[hwnd]
        if (st.snapped && st.mon && st.leaf) {
            try {
                Layout_Ensure(st.mon)
                if (Layout_Node(st.mon, st.leaf)) {
                    SnapToLeaf(hwnd, st.mon, st.leaf)
                    restoredToLeaf := true
                }
            }
            catch Error as e {
                LogException(e, "Hotkey #+Down: SnapToLeaf restore failed")
            }
        }
        MaximizeRestoreState.Delete(hwnd)
    }

    if (!restoredToLeaf) {
        try {
            if (WinGetMinMax("ahk_id " hwnd) = 1)
                WinRestore "ahk_id " hwnd
        }
        catch Error as e {
            LogException(e, "Hotkey #+Down: WinRestore failed")
        }
    }

    try {
        WindowPills_BringToFront()
    }
    catch Error as e {
        LogException(e, "Hotkey #+Down: WindowPills_BringToFront failed")
    }
}

; Win+Shift+Right: Fenster auf rechte Nachbar-Area erweitern
#+Right:: {
    ExpandWindowAcrossNeighbor("right")
}

; Win+Shift+Left: Fenster auf linke Nachbar-Area erweitern oder Reduktion bei vorheriger Rechts-Expansion
#+Left:: {
    ExpandWindowAcrossNeighbor("left")
}

; Alternative Vertikal-Expansion (Konflikt: #+Up/# +Down belegt)
#^+Up:: {
    ExpandWindowAcrossNeighbor("up")
}
#^+Down:: {
    ExpandWindowAcrossNeighbor("down")
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

; Ctrl+Alt+Win+A: alle Fenster in ihren jeweiligen Snap-Areas einsammeln
^#!a::CollectWindowsInAllLeaves()

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
    global CurrentLeafSelection
    enabled := StateToggle("HighlightEnabled", false)
    if (!enabled)
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

; =========================
; Drag-Resize/Move/Opacity (Alt modifiers)
; =========================

; Alt + Linksklick halten: Fenster unter Maus verschieben
!LButton:: {
    DR_StartAltDragMove()
}

; Alt + Rechtsklick halten: Fenstergröße ändern (Ecke abhängig von Startposition)
!RButton:: {
    DR_StartAltDragResize()
}

; Alt + Mausrad runter ODER Alt + XButton2: Fenster unter Maus minimieren
!WheelDown::DR_MinimizeUnderMouse()
!XButton2::DR_MinimizeUnderMouse()

; Alt+Ctrl+Win + Plus/Minus: aktive Fenster-Transparenz anpassen
!^#+::DR_AdjustActiveTransparency(15)
!^#-::DR_AdjustActiveTransparency(-15)

; Alt+Win + Mausrad: aktive Fenster-Transparenz anpassen
!#WheelUp::DR_AdjustActiveTransparency(15)
!#WheelDown::DR_AdjustActiveTransparency(-15)

; Toggle Window Pills overlay
^!w:: {
    WindowPills_Toggle()
}

; Ctrl+Alt+B: aktives Fenster fuer AutoSnap blacklisten/de-blacklisten
^!b:: {
    ToggleBlacklistForActiveWindow()
}

; Script beenden
^#!q:: {
    LogInfo("ExitApp via hotkey")
    ExitApp()
}

; =========================
; Layout Preset Hotkeys (pro aktueller Monitor)
; =========================

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

#HotIf
