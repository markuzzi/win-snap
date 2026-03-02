; =========================
; Window Pills Overlay (floating pills per SnapArea)
; =========================

; Globals and defaults are defined in WinSnap.ahk. This module implements an
; optional overlay that shows small rounded rectangles ("pills") listing the
; window titles inside each SnapArea, anchored at the top-left corner of the
; area. The current window appears with a darker color.

; Track last rebuild time to rate‑limit updates
WindowPills := { pills: [], shown:false, lastSig:"", guiToHwnd: Map(), hooks:false, lastRebuild:0, borderGui:0, zMode:"front", zTarget:0, zApplied:Map() }

WindowPills_Init() {
    global WindowPills
    if (!IsObject(WindowPills))
        WindowPills := { pills: [], shown:false, lastSig:"", guiToHwnd: Map(), hooks:false, borderGui:0, zMode:"front", zTarget:0, zApplied:Map() }
    if (!WindowPills.HasOwnProp("guiToHwnd") || !(WindowPills.guiToHwnd is Map))
        WindowPills.guiToHwnd := Map()
    if (!WindowPills.HasOwnProp("borderGui"))
        WindowPills.borderGui := 0
    if (!WindowPills.HasOwnProp("zMode"))
        WindowPills.zMode := "front"
    if (!WindowPills.HasOwnProp("zTarget"))
        WindowPills.zTarget := 0
    if (!WindowPills.HasOwnProp("zApplied") || !(WindowPills.zApplied is Map))
        WindowPills.zApplied := Map()
    if (!WindowPills.hooks) {
        try {
            OnMessage(0x0201, WP_OnMouse) ; WM_LBUTTONDOWN
            OnMessage(0x0202, WP_OnMouse) ; WM_LBUTTONUP
            WindowPills.hooks := true
        }
        catch Error as e {
            LogError("WindowPills_Init: OnMessage hook failed")
        }
    }
}

WindowPills_Clear() {
    global WindowPills
    global WindowPillsReserve
    WindowPills_Init()
    for pill in WindowPills.pills {
        try {
            pill.Destroy()
        }
        catch Error as e {
            LogError("WindowPills_Clear: pill.Destroy failed")
        }
    }
    WindowPills.pills := []
    WindowPills.shown := false
    WP_HideActivePillBorder()
    ; Keep WindowPillsReserve to avoid unnecessary window reapply flicker
    try {
        WindowPills.guiToHwnd := Map()
        WindowPills.zApplied := Map()
    }
    catch Error as e {
        LogException(e, "WindowPills_Clear: reset guiToHwnd failed")
    }
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
                try {
                    ReapplySubtree(mon, Layouts[mon].root)
                }
                catch Error as e {
                    LogError("WindowPills_Toggle: ReapplySubtree failed")
                }
            }
        }
        catch Error as e {
            LogError("WindowPills_Toggle: reclaim loop failed")
        }
    } else {
        ; Force immediate update to compute reserves and render pills
        global WindowPills
        try {
            WindowPills.lastSig := ""
        }
        catch Error as e {
            LogError("WindowPills_Toggle: reset lastSig failed")
        }
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
    try {
        focused := WinGetID("A")
    }
    catch Error as e {
        focused := 0
    }
    sig.Push("E:" (WindowPillsEnabled ? 1 : 0))
    sig.Push("M:" (IsSet(WindowPillsMaxTitle) ? WindowPillsMaxTitle : 20))
    entries := []
    for key, arr in LeafWindows {
        ; key is "mon:leaf"
        ids := []
        for hwnd in arr
            ids.Push("" hwnd)
        ; sort ids for stability
        try {
            ids := ArraySort(ids, StrCompare)
        }
        catch Error as e {
            LogException(e, "WindowPills: sorting signature ids failed")
        }
        ; geometry
        mon := 0, leaf := 0
        try {
            parts := StrSplit(key, ":")
            if (parts.Length >= 2) {
                mon := parts[1] + 0
                leaf := parts[2] + 0
            }
        }
        catch Error as e {
            LogException(e, "WindowPills: parsing signature key failed")
        }
        rectSig := "@(0,0,0,0)"
        if (mon && leaf) {
            try {
                r := GetLeafRectPx(mon, leaf)
                rectSig := Format("@({},{},{},{})", Round(r.L), Round(r.T), Round(r.R), Round(r.B))
            }
            catch Error as e {
                LogException(e, "WindowPills: GetLeafRectPx failed for signature")
            }
        }
        entries.Push(key ":" StrJoin(ids, ",") rectSig)
    }
    ; sort entries for stable signature
    try {
        entries := ArraySort(entries, StrCompare)
    }
    catch Error as e {
        LogException(e, "WindowPills: sorting signature entries failed")
    }
    sig.Push("L:" StrJoin(entries, "|"))
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
    global WindowPillsShowIcons, WindowPillsIconSize

    color := isActive ? WindowPillColorActive : WindowPillColor
    tColor := isActive ? WindowPillsActiveTextColor : WindowPillsTextColor

    ; Layered + NoActivate; use pixel coordinates (no DPI scaling) for exact alignment
    ; 0x80000 (WS_EX_LAYERED) | 0x08000000 (WS_EX_NOACTIVATE)
    style := "+AlwaysOnTop -Caption +ToolWindow +E0x08080000 -DPIScale"
    g := Gui(style)
    g.BackColor := color
    try {
        WinSetTransparent(WindowPillsOpacity, g)
    }
    catch Error as e {
        LogException(e, "WindowPills: WinSetTransparent failed")
    }
    try {
        g.SetFont(Format("s{} {}", WindowPillsFontSize, tColor), WindowPillsFont)
    }
    catch Error as e {
        LogException(e, "WindowPills: SetFont failed")
    }
    pic := 0
    iconOk := false
    if (IsSet(WindowPillsShowIcons) && WindowPillsShowIcons && targetHwnd) {
        try {
            path := WinGetProcessPath("ahk_id " targetHwnd)
            if (path && FileExist(path)) {
                pic := g.AddPicture(Format("xm ym w{} h{} Icon1 BackgroundTrans", WindowPillsIconSize, WindowPillsIconSize), path)
                iconOk := true
            }
        }
        catch Error as e {
            LogDebug("WindowPills: AddPicture (icon) failed")
        }
    }
    ctrl := g.AddText("x+0 ym +0x0100 BackgroundTrans", text) ; +SS_NOTIFY for click

    ; Initial show off-screen to allow proper measurement
    g.Show("NA Hide")
    ctrl.GetPos(, , &tw, &th)
    contentW := tw + (iconOk ? (WindowPillsIconSize + WindowPillsIconGap) : 0)
    contentH := Max(th, iconOk ? WindowPillsIconSize : th)
    w := Max(1, contentW + 2 * WindowPillsPaddingX)
    h := Max(1, contentH + 2 * WindowPillsPaddingY)

    ; Rounded region
    WP_SetPillRegion(g, w, h)

    ; Center text within pill by adding padding offset
    ; Layout content: icon (if any) + gap + text, vertically centered
    tx := WindowPillsPaddingX + (iconOk ? (WindowPillsIconSize + WindowPillsIconGap) : 0)
    ty := WindowPillsPaddingY + Floor((h - 2*WindowPillsPaddingY - th) / 2)
    if (iconOk) {
        ix := WindowPillsPaddingX
        iy := WindowPillsPaddingY + Floor((h - 2*WindowPillsPaddingY - WindowPillsIconSize) / 2)
        try {
            pic.Move(ix, iy, WindowPillsIconSize, WindowPillsIconSize)
        }
        catch Error as e {
            LogError("WindowPills: icon Move failed")
        }
    }
    ctrl.Move(tx, ty)

    g.Move(Round(x), Round(y), w, h)
    ; visible state will be controlled by caller (shown after final placement)
    ; Register click mapping
    try {
        global WindowPills
        if (targetHwnd)
            WindowPills.guiToHwnd[g.Hwnd] := targetHwnd
        if (IsObject(g))
            g.OnEvent("ContextMenu", (*) => WP_OnPillContextMenu(targetHwnd))
        if (IsObject(ctrl))
            ctrl.OnEvent("Click", (*) => WP_OnPillClick(targetHwnd))
        if (IsObject(ctrl))
            ctrl.OnEvent("ContextMenu", (*) => WP_OnPillContextMenu(targetHwnd))
        if (IsObject(pic))
            pic.OnEvent("Click", (*) => WP_OnPillClick(targetHwnd))
        if (IsObject(pic))
            pic.OnEvent("ContextMenu", (*) => WP_OnPillContextMenu(targetHwnd))
    }
    catch Error as e {
        LogException(e, "WindowPills: event hookup failed")
    }
    ; return as object to allow later updates
    return { gui:g, ctrl:ctrl, pic:pic }
}

; --- Layout/update ---------------------------------------------------------

WindowPills_Update() {
    global WindowPillsEnabled
    if (!IsSet(WindowPillsEnabled) || !WindowPillsEnabled) {
        WindowPills_Clear()
        return
    }
    if (StateGet("ScriptPaused", false)) {
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
    ; Rate‑limit rebuilds slightly to avoid flicker when geometry bounces
    try {
        global WindowPillsMinRebuildInterval
        minGap := (IsSet(WindowPillsMinRebuildInterval) ? WindowPillsMinRebuildInterval : 250)
    }
    catch {
        minGap := 250
    }
    now := A_TickCount
    if ((now - WindowPills.lastRebuild) < minGap) {
        ; Defer once
        SetTimer(WindowPills_UpdateTick, -minGap)
        return
    }
    WindowPills.lastSig := sig
    WindowPills.lastRebuild := now

    ; Double-buffered rebuild to avoid visible gaps
    global WindowPills
    oldPills := WindowPills.pills
    WindowPills.pills := []
    WindowPills.guiToHwnd := Map()

    ; Iterate all leaves with windows
    for key, arr in LeafWindows {
        ; Proactively drop dead hwnds so pills vanish immediately after close
        try {
            LeafCleanupList(key)
            if (LeafWindows.Has(key))
                arr := LeafWindows[key]
            else
                arr := []
        }
        catch Error as e {
            LogException(e, "WindowPills_Update: LeafCleanupList failed")
        }
        ; Parse key "mon:leaf"
        parts := StrSplit(key, ":")
        if (parts.Length != 2)
            continue
        mon := parts[1] + 0
        leafId := parts[2] + 0

        ; Validate rect
        try {
            r := GetLeafRectPx(mon, leafId)
        }
        catch Error as e {
            r := 0
            LogError("WindowPills_Update: GetLeafRectPx failed")
        }
        if (!IsObject(r))
            continue

        ; Determine which hwnd should be highlighted for this leaf
        activeHwnd := 0
        try {
            sysActive := WinGetID("A")
        }
        catch Error as e {
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
        items := []  ; each: { gui, ctrl, pic, w, h, hwnd }
        for hwnd in arr {
            try {
                title := WinGetTitle("ahk_id " hwnd)
            }
            catch Error as e {
                title := ""
            }
            if (title = "")
                title := "(untitled)"
            txt := WP_TruncateTitle(title, WindowPillsMaxTitle)
            isActive := (hwnd = activeHwnd)
            obj := WP_CreatePill(-10000, -10000, txt, isActive, hwnd)
            ; measure
            try {
                obj.ctrl.GetPos(, , &tw, &th)
            }
            catch Error as e {
                tw := 40, th := 18
            }
            hasIcon := (IsSet(WindowPillsShowIcons) && WindowPillsShowIcons && obj.HasOwnProp("pic") && obj.pic)
            contentW := tw + (hasIcon ? (WindowPillsIconSize + WindowPillsIconGap) : 0)
            contentH := Max(th, hasIcon ? WindowPillsIconSize : th)
            pw := Max(1, contentW + 2 * WindowPillsPaddingX)
            ph := Max(1, contentH + 2 * WindowPillsPaddingY)
            items.Push({ gui:obj.gui, ctrl:obj.ctrl, pic:obj.pic, w:pw, h:ph, hwnd:hwnd })
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

        ; Update reserve map and reapply window positions if changed (with tolerance)
        try {
            global WindowPillsReserve
            prev := WindowPillsReserve.Has(mon ":" leafId) ? WindowPillsReserve[mon ":" leafId] : -1
            WindowPillsReserve[mon ":" leafId] := reserveH
            tol := 0
            try {
                global WindowPillsReserveChangeTolerance
                tol := IsSet(WindowPillsReserveChangeTolerance) ? WindowPillsReserveChangeTolerance : 2
            }
            catch {
                tol := 2
            }
            if (Abs(prev - reserveH) >= tol) {
                try {
                    ReapplySubtree(mon, leafId)
                }
                catch Error as e {
                    LogError("WindowPills_Update: ReapplySubtree failed")
                }
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
            try {
                it.gui.Show("NA")
            }
            catch Error as e {
                LogError("WindowPills_Update: show pill failed (first)")
            }
                WP_SetPillRegion(it.gui, pw, ph)
                WP_ApplyDwmCorners(it.gui)
                WP_LayoutPillContent(it.gui, it.ctrl, it.pic, pw, ph)
                curW := pw
                lineH := Max(lineH, ph)
            } else if ((r.L + WindowPillsMarginX + curW + WindowPillsGap + pw) <= maxX) {
                it.gui.Move(Round(r.L + WindowPillsMarginX + curW + WindowPillsGap), Round(y), pw, ph)
                try {
                    it.gui.Show("NA")
                }
                catch Error as e {
                    LogError("WindowPills_Update: show pill failed (inline)")
                }
                WP_SetPillRegion(it.gui, pw, ph)
                WP_ApplyDwmCorners(it.gui)
                WP_LayoutPillContent(it.gui, it.ctrl, it.pic, pw, ph)
                curW := curW + WindowPillsGap + pw
                lineH := Max(lineH, ph)
            } else {
                y += lineH + WindowPillsGap
                curW := pw
                lineH := ph
                it.gui.Move(Round(r.L + WindowPillsMarginX), Round(y), pw, ph)
                try {
                    it.gui.Show("NA")
                }
                catch Error as e {
                    LogError("WindowPills_Update: show pill failed (wrap)")
                }
                WP_SetPillRegion(it.gui, pw, ph)
                WP_ApplyDwmCorners(it.gui)
                WP_LayoutPillContent(it.gui, it.ctrl, it.pic, pw, ph)
            }
            WindowPills.pills.Push(it.gui)
        }
    }

    WindowPills.shown := (WindowPills.pills.Length > 0)
    WP_RefreshActiveStyles()
    ; Destroy old after new are shown (double buffering)
    for g in oldPills {
        try {
            g.Destroy()
        }
        catch Error as e {
            LogError("WindowPills_Update: destroy old pill failed")
        }
    }
}

WindowPills_UpdateTick(*) {
    try {
        WindowPills_Update()
    }
    catch Error as e {
        LogException(e, "WindowPills_UpdateTick: update failed")
    }
}

; --- Click handling ---------------------------------------------------------

WP_SetPillRegion(gui, w, h) {
    try {
        global WindowPillsRadius
        radius := WindowPillsRadius
        hRgn := DllCall("CreateRoundRectRgn", "Int", 0, "Int", 0, "Int", w, "Int", h, "Int", radius, "Int", radius, "Ptr")
        if (hRgn)
            DllCall("SetWindowRgn", "Ptr", gui.Hwnd, "Ptr", hRgn, "Int", true)
    }
    catch Error as e {
        LogException(e, "WP_SetPillRegion: failed to set region")
    }
}

WP_SetRingRegion(gui, w, h, radius, borderPx) {
    try {
        outerRgn := DllCall("CreateRoundRectRgn", "Int", 0, "Int", 0, "Int", w, "Int", h, "Int", radius, "Int", radius, "Ptr")
        innerRadius := Max(2, radius - borderPx)
        innerRgn := DllCall("CreateRoundRectRgn", "Int", borderPx, "Int", borderPx, "Int", w - borderPx, "Int", h - borderPx, "Int", innerRadius, "Int", innerRadius, "Ptr")
        ringRgn := DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", 0, "Int", 0, "Ptr")
        DllCall("CombineRgn", "Ptr", ringRgn, "Ptr", outerRgn, "Ptr", innerRgn, "Int", 4) ; RGN_DIFF
        DllCall("SetWindowRgn", "Ptr", gui.Hwnd, "Ptr", ringRgn, "Int", true)
        DllCall("DeleteObject", "Ptr", outerRgn)
        DllCall("DeleteObject", "Ptr", innerRgn)
    }
    catch Error as e {
        LogException(e, "WP_SetRingRegion: failed")
    }
}

WP_EnsureActivePillBorderGui() {
    global WindowPills, WindowPillsActiveBorderColor
    try {
        if (IsObject(WindowPills.borderGui))
            return WindowPills.borderGui
        ; Layered + no-activate + click-through
        style := "+AlwaysOnTop -Caption +ToolWindow +E0x08080020 -DPIScale"
        g := Gui(style)
        g.BackColor := WindowPillsActiveBorderColor
        try WinSetTransparent(255, g)
        WindowPills.borderGui := g
        return g
    }
    catch Error as e {
        LogException(e, "WP_EnsureActivePillBorderGui: failed")
        return 0
    }
}

WP_HideActivePillBorder() {
    global WindowPills
    try {
        if (IsObject(WindowPills.borderGui))
            WindowPills.borderGui.Hide()
    }
    catch Error as e {
        LogException(e, "WP_HideActivePillBorder: failed")
    }
}

WP_ShowActivePillBorder(pillGui) {
    global WindowPillsActiveBorderPx, WindowPillsRadius
    if (!IsObject(pillGui))
        return
    g := WP_EnsureActivePillBorderGui()
    if (!IsObject(g))
        return
    try {
        WinGetPos(&x, &y, &w, &h, "ahk_id " pillGui.Hwnd)
        b := Max(1, WindowPillsActiveBorderPx)
        bx := x - b
        by := y - b
        bw := w + (2 * b)
        bh := h + (2 * b)
        g.Move(Round(bx), Round(by), Round(bw), Round(bh))
        WP_SetRingRegion(g, bw, bh, WindowPillsRadius +10 + b, b)
        g.Show("NA")
    }
    catch Error as e {
        LogException(e, "WP_ShowActivePillBorder: failed")
    }
}

WP_LayoutPillContent(gui, ctrlText, ctrlPic, w, h) {
    try {
        global WindowPillsPaddingX, WindowPillsPaddingY, WindowPillsIconGap, WindowPillsIconSize
        ctrlText.GetPos(, , &tw, &th)
        tx := WindowPillsPaddingX
        if (IsObject(ctrlPic)) {
            ix := WindowPillsPaddingX
            iy := WindowPillsPaddingY + Floor((h - 2*WindowPillsPaddingY - WindowPillsIconSize) / 2)
            ctrlPic.Move(ix, iy, WindowPillsIconSize, WindowPillsIconSize)
            tx += WindowPillsIconSize + WindowPillsIconGap
        }
        ty := WindowPillsPaddingY + Floor((h - 2*WindowPillsPaddingY - th) / 2)
        ctrlText.Move(tx, ty)
    }
    catch Error as e {
        LogException(e, "WP_LayoutPillContent: layout failed")
    }
}

WP_ApplyDwmCorners(gui) {
    try {
        pref := Buffer(4, 0)  ; 4 Bytes für int (DWMWCP_ROUND = 2)
        NumPut("Int", 2, pref)
        DllCall("dwmapi\DwmSetWindowAttribute", "ptr", gui.Hwnd, "int", 33, "ptr", pref.Ptr, "int", 4, "int")
    }
    catch Error as e {
        LogException(e, "WP_ApplyDwmCorners: DWM attribute failed")
    }
}

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
    catch Error as e {
        LogException(e, "WP_OnPillClick: failed")
    }
}

WP_OnPillContextMenu(targetHwnd) {
    global WindowPills
    if (!targetHwnd)
        return
    now := A_TickCount
    lastTick := (IsObject(WindowPills) && WindowPills.HasOwnProp("ctxTick")) ? WindowPills.ctxTick : 0
    lastHwnd := (IsObject(WindowPills) && WindowPills.HasOwnProp("ctxHwnd")) ? WindowPills.ctxHwnd : 0
    if (targetHwnd = lastHwnd && (now - lastTick) < 200)
        return
    if (IsObject(WindowPills)) {
        WindowPills.ctxTick := now
        WindowPills.ctxHwnd := targetHwnd
    }
    info := WP_GetWindowIdentity(targetHwnd)
    if (!info)
        return
    label := info.exe
    if (info.className)
        label := label . " (" . info.className . ")"

    m := Menu()
    isBlack := IsBlacklistedExe(info.exe, info.className)
    if (isBlack) {
        m.Add("Aus AutoSnap-Blacklist entfernen", (*) => WP_RemoveWindowFromBlacklist(targetHwnd))
        m.Add("Zu AutoSnap-Blacklist hinzufuegen", (*) => 0)
        m.Disable("Zu AutoSnap-Blacklist hinzufuegen")
    } else {
        m.Add("Zu AutoSnap-Blacklist hinzufuegen", (*) => WP_AddWindowToBlacklist(targetHwnd))
        m.Add("Aus AutoSnap-Blacklist entfernen", (*) => 0)
        m.Disable("Aus AutoSnap-Blacklist entfernen")
    }
    m.Add()
    m.Add("Fenster aktivieren", (*) => WP_OnPillClick(targetHwnd))
    m.Add("Info: " . label, (*) => 0)
    m.Add("Close", (*) => WP_CloseWindowOrApplication(targetHwnd))
    m.Disable("Info: " . label)
    try {
        m.Show()
    }
    catch Error as e {
        LogException(e, "WP_OnPillContextMenu: menu.Show failed")
    }
}

WP_CloseWindowOrApplication(hwnd) {
    if (!hwnd)
        return
    if (!DllCall("IsWindow", "ptr", hwnd) || !WinExist("ahk_id " hwnd))
        return
    try {
        WinClose("ahk_id " hwnd)
        LogInfo(Format("WP_CloseWindowOrApplication: sent WinClose to hwnd={}", hwnd))
    }
    catch Error as e {
        LogException(e, "WP_CloseWindowOrApplication: WinClose failed")
    }
}

WP_GetWindowIdentity(hwnd) {
    if (!hwnd)
        return 0
    if (!DllCall("IsWindow", "ptr", hwnd) || !WinExist("ahk_id " hwnd))
        return 0
    try {
        exe := WinGetProcessName("ahk_id " hwnd)
    } catch {
        exe := ""
    }
    try {
        className := WinGetClass("ahk_id " hwnd)
    } catch {
        className := ""
    }
    if (!exe || !className)
        return 0
    return { exe:exe, className:className }
}

WP_AddWindowToBlacklist(hwnd) {
    global AutoSnapBlackList
    info := WP_GetWindowIdentity(hwnd)
    if (!info)
        return
    if (!IsSet(AutoSnapBlackList) || !(AutoSnapBlackList is Map))
        AutoSnapBlackList := Map()
    comboKey := "exe:" . StrLower(info.exe) . "|class:" . info.className
    if (AutoSnapBlackList.Has(comboKey)) {
        ShowTrayTip("Bereits auf AutoSnap-Blacklist: " . info.exe . " (" . info.className . ")", 1500)
        return
    }
    AutoSnapBlackList[comboKey] := true
    try BlackList_Save()
    ShowTrayTip("AutoSnap Blacklist hinzugefuegt: " . info.exe . " (" . info.className . ")", 1500)
    LogInfo(Format("WP_AddWindowToBlacklist: added exe={}, class={}", info.exe, info.className))
}

WP_RemoveWindowFromBlacklist(hwnd) {
    global AutoSnapBlackList
    info := WP_GetWindowIdentity(hwnd)
    if (!info)
        return
    if (!IsSet(AutoSnapBlackList) || !(AutoSnapBlackList is Map))
        AutoSnapBlackList := Map()
    exeKey := "exe:" . StrLower(info.exe)
    classKey := "class:" . info.className
    comboKey := exeKey . "|" . classKey
    changed := false
    if (AutoSnapBlackList.Has(comboKey))
        AutoSnapBlackList.Delete(comboKey), changed := true
    if (AutoSnapBlackList.Has(exeKey))
        AutoSnapBlackList.Delete(exeKey), changed := true
    if (AutoSnapBlackList.Has(classKey))
        AutoSnapBlackList.Delete(classKey), changed := true
    if (!changed) {
        ShowTrayTip("Nicht auf AutoSnap-Blacklist: " . info.exe . " (" . info.className . ")", 1500)
        return
    }
    try BlackList_Save()
    ShowTrayTip("AutoSnap Blacklist entfernt: " . info.exe . " (" . info.className . ")", 1500)
    LogInfo(Format("WP_RemoveWindowFromBlacklist: removed exe={}, class={}", info.exe, info.className))
}

WP_RefreshActiveStyles() {
    try {
        global WindowPills, WinToLeaf, CurrentHighlight
        if (!IsObject(WindowPills) || !WindowPills.pills.Length) {
            WP_HideActivePillBorder()
            WP_ApplyZOrderMode()
            return
        }
        ; Build active per leaf
        activeMap := Map() ; key mon:leaf -> hwnd
        try {
            sysActive := WinGetID("A")
        }
        catch Error as e {
            sysActive := 0
        }
        for hwnd, info in WinToLeaf {
            key := info.mon ":" info.leaf
            if (!activeMap.Has(key))
                activeMap[key] := LeafGetTopWindow(info.mon, info.leaf)
        }
        if (sysActive && WinToLeaf.Has(sysActive)) {
            st := WinToLeaf[sysActive]
            activeMap[st.mon ":" st.leaf] := sysActive
        }
        ; Determine the currently active SnapArea (prefer focused window's monitor/selection)
        activeAreaMon := 0
        activeAreaLeaf := 0
        if (sysActive && WinToLeaf.Has(sysActive)) {
            ai := WinToLeaf[sysActive]
            activeAreaMon := ai.mon
            selected := GetSelectedLeaf(ai.mon)
            activeAreaLeaf := selected ? selected : ai.leaf
        } else if (CurrentHighlight.mon && CurrentHighlight.leaf) {
            activeAreaMon := CurrentHighlight.mon
            activeAreaLeaf := CurrentHighlight.leaf
        }

        ; Update each pill's appearance
        borderShown := false
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
            isInActiveArea := (activeAreaMon = info.mon && activeAreaLeaf = info.leaf)
            WP_SetPillAppearance(g, isActive)
            if (isActive && isInActiveArea && !borderShown) {
                WP_ShowActivePillBorder(g)
                borderShown := true
            }
        }
        if (!borderShown)
            WP_HideActivePillBorder()
        WP_ApplyZOrderMode()
    }
    catch Error as e {
        LogException(e, "WP_RefreshActiveStyles: failed")
    }
}

; Schiebt alle Pills hinter ein Ziel-Fenster (fuer Maximize/Restore-Flow).
WindowPills_SendBehindWindow(targetHwnd) {
    global WindowPills
    WindowPills_Init()
    if (!targetHwnd)
        return
    if (!DllCall("IsWindow", "ptr", targetHwnd) || !WinExist("ahk_id " targetHwnd))
        return
    WindowPills.zMode := "behind"
    WindowPills.zTarget := targetHwnd
    WP_ApplyZOrderMode()
}

; Stellt die uebliche Topmost-zOrder fuer Pills wieder her.
WindowPills_BringToFront() {
    global WindowPills
    WindowPills_Init()
    WindowPills.zMode := "front"
    WindowPills.zTarget := 0
    WP_ApplyZOrderMode()
}

WP_ApplyZOrderMode() {
    global WindowPills
    WindowPills_Init()
    mode := WindowPills.zMode
    target := WindowPills.zTarget

    if (mode = "behind") {
        if (!target || !DllCall("IsWindow", "ptr", target) || !WinExist("ahk_id " target)) {
            mode := "front"
            target := 0
            WindowPills.zMode := mode
            WindowPills.zTarget := target
        }
    }

    ; Clean up stale z-order cache entries for destroyed GUIs.
    valid := Map()
    for g in WindowPills.pills {
        valid[g.Hwnd] := true
        WP_ApplyGuiZOrder(g, mode, target)
    }
    if (IsObject(WindowPills.borderGui))
        valid[WindowPills.borderGui.Hwnd] := true
    staleKeys := []
    for k in WindowPills.zApplied {
        if (!valid.Has(k))
            staleKeys.Push(k)
    }
    for k in staleKeys
        WindowPills.zApplied.Delete(k)

    if (IsObject(WindowPills.borderGui))
        WP_ApplyGuiZOrder(WindowPills.borderGui, mode, target)
}

WP_ApplyGuiZOrder(guiObj, mode := "front", targetHwnd := 0) {
    global WindowPills
    if (!IsObject(guiObj))
        return
    ghwnd := guiObj.Hwnd
    if (!ghwnd)
        return
    if (!DllCall("IsWindow", "ptr", ghwnd) || !WinExist("ahk_id " ghwnd))
        return

    SWP_NOSIZE := 0x0001
    SWP_NOMOVE := 0x0002
    SWP_NOACTIVATE := 0x0010
    SWP_NOOWNERZORDER := 0x0200
    flags := SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE | SWP_NOOWNERZORDER

    cacheKey := mode ":" targetHwnd
    if (WindowPills.zApplied.Has(ghwnd) && WindowPills.zApplied[ghwnd] = cacheKey)
        return

    try {
        if (mode = "behind" && targetHwnd) {
            WinSetAlwaysOnTop(0, "ahk_id " ghwnd)
            DllCall("SetWindowPos", "ptr", ghwnd, "ptr", targetHwnd, "int", 0, "int", 0, "int", 0, "int", 0, "uint", flags)
        } else {
            WinSetAlwaysOnTop(1, "ahk_id " ghwnd)
            DllCall("SetWindowPos", "ptr", ghwnd, "ptr", -1, "int", 0, "int", 0, "int", 0, "int", 0, "uint", flags)
        }
        WindowPills.zApplied[ghwnd] := cacheKey
    }
    catch Error as e {
        if (WindowPills.zApplied.Has(ghwnd))
            WindowPills.zApplied.Delete(ghwnd)
        LogException(e, "WP_ApplyGuiZOrder: failed")
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
            ; Find a Text control specifically
            for c in g {
                try {
                    t := c.Type
                }
                catch Error as e {
                    t := ""
                }
                if (t = "Text") {
                    ctrl := c
                    break
                }
            }
            if (ctrl) {
                col := isActive ? WindowPillsActiveTextColor : WindowPillsTextColor
                try {
                    ctrl.SetFont(Format("s{} {}", WindowPillsFontSize, col), WindowPillsFont)
                }
                catch Error as e {
                    LogError("WP_SetPillAppearance: SetFont failed")
                }
            }
        }
        catch Error as e {
            LogError("WP_SetPillAppearance: inner failed")
        }
    }
    catch Error as e {
        LogException(e, "WP_SetPillAppearance: outer failed")
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
    catch Error as e {
        LogException(e, "WP_OnMouse: failed")
    }
}

; External invalidation: force a rebuild on next tick
WindowPills_Invalidate() {
    try {
        ; Schedule a one-shot update shortly after the triggering event.
        ; This keeps updates event-driven without a continuous timer.
        SetTimer(WindowPills_UpdateTick, -10)
    }
    catch Error as e {
        LogException(e, "WindowPills_Invalidate: schedule update failed")
    }
}
