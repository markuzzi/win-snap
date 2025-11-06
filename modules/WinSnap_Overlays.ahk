; =========================
; Snap-Area Overlays
; =========================
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
    global SnapOverlay, OverlayOpacity
    x := Round(rect.L)
    y := Round(rect.T)
    w := Max(1, Round(rect.R - rect.L))
    h := Max(1, Round(rect.B - rect.T))
    g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale")
    g.BackColor := color
    g.Move(x, y, w, h)
    g.Show("NA")
    opacity := OverlayOpacity ? OverlayOpacity : 150
    try WinSetTransparent(opacity, g)
    SnapOverlay.edges.Push(g)
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
