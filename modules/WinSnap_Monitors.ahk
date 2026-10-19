; =========================
; Monitors: stabile Identitaet, Lookup und Hotplug-Handling
; =========================
; Hintergrund: AutoHotkey adressiert Monitore nur ueber einen fluechtigen Index
; (1..N in Enumerationsreihenfolge). Wird ein Monitor ab- oder angesteckt,
; verschieben sich die Indizes. Dieses Modul haelt eine Registry mit stabilen
; Schluesseln (Device-Interface-ID des Monitors) und schluesselt bei einem
; Display-Wechsel alle index-basierten Zustaende (Layouts, Fensterzuordnungen,
; Auswahl, Reserven) auf die neuen Indizes um.

global Monitors := { list: [], byKey: Map(), byHandle: Map(), count: 0 }
global MonitorsOffline := Map()      ; key -> Layout-Objekt nicht angeschlossener Monitore
global MonitorsDisplaced := Map()    ; hwnd -> {key, leaf} Fenster, deren Monitor verschwunden ist
global MonitorsChangeDelayMs := 700  ; Debounce fuer WM_DISPLAYCHANGE (kommt mehrfach)
global Monitors_EnumTmp := []

; --- Enumeration --------------------------------------------------------------

Monitors_EnumProc(hMon, hdc, pRect, lParam) {
    global Monitors_EnumTmp
    Monitors_EnumTmp.Push(hMon)
    return true
}

; Liefert eine Liste {index, key, name, hmon, L,T,R,B, wL,wT,wR,wB} in AHK-Indexreihenfolge.
Monitors_Enumerate() {
    global Monitors_EnumTmp
    Monitors_EnumTmp := []
    handles := []
    try {
        cb := CallbackCreate(Monitors_EnumProc, "F", 4)
        try {
            DllCall("EnumDisplayMonitors", "ptr", 0, "ptr", 0, "ptr", cb, "ptr", 0)
        }
        CallbackFree(cb)
        handles := Monitors_EnumTmp
    }
    catch Error as e {
        LogException(e, "Monitors_Enumerate: EnumDisplayMonitors failed")
    }
    Monitors_EnumTmp := []

    ; MONITORINFOEXW: cbSize(4) rcMonitor(16) rcWork(16) dwFlags(4) szDevice[32]
    infos := Map()
    for hMon in handles {
        try {
            mi := Buffer(104, 0)
            NumPut("UInt", 104, mi, 0)
            if (!DllCall("GetMonitorInfoW", "ptr", hMon, "ptr", mi))
                continue
            name := StrGet(mi.Ptr + 40, 32, "UTF-16")
            infos[name] := {
                hmon: hMon,
                L: NumGet(mi, 4, "Int"), T: NumGet(mi, 8, "Int"),
                R: NumGet(mi, 12, "Int"), B: NumGet(mi, 16, "Int")
            }
        }
        catch Error as e {
            LogException(e, "Monitors_Enumerate: GetMonitorInfo failed")
        }
    }

    list := []
    count := MonitorGetCount()
    Loop count {
        i := A_Index
        name := ""
        try name := MonitorGetName(i)
        try {
            MonitorGet(i, &L, &T, &R, &B)
            MonitorGetWorkArea(i, &wL, &wT, &wR, &wB)
        }
        catch Error as e {
            continue
        }
        hMon := 0
        if (name != "" && infos.Has(name))
            hMon := infos[name].hmon
        if (!hMon) {
            for n, inf in infos {
                if (inf.L = L && inf.T = T && inf.R = R && inf.B = B) {
                    hMon := inf.hmon
                    break
                }
            }
        }
        key := Monitors_StableKey(name, L, T, R, B)
        list.Push({ index:i, key:key, name:name, hmon:hMon, L:L, T:T, R:R, B:B, wL:wL, wT:wT, wR:wR, wB:wB })
    }
    return list
}

; Stabiler Schluessel: Device-Interface-ID (enthaelt Hersteller/Modell/Port-UID),
; Fallback: Geraetename + Aufloesung.
Monitors_StableKey(name, L, T, R, B) {
    id := ""
    if (name != "") {
        try {
            ; DISPLAY_DEVICEW: cb(4) DeviceName[32] DeviceString[128] StateFlags(4) DeviceID[128] DeviceKey[128]
            dd := Buffer(840, 0)
            NumPut("UInt", 840, dd, 0)
            ; EDD_GET_DEVICE_INTERFACE_NAME = 1
            if (DllCall("EnumDisplayDevicesW", "wstr", name, "uint", 0, "ptr", dd, "uint", 1))
                id := StrGet(dd.Ptr + 328, 128, "UTF-16")
        }
        catch Error as e {
            id := ""
        }
    }
    if (id != "")
        return id
    return Format("{}|{}x{}", (name != "" ? name : "mon"), R - L, B - T)
}

; Aktualisiert die Registry (lazy: nur wenn sich die Monitoranzahl geaendert hat oder force).
Monitors_Refresh(force := false) {
    global Monitors
    if (!force && Monitors.list.Length && Monitors.count = MonitorGetCount())
        return Monitors
    list := Monitors_Enumerate()
    byKey := Map()
    byHandle := Map()
    for m in list {
        if (byKey.Has(m.key))
            m.key := m.key "#" m.index
        byKey[m.key] := m.index
        if (m.hmon)
            byHandle[m.hmon] := m.index
    }
    Monitors.list := list
    Monitors.byKey := byKey
    Monitors.byHandle := byHandle
    Monitors.count := list.Length
    return Monitors
}

Monitors_Describe() {
    reg := Monitors_Refresh()
    parts := []
    for m in reg.list
        parts.Push(Format("{}={} [{}] ({},{})-({},{})", m.index, m.name, m.key, m.L, m.T, m.R, m.B))
    return StrJoin(parts, "; ")
}

; --- Lookups ------------------------------------------------------------------

Monitors_Count() {
    return Monitors_Refresh().count
}

Monitors_IsValid(mon) {
    try {
        mon := Integer(mon)
    }
    catch Error as e {
        return false
    }
    return (mon >= 1 && mon <= Monitors_Refresh().count)
}

Monitors_KeyFromIndex(mon) {
    reg := Monitors_Refresh()
    for m in reg.list {
        if (m.index = mon)
            return m.key
    }
    return ""
}

Monitors_NameFromIndex(mon) {
    reg := Monitors_Refresh()
    for m in reg.list {
        if (m.index = mon)
            return m.name
    }
    return ""
}

; Liefert den aktuellen Index zu einem stabilen Schluessel (0 = nicht angeschlossen).
Monitors_IndexFromKey(key) {
    if (key = "")
        return 0
    reg := Monitors_Refresh()
    return reg.byKey.Has(key) ? reg.byKey[key] : 0
}

Monitors_PackPoint(x, y) {
    x := Round(x)
    y := Round(y)
    return ((y & 0xFFFFFFFF) << 32) | (x & 0xFFFFFFFF)
}

; Monitorindex zum Punkt (x,y); nutzt MonitorFromPoint (naechster Monitor als Fallback).
Monitors_IndexFromPoint(x, y) {
    reg := Monitors_Refresh()
    if (reg.count <= 0)
        return 1
    hMon := 0
    try {
        if (A_PtrSize = 8)
            hMon := DllCall("MonitorFromPoint", "int64", Monitors_PackPoint(x, y), "uint", 2, "ptr") ; MONITOR_DEFAULTTONEAREST
        else
            hMon := DllCall("MonitorFromPoint", "int", Round(x), "int", Round(y), "uint", 2, "ptr")
    }
    catch Error as e {
        hMon := 0
    }
    if (hMon && reg.byHandle.Has(hMon))
        return reg.byHandle[hMon]
    for m in reg.list {
        if (x >= m.L && x < m.R && y >= m.T && y < m.B)
            return m.index
    }
    return 1
}

; Monitorindex zum Fenster; nutzt MonitorFromWindow (groesste Ueberlappung, sonst naechster).
Monitors_IndexFromWindow(hwnd) {
    reg := Monitors_Refresh()
    if (reg.count <= 0)
        return 1
    hMon := 0
    try hMon := DllCall("MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr") ; MONITOR_DEFAULTTONEAREST
    if (hMon && reg.byHandle.Has(hMon))
        return reg.byHandle[hMon]
    try {
        WinGetPos &x, &y, &w, &h, "ahk_id " hwnd
        return Monitors_IndexFromPoint(x + w / 2, y + h / 2)
    }
    catch Error as e {
        return 1
    }
}

; --- Display-Change-Handling --------------------------------------------------

Monitors_InitDisplayChangeHook() {
    Monitors_Refresh(true)
    try {
        OnMessage(0x007E, Monitors_OnDisplayChangeMsg)   ; WM_DISPLAYCHANGE
        OnMessage(0x001A, Monitors_OnSettingChangeMsg)   ; WM_SETTINGCHANGE (Workarea/Taskbar)
        LogInfo("Monitors_InitDisplayChangeHook: registered; monitors: " Monitors_Describe())
    }
    catch Error as e {
        LogException(e, "Monitors_InitDisplayChangeHook failed")
    }
}

Monitors_OnDisplayChangeMsg(wParam, lParam, msg, hwnd) {
    Monitors_ScheduleChange("WM_DISPLAYCHANGE")
    return 0
}

Monitors_OnSettingChangeMsg(wParam, lParam, msg, hwnd) {
    if (wParam = 0x2F) ; SPI_SETWORKAREA
        Monitors_ScheduleChange("SPI_SETWORKAREA")
    return 0
}

; Debounced: Windows schickt waehrend eines Hotplugs mehrere Nachrichten, und
; die Fenster des abgesteckten Monitors werden erst kurz danach verschoben.
Monitors_ScheduleChange(reason := "") {
    global MonitorsChangeDelayMs
    if (!StateGet("DisplayChangePending", false))
        LogInfo(Format("Monitors_ScheduleChange: {} -> pending", reason))
    StateSet("DisplayChangePending", true)
    try {
        SetTimer(Monitors_ApplyPendingChange, -MonitorsChangeDelayMs)
    }
    catch Error as e {
        StateSet("DisplayChangePending", false)
        LogException(e, "Monitors_ScheduleChange: SetTimer failed")
    }
}

Monitors_ApplyPendingChange(*) {
    try {
        Monitors_ApplyChange()
    }
    catch Error as e {
        LogException(e, "Monitors_ApplyChange failed")
    }
    StateSet("DisplayChangePending", false)
}

; Schluesselt alle index-basierten Zustaende auf die neue Monitor-Konfiguration um.
Monitors_ApplyChange() {
    global Monitors, MonitorsOffline, MonitorsDisplaced
    global Layouts, LeafWindows, WinToLeaf, CurrentLeafSelection, ManualNav, CurrentHighlight
    global WindowPillsReserve, ExpandedWindows, MaximizeRestoreState, FrameComp, WindowPills

    oldKeyByIndex := Map()
    for m in Monitors.list
        oldKeyByIndex[m.index] := m.key

    Monitors_Refresh(true)
    LogInfo("Monitors_ApplyChange: new configuration: " Monitors_Describe())

    ; alter Index -> neuer Index (0 = Monitor verschwunden)
    remap := Map()
    for oldIdx, key in oldKeyByIndex
        remap[oldIdx] := Monitors_IndexFromKey(key)
    MapIdx := (idx) => (remap.Has(idx) ? remap[idx] : 0)

    try DragSnap_Cancel()
    try HideSnapOverlay()
    try WindowSearch_Close()

    ; --- Layouts -------------------------------------------------------------
    newLayouts := Map()
    for oldIdx, layout in Layouts {
        newIdx := MapIdx(oldIdx)
        if (newIdx) {
            newLayouts[newIdx] := layout
        } else if (oldKeyByIndex.Has(oldIdx)) {
            MonitorsOffline[oldKeyByIndex[oldIdx]] := layout
            LogInfo(Format("Monitors_ApplyChange: monitor {} [{}] gone -> layout parked", oldIdx, oldKeyByIndex[oldIdx]))
        }
    }
    Layouts.Clear()
    for idx, layout in newLayouts
        Layouts[idx] := layout
    returnedKeys := Map()
    for m in Monitors.list {
        if (Layouts.Has(m.index))
            continue
        if (MonitorsOffline.Has(m.key)) {
            Layouts[m.index] := MonitorsOffline[m.key]
            MonitorsOffline.Delete(m.key)
            returnedKeys[m.key] := m.index
            LogInfo(Format("Monitors_ApplyChange: monitor {} [{}] returned -> layout restored", m.index, m.key))
        } else {
            Layout_Ensure(m.index)
        }
    }

    ; --- Fensterzuordnungen ---------------------------------------------------
    orphans := []
    newW2L := Map()
    for hwnd, info in WinToLeaf {
        newIdx := MapIdx(info.mon)
        if (newIdx && Layouts.Has(newIdx) && Layouts[newIdx].nodes.Has(info.leaf)) {
            newW2L[hwnd] := { mon:newIdx, leaf:info.leaf }
        } else {
            orphans.Push(hwnd)
            if (oldKeyByIndex.Has(info.mon))
                MonitorsDisplaced[hwnd] := { key:oldKeyByIndex[info.mon], leaf:info.leaf }
        }
    }
    newLW := Map()
    for key, arr in LeafWindows {
        parts := StrSplit(key, ":")
        if (parts.Length != 2)
            continue
        newIdx := MapIdx(Layout_ToInt(parts[1], 0))
        leaf := Layout_ToInt(parts[2], 0)
        if (newIdx && Layouts.Has(newIdx) && Layouts[newIdx].nodes.Has(leaf))
            newLW[newIdx ":" leaf] := arr
    }
    WinToLeaf.Clear()
    for hwnd, info in newW2L
        WinToLeaf[hwnd] := info
    LeafWindows.Clear()
    for key, arr in newLW
        LeafWindows[key] := arr

    ; --- Auswahl / Navigation / Highlight -------------------------------------
    newSel := Map()
    for oldIdx, state in CurrentLeafSelection {
        newIdx := MapIdx(oldIdx)
        if (newIdx && Layouts.Has(newIdx) && Layouts[newIdx].nodes.Has(state.leaf))
            newSel[newIdx] := state
    }
    CurrentLeafSelection.Clear()
    for idx, state in newSel
        CurrentLeafSelection[idx] := state
    if (ManualNav.mon) {
        newIdx := MapIdx(ManualNav.mon)
        if (newIdx && Layouts.Has(newIdx) && Layouts[newIdx].nodes.Has(ManualNav.leaf))
            ManualNav.mon := newIdx
        else
            ManualNav_Clear()
    }
    try HideHighlight()

    ; --- Sonstige index-basierte Caches ---------------------------------------
    newReserve := Map()
    for key, px in WindowPillsReserve {
        parts := StrSplit(key, ":")
        if (parts.Length != 2)
            continue
        newIdx := MapIdx(Layout_ToInt(parts[1], 0))
        if (newIdx)
            newReserve[newIdx ":" parts[2]] := px
    }
    WindowPillsReserve.Clear()
    for key, px in newReserve
        WindowPillsReserve[key] := px
    try {
        delExp := []
        for hwnd, st in ExpandedWindows {
            newIdx := MapIdx(st.mon)
            if (newIdx)
                st.mon := newIdx
            else
                delExp.Push(hwnd)
        }
        for hwnd in delExp
            ExpandedWindows.Delete(hwnd)
    }
    try {
        for hwnd, st in MaximizeRestoreState {
            if (!st.snapped)
                continue
            newIdx := MapIdx(st.mon)
            if (newIdx)
                st.mon := newIdx
            else
                st.snapped := false
        }
    }
    FrameComp.Clear() ; EFB-Offsets sind pro Monitor/DPI gecacht

    ; --- Zurueckgekehrte Monitore: verdraengte Fenster zurueckholen -------------
    returned := 0
    if (returnedKeys.Count) {
        delDisp := []
        for hwnd, st in MonitorsDisplaced {
            if (!returnedKeys.Has(st.key))
                continue
            delDisp.Push(hwnd)
            mon := returnedKeys[st.key]
            if (!Layouts[mon].nodes.Has(st.leaf) || Layouts[mon].nodes[st.leaf].split != "")
                continue
            if (!DllCall("IsWindow", "ptr", hwnd) || !WinExist("ahk_id " hwnd))
                continue
            try {
                SnapWindowToLeaf(hwnd, mon, st.leaf)
                returned += 1
            }
            catch Error as e {
                LogException(e, "Monitors_ApplyChange: returning displaced window failed")
            }
        }
        for hwnd in delDisp
            MonitorsDisplaced.Delete(hwnd)
    }

    ; --- Verwaiste Fenster: dort einsortieren, wo Windows sie hingelegt hat ----
    reassigned := 0
    if (orphans.Length) {
        leafRects := []
        for m in Monitors.list {
            for leafId, _ in Layout_AllLeafRects(m.index)
                leafRects.Push({ mon:m.index, leaf:leafId, rect:GetLeafRectPx(m.index, leafId) })
        }
        for hwnd in orphans {
            if (WinToLeaf.Has(hwnd))
                continue ; bereits zurueckgeholt
            if (!IsCollectibleSnapWindow(hwnd))
                continue
            target := FindBestIntersectingLeafForWindow(hwnd, leafRects)
            if (!target)
                continue
            try {
                SnapWindowToLeaf(hwnd, target.mon, target.leaf)
                reassigned += 1
            }
            catch Error as e {
                LogException(e, "Monitors_ApplyChange: reassigning orphan failed")
            }
        }
    }

    ; --- Geometrie neu anwenden (auch bei reiner Aufloesungs-/Workarea-Aenderung)
    for m in Monitors.list {
        try {
            ReapplySubtree(m.index, Layouts[m.index].root)
        }
        catch Error as e {
            LogException(e, "Monitors_ApplyChange: ReapplySubtree failed")
        }
    }

    try {
        if (IsObject(WindowPills))
            WindowPills.lastSig := ""
        WindowPills_Invalidate()
    }
    try UpdateActiveHighlight()
    Layout_SaveAll()
    SnappedWindows_ScheduleWrite()
    LogInfo(Format("Monitors_ApplyChange: done; monitors={}, orphans={}, reassigned={}, returned={}, parkedLayouts={}", Monitors.count, orphans.Length, reassigned, returned, MonitorsOffline.Count))
    ShowTrayTip(Format("Monitore: {} erkannt", Monitors.count), 1500)
}
