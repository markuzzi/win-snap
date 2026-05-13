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

WindowPills_StartBadgeRefresh() {
    global WindowPillsBadgeRefreshInterval
    interval := (IsSet(WindowPillsBadgeRefreshInterval) ? WindowPillsBadgeRefreshInterval : 0)
    if (interval > 0)
        SetTimer(WindowPills_BadgeRefreshTick, interval)
}

WindowPills_BadgeRefreshTick(*) {
    global WindowPillsEnabled
    if (!IsSet(WindowPillsEnabled) || !WindowPillsEnabled)
        return
    if (StateGet("ScriptPaused", false))
        return
    try {
        WindowPills_Update()
    }
    catch Error as e {
        LogException(e, "WindowPills_BadgeRefreshTick: update failed")
    }
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

WP_GetPillDisplayText(className, title) {
    global WindowPillsMaxTitle
    badge := WP_ExtractBadgeFromTitle(className, title)
    displayTitle := badge.title
    if (displayTitle = "")
        displayTitle := "(untitled)"
    txt := WP_TruncateTitle(displayTitle, WindowPillsMaxTitle)
    if (badge.count != "")
        txt .= WP_FormatBadgeCount(badge.count)
    return txt
}

WP_ExtractBadgeFromTitle(className, title) {
    global WindowPillsBadgesEnabled, WindowPillsBadgeRules
    if (!IsSet(WindowPillsBadgesEnabled) || !WindowPillsBadgesEnabled)
        return { count:"", title:title }
    if (!IsSet(WindowPillsBadgeRules) || !(WindowPillsBadgeRules is Array))
        return { count:"", title:title }
    for rule in WindowPillsBadgeRules {
        try {
            titleRegex := WP_GetRuleProp(rule, "titleRegex", "")
            if (titleRegex = "")
                continue
            classRegex := WP_GetRuleProp(rule, "classRegex", "")
            if (classRegex != "" && !RegExMatch(className, classRegex))
                continue
            if (!RegExMatch(title, titleRegex, &m))
                continue
            badgeGroup := WP_GetRuleProp(rule, "badgeGroup", 1)
            count := WP_GetMatchGroup(m, badgeGroup)
            if (count = "")
                continue
            count := Trim(count)
            titleGroup := WP_GetRuleProp(rule, "titleGroup", 0)
            displayTitle := title
            if (titleGroup) {
                matchedTitle := Trim(WP_GetMatchGroup(m, titleGroup))
                if (matchedTitle != "")
                    displayTitle := matchedTitle
            }
            return { count:count, title:displayTitle }
        }
        catch Error as e {
            LogException(e, "WP_ExtractBadgeFromTitle: rule failed")
        }
    }
    return { count:"", title:title }
}

WP_GetRuleProp(rule, propName, defaultValue := "") {
    if (!IsObject(rule))
        return defaultValue
    try {
        if (rule is Map) {
            if (rule.Has(propName))
                return rule[propName]
        } else if (rule.HasOwnProp(propName)) {
            return rule.%propName%
        }
    }
    catch Error as e {
    }
    return defaultValue
}

WP_GetMatchGroup(match, groupIndex) {
    try {
        if (groupIndex = "" || groupIndex = 0)
            return ""
        return match[groupIndex]
    }
    catch Error as e {
        return ""
    }
}

WP_FormatBadgeCount(count) {
    global WindowPillsBadgeFormat
    fmt := (IsSet(WindowPillsBadgeFormat) && WindowPillsBadgeFormat != "") ? WindowPillsBadgeFormat : " [{}]"
    try {
        return Format(fmt, count)
    }
    catch Error as e {
        return " [" . count . "]"
    }
}

WP_AddWindowIconPicture(g, targetHwnd, iconSize) {
    path := ""
    try path := WinGetProcessPath("ahk_id " targetHwnd)

    ; MSIX/Store apps often keep their real icon in package PNG assets, not in the exe.
    if (path) {
        pic := WP_TryAddMsixIconPicture(g, path, iconSize)
        if (IsObject(pic))
            return pic
    }

    if (path && FileExist(path)) {
        pic := WP_TryAddExeIconPicture(g, path, iconSize)
        if (IsObject(pic))
            return pic
    }

    pic := WP_TryAddWindowHandleIconPicture(g, targetHwnd, iconSize)
    if (IsObject(pic))
        return pic

    if (path && FileExist(path)) {
        pic := WP_TryAddShellIconPicture(g, path, iconSize)
        if (IsObject(pic))
            return pic
    }

    return 0
}

WP_TryAddExeIconPicture(g, path, iconSize) {
    try {
        return g.AddPicture(Format("xm ym w{} h{} Icon1 BackgroundTrans", iconSize, iconSize), path)
    }
    catch Error as e {
        return 0
    }
}

WP_TryAddWindowHandleIconPicture(g, hwnd, iconSize) {
    hIcon := WP_GetWindowIconHandle(hwnd)
    if (!hIcon)
        return 0
    try {
        return g.AddPicture(Format("xm ym w{} h{} BackgroundTrans", iconSize, iconSize), "HICON:*" hIcon)
    }
    catch Error as e {
        return 0
    }
}

WP_TryAddShellIconPicture(g, path, iconSize) {
    try {
        sfiSize := A_PtrSize + 688
        sfi := Buffer(sfiSize, 0)
        flags := 0x100  ; SHGFI_ICON
        flags |= (iconSize <= 16) ? 0x1 : 0x0  ; SHGFI_SMALLICON / SHGFI_LARGEICON
        if (!DllCall("shell32\SHGetFileInfoW", "WStr", path, "UInt", 0, "Ptr", sfi.Ptr, "UInt", sfiSize, "UInt", flags, "Ptr"))
            return 0
        hIcon := NumGet(sfi, 0, "Ptr")
        if (!hIcon)
            return 0
        pic := 0
        try pic := g.AddPicture(Format("xm ym w{} h{} BackgroundTrans", iconSize, iconSize), "HICON:*" hIcon)
        try DllCall("DestroyIcon", "Ptr", hIcon)
        return IsObject(pic) ? pic : 0
    }
    catch Error as e {
        try {
            if (IsSet(hIcon) && hIcon)
                DllCall("DestroyIcon", "Ptr", hIcon)
        }
        return 0
    }
}

WP_GetWindowIconHandle(hwnd) {
    static WM_GETICON := 0x7F
    if (!hwnd)
        return 0

    for iconType in [2, 0, 1] {  ; ICON_SMALL2, ICON_SMALL, ICON_BIG
        try {
            hIcon := SendMessage(WM_GETICON, iconType, 0,, "ahk_id " hwnd)
            if (hIcon)
                return hIcon
        }
    }

    fn := (A_PtrSize = 8) ? "GetClassLongPtrW" : "GetClassLongW"
    for index in [-34, -14] {  ; GCLP_HICONSM, GCLP_HICON
        try {
            hIcon := DllCall(fn, "Ptr", hwnd, "Int", index, "Ptr")
            if (hIcon)
                return hIcon
        }
    }
    return 0
}

WP_TryAddMsixIconPicture(g, processPath, iconSize) {
    asset := WP_GetMsixIconAsset(processPath, iconSize)
    if (asset = "" || !FileExist(asset))
        return 0
    try {
        return g.AddPicture(Format("xm ym w{} h{} BackgroundTrans", iconSize, iconSize), asset)
    }
    catch Error as e {
        return 0
    }
}

WP_GetMsixIconAsset(processPath, iconSize) {
    static cache := Map()
    packageRoot := WP_FindMsixPackageRoot(processPath)
    if (packageRoot = "")
        return ""

    key := packageRoot "|" iconSize
    if (cache.Has(key))
        return cache[key]

    best := ""
    for relPath in WP_ReadMsixLogoRefs(packageRoot) {
        best := WP_FindBestMsixAsset(packageRoot, relPath, iconSize)
        if (best != "")
            break
    }

    cache[key] := best
    return best
}

WP_FindMsixPackageRoot(path) {
    static cache := Map()
    if (path = "")
        return ""
    if (cache.Has(path))
        return cache[path]

    dir := path
    if (!InStr(FileExist(path), "D")) {
        try SplitPath path, , &dir
    }

    Loop 8 {
        if (dir = "")
            break
        if (FileExist(dir "\AppxManifest.xml")) {
            cache[path] := dir
            return dir
        }
        parent := ""
        try SplitPath dir, , &parent
        if (parent = "" || parent = dir)
            break
        dir := parent
    }
    cache[path] := ""
    return ""
}

WP_ReadMsixLogoRefs(packageRoot) {
    refs := []
    seen := Map()
    manifestPath := packageRoot "\AppxManifest.xml"
    if (!FileExist(manifestPath))
        return refs

    try {
        doc := ComObject("MSXML2.DOMDocument.6.0")
        doc.async := false
        doc.setProperty("SelectionLanguage", "XPath")
        if (!doc.load(manifestPath))
            return refs

        nodes := doc.selectNodes("//*[local-name()='VisualElements']")
        for node in nodes {
            for attr in ["Square44x44Logo", "Square150x150Logo", "Logo"] {
                relPath := node.getAttribute(attr)
                if (relPath != "" && !seen.Has(relPath)) {
                    seen[relPath] := true
                    refs.Push(relPath)
                }
            }
        }
    }
    catch Error as e {
        return refs
    }

    return refs
}

WP_FindBestMsixAsset(packageRoot, relPath, iconSize) {
    base := WP_NormalizeMsixAssetPath(packageRoot, relPath)
    if (base = "")
        return ""

    candidates := []
    seen := Map()
    WP_PushUniquePath(candidates, seen, base)

    try {
        SplitPath base, , &dir, &ext, &nameNoExt
        if (dir != "" && ext != "") {
            Loop Files, dir "\" nameNoExt "*." ext, "F" {
                WP_PushUniquePath(candidates, seen, A_LoopFileFullPath)
            }
        }
    }

    best := ""
    bestScore := 1000000
    for candidate in candidates {
        if (!FileExist(candidate))
            continue
        score := WP_ScoreMsixAsset(candidate, iconSize)
        if (score < bestScore) {
            best := candidate
            bestScore := score
        }
    }
    return best
}

WP_NormalizeMsixAssetPath(packageRoot, relPath) {
    relPath := Trim(relPath)
    if (relPath = "" || InStr(relPath, ":"))
        return ""
    relPath := StrReplace(relPath, "/", "\")
    relPath := RegExReplace(relPath, "^\\+")
    return packageRoot "\" relPath
}

WP_PushUniquePath(arr, seen, path) {
    if (path = "" || seen.Has(path))
        return
    seen[path] := true
    arr.Push(path)
}

WP_ScoreMsixAsset(path, requestedSize) {
    SplitPath path, &fileName
    name := StrLower(fileName)
    score := 5000

    if (RegExMatch(name, "targetsize-(\d+)", &m)) {
        score := Abs(Integer(m[1]) - requestedSize)
    } else if (RegExMatch(name, "scale-(\d+)", &m)) {
        baseSize := 44
        if (RegExMatch(name, "square(\d+)x", &m2))
            baseSize := Integer(m2[1])
        score := 100 + Abs(Round(baseSize * Integer(m[1]) / 100) - requestedSize)
    } else if (RegExMatch(name, "square(\d+)x", &m)) {
        score := 200 + Abs(Integer(m[1]) - requestedSize)
    }

    if (InStr(name, "targetsize"))
        score -= 30
    if (InStr(name, "altform-unplated"))
        score -= 20
    if (InStr(name, "contrast"))
        score += 300
    if (InStr(name, "badge") || InStr(name, "splash"))
        score += 500

    return score
}

WP_BuildStateSignature() {
    ; Create a compact signature of all leaf->window lists and the focused hwnd.
    global LeafWindows, WindowPillsEnabled, WindowPillsMaxTitle
    global WindowPillsBadgesEnabled, WindowPillsBadgeFormat
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
    sig.Push("B:" ((IsSet(WindowPillsBadgesEnabled) && WindowPillsBadgesEnabled) ? 1 : 0))
    sig.Push("BF:" (IsSet(WindowPillsBadgeFormat) ? WindowPillsBadgeFormat : ""))
    entries := []
    for key, arr in LeafWindows {
        ; key is "mon:leaf"
        ids := []
        for hwnd in arr {
            hClass := "", title := ""
            try hClass := WinGetClass("ahk_id " hwnd)
            try title := WinGetTitle("ahk_id " hwnd)
            displayText := WP_GetPillDisplayText(hClass, title)
            ids.Push("" hwnd "#" hClass "#" displayText)
        }
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
    global WindowPillsShowIcons, WindowPillsIconSize, WindowPillsIconGap

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
        pic := WP_AddWindowIconPicture(g, targetHwnd, WindowPillsIconSize)
        iconOk := IsObject(pic)
        if (!iconOk)
            LogDebug("WindowPills: no icon available for pill")
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
                hClass := WinGetClass("ahk_id " hwnd)
            }
            catch Error as e {
                hClass := ""
            }
            try {
                title := WinGetTitle("ahk_id " hwnd)
            }
            catch Error as e {
                title := ""
            }
            if (IsPillBlacklisted(hClass, title))
                continue
            txt := WP_GetPillDisplayText(hClass, title)
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
    BlackList_AddMenuItems(m, targetHwnd)

    m.Add()

    ; Pill-Blacklist
    global PillBlackList
    if (!IsSet(PillBlackList) || !(PillBlackList is Map))
        PillBlackList := Map()
    classKey := "class:" . info.className
    titleKey  := (info.title ? "title:" . info.title : "")
    comboKey  := (info.className && info.title ? "class:" . info.className . "|title:" . info.title : "")
    pillHasClass := (info.className != "" && PillBlackList.Has(classKey))
    pillHasTitle := (titleKey != "" && PillBlackList.Has(titleKey))
    pillHasCombo := (comboKey != "" && PillBlackList.Has(comboKey))

    if (!pillHasClass) {
        m.Add("Zu Pill-Blacklist hinzufuegen (Klasse)", (*) => WP_AddWindowToPillBlacklist(targetHwnd, "class"))
    } else {
        m.Add("Zu Pill-Blacklist hinzufuegen (Klasse) [aktiv]", (*) => 0)
        m.Disable("Zu Pill-Blacklist hinzufuegen (Klasse) [aktiv]")
    }
    if (info.title) {
        if (!pillHasTitle) {
            m.Add("Zu Pill-Blacklist hinzufuegen (Titel)", (*) => WP_AddWindowToPillBlacklist(targetHwnd, "title"))
        } else {
            m.Add("Zu Pill-Blacklist hinzufuegen (Titel) [aktiv]", (*) => 0)
            m.Disable("Zu Pill-Blacklist hinzufuegen (Titel) [aktiv]")
        }
        if (!pillHasCombo) {
            m.Add("Zu Pill-Blacklist hinzufuegen (Klasse+Titel)", (*) => WP_AddWindowToPillBlacklist(targetHwnd, "combo"))
        } else {
            m.Add("Zu Pill-Blacklist hinzufuegen (Klasse+Titel) [aktiv]", (*) => 0)
            m.Disable("Zu Pill-Blacklist hinzufuegen (Klasse+Titel) [aktiv]")
        }
    }
    if (pillHasClass || pillHasTitle || pillHasCombo) {
        m.Add("Aus Pill-Blacklist entfernen", (*) => WP_RemoveWindowFromPillBlacklist(targetHwnd))
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
    try {
        title := WinGetTitle("ahk_id " hwnd)
    } catch {
        title := ""
    }
    if (!exe || !className)
        return 0
    return { exe:exe, className:className, title:title }
}

WP_AddWindowToBlacklist(hwnd, mode := "processClass") {
    BlackList_AddWindowRuleByHwnd(hwnd, mode)
}

WP_AddWindowToPillBlacklist(hwnd, mode) {
    global PillBlackList
    info := WP_GetWindowIdentity(hwnd)
    if (!info)
        return
    if (!IsSet(PillBlackList) || !(PillBlackList is Map))
        PillBlackList := Map()
    if (mode = "class") {
        key   := "class:" . info.className
        label := info.className
    } else if (mode = "title") {
        if (!info.title) {
            ShowTrayTip("Kein Fenstertitel vorhanden", 1500)
            return
        }
        pattern := WP_RequestPillTitleRegex(info.title)
        if (pattern = "")
            return
        key   := "titleRegex:" . pattern
        label := pattern
    } else { ; combo
        if (!info.title) {
            ShowTrayTip("Kein Fenstertitel vorhanden", 1500)
            return
        }
        pattern := WP_RequestPillTitleRegex(info.title)
        if (pattern = "")
            return
        key   := "class:" . info.className . "|titleRegex:" . pattern
        label := info.className . " + " . pattern
    }
    if (PillBlackList.Has(key)) {
        ShowTrayTip("Bereits auf Pill-Blacklist: " . label, 1500)
        return
    }
    PillBlackList[key] := true
    try PillBlackList_Save()
    ShowTrayTip("Pill-Blacklist hinzugefuegt (" . mode . "): " . label, 1500)
    LogInfo(Format("WP_AddWindowToPillBlacklist: added {}={}", mode, label))
    try {
        global WindowPills
        WindowPills.lastSig := ""
    }
    WindowPills_Invalidate()
}

WP_RequestPillTitleRegex(title) {
    defaultPattern := "^" . WP_EscapeRegex(title) . "$"
    try {
        ib := InputBox("Regex fuer den Fenstertitel:", "Pill-Blacklist", "w520 h140", defaultPattern)
    } catch Error as e {
        LogException(e, "WP_RequestPillTitleRegex: InputBox failed")
        return ""
    }
    if (ib.Result != "OK")
        return ""
    pattern := Trim(ib.Value)
    if (pattern = "") {
        ShowTrayTip("Leerer Regex - nicht hinzugefuegt", 1500)
        return ""
    }
    try {
        RegExMatch(title, pattern)
    } catch Error as e {
        MsgBox("Ungueltiger Regex:`n" . pattern, "Pill-Blacklist")
        LogException(e, "WP_RequestPillTitleRegex: invalid regex")
        return ""
    }
    return pattern
}

WP_EscapeRegex(text) {
    special := "\.^$|?*+()[]{}"
    out := ""
    Loop Parse text {
        ch := A_LoopField
        if (InStr(special, ch))
            out .= "\" . ch
        else
            out .= ch
    }
    return out
}

WP_RemoveWindowFromPillBlacklist(hwnd) {
    global PillBlackList
    info := WP_GetWindowIdentity(hwnd)
    if (!info)
        return
    if (!IsSet(PillBlackList) || !(PillBlackList is Map))
        PillBlackList := Map()
    classKey := "class:" . info.className
    titleKey  := (info.title ? "title:" . info.title : "")
    comboKey  := (info.title ? "class:" . info.className . "|title:" . info.title : "")
    changed := false
    if (PillBlackList.Has(classKey))
        PillBlackList.Delete(classKey), changed := true
    if (titleKey && PillBlackList.Has(titleKey))
        PillBlackList.Delete(titleKey), changed := true
    if (comboKey && PillBlackList.Has(comboKey))
        PillBlackList.Delete(comboKey), changed := true
    if (!changed) {
        ShowTrayTip("Nicht auf Pill-Blacklist", 1500)
        return
    }
    try PillBlackList_Save()
    ShowTrayTip("Pill-Blacklist entfernt: " . info.className, 1500)
    LogInfo(Format("WP_RemoveWindowFromPillBlacklist: removed class={}, title={}", info.className, info.title))
    try {
        global WindowPills
        WindowPills.lastSig := ""
    }
    WindowPills_Invalidate()
}

WP_RemoveWindowFromBlacklist(hwnd) {
    BlackList_RemoveWindowRulesByHwnd(hwnd)
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
