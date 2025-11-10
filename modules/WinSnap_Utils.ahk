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

MoveWindow(hwnd, x, y, w, h) {
    try {
        exists := DllCall("IsWindow", "ptr", hwnd) && WinExist("ahk_id " hwnd)
    }
    catch {
        exists := false
    }
    if (!exists)
        return false
    EnsureRestorable(hwnd)
    x := Round(x)
    y := Round(y)
    w := Max(1, Round(w))
    h := Max(1, Round(h))
    attempts := 0
    done := false
    while (attempts < 3 && !done) {
        attempts += 1
        try {
            WinMove x, y, w, h, "ahk_id " hwnd
        }
        catch {
            return false
        }
        Sleep 15
        try {
            WinGetPos &cx, &cy, &cw, &ch, "ahk_id " hwnd
        }
        catch {
            break
        }
        if (Abs(cx - x) <= 1 && Abs(cy - y) <= 1 && Abs(cw - w) <= 1 && Abs(ch - h) <= 1)
            done := true
    }
    if (done) {
        try {
            global WinToLeaf
            if (WinToLeaf.Has(hwnd)) {
                info := WinToLeaf[hwnd]
                ApplyLeafHighlight(info.mon, info.leaf)
            }
        }
    }
    return done
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
