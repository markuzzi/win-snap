; =========================
; WinSnap_Overlays.ahk (optimiert, nutzt Utils.GetLeafRectPx)
; =========================

OverlayEnsure() {
    global SnapOverlay
    if (!IsObject(SnapOverlay))
        SnapOverlay := {}
    if (!SnapOverlay.HasOwnProp("edges"))
        SnapOverlay.edges := []
}

OverlayClear() {
    global SnapOverlay
    OverlayEnsure()
    for edge in SnapOverlay.edges {
        try {
            edge.Destroy()
        }
    }
    SnapOverlay.edges := []
    LogDebug("OverlayClear: cleared all edges")
}

OverlayAddRect(rect, color, thickness := 0) {
    global SnapOverlay, OverlayOpacity
    OverlayEnsure()

    x := Round(rect.L)
    y := Round(rect.T)
    w := Max(1, Round(rect.R - rect.L))
    h := Max(1, Round(rect.B - rect.T))

    try {
        style := "+AlwaysOnTop -Caption +ToolWindow +E0x80020 +DPIScale"
        g := Gui(style)
        g.BackColor := color
        g.Show("NA")
        opacity := (IsSet(OverlayOpacity) && OverlayOpacity) ? OverlayOpacity : 150
        try {
            WinSetTransparent(opacity, g)
        }
        g.Move(x, y, w, h)
        SnapOverlay.edges.Push(g)
    } catch Error as e {
        MsgBox "Fehler in OverlayAddRect:`n" e.Message
    }
}


ShowRectOverlay(rectArray, color, duration := 0) {
    OverlayClear()

    for rect in rectArray {
        try {
            OverlayAddRect(rect, color)
        }
    }

    if (duration > 0)
        try {
            SetTimer(HideSnapOverlay, -Abs(duration))
        }
    LogInfo(Format("ShowRectOverlay: count={}, color={}, duration={}ms", rectArray.Length, color, duration))
}

HideSnapOverlay(*) {
    OverlayClear()
    LogDebug("HideSnapOverlay: hidden")
}

FlashLeafOutline(mon, leafId, color := "", duration := 0) {
    global SelectionFlashColor, SelectionFlashDuration
    Layout_Ensure(mon)
    r := GetLeafRectPx(mon, leafId)
    useColor := (color != "") ? color : SelectionFlashColor
    useDuration := (duration > 0) ? duration : SelectionFlashDuration
    ShowRectOverlay([r], useColor, useDuration)
    LogInfo(Format("FlashLeafOutline: mon={}, leaf={}, color={}, dur={}ms", mon, leafId, useColor, useDuration))
}

ShowAllSnapAreasForMonitor(mon) {
    global OverlayColor, OverlayDuration
    Layout_Ensure(mon)
    rects := Layout_AllLeafRects(mon)
    arr := []
    for id, _ in rects {
        r := GetLeafRectPx(mon, id)
        arr.Push(r)
    }
    if (arr.Length = 0)
        return
    ShowRectOverlay(arr, OverlayColor, OverlayDuration)
    LogInfo(Format("ShowAllSnapAreasForMonitor: mon={}, count={}", mon, arr.Length))
}
