; =========================
; Window Pills Overlay (floating pills per SnapArea)
; =========================

; Globals and defaults are defined in WinSnap.ahk. This module implements an
; optional overlay that shows small rounded rectangles ("pills") listing the
; window titles inside each SnapArea, anchored at the top-left corner of the
; area. The current window appears with a darker color.

WindowPills := { pills: [], shown:false, lastSig:"", guiToHwnd: Map(), hooks:false }

WindowPills_Init() {
    global WindowPills
    if (!IsObject(WindowPills))
        WindowPills := { pills: [], shown:false, lastSig:"", guiToHwnd: Map(), hooks:false }
    if (!WindowPills.HasOwnProp("guiToHwnd") || !(WindowPills.guiToHwnd is Map))
        WindowPills.guiToHwnd := Map()
    if (!WindowPills.hooks) {
        try {
            OnMessage(0x0201, WP_OnMouse) ; WM_LBUTTONDOWN
            OnMessage(0x0202, WP_OnMouse) ; WM_LBUTTONUP
            WindowPills.hooks := true
        }
    }
}

WindowPills_Clear() {
    global WindowPills
    global WindowPillsReserve
    WindowPills_Init()
    for pill in WindowPills.pills {
        try pill.Destroy()
    }
    WindowPills.pills := []
    WindowPills.shown := false
    ; Keep WindowPillsReserve to avoid unnecessary window reapply flicker
    try WindowPills.guiToHwnd := Map()
}

WindowPills_Toggle() {
    global WindowPillsEnabled
    WindowPillsEnabled := !WindowPillsEnabled
    if (!WindowPillsEnabled) {
        WindowPills_Clear()
        ; Reapply all leaves to reclaim reserved area
        try {
            count := MonitorGetCount()
            Loop count {
                mon := A_Index
                Layout_Ensure(mon)
                global Layouts
                try ReapplySubtree(mon, Layouts[mon].root)
            }
        }
    } else {
        ; Force immediate update to compute reserves and render pills
        global WindowPills
        try WindowPills.lastSig := ""
        WindowPills_Update()
    }
    LogInfo(Format("WindowPills_Toggle: {}", WindowPillsEnabled ? "ENABLED" : "DISABLED"))
}

; --- Helpers ---------------------------------------------------------------

WP_TruncateTitle(txt, maxLen) {
    if (!IsSet(maxLen) || maxLen <= 0)
        return txt
    try {
        len := StrLen(txt)
    } catch {
        len := 0
    }
    if (len <= maxLen)
        return txt
    if (maxLen <= 1)
        return "…"
    return SubStr(txt, 1, maxLen - 1) . "…"
}

WP_BuildStateSignature() {
    ; Create a compact signature of all leaf->window lists and the focused hwnd.
    global LeafWindows, WindowPillsEnabled, WindowPillsMaxTitle
    sig := []
    focused := 0
    try focused := WinGetID("A")
    sig.Push("E:" (WindowPillsEnabled ? 1 : 0))
    sig.Push("M:" (IsSet(WindowPillsMaxTitle) ? WindowPillsMaxTitle : 20))
    for key, arr in LeafWindows {
        ; key is "mon:leaf"
        ids := []
        for hwnd in arr
            ids.Push("" hwnd)
        ; ignore order in signature to avoid rebuild flicker on activation reordering
        try ids.Sort()
        sig.Push(key ":" StrJoin(ids, ","))
    }
    ; Focus intentionally excluded from signature to avoid rebuild flicker on activation
    return StrJoin(sig, "|")
}

; Creates one rounded rectangle GUI pill at position (x,y) with measured text.
; targetHwnd: window handle to activate when clicked.
WP_CreatePill(x, y, text, isActive, targetHwnd := 0) {
    global WindowPillsOpacity, WindowPillsRadius
    global WindowPillColor, WindowPillColorActive
    global WindowPillsFont, WindowPillsFontSize
    global WindowPillsTextColor, WindowPillsActiveTextColor
    global WindowPillsPaddingX, WindowPillsPaddingY

    color := isActive ? WindowPillColorActive : WindowPillColor
    tColor := isActive ? WindowPillsActiveTextColor : WindowPillsTextColor

    ; Layered + NoActivate (but NOT Transparent) so the pill can receive clicks
    ; 0x80000 (WS_EX_LAYERED) | 0x08000000 (WS_EX_NOACTIVATE)
    style := "+AlwaysOnTop -Caption +ToolWindow +E0x08080000 +DPIScale"
    g := Gui(style)
    g.BackColor := color
    try WinSetTransparent(WindowPillsOpacity, g)
    try g.SetFont(Format("s{} {}", WindowPillsFontSize, tColor), WindowPillsFont)
    ctrl := g.AddText("xm ym +0x0100 BackgroundTrans", text) ; +SS_NOTIFY for click

    ; Initial show off-screen to allow proper measurement
    g.Show("NA Hide")
    ctrl.GetPos(, , &tw, &th)
    w := Max(1, tw + 2 * WindowPillsPaddingX)
    h := Max(1, th + 2 * WindowPillsPaddingY)

    ; Rounded region
    radius := WindowPillsRadius
    hRgn := DllCall("CreateRoundRectRgn", "Int", 0, "Int", 0, "Int", w, "Int", h, "Int", radius, "Int", radius, "Ptr")
    if (hRgn)
        DllCall("SetWindowRgn", "Ptr", g.Hwnd, "Ptr", hRgn, "Int", true)

    ; Center text within pill by adding padding offset
    ctrl.Move(WindowPillsPaddingX, WindowPillsPaddingY)

    g.Move(Round(x), Round(y), w, h)
    ; visible state will be controlled by caller (shown after final placement)
    ; Register click mapping
    try {
        global WindowPills
        if (targetHwnd)
            WindowPills.guiToHwnd[g.Hwnd] := targetHwnd
        if (IsObject(ctrl))
            ctrl.OnEvent("Click", (*) => WP_OnPillClick(targetHwnd))
    }
    ; return as object to allow later updates
    return { gui:g, ctrl:ctrl }
}

; --- Layout/update ---------------------------------------------------------

WindowPills_Update() {
    global WindowPillsEnabled, ScriptPaused
    if (!IsSet(WindowPillsEnabled) || !WindowPillsEnabled) {
        WindowPills_Clear()
        return
    }
    if (IsSet(ScriptPaused) && ScriptPaused) {
        WindowPills_Clear()
        return
    }
    global LeafWindows
    global WindowPillsReserve
    WindowPills_Init()
    if (!IsObject(WindowPillsReserve))
        WindowPillsReserve := Map()

    sig := WP_BuildStateSignature()
    if (sig = WindowPills.lastSig) {
        ; Update only active state styling without rebuild to avoid flicker
        WP_RefreshActiveStyles()
        return
    }
    WindowPills.lastSig := sig

    ; Double-buffered rebuild to avoid visible gaps
    global WindowPills
    oldPills := WindowPills.pills
    WindowPills.pills := []
    WindowPills.guiToHwnd := Map()

    ; Iterate all leaves with windows
    for key, arr in LeafWindows {
        ; Parse key "mon:leaf"
        parts := StrSplit(key, ":")
        if (parts.Length != 2)
            continue
        mon := parts[1] + 0
        leafId := parts[2] + 0

        ; Validate rect
        try r := GetLeafRectPx(mon, leafId)
        if (!IsObject(r))
            continue

        ; Determine which hwnd should be highlighted for this leaf
        activeHwnd := 0
        try {
            sysActive := WinGetID("A")
        }
        catch {
            sysActive := 0
        }
        if (sysActive) {
            ; If active window belongs to this leaf, prefer it; else top window
            try {
                global WinToLeaf
                if (WinToLeaf.Has(sysActive)) {
                    info := WinToLeaf[sysActive]
                    if (info.mon = mon && info.leaf = leafId)
                        activeHwnd := sysActive
                }
            }
        }
        if (!activeHwnd)
            activeHwnd := LeafGetTopWindow(mon, leafId)

        ; Placement parameters
        global WindowPillsMarginX, WindowPillsMarginY, WindowPillsGap
        maxX := r.R - WindowPillsMarginX  ; right bound for wrapping

        ; First pass: create and measure all pills
        items := []  ; each: { gui, ctrl, w, h, hwnd }
        for hwnd in arr {
            try {
                title := WinGetTitle("ahk_id " hwnd)
            }
            catch {
                title := ""
            }
            if (title = "")
                title := "(untitled)"
            txt := WP_TruncateTitle(title, WindowPillsMaxTitle)
            isActive := (hwnd = activeHwnd)
            obj := WP_CreatePill(-10000, -10000, txt, isActive, hwnd)
            ; measure
            try obj.ctrl.GetPos(, , &tw, &th)
            catch {
                tw := 40, th := 18
            }
            pw := Max(1, tw + 2 * WindowPillsPaddingX)
            ph := Max(1, th + 2 * WindowPillsPaddingY)
            items.Push({ gui:obj.gui, ctrl:obj.ctrl, w:pw, h:ph, hwnd:hwnd })
        }

        ; Second pass: compute required reserve height with wrapping
        availableWidth := Max(1, (r.R - r.L) - 2*WindowPillsMarginX)
        totH := WindowPillsMarginY  ; top margin
        lineH := 0
        curW := 0
        for it in items {
            if (curW = 0) {
                curW := it.w
                lineH := Max(lineH, it.h)
            } else if ((curW + WindowPillsGap + it.w) <= availableWidth) {
                curW += WindowPillsGap + it.w
                lineH := Max(lineH, it.h)
            } else {
                totH += lineH + WindowPillsGap
                curW := it.w
                lineH := it.h
            }
        }
        totH += lineH + WindowPillsMarginY  ; bottom margin
        reserveH := Max(WindowPillsMarginY*2 + 1, totH)

        ; Update reserve map and reapply window positions if changed
        try {
            global WindowPillsReserve
            prev := WindowPillsReserve.Has(mon ":" leafId) ? WindowPillsReserve[mon ":" leafId] : -1
            WindowPillsReserve[mon ":" leafId] := reserveH
            if (prev != reserveH) {
                try ReapplySubtree(mon, leafId)
            }
        }

        ; Third pass: place pills above the SnapArea using computed reserve
        x := r.L + WindowPillsMarginX
        y := r.T - reserveH + WindowPillsMarginY
        lineH := 0
        curW := 0
        for it in items {
            pw := it.w, ph := it.h
            if (curW = 0) {
                it.gui.Move(Round(x), Round(y), pw, ph)
                curW := pw
                lineH := Max(lineH, ph)
            } else if ((r.L + WindowPillsMarginX + curW + WindowPillsGap + pw) <= maxX) {
                it.gui.Move(Round(r.L + WindowPillsMarginX + curW + WindowPillsGap), Round(y), pw, ph)
                curW := curW + WindowPillsGap + pw
                lineH := Max(lineH, ph)
            } else {
                y += lineH + WindowPillsGap
                curW := pw
                lineH := ph
                it.gui.Move(Round(r.L + WindowPillsMarginX), Round(y), pw, ph)
            }
            try it.gui.Show("NA")
            WindowPills.pills.Push(it.gui)
        }
    }

    WindowPills.shown := (WindowPills.pills.Length > 0)
    ; Destroy old after new are shown (double buffering)
    for g in oldPills {
        try g.Destroy()
    }
}

WindowPills_UpdateTick(*) {
    try WindowPills_Update()
}

; Start periodic update
SetTimer(WindowPills_UpdateTick, 300)

; --- Click handling ---------------------------------------------------------

WP_OnPillClick(targetHwnd) {
    if (!targetHwnd)
        return
    try {
        if (DllCall("IsWindow", "ptr", targetHwnd) && WinExist("ahk_id " targetHwnd)) {
            ; Bring matching leaf into selection, then activate
            global WinToLeaf
            if (WinToLeaf.Has(targetHwnd)) {
                info := WinToLeaf[targetHwnd]
                SelectLeaf(info.mon, info.leaf, "manual")
            }
            WinActivate "ahk_id " targetHwnd
        }
    }
}

WP_RefreshActiveStyles() {
    try {
        global WindowPills, WinToLeaf
        if (!IsObject(WindowPills) || !WindowPills.pills.Length)
            return
        ; Build active per leaf
        activeMap := Map() ; key mon:leaf -> hwnd
        try sysActive := WinGetID("A")
        for hwnd, info in WinToLeaf {
            key := info.mon ":" info.leaf
            if (!activeMap.Has(key))
                activeMap[key] := LeafGetTopWindow(info.mon, info.leaf)
        }
        if (sysActive && WinToLeaf.Has(sysActive)) {
            st := WinToLeaf[sysActive]
            activeMap[st.mon ":" st.leaf] := sysActive
        }
        ; Update each pill's appearance
        for g in WindowPills.pills {
            guiHwnd := g.Hwnd
            if (!WindowPills.guiToHwnd.Has(guiHwnd))
                continue
            target := WindowPills.guiToHwnd[guiHwnd]
            if (!WinToLeaf.Has(target))
                continue
            info := WinToLeaf[target]
            key := info.mon ":" info.leaf
            isActive := (activeMap.Has(key) && activeMap[key] = target)
            WP_SetPillAppearance(g, isActive)
        }
    }
}

WP_SetPillAppearance(g, isActive) {
    global WindowPillColor, WindowPillColorActive
    global WindowPillsTextColor, WindowPillsActiveTextColor, WindowPillsFont, WindowPillsFontSize
    try {
        g.BackColor := (isActive ? WindowPillColorActive : WindowPillColor)
        ; Update text color via stored control mapping (if available)
        try {
            ctrl := 0
            ; We stored control object when creating; recover via enumeration
            ; Best effort: find a Text control and set font color
            for c in g {
                ctrl := c
                break
            }
            if (ctrl) {
                col := isActive ? WindowPillsActiveTextColor : WindowPillsTextColor
                ctrl.SetFont(Format("s{} {}", WindowPillsFontSize, col), WindowPillsFont)
            }
        }
    }
}

WP_OnMouse(wParam, lParam, msg, hwnd) {
    try {
        global WindowPills
        if (!IsObject(WindowPills) || !WindowPills.HasOwnProp("guiToHwnd"))
            return
        if (WindowPills.guiToHwnd.Has(hwnd)) {
            target := WindowPills.guiToHwnd[hwnd]
            WP_OnPillClick(target)
        }
    }
}
