; =========================
; Snap-Area Overlays
; =========================
OverlayClear() {
    global SnapOverlay
    if !SnapOverlay.HasOwnProp("edges")
        SnapOverlay.edges := []
    for edge in SnapOverlay.edges {
        try {
            edge.Destroy()
        }
    }
    SnapOverlay.edges := []
}

OverlayAddRect(rect, color, thickness := 0) {
    global SnapOverlay, OverlayOpacity
    x := Round(rect.L)
    y := Round(rect.T)
    w := Max(1, Round(rect.R - rect.L))
    h := Max(1, Round(rect.B - rect.T))
    try {
        g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale")
        g.BackColor := color
        g.Move(x, y, w, h)
        g.Show("NA")
        opacity := OverlayOpacity ? OverlayOpacity : 150
        WinSetTransparent(opacity, g)
        SnapOverlay.edges.Push(g)
    } catch {
        ; GUI konnte nicht erzeugt werden – ignorieren
    }
}

ShowRectOverlay(rectArray, color, duration := 0) {
    OverlayClear()
    for rect in rectArray
        OverlayAddRect(rect, color)
    if (duration > 0)
        SetTimer(HideSnapOverlay, -duration)
}

HideSnapOverlay(*) {
    OverlayClear()
}

; erkennt, ob Werte normiert (0–1) oder in Pixeln sind und wandelt um
NormalizeRect(mon, r) {
    m := GetMonitorWork(mon)
    if (r.R <= 1 && r.B <= 1 && r.L >= 0 && r.T >= 0) {
        mw := m.right - m.left
        mh := m.bottom - m.top
        return {
            L: m.left + (r.L * mw),
            T: m.top  + (r.T * mh),
            R: m.left + (r.R * mw),
            B: m.top  + (r.B * mh)
        }
    }
    return r
}

FlashLeafOutline(mon, leafId, color := "", duration := 0) {
    global SelectionFlashColor, SelectionFlashDuration
    Layout_Ensure(mon)
    rect := NormalizeRect(mon, GetLeafRect(mon, leafId))
    useColor := color ? color : SelectionFlashColor
    useDuration := duration ? duration : SelectionFlashDuration
    ShowRectOverlay([rect], useColor, useDuration)
}

ShowAllSnapAreasForMonitor(mon) {
    global OverlayColor, OverlayDuration
    Layout_Ensure(mon)
    rects := Layout_AllLeafRects(mon)
    arr := []
    for id, rect in rects {
        r := NormalizeRect(mon, GetLeafRect(mon, id))
        arr.Push(r)
    }
    if (arr.Length = 0)
        return
    ShowRectOverlay(arr, OverlayColor, OverlayDuration)
}
