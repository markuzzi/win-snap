; =========================
; Leaf-Window-Management
; =========================
LeafKey(mon, leafId) {
    return mon ":" leafId
}

LeafCleanupList(key) {
    global LeafWindows
    if !LeafWindows.Has(key)
        return
    arr := LeafWindows[key]
    idx := 1
    while (idx <= arr.Length) {
        hwnd := arr[idx]
        if !WinExist("ahk_id " hwnd)
            arr.RemoveAt(idx)
        else
            idx++
    }
    if (arr.Length = 0)
        LeafWindows.Delete(key)
}

LeafAttachWindow(hwnd, mon, leafId) {
    global LeafWindows, WinToLeaf
    LeafDetachWindow(hwnd, false)
    key := LeafKey(mon, leafId)
    if !LeafWindows.Has(key)
        LeafWindows[key] := []
    else
        LeafCleanupList(key)
    if !LeafWindows.Has(key)
        LeafWindows[key] := []
    arr := LeafWindows[key]
    idx := 1
    while (idx <= arr.Length) {
        if (arr[idx] = hwnd) {
            arr.RemoveAt(idx)
            break
        }
        idx++
    }
    arr.InsertAt(1, hwnd)
    WinToLeaf[hwnd] := { mon:mon, leaf:leafId }
    SelectLeaf(mon, leafId, "auto")
}

LeafDetachWindow(hwnd, removeMapping := false) {
    global LeafWindows, WinToLeaf
    if !WinToLeaf.Has(hwnd)
        return
    info := WinToLeaf[hwnd]
    key := LeafKey(info.mon, info.leaf)
    if LeafWindows.Has(key) {
        arr := LeafWindows[key]
        idx := 1
        while (idx <= arr.Length) {
            if (arr[idx] = hwnd) {
                arr.RemoveAt(idx)
                break
            }
            idx++
        }
        if (arr.Length = 0)
            LeafWindows.Delete(key)
    }
    if removeMapping
        WinToLeaf.Delete(hwnd)
}

LeafGetTopWindow(mon, leafId) {
    global LeafWindows
    key := LeafKey(mon, leafId)
    if !LeafWindows.Has(key)
        return 0
    arr := LeafWindows[key]
    idx := 1
    while (idx <= arr.Length) {
        hwnd := arr[idx]
        if WinExist("ahk_id " hwnd)
            return hwnd
        arr.RemoveAt(idx)
    }
    if (arr.Length = 0)
        LeafWindows.Delete(key)
    return 0
}

LeafGetOrderedList(mon, leafId) {
    global LeafWindows
    key := LeafKey(mon, leafId)
    if !LeafWindows.Has(key)
        return []
    LeafCleanupList(key)
    if !LeafWindows.Has(key)
        return []
    return LeafWindows[key]
}

LeafHasWindows(mon, leafId) {
    global LeafWindows
    key := LeafKey(mon, leafId)
    if !LeafWindows.Has(key)
        return false
    LeafCleanupList(key)
    if !LeafWindows.Has(key)
        return false
    return LeafWindows[key].Length > 0
}

SelectLeaf(mon, leafId, source := "manual") {
    global CurrentLeafSelection, CurrentHighlight, ManualNav
    if !mon {
        if (source = "manual" || ManualNav.mon = mon)
            ManualNav := {mon:0, leaf:0}
        HideHighlight()
        return
    }
    state := CurrentLeafSelection.Has(mon) ? CurrentLeafSelection[mon] : {leaf:0, source:"auto"}
    if (!leafId) {
        if (source = "auto" && state.source = "manual" && state.leaf && !LeafHasWindows(mon, state.leaf))
            return
        if CurrentLeafSelection.Has(mon)
            CurrentLeafSelection.Delete(mon)
        if (CurrentHighlight.mon = mon)
            HideHighlight()
        if (ManualNav.mon = mon)
            ManualNav := {mon:0, leaf:0}
        return
    }
    if (source = "auto" && state.source = "manual" && state.leaf && state.leaf != leafId && !LeafHasWindows(mon, state.leaf))
        return
    CurrentLeafSelection[mon] := { leaf:leafId, source:source }
    if (source = "manual")
        ManualNav := { mon:mon, leaf:leafId }
    else if (ManualNav.mon = mon)
        ManualNav := {mon:0, leaf:0}
    ApplyLeafHighlight(mon, leafId)
}

GetSelectedLeaf(mon) {
    global CurrentLeafSelection
    if CurrentLeafSelection.Has(mon)
        return CurrentLeafSelection[mon].leaf
    return 0
}

LeafRecordActivation(hwnd) {
    global LeafWindows, WinToLeaf
    if !WinToLeaf.Has(hwnd)
        return
    info := WinToLeaf[hwnd]
    key := LeafKey(info.mon, info.leaf)
    if LeafWindows.Has(key)
        LeafCleanupList(key)
    if !LeafWindows.Has(key)
        LeafWindows[key] := []
    arr := LeafWindows[key]
    idx := 1
    while (idx <= arr.Length) {
        current := arr[idx]
        if (current = hwnd) {
            arr.RemoveAt(idx)
            break
        }
        if !WinExist("ahk_id " current)
            arr.RemoveAt(idx)
        else
            idx++
    }
    arr.InsertAt(1, hwnd)
    SelectLeaf(info.mon, info.leaf, "auto")
}

GetLeafNavigationContext() {
    global CurrentLeafSelection, WinToLeaf, Layouts
    win := GetActiveWindow()
    if win {
        hwnd := win.hwnd
        if WinToLeaf.Has(hwnd) {
            info := WinToLeaf[hwnd]
            return { mon:info.mon, leaf:info.leaf, hwnd:hwnd }
        }
        monInfo := GetMonitorIndexAndArea(hwnd)
        mon := monInfo.index
        Layout_Ensure(mon)
        cx := win.x + win.w/2
        cy := win.y + win.h/2
        leaf := GetSelectedLeaf(mon)
        if !leaf
            leaf := Layout_FindLeafAtPoint(mon, cx, cy)
        return { mon:mon, leaf:leaf, hwnd:hwnd }
    }
    if (MonitorGetCount() = 0)
        return { mon:1, leaf:0, hwnd:0 }
    mon := 1
    Layout_Ensure(mon)
    leaf := GetSelectedLeaf(mon)
    if !leaf
        leaf := Layouts[mon].root
    return { mon:mon, leaf:leaf, hwnd:0 }
}

GetManualNavigationContext() {
    global ManualNav, Layouts
    if (ManualNav.mon && ManualNav.leaf) {
        Layout_Ensure(ManualNav.mon)
        if Layouts[ManualNav.mon].nodes.Has(ManualNav.leaf)
            return { mon:ManualNav.mon, leaf:ManualNav.leaf }
        ManualNav := {mon:0, leaf:0}
    }
    return { mon:0, leaf:0 }
}

ApplyManualNavigation(ctx) {
    nav := GetManualNavigationContext()
    if nav.mon {
        ctx.mon := nav.mon
        ctx.leaf := nav.leaf
    }
    return ctx
}
