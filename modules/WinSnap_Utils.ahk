; =========================
; Utilities
; =========================
ClampFrac(val) {
    global MinFrac, MaxFrac
    return Max(MinFrac, Min(MaxFrac, val))
}

GetActiveWindow() {
    try hwnd := WinGetID("A")
    catch
        return 0
    if !hwnd || !WinExist("ahk_id " hwnd)
        return 0
    try WinGetPos &x, &y, &w, &h, "ahk_id " hwnd
    catch
        return 0
    return { hwnd:hwnd, x:x, y:y, w:w, h:h }
}

GetMonitorIndexAndArea(hwnd) {
    WinGetPos &wx, &wy, &ww, &wh, "ahk_id " hwnd
    cx := wx + ww/2
    cy := wy + wh/2
    count := MonitorGetCount()
    Loop count {
        MonitorGetWorkArea(A_Index, &L, &T, &R, &B)
        if (cx >= L && cx < R && cy >= T && cy < B)
            return { index: A_Index, left: L, top: T, right: R, bottom: B }
    }
    MonitorGetWorkArea(1, &L, &T, &R, &B)
    return { index: 1, left: L, top: T, right: R, bottom: B }
}

GetMonitorWork(mon) {
    MonitorGetWorkArea(mon, &L, &T, &R, &B)
    return { left:L, top:T, right:R, bottom:B }
}

EnsureRestorable(hwnd) {
    mm := WinGetMinMax("ahk_id " hwnd)  ; -1=min, 1=max, 0=normal
    if (mm = 0)
        return
    WinRestore "ahk_id " hwnd
    deadline := A_TickCount + 400
    while (A_TickCount < deadline) {
        try {
            mm := WinGetMinMax("ahk_id " hwnd)
        } catch {
            mm := 0
        }
        if (mm = 0)
            break
        Sleep 15
    }
}

MoveWindow(hwnd, x, y, w, h) {
    if !WinExist("ahk_id " hwnd)
        return false
    EnsureRestorable(hwnd)
    x := Round(x), y := Round(y), w := Max(1, Round(w)), h := Max(1, Round(h))
    attempts := 0
    done := false
    while (attempts < 3 && !done) {
        attempts += 1
        try {
            ; AHK v2: WinMove X, Y, W, H, WinTitle
            WinMove x, y, w, h, "ahk_id " hwnd
        } catch {
            return false
        }
        Sleep 15
        WinGetPos &cx, &cy, &cw, &ch, "ahk_id " hwnd
        if (Abs(cx - x) <= 1 && Abs(cy - y) <= 1 && Abs(cw - w) <= 1 && Abs(ch - h) <= 1)
            done := true
    }
    return done
}
