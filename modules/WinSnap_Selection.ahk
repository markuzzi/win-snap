; =========================
; Leaf Selection & Navigation
; =========================
; Steuert, ob LeafRecordActivation die Reihenfolge der Fensterliste umsortiert.
; Wird von CycleWindowInLeaf temporaer gesetzt, um toggling zu vermeiden.
global SuppressActivationReorder := false
; Prueft, ob die Leaf-Area Fenster enthaelt.
LeafHasWindows(mon, leafId) {
    global LeafWindows
    key := LeafKey(mon, leafId)
    if (!LeafWindows.Has(key))
        return false
    LeafCleanupList(key)
    if (!LeafWindows.Has(key))
        return false
    return LeafWindows[key].Length > 0
}

; Setzt die aktuelle Leaf-Auswahl (manuell/auto) und aktualisiert Highlight.
SelectLeaf(mon, leafId, source := "manual") {
    global CurrentLeafSelection, CurrentHighlight
    if (!mon) {
        if (source = "manual")
            ManualNav_Clear()
        HideHighlight()
        return
    }
    state := CurrentLeafSelection.Has(mon) ? CurrentLeafSelection[mon] : {leaf:0, source:"auto"}
    if (!leafId) {
        if (source = "auto" && state.source = "manual" && state.leaf && !LeafHasWindows(mon, state.leaf))
            return
        if (CurrentLeafSelection.Has(mon))
            CurrentLeafSelection.Delete(mon)
        if (CurrentHighlight.mon = mon)
            HideHighlight()
        ManualNav_Clear(mon)
        return
    }
    if (source = "auto" && state.source = "manual" && state.leaf && state.leaf != leafId && !LeafHasWindows(mon, state.leaf))
        return
    CurrentLeafSelection[mon] := { leaf:leafId, source:source }
    if (source = "manual")
        ManualNav_Set(mon, leafId)
    else
        ManualNav_Clear(mon)
    ApplyLeafHighlight(mon, leafId)
    try {
        WindowPills_Invalidate()
    }
    catch Error as e {
        LogException(e, "SelectLeaf: WindowPills_Invalidate failed")
    }
}

; Liefert die aktuell ausgewaehlte Leaf-Id fuer den Monitor.
GetSelectedLeaf(mon) {
    global CurrentLeafSelection
    if (CurrentLeafSelection.Has(mon))
        return CurrentLeafSelection[mon].leaf
    return 0
}

; Merkt Aktivierung eines Fensters und setzt es in der Leaf-Liste nach oben.
LeafRecordActivation(hwnd) {
    global LeafWindows, WinToLeaf
    if (!WinToLeaf.Has(hwnd))
        return
    info := WinToLeaf[hwnd]
    key := LeafKey(info.mon, info.leaf)
    if (LeafWindows.Has(key))
        LeafCleanupList(key)
    if (!LeafWindows.Has(key))
        LeafWindows[key] := []
    arr := LeafWindows[key]
    ; Wenn Unterdrueckung aktiv ist, Liste nur bereinigen und sicherstellen,
    ; dass hwnd enthalten ist, ohne die Reihenfolge zu verschieben.
    if (IsSet(SuppressActivationReorder) && SuppressActivationReorder) {
        found := false
        idx := 1
        while (idx <= arr.Length) {
            current := arr[idx]
            try {
                exists := WinExist("ahk_id " current)
            } catch {
                exists := false
            }
            if (current = hwnd)
                found := true
            if (!exists) {
                arr.RemoveAt(idx)
                continue
            }
            idx++
        }
        if (!found)
            arr.Push(hwnd)
        SelectLeaf(info.mon, info.leaf, "auto")
        return
    }
    ; Standard: Aktiviertes Fenster nach vorn ziehen.
    idx := 1
    while (idx <= arr.Length) {
        current := arr[idx]
        try {
            exists := WinExist("ahk_id " current)
        } catch {
            exists := false
        }
        if (current = hwnd) {
            arr.RemoveAt(idx)
            break
        }
        if (!exists)
            arr.RemoveAt(idx)
        else
            idx++
    }
    arr.InsertAt(1, hwnd)
    SelectLeaf(info.mon, info.leaf, "auto")

    try {
        WindowPills_Invalidate()
    }
    catch Error as e {
        LogException(e, "LeafRecordActivation: WindowPills_Invalidate failed")
    }
}

; Ermittelt Navigationskontext (Monitor, Leaf, hwnd) anhand aktivem Fenster.
GetLeafNavigationContext() {
    global CurrentLeafSelection, WinToLeaf, Layouts
    win := GetActiveWindow()
    if (win) {
        hwnd := win.hwnd
        if (WinToLeaf.Has(hwnd)) {
            info := WinToLeaf[hwnd]
            return { mon:info.mon, leaf:info.leaf, hwnd:hwnd }
        }
        monInfo := GetMonitorIndexAndArea(hwnd)
        mon := monInfo.index
        Layout_Ensure(mon)
        cx := win.x + win.w / 2
        cy := win.y + win.h / 2
        leaf := GetSelectedLeaf(mon)
        if (!leaf)
            leaf := Layout_FindLeafAtPoint(mon, cx, cy)
        return { mon:mon, leaf:leaf, hwnd:hwnd }
    }
    if (MonitorGetCount() = 0)
        return { mon:1, leaf:0, hwnd:0 }
    mon := 1
    Layout_Ensure(mon)
    leaf := GetSelectedLeaf(mon)
    if (!leaf)
        leaf := Layouts[mon].root
    return { mon:mon, leaf:leaf, hwnd:0 }
}

; Liefert den manuellen Navigationskontext, falls gesetzt.
GetManualNavigationContext() {
    global ManualNav, Layouts
    if (ManualNav.mon && ManualNav.leaf) {
        Layout_Ensure(ManualNav.mon)
        if (Layouts[ManualNav.mon].nodes.Has(ManualNav.leaf))
            return { mon:ManualNav.mon, leaf:ManualNav.leaf }
        ManualNav_Clear()
    }
    return { mon:0, leaf:0 }
}

; Ueberschreibt ctx mit manuell gesetzter Leaf-Auswahl (falls vorhanden).
ApplyManualNavigation(ctx) {
    nav := GetManualNavigationContext()
    if (nav.mon) {
        ctx.mon := nav.mon
        ctx.leaf := nav.leaf
    }
    return ctx
}

; Setzt die manuelle Navigation auf (mon, leaf).
ManualNav_Set(mon, leaf) {
    global ManualNav
    ManualNav := { mon:mon, leaf:leaf }
}

; Loescht die manuelle Navigation (optional nur fuer einen Monitor).
ManualNav_Clear(mon := 0) {
    global ManualNav
    if (!mon || ManualNav.mon = mon)
        ManualNav := { mon:0, leaf:0 }
}
