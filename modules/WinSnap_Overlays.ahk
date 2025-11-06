; =========================
; Snap-Area Overlays
; =========================
OverlayCreateEdge(color, x, y, w, h) {
    global SnapOverlay
    g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    g.BackColor := color
    g.Move(x, y, w, h)
    g.Show("NA")
    SnapOverlay.edges.Push(g)
}

OverlayClear() {
    global SnapOverlay
    if !SnapOverlay.HasOwnProp("edges")
        SnapOverlay.edges := []
    for idx, edge in SnapOverlay.edges {
        try edge.Destroy()
    }
    SnapOverlay.edges := []
}

OverlayAddRect(rect, color, thickness := 0) {
    global BorderPx
    px := thickness ? thickness : Max(2, BorderPx)
    OverlayCreateEdge(color, rect.L-1, rect.T-1, rect.R-rect.L+2, px)
    OverlayCreateEdge(color, rect.L-1, rect.B-1, rect.R-rect.L+2, px)
    OverlayCreateEdge(color, rect.L-1, rect.T-1, px, rect.B-rect.T+2)
    OverlayCreateEdge(color, rect.R-1, rect.T-1, px, rect.B-rect.T+2)
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

FlashLeafOutline(mon, leafId, color := "", duration := 0) {
    global SelectionFlashColor, SelectionFlashDuration
    Layout_Ensure(mon)
    rect := GetLeafRect(mon, leafId)
    useColor := color ? color : SelectionFlashColor
    useDuration := duration ? duration : SelectionFlashDuration
    ShowRectOverlay([rect], useColor, useDuration)
}

ShowAllSnapAreasForMonitor(mon) {
    global OverlayColor, OverlayDuration
    Layout_Ensure(mon)
    rects := Layout_AllLeafRects(mon)
    arr := []
    for id, rect in rects
        arr.Push(GetLeafRect(mon, id))
    if (arr.Length = 0)
        return
    ShowRectOverlay(arr, OverlayColor, OverlayDuration)
}
