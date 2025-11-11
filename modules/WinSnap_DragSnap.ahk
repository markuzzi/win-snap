; =========================
; Drag-Snap: RMB during window drag (moved from WinSnap.ahk)
; =========================

global DragSnap := { active:false, hwnd:0, lastMon:0, lastLeaf:0 }
global DragSnapOverlayColor := "Blue"
global DragSnapTimerMs := 35

#HotIf GetKeyState("LButton", "P")
RButton:: {
    DragSnap_Start()
    return
}
#HotIf

DragSnap_IsActive() {
    global DragSnap
    return DragSnap.active
}

#HotIf DragSnap_IsActive()
~LButton Up:: {
    DragSnap_Drop()
    return
}
Esc:: {
    DragSnap_Cancel()
    return
}
#HotIf

DragSnap_Start() {
    global DragSnap, DragSnapTimerMs
    if (DragSnap.active)
        return
    ; ensure screen coordinates for mouse
    CoordMode "Mouse", "Screen"
    try {
        MouseGetPos &mx, &my, &hUnder
    } catch {
        return
    }
    if (!hUnder)
        return
    ; nur für echte Fenster reagieren
    try {
        if (!IsCollectibleSnapWindow(hUnder))
            return
    }
    mon := FindMonitorByPoint(mx, my)
    if (!mon)
        mon := 1
    Layout_Ensure(mon)
    leaf := Layout_FindLeafAtPoint(mon, mx, my)
    if (!leaf)
        leaf := Layouts[mon].root
    DragSnap.active := true
    DragSnap.hwnd := hUnder
    DragSnap.lastMon := mon
    DragSnap.lastLeaf := leaf
    DragSnap_UpdateOverlay(mon, leaf)
    ; also move regular highlight to mouse leaf
    try ApplyLeafHighlight(mon, leaf)
    try SetTimer(DragSnap_Tick, DragSnapTimerMs)
    LogInfo(Format("DragSnap_Start: hwnd={}, mon={}, leaf={}", hUnder, mon, leaf))
}

DragSnap_Tick(*) {
    global DragSnap
    if (!DragSnap.active) {
        try SetTimer(DragSnap_Tick, 0)
        return
    }
    if (!GetKeyState("LButton", "P")) {
        ; Falls Up verpasst wurde
        DragSnap_Cancel()
        return
    }
    CoordMode "Mouse", "Screen"
    try {
        MouseGetPos &mx, &my
    } catch {
        return
    }
    mon := FindMonitorByPoint(mx, my)
    if (!mon)
        mon := DragSnap.lastMon ? DragSnap.lastMon : 1
    Layout_Ensure(mon)
    leaf := Layout_FindLeafAtPoint(mon, mx, my)
    if (!leaf)
        leaf := Layouts[mon].root
    if (leaf != DragSnap.lastLeaf || mon != DragSnap.lastMon) {
        DragSnap.lastLeaf := leaf
        DragSnap.lastMon := mon
        DragSnap_UpdateOverlay(mon, leaf)
        ; keep highlight following the mouse
        try ApplyLeafHighlight(mon, leaf)
        LogTrace(Format("DragSnap_Tick: mon={}, leaf={} (updated)", mon, leaf))
    }
}

DragSnap_UpdateOverlay(mon, leaf) {
    global DragSnapOverlayColor
    r := GetLeafRectPx(mon, leaf)
    ShowRectOverlay([r], DragSnapOverlayColor, 0)
}

DragSnap_Drop() {
    global DragSnap
    if (!DragSnap.active)
        return
    try SetTimer(DragSnap_Tick, 0)
    HideSnapOverlay()
    hwnd := DragSnap.hwnd
    mon := DragSnap.lastMon
    leaf := DragSnap.lastLeaf
    DragSnap.active := false
    DragSnap.hwnd := 0
    if (!hwnd || !mon || !leaf)
        return
    try {
        ; Safety: release mouse capture if any remains
        try DllCall("ReleaseCapture")
        SnapToLeaf(hwnd, mon, leaf)
        LogInfo(Format("DragSnap_Drop: snapped hwnd={} to mon={}, leaf={}", hwnd, mon, leaf))
    }
}

DragSnap_Cancel() {
    global DragSnap
    try SetTimer(DragSnap_Tick, 0)
    HideSnapOverlay()
    DragSnap.active := false
    DragSnap.hwnd := 0
    LogDebug("DragSnap_Cancel: canceled")
}

FindMonitorByPoint(x, y) {
    count := MonitorGetCount()
    if (count <= 0)
        return 1
    Loop count {
        MonitorGetWorkArea(A_Index, &L, &T, &R, &B)
        if (x >= L && x < R && y >= T && y < B)
            return A_Index
    }
    return 1
}
