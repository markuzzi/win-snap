; =========================
; Highlight (roter Rahmen)
; =========================
HL_Init() {
    global HL, BorderPx
    if (HL.init)
        return
    makeEdge() {
        g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20") ; click-through
        g.BackColor := "Teal"
        return g
    }
    HL.top   := makeEdge()
    HL.bot   := makeEdge()
    HL.left  := makeEdge()
    HL.right := makeEdge()
    HL.init := true
    LogDebug("HL_Init: highlight edges created")
}

ShowHighlightRect(rect) {
    global HighlightEnabled, HL, BorderPx
    if (!HighlightEnabled)
        return
    HL_Init()
    x := rect.L, y := rect.T
    w := rect.R - rect.L
    h := rect.B - rect.T
    LogDebug(Format("ShowHighlightRect: L={},T={},R={},B={} (w={},h={})", rect.L, rect.T, rect.R, rect.B, w, h))
    HL.top.Move(x-1, y-1, w+2, BorderPx),      HL.top.Show("NA")
    HL.bot.Move(x-1, y+h-1, w+2, BorderPx),    HL.bot.Show("NA")
    HL.left.Move(x-1, y-1, BorderPx, h+2),     HL.left.Show("NA")
    HL.right.Move(x+w-1, y-1, BorderPx, h+2),  HL.right.Show("NA")
}

HideHighlight() {
    global HL, CurrentHighlight
    if (HL.init) {
        try {
            HL.top.Hide()
        }
        try {
            HL.bot.Hide()
        }
        try {
            HL.left.Hide()
        }
        try {
            HL.right.Hide()
        }
    }
    CurrentHighlight := {mon:0, leaf:0}
    LogDebug("HideHighlight: hidden")
}

ApplyLeafHighlight(mon, leafId) {
    global HighlightEnabled, CurrentHighlight, Layouts, CurrentLeafSelection
    if (!HighlightEnabled) {
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
    CurrentHighlight := {mon:mon, leaf:leafId}
    LogInfo(Format("ApplyLeafHighlight: mon={}, leaf={}", mon, leafId))
}

UpdateActiveHighlight(*) {
    global WinToLeaf, WindowSearch
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
    LogDebug("UpdateActiveHighlight tick")
}

UpdateActiveHighlight()
SetTimer(UpdateActiveHighlight, 150)
