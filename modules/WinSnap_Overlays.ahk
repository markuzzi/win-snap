; =========================
; WinSnap_Overlays.ahk (optimiert, nutzt Utils.GetLeafRectPx)
; =========================

; Stellt sicher, dass die Overlay-Datenstruktur initialisiert ist.
OverlayEnsure() {
    global SnapOverlay
    if (!IsObject(SnapOverlay))
        SnapOverlay := {}
    if (!SnapOverlay.HasOwnProp("edges"))
        SnapOverlay.edges := []
}

; Entfernt und zerstoert alle aktuell angezeigten Overlay-Elemente.
OverlayClear() {
    global SnapOverlay
    OverlayEnsure()
    for edge in SnapOverlay.edges {
        try {
            edge.Destroy()
        }
        catch Error as e {
            LogError("OverlayClear: edge.Destroy failed")
        }
    }
    SnapOverlay.edges := []
    LogDebug("OverlayClear: cleared all edges")
}

; Fuegt ein abgerundetes, transparentes Rechteck-Overlay hinzu.
OverlayAddRect(rect, color, thickness := 0) {
    global SnapOverlay, OverlayOpacity
    OverlayEnsure()

    ; --- Validierung ---
    if (!IsObject(rect)) {
        LogError("OverlayAddRect: rect is not an object!")
        return
    }
    if (!rect.HasOwnProp("L") || !rect.HasOwnProp("T") || !rect.HasOwnProp("R") || !rect.HasOwnProp("B")) {
        LogError("OverlayAddRect: rect is missing required properties (L, T, R, B)")
        return
    }

    x := Round(rect.L)
    y := Round(rect.T)
    w := Max(1, Round(rect.R - rect.L))
    h := Max(1, Round(rect.B - rect.T))

    if (w <= 0 || h <= 0) {
        LogWarn(Format("OverlayAddRect: Ignoring rectangle with invalid size (w={}, h={})", w, h))
        return
    }

    if (color = "") {
        LogWarn("OverlayAddRect: No color specified, defaulting to 'Lime'")
        color := "Lime"
    }

    ; --- Abrundungsradius & Transparenz vorbereiten ---
    radius := 16
    opacity := (IsSet(OverlayOpacity) && OverlayOpacity > 0) ? OverlayOpacity : 150

    try {
        style := "+AlwaysOnTop -Caption +ToolWindow +E0x80020 +DPIScale"
        g := Gui(style)
        g.BackColor := color
        g.Show("NA")  ; NoActivate
        WinSetTransparent(opacity, g)

        ; --- Rounded Region erstellen ---
        hRgn := DllCall("CreateRoundRectRgn", "Int", 0, "Int", 0, "Int", w, "Int", h, "Int", radius, "Int", radius, "Ptr")
        if (!hRgn) {
            LogError("OverlayAddRect: Failed to create region via CreateRoundRectRgn")
            g.Destroy()
            return
        }

        success := DllCall("SetWindowRgn", "Ptr", g.Hwnd, "Ptr", hRgn, "Int", true)
        if (!success) {
            LogError("OverlayAddRect: SetWindowRgn failed for hwnd=" g.Hwnd)
            DllCall("DeleteObject", "Ptr", hRgn)
            g.Destroy()
            return
        }

        g.Move(x, y, w, h)
        SnapOverlay.edges.Push(g)
        LogDebug(Format("OverlayAddRect: success (x={}, y={}, w={}, h={}, color={}, opacity={}, radius={})", x, y, w, h, color, opacity, radius))

    } catch Error as e {
        LogError("OverlayAddRect: Exception occurred → " . e.Message)
        try {
            g.Destroy()
        }
        catch Error as e {
            ; ignore
        }
    }
}




; Zeigt mehrere Rechtecke als Overlay fuer eine Dauer (0 = persistent).
ShowRectOverlay(rectArray, color, duration := 0) {
    OverlayClear()

    for rect in rectArray {
        try {
            OverlayAddRect(rect, color)
        }
        catch Error as e {
            LogError("ShowRectOverlay: OverlayAddRect failed")
        }
    }

    if (duration > 0)
        try {
            SetTimer(HideSnapOverlay, -Abs(duration))
        }
        catch Error as e {
            LogError("ShowRectOverlay: SetTimer failed")
        }
    LogInfo(Format("ShowRectOverlay: count={}, color={}, duration={}ms", rectArray.Length, color, duration))
}

; Blendet alle Snap-Overlays aus und leert den Zustand.
HideSnapOverlay(*) {
    OverlayClear()
    LogDebug("HideSnapOverlay: hidden")
}

; Blitzt die Umrandung einer Leaf-Area kurz auf.
FlashLeafOutline(mon, leafId, color := "", duration := 0) {
    global SelectionFlashColor, SelectionFlashDuration
    Layout_Ensure(mon)
    r := GetLeafRectPx(mon, leafId)
    useColor := (color != "") ? color : SelectionFlashColor
    useDuration := (duration > 0) ? duration : SelectionFlashDuration
    ShowRectOverlay([r], useColor, useDuration)
    LogInfo(Format("FlashLeafOutline: mon={}, leaf={}, color={}, dur={}ms", mon, leafId, useColor, useDuration))
}

; Zeigt alle Snap-Areas des angegebenen Monitors als Overlay an.
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





