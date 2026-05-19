; =========================
; WinSnap_Overlays.ahk (optimiert, nutzt Utils.GetLeafRectPx)
; =========================

; Stellt sicher, dass die Overlay-Datenstruktur initialisiert ist.
OverlayEnsure() {
    global SnapOverlay, AppState
    if (!IsObject(SnapOverlay)) {
        SnapOverlay := {edges:[]}
        try {
            if (IsObject(AppState))
                AppState.SnapOverlay := SnapOverlay
        }
        catch Error as e {
            ; keep local fallback
        }
    }
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
OverlayAddRect(rect, color, thickness := 0, label := "") {
    global SnapOverlay
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
    opacity := StateGet("OverlayOpacity", 160)
    if (opacity <= 0)
        opacity := 150

    try {
        ; Use pixel coordinates for overlays to avoid DPI scaling offsets
        style := "+AlwaysOnTop -Caption +ToolWindow +E0x80020 -DPIScale"
        g := Gui(style)
        g.BackColor := color
        if (label != "") {
            fontSize := OverlayLabelFontSize(w, h, label)
            g.SetFont(Format("s{} Bold cWhite", fontSize), "Segoe UI")
            g.AddText(Format("x0 y0 w{} h{} Center +0x200 BackgroundTrans", w, h), label)
        }
        g.Show(Format("NA x{} y{} w{} h{}", x, y, w, h))  ; NoActivate
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
        LogDebug(Format("OverlayAddRect: success (x={}, y={}, w={}, h={}, color={}, opacity={}, radius={}, label={})", x, y, w, h, color, opacity, radius, label))

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

; Berechnet eine gut sichtbare Label-Schriftgroesse fuer ein Overlay-Rechteck.
OverlayLabelFontSize(w, h, label) {
    digits := Max(1, StrLen(String(label)))
    heightLimit := Floor(h * 0.38)
    widthLimit := Floor((w * 0.70) / (digits * 0.60))
    size := Min(96, heightLimit, widthLimit)
    return Max(18, size)
}

; Zeigt mehrere Rechtecke als Overlay fuer eine Dauer (0 = persistent).
ShowRectOverlay(rectArray, color, duration := 0, labelArray := 0) {
    OverlayClear()

    idx := 0
    for rect in rectArray {
        idx += 1
        label := ""
        if (IsObject(labelArray) && labelArray.Length >= idx)
            label := labelArray[idx]
        try {
            OverlayAddRect(rect, color, 0, label)
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
    Layout_Ensure(mon)
    r := GetLeafRectPx(mon, leafId)
    useColor := (color != "") ? color : StateGet("SelectionFlashColor", "Teal")
    useDuration := (duration > 0) ? duration : StateGet("SelectionFlashDuration", 350)
    ShowRectOverlay([r], useColor, useDuration)
    LogInfo(Format("FlashLeafOutline: mon={}, leaf={}, color={}, dur={}ms", mon, leafId, useColor, useDuration))
}

; Zeigt alle Snap-Areas des angegebenen Monitors als Overlay an.
ShowAllSnapAreasForMonitor(mon) {
    overlayColor := StateGet("OverlayColor", "Navy")
    overlayDuration := StateGet("OverlayDuration", 1200)
    Layout_Ensure(mon)
    arr := []
    labels := []
    idx := 1
    for id in Layout_LeafOrder(mon) {
        r := GetLeafRectPx(mon, id)
        arr.Push(r)
        labels.Push(String(idx))
        idx += 1
    }
    if (arr.Length = 0)
        return
    ShowRectOverlay(arr, overlayColor, overlayDuration, labels)
    LogInfo(Format("ShowAllSnapAreasForMonitor: mon={}, count={}", mon, arr.Length))
}





