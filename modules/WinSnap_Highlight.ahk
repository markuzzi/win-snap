; =========================
; Highlight (roter Rahmen)
; =========================
; Initialisiert die GUI-Struktur fuer den Highlight-Rahmen (click-through).
HL_Init() {
    global HL
    if (HL.init)
        return
    ; Use pixel coordinates (no DPI scaling) to align with window rects
    g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale") ; click-through
    g.BackColor := "Teal"
    HL.gui := g
    HL.init := true
    LogDebug("HL_Init: highlight GUI initialized")
}

; Zeigt einen abgerundeten Rahmen um das angegebene Rechteck an.
ShowHighlightRect(rect) {
    global HL, BorderPx
    if (!StateGet("HighlightEnabled", false))
        return
    HL_Init()

    x := rect.L
    y := rect.T
    w := Max(1, rect.R - rect.L)
    h := Max(1, rect.B - rect.T)
    radius := 12
    border := BorderPx

    ; Äußere Region (Vollgröße mit runden Ecken)
    outerRgn := DllCall("CreateRoundRectRgn", "Int", 0, "Int", 0, "Int", w, "Int", h, "Int", radius, "Int", radius, "Ptr")

    ; Innere Region (kleiner, ausgeschnitten)
    innerRgn := DllCall("CreateRoundRectRgn", "Int", border, "Int", border, "Int", w - border, "Int", h - border, "Int", radius - border, "Int", radius - border, "Ptr")

    ; Differenz bilden = nur der Rand bleibt sichtbar
    combinedRgn := DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", 0, "Int", 0, "Ptr")
    DllCall("CombineRgn", "Ptr", combinedRgn, "Ptr", outerRgn, "Ptr", innerRgn, "Int", 4)  ; RGN_DIFF = 4

    ; Fensterregion setzen
    DllCall("SetWindowRgn", "Ptr", HL.gui.Hwnd, "Ptr", combinedRgn, "Int", true)

    ; GUI anzeigen
    HL.gui.Show("NA")
    HL.gui.Move(x, y, w, h)

    ; Ressourcen freigeben (nur inner & outer, combined gehört nun dem Fenster)
    DllCall("DeleteObject", "Ptr", outerRgn)
    DllCall("DeleteObject", "Ptr", innerRgn)
}

; Blendet das Highlight aus und setzt den aktuellen Zustand zurueck.
HideHighlight() {
    global HL, CurrentHighlight, AppState
    if (HL.init) {
        try {
            HL.gui.Hide()
        }
        catch Error as e {
            LogError("HideHighlight: gui.Hide failed")
        }
    }
    if (!IsObject(CurrentHighlight)) {
        CurrentHighlight := {mon:0, leaf:0}
        try {
            if (IsObject(AppState))
                AppState.CurrentHighlight := CurrentHighlight
        }
    }
    CurrentHighlight.mon := 0
    CurrentHighlight.leaf := 0
    LogDebug("HideHighlight: hidden")
}


; Zeigt das Highlight fuer die angegebene Leaf-Area (oder entfernt es).
ApplyLeafHighlight(mon, leafId) {
    global CurrentHighlight, Layouts, CurrentLeafSelection, AppState
    if (!StateGet("HighlightEnabled", false)) {
        HideHighlight()
        return
    }
    if (!mon || !leafId) {
        HideHighlight()
        return
    }
    Layout_Ensure(mon)
    if (!Layouts[mon].nodes.Has(leafId)) {
        if (CurrentLeafSelection.Has(mon))
            CurrentLeafSelection.Delete(mon)
        HideHighlight()
        return
    }
    rect := ToPixelRect(mon, GetLeafRect(mon, leafId))
    ShowHighlightRect(rect)
    if (!IsObject(CurrentHighlight)) {
        CurrentHighlight := {mon:0, leaf:0}
        try {
            if (IsObject(AppState))
                AppState.CurrentHighlight := CurrentHighlight
        }
    }
    CurrentHighlight.mon := mon
    CurrentHighlight.leaf := leafId
    LogTrace(Format("ApplyLeafHighlight: mon={}, leaf={}", mon, leafId))
}

; Aktualisiert das Highlight basierend auf aktivem Fenster/manueller Auswahl.
UpdateActiveHighlight(*) {
    global WinToLeaf, WindowSearch, DragSnap
    try {
        if (IsSet(DragSnap) && DragSnap.active)
            return
    }
    catch Error as e {
        LogError("UpdateActiveHighlight: DragSnap check failed")
    }
    manual := GetManualNavigationContext()
    if (manual.mon) {
        ApplyLeafHighlight(manual.mon, manual.leaf)
        return
    }
    if (WindowSearch.active)
        return
    try {
        hwnd := WinGetID("A")
    } catch {
        hwnd := 0
    }
    if (!hwnd || !DllCall("IsWindow", "ptr", hwnd) || !WinExist("ahk_id " hwnd))
        return
    if (WinToLeaf.Has(hwnd))
        LeafRecordActivation(hwnd)
    else {
        monInfo := GetMonitorIndexAndArea(hwnd)
        SelectLeaf(monInfo.index, 0, "auto")
    }
    LogTrace("UpdateActiveHighlight tick")
}

; Startet den Highlight-Ticker zentral aus der App-Startup-Sequenz.
Highlight_Start() {
    try {
        UpdateActiveHighlight()
    }
    catch Error as e {
        LogException(e, "Highlight_Start: initial update failed")
    }
    try {
        SetTimer(UpdateActiveHighlight, 150)
    }
    catch Error as e {
        LogException(e, "Highlight_Start: SetTimer failed")
    }
}
