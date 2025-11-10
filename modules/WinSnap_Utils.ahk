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

; Backward compat
DebugLog(msg) {
    LogDebug(msg)
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
    cacheKey := className ":" procName
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
        dxL := Max(0, efb.L - x)
        dxT := Max(0, efb.T - y)
        dxR := Max(0, (x + w) - efb.R)
        dxB := Max(0, (y + h) - efb.B)
        DebugLog(Format("EFB deltas L={},T={},R={},B={} for target=({}, {}, {}, {})", dxL, dxT, dxR, dxB, x, y, w, h))
        if (dxL || dxT || dxR || dxB) {
            x1 := x - dxL
            y1 := y - dxT
            w1 := w + dxL + dxR
            h1 := h + dxT + dxB
            try {
                WinMove x1, y1, w1, h1, "ahk_id " hwnd
            }
            Sleep 10
            try {
                ; Cache pro Klassenname ablegen
                if (cacheKey != ":unknown") {
                    FrameComp[cacheKey] := { L:dxL, T:dxT, R:dxR, B:dxB }
                    DebugLog(Format("Cached offset for key {}: L={},T={},R={},B={}", cacheKey, dxL, dxT, dxR, dxB))
                }
            }
        }
        else {
            DebugLog("No EFB correction needed")
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
