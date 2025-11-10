; =========================
; Utilities
; =========================
ClampFrac(val) {
    global MinFrac, MaxFrac
    return Max(MinFrac, Min(MaxFrac, val))
}

GetActiveWindow() {
    try {
        hwnd := WinGetID("A")
    } catch {
        return 0
    }
    if (!hwnd || !DllCall("IsWindow", "ptr", hwnd) || !WinExist("ahk_id " hwnd))
        return 0
    try {
        WinGetPos &x, &y, &w, &h, "ahk_id " hwnd
    } catch {
        return 0
    }
    return { hwnd:hwnd, x:x, y:y, w:w, h:h }
}

GetMonitorIndexAndArea(hwnd) {
    try {
        WinGetPos &wx, &wy, &ww, &wh, "ahk_id " hwnd
    } catch {
        return { index:1, left:0, top:0, right:A_ScreenWidth, bottom:A_ScreenHeight }
    }
    cx := wx + ww / 2
    cy := wy + wh / 2
    count := MonitorGetCount()
    Loop count {
        MonitorGetWorkArea(A_Index, &L, &T, &R, &B)
        if (cx >= L && cx < R && cy >= T && cy < B)
            return { index:A_Index, left:L, top:T, right:R, bottom:B }
    }
    MonitorGetWorkArea(1, &L, &T, &R, &B)
    return { index:1, left:L, top:T, right:R, bottom:B }
}

GetMonitorWork(mon) {
    count := MonitorGetCount()
    if (count <= 0)
        count := 1
    if (mon < 1 || mon > count)
        mon := 1
    try {
        MonitorGetWorkArea(mon, &L, &T, &R, &B)
    } catch {
        MonitorGetWorkArea(1, &L, &T, &R, &B)
    }
    return { left:L, top:T, right:R, bottom:B }
}

EnsureRestorable(hwnd) {
    mm := 0
    try {
        mm := WinGetMinMax("ahk_id " hwnd)
    }
    catch {
        mm := 0
    }
    if (mm = 0)
        return
    WinRestore "ahk_id " hwnd
    deadline := A_TickCount + 400
    while (A_TickCount < deadline) {
        try {
            mm := WinGetMinMax("ahk_id " hwnd)
        }
        catch {
            mm := 0
        }
        if (mm = 0)
            break
        Sleep 15
    }
}

; --- Logging ---------------------------------------------------------------
LogWrite(levelNum, levelName, msg) {
    global LoggingEnabled, LoggingLevel, LoggingPath, FrameCompDebug, FrameCompLogPath
    enabled := IsSet(LoggingEnabled) ? LoggingEnabled : (IsSet(FrameCompDebug) ? FrameCompDebug : false)
    if (!enabled)
        return
    thresh := IsSet(LoggingLevel) ? LoggingLevel : 2
    if (levelNum > thresh)
        return
    path := IsSet(LoggingPath) ? LoggingPath : (IsSet(FrameCompLogPath) ? FrameCompLogPath : A_ScriptDir "\WinSnap.log")
    try {
        stamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        FileAppend(stamp " | " levelName " | " msg "`n", path, "UTF-8")
    }
}

LogInfo(msg) {
    LogWrite(1, "INFO", msg)
}

LogDebug(msg) {
    LogWrite(2, "DEBUG", msg)
}

LogTrace(msg) {
    LogWrite(3, "TRACE", msg)
}

; Backward compat
DebugLog(msg) {
    LogDebug(msg)
}

; --- Small helpers ---------------------------------------------------------
StrJoin(arr, sep := "") {
    if !(arr is Array)
        return ""
    out := ""
    for i, v in arr {
        if (i > 1)
            out .= sep
        out .= v
    }
    return out
}

TraySetToolTip(text) {
    try {
        A_IconTip := text
    }
}

; Liefert die von DWM gemeldeten Extended Frame Bounds (sichtbare Fensteraussenkanten)
GetExtendedFrameBounds(hwnd) {
    try {
        buf := Buffer(16, 0)
        hMod := DllCall("GetModuleHandle", "str", "dwmapi.dll", "ptr")
        if (!hMod) {
            DebugLog("dwmapi.dll not loaded, calling LoadLibrary")
            hMod := DllCall("LoadLibrary", "str", "dwmapi.dll", "ptr")
        }
        if (!hMod) {
            DebugLog("LoadLibrary(dwmapi.dll) failed")
            return 0
        }
        pfn := DllCall("GetProcAddress", "ptr", hMod, "astr", "DwmGetWindowAttribute", "ptr")
        if (!pfn) {
            DebugLog("GetProcAddress(DwmGetWindowAttribute) failed")
            return 0
        }
        ; DWMWA_EXTENDED_FRAME_BOUNDS = 9
        hr := DllCall(pfn, "ptr", hwnd, "int", 9, "ptr", buf.Ptr, "uint", 16, "int")
        if (hr != 0) {
            DebugLog(Format("EFB hr={} (non-zero) for hwnd={}", hr, hwnd))
            return 0
        }
        l := NumGet(buf, 0, "Int")
        t := NumGet(buf, 4, "Int")
        r := NumGet(buf, 8, "Int")
        b := NumGet(buf, 12, "Int")
        DebugLog(Format("EFB L={},T={},R={},B={} for hwnd={}", l, t, r, b, hwnd))
        return { L:l, T:t, R:r, B:b }
    } catch {
        DebugLog(Format("EFB call failed for hwnd={}", hwnd))
        return 0
    }
}

MoveWindow(hwnd, x, y, w, h) {
    try {
        exists := DllCall("IsWindow", "ptr", hwnd) && WinExist("ahk_id " hwnd)
    } catch {
        exists := false
    }
    if (!exists)
        return false

    EnsureRestorable(hwnd)

    ; Zielrechteck runden und validieren
    x := Round(x)
    y := Round(y)
    w := Max(1, Round(w))
    h := Max(1, Round(h))

    ; Klassen-/Prozess-basierte Kompensation anwenden (falls vorhanden)
    x0 := x, y0 := y, w0 := w, h0 := h
    className := ""
    try {
        className := WinGetClass("ahk_id " hwnd)
    }
    procName := ""
    try {
        procName := WinGetProcessName("ahk_id " hwnd)
    }
    if (procName = "")
        procName := "unknown"
    monIdx := 0
    try {
        mi := GetMonitorIndexAndArea(hwnd)
        monIdx := mi.index
    }
    cacheKey := className ":" procName ":" monIdx
    DebugLog(Format("MoveWindow start hwnd={}, class={}, proc={}, key={}, target=({}, {}, {}, {})", hwnd, className, procName, cacheKey, x, y, w, h))

    try {
        global FrameComp
        if (FrameComp.Has(cacheKey)) {
            off := FrameComp[cacheKey]
            if (off) {
                x0 := x - off.L
                y0 := y - off.T
                w0 := w + off.L + off.R
                h0 := h + off.T + off.B
                DebugLog(Format("Using cached offset for key {}: L={},T={},R={},B={} => preMove=({}, {}, {}, {})", cacheKey, off.L, off.T, off.R, off.B, x0, y0, w0, h0))
            }
        }
    }

    ; Erster Move (ggf. bereits kompensiert)
    try {
        WinMove x0, y0, w0, h0, "ahk_id " hwnd
    } catch {
        DebugLog("WinMove initial failed")
        return false
    }
    Sleep 15

    ; Extended Frame Bounds ermitteln und ggf. korrigieren
    efb := GetExtendedFrameBounds(hwnd)
    if (efb) {
        cacheOk := true
        ; Margins zwischen gesetztem Rechteck (x0..x0+w0) und EFB messen
        mL := efb.L - x0
        mT := efb.T - y0
        mR := (x0 + w0) - efb.R
        mB := (y0 + h0) - efb.B
        DebugLog(Format("EFB margins L={},T={},R={},B={} for preMove=({}, {}, {}, {})", mL, mT, mR, mB, x0, y0, w0, h0))
        ; Neues Ziel unter Bercksichtigung der Margins berechnen (kann schrumpfen oder wachsen)
        x1 := x - mL
        y1 := y - mT
        w1 := w + mL + mR
        h1 := h + mT + mB
        ; minimale Gre garantieren
        w1 := Max(1, Round(w1))
        h1 := Max(1, Round(h1))
        ; Sanity-Check: Ausreißer erkennen (z.B. Terminal/Conhost)
        maxSide := 60  ; px pro Seite
        if (Abs(mL) > maxSide || Abs(mT) > maxSide || Abs(mR) > maxSide || Abs(mB) > maxSide) {
            DebugLog("EFB correction skipped (margins out of range)")
            x1 := x0, y1 := y0, w1 := w0, h1 := h0
            cacheOk := false
        } else {
            minW := Max(100, Floor(w * 0.6))
            minH := Max(80,  Floor(h * 0.6))
            maxW := Ceil(w * 1.6)
            maxH := Ceil(h * 1.6)
            if (w1 < minW || h1 < minH || w1 > maxW || h1 > maxH) {
                DebugLog("EFB correction skipped (bad corrected size)")
                x1 := x0, y1 := y0, w1 := w0, h1 := h0
                cacheOk := false
            }
        }
        ; Nur bewegen, wenn sich etwas ndert
        if (x1 != x0 || y1 != y0 || w1 != w0 || h1 != h0) {
            try {
                WinMove x1, y1, w1, h1, "ahk_id " hwnd
            }
            Sleep 10
        } else {
            DebugLog("No EFB correction needed (margins 0)")
        }
        ; Cache pro Klasse/Prozess ablegen (mit Vorzeichen)
        try {
            if (cacheOk && cacheKey != ":unknown:0") {
                FrameComp[cacheKey] := { L:mL, T:mT, R:mR, B:mB }
                DebugLog(Format("Cached margins for key {}: L={},T={},R={},B={}", cacheKey, mL, mT, mR, mB))
            }
        }
    } else {
        DebugLog("EFB unavailable; skip correction")
    }

    ; Highlight reaktivieren, falls bekanntem Leaf zugeordnet
    try {
        global WinToLeaf
        if (WinToLeaf.Has(hwnd)) {
            info := WinToLeaf[hwnd]
            ApplyLeafHighlight(info.mon, info.leaf)
        }
    }

    DebugLog("MoveWindow end OK")
    return true
}

; --- Hilfsfunktionen: Normierte Rechtecke → Pixelkoordinaten ---
ToPixelRect(mon, r) {
    ; Erkennt 0–1-Rects und skaliert sie auf Monitorpixel
    m := GetMonitorWork(mon)
    rw := r.R - r.L
    rh := r.B - r.T
    if (rw <= 1.0 && rh <= 1.0 && rw >= 0 && rh >= 0) {
        mw := m.right - m.left
        mh := m.bottom - m.top
        L := m.left + (r.L * mw)
        T := m.top  + (r.T * mh)
        R := m.left + (r.R * mw)
        B := m.top  + (r.B * mh)
        return {L:L, T:T, R:R, B:B}
    }
    return r
}

GetLeafRectPx(mon, leafId) {
    return ToPixelRect(mon, GetLeafRect(mon, leafId))
}
