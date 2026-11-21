; =========================
; Monitors: stabile Identitaet, Lookup und Hotplug-Handling
; =========================
; Hintergrund: AutoHotkey adressiert Monitore nur ueber einen fluechtigen Index
; (1..N in Enumerationsreihenfolge). Wird ein Monitor ab- oder angesteckt,
; verschieben sich die Indizes. Dieses Modul haelt eine Registry mit stabilen
; Schluesseln (Device-Interface-ID des Monitors) und schluesselt bei einem
; Display-Wechsel alle index-basierten Zustaende (Layouts, Fensterzuordnungen,
; Auswahl, Reserven) auf die neuen Indizes um.
;
; Regeln:
; - Die Registry wird im laufenden Betrieb NUR in Monitors_ApplyChange erneuert.
;   Ein stilles Umschluesseln an anderer Stelle (z.B. weil ein Timer die
;   Monitoranzahl prueft) wuerde die Umschluesselung der Layouts ueberspringen,
;   und das Layout des verschwundenen Monitors wuerde auf Monitor 1 gerendert.
; - Direkt nach einem Wechsel/Wake fehlt die Device-ID eines Monitors oft noch.
;   Dann wird kurz gewartet (Retry) und erst danach ein gelernter Alias
;   (Fallback-Key -> Device-ID) bzw. der Fallback-Key benutzt.
; - Fenster eines abgesteckten Monitors werden erst nach einer Karenzzeit in
;   die verbleibenden Areas einsortiert: beim Wake/Dock-Wechsel kommt der
;   Monitor meist innerhalb weniger Sekunden zurueck.

global Monitors := { list: [], byKey: Map(), byHandle: Map(), count: 0, sig: "" }
global MonitorsOffline := Map()      ; key -> Layout-Objekt nicht angeschlossener Monitore
global MonitorsDisplaced := Map()    ; hwnd -> {key, leaf} Fenster, deren Monitor verschwunden ist
global MonitorsKeyAlias := Map()     ; Fallback-Key (Adapter|physische Aufloesung) -> zuletzt gesehene Device-ID
global MonitorsChangeDelayMs := 700  ; Debounce fuer WM_DISPLAYCHANGE (kommt mehrfach)
global MonitorsKeyRetryDelayMs := 1000 ; Wartezeit, wenn die Device-ID eines Monitors noch fehlt
global MonitorsKeyRetryMax := 3
global MonitorsOrphanGraceMs := 5000 ; Karenz, bevor verdraengte Fenster neu einsortiert werden
global MonitorsApplyBusy := false
global MonitorsChangeQueued := false
global MonitorsKeyRetries := 0
global MonitorsPendingOrphans := Map() ; hwnd -> true, wartet auf das Ende der Karenz
global Monitors_EnumTmp := []

; --- Enumeration --------------------------------------------------------------

Monitors_EnumProc(hMon, hdc, pRect, lParam) {
    global Monitors_EnumTmp
    Monitors_EnumTmp.Push(hMon)
    return true
}

; Liefert eine Liste {index, key, weak, fallback, name, hmon, L,T,R,B, wL,wT,wR,wB}
; in AHK-Indexreihenfolge. Hat keine Seiteneffekte auf die Registry.
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
        id := Monitors_ResolveKey(name, L, T, R, B)
        list.Push({ index:i, key:id.key, weak:id.weak, fallback:id.fallback, name:name, hmon:hMon,
                    L:L, T:T, R:R, B:B, wL:wL, wT:wT, wR:wR, wB:wB })
    }
    return list
}

; Device-Interface-ID des Monitors am Adapter name ("" wenn (noch) nicht verfuegbar).
; Direkt nach einem Hotplug/Wake liefert EnumDisplayDevices fuer den Adapter oft
; noch keinen Monitor; dann bleibt die ID leer und der Aufrufer wartet/aliased.
Monitors_DeviceInterfaceId(name) {
    if (name = "")
        return ""
    first := ""
    Loop 8 {
        ; DISPLAY_DEVICEW: cb(4) DeviceName[32] DeviceString[128] StateFlags(4) DeviceID[128] DeviceKey[128]
        dd := Buffer(840, 0)
        NumPut("UInt", 840, dd, 0)
        ok := false
        ; EDD_GET_DEVICE_INTERFACE_NAME = 1
        try ok := DllCall("EnumDisplayDevicesW", "wstr", name, "uint", A_Index - 1, "ptr", dd, "uint", 1)
        if (!ok)
            break
        id := StrGet(dd.Ptr + 328, 128, "UTF-16")
        if (id = "")
            continue
        flags := NumGet(dd, 324, "UInt")
        if (flags & 0x3) ; DISPLAY_DEVICE_ACTIVE | DISPLAY_DEVICE_ATTACHED
            return id
        if (first = "")
            first := id
    }
    return first
}

; Fallback-Key: Adaptername + physische Aufloesung (DEVMODE). Die Pixelmasse aus
; MonitorGet sind DPI-virtualisiert und haengen von der System-DPI beim Logon
; ab (derselbe Monitor erschien mal als 3440x1440, mal als 5160x2160).
Monitors_FallbackKey(name, L, T, R, B) {
    w := R - L
    h := B - T
    if (name != "") {
        try {
            dm := Buffer(220, 0)
            NumPut("UShort", 220, dm, 68) ; dmSize
            ; ENUM_CURRENT_SETTINGS = -1
            if (DllCall("EnumDisplaySettingsW", "wstr", name, "int", -1, "ptr", dm)) {
                pw := NumGet(dm, 172, "UInt") ; dmPelsWidth
                ph := NumGet(dm, 176, "UInt") ; dmPelsHeight
                if (pw > 0 && ph > 0) {
                    w := pw
                    h := ph
                }
            }
        }
        catch Error as e {
            ; Fallback auf die virtuellen Masse
        }
    }
    return Format("{}|{}x{}", (name != "" ? name : "mon"), w, h)
}

; Ermittelt den stabilen Schluessel {key, weak, fallback} eines Monitors.
; weak = true, wenn keine Device-ID verfuegbar war (Alias oder Fallback-Key).
Monitors_ResolveKey(name, L, T, R, B) {
    global MonitorsKeyAlias
    fallback := Monitors_FallbackKey(name, L, T, R, B)
    id := Monitors_DeviceInterfaceId(name)
    if (id != "") {
        if (!MonitorsKeyAlias.Has(fallback) || MonitorsKeyAlias[fallback] != id) {
            MonitorsKeyAlias[fallback] := id
            LogInfo(Format("Monitors_ResolveKey: learned alias {} -> {}", fallback, id))
        }
        return { key:id, weak:false, fallback:fallback }
    }
    if (MonitorsKeyAlias.Has(fallback)) {
        LogWarn(Format("Monitors_ResolveKey: no device id for {} -> using alias {}", fallback, MonitorsKeyAlias[fallback]))
        return { key:MonitorsKeyAlias[fallback], weak:true, fallback:fallback }
    }
    LogWarn(Format("Monitors_ResolveKey: no device id for {} -> fallback key", fallback))
    return { key:fallback, weak:true, fallback:fallback }
}

; Kompatibilitaet: nur der Schluessel.
Monitors_StableKey(name, L, T, R, B) {
    return Monitors_ResolveKey(name, L, T, R, B).key
}

; Uebernimmt gelernte Aliase (z.B. aus der Layout-Datei).
Monitors_SetAliases(aliases) {
    global MonitorsKeyAlias
    if (!(aliases is Map))
        return
    for fallback, id in aliases {
        if (fallback != "" && id != "")
            MonitorsKeyAlias[String(fallback)] := String(id)
    }
}

; Ein Monitor mit fehlender Device-ID ist in der aktuellen Enumeration?
Monitors_EnumerationHasWeakKeys() {
    for m in Monitors_Enumerate() {
        if (m.weak)
            return true
    }
    return false
}

; Signatur der Monitorgeometrie (Keys, Monitor- und Workarea-Rechtecke).
Monitors_Signature(list) {
    parts := []
    for m in list
        parts.Push(Format("{}@{},{},{},{}/{},{},{},{}", m.key, m.L, m.T, m.R, m.B, m.wL, m.wT, m.wR, m.wB))
    return StrJoin(parts, ";")
}

; Aktualisiert die Registry. Ohne force wird NICHT still umgeschluesselt: hat
; sich die Monitoranzahl geaendert, wird nur der Display-Change-Handler
; angestossen und die bisherige Registry zurueckgegeben.
Monitors_Refresh(force := false) {
    global Monitors, MonitorsApplyBusy
    if (!force) {
        if (!Monitors.list.Length)
            force := true
        else {
            if (!MonitorsApplyBusy && Monitors.count != MonitorGetCount())
                Monitors_ScheduleChange("monitor count changed", false)
            return Monitors
        }
    }
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
    Monitors.sig := Monitors_Signature(list)
    return Monitors
}

Monitors_Describe() {
    reg := Monitors_Refresh()
    parts := []
    for m in reg.list
        parts.Push(Format("{}={} [{}]{} ({},{})-({},{})", m.index, m.name, m.key, (m.weak ? " (weak)" : ""), m.L, m.T, m.R, m.B))
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
; Akzeptiert auch Fallback-Keys (aus aelteren Status-/Layout-Dateien), wenn sie
; per Alias oder ueber den Fallback-Key eines angeschlossenen Monitors aufloesbar sind.
Monitors_IndexFromKey(key) {
    global MonitorsKeyAlias
    if (key = "")
        return 0
    reg := Monitors_Refresh()
    if (reg.byKey.Has(key))
        return reg.byKey[key]
    if (MonitorsKeyAlias.Has(key) && reg.byKey.Has(MonitorsKeyAlias[key]))
        return reg.byKey[MonitorsKeyAlias[key]]
    for m in reg.list {
        if (m.fallback = key)
            return m.index
    }
    return 0
}

; Liefert die Schluessel, unter denen Zustand fuer diesen Monitor abgelegt sein
; kann: stabiler Key zuerst, danach der Fallback-Key.
Monitors_CandidateKeys(m) {
    keys := [m.key]
    if (m.fallback != "" && m.fallback != m.key)
        keys.Push(m.fallback)
    return keys
}

; Holt ein geparktes Layout fuer den Monitor aus MonitorsOffline (0 = keins).
; Stabiler Key gewinnt; ein zusaetzlich unter dem Fallback-Key geparktes Layout
; ist eine Altlast und wird verworfen.
Monitors_TakeOfflineLayout(m) {
    global MonitorsOffline
    layout := 0
    for key in Monitors_CandidateKeys(m) {
        if (!MonitorsOffline.Has(key))
            continue
        if (!layout)
            layout := MonitorsOffline[key]
        else
            LogInfo(Format("Monitors_TakeOfflineLayout: stale duplicate layout [{}] dropped", key))
        MonitorsOffline.Delete(key)
    }
    return layout
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
; rearm = false: einen bereits laufenden Debounce nicht verlaengern (fuer
; Aufrufer, die haeufig feuern koennten).
Monitors_ScheduleChange(reason := "", rearm := true) {
    global MonitorsChangeDelayMs, MonitorsApplyBusy, MonitorsChangeQueued
    pending := StateGet("DisplayChangePending", false)
    if (!pending)
        LogInfo(Format("Monitors_ScheduleChange: {} -> pending", reason))
    if (MonitorsApplyBusy) {
        ; Waehrend der Umschluesselung eingetroffen: danach nochmal komplett anwenden
        MonitorsChangeQueued := true
        StateSet("DisplayChangePending", true)
        return
    }
    if (pending && !rearm)
        return
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
    global MonitorsApplyBusy, MonitorsChangeQueued, MonitorsKeyRetries
    global MonitorsKeyRetryMax, MonitorsKeyRetryDelayMs, MonitorsChangeDelayMs
    if (MonitorsApplyBusy) {
        MonitorsChangeQueued := true
        return
    }
    ; Device-IDs fehlen direkt nach dem Umschalten oft noch: kurz warten, statt
    ; ueber einen Fallback-Key ein fremdes Layout zu laden.
    if (MonitorsKeyRetries < MonitorsKeyRetryMax && Monitors_EnumerationHasWeakKeys()) {
        MonitorsKeyRetries += 1
        LogInfo(Format("Monitors_ApplyPendingChange: device id missing -> retry {}/{} in {} ms", MonitorsKeyRetries, MonitorsKeyRetryMax, MonitorsKeyRetryDelayMs))
        try {
            SetTimer(Monitors_ApplyPendingChange, -MonitorsKeyRetryDelayMs)
            return
        }
        catch Error as e {
            LogException(e, "Monitors_ApplyPendingChange: retry timer failed")
        }
    }
    MonitorsKeyRetries := 0
    MonitorsApplyBusy := true
    MonitorsChangeQueued := false
    try {
        Monitors_ApplyChange()
    }
    catch Error as e {
        LogException(e, "Monitors_ApplyChange failed")
    }
    MonitorsApplyBusy := false
    if (MonitorsChangeQueued) {
        MonitorsChangeQueued := false
        LogInfo("Monitors_ApplyPendingChange: display changed again during apply -> re-run")
        try {
            SetTimer(Monitors_ApplyPendingChange, -MonitorsChangeDelayMs)
            return
        }
        catch Error as e {
            LogException(e, "Monitors_ApplyPendingChange: re-run timer failed")
        }
    }
    StateSet("DisplayChangePending", false)
}

; Schluesselt alle index-basierten Zustaende auf die neue Monitor-Konfiguration um.
Monitors_ApplyChange() {
    global Monitors, MonitorsOffline, MonitorsDisplaced, MonitorsPendingOrphans
    global Layouts, LeafWindows, WinToLeaf, CurrentLeafSelection, ManualNav, CurrentHighlight
    global WindowPillsReserve, ExpandedWindows, MaximizeRestoreState, FrameComp, WindowPills

    oldKeyByIndex := Map()
    for m in Monitors.list
        oldKeyByIndex[m.index] := m.key
    oldSig := Monitors.sig

    Monitors_Refresh(true)
    geometryChanged := (Monitors.sig != oldSig)
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
    gone := 0
    for oldIdx, layout in Layouts {
        newIdx := MapIdx(oldIdx)
        if (newIdx) {
            newLayouts[newIdx] := layout
        } else if (oldKeyByIndex.Has(oldIdx)) {
            MonitorsOffline[oldKeyByIndex[oldIdx]] := layout
            gone += 1
            LogInfo(Format("Monitors_ApplyChange: monitor {} [{}] gone -> layout parked", oldIdx, oldKeyByIndex[oldIdx]))
        } else {
            LogWarn(Format("Monitors_ApplyChange: layout of unknown monitor index {} dropped", oldIdx))
        }
    }
    Layouts.Clear()
    for idx, layout in newLayouts
        Layouts[idx] := layout
    returnedKeys := Map() ; key oder fallback -> neuer Index
    for m in Monitors.list {
        if (Layouts.Has(m.index))
            continue
        layout := Monitors_TakeOfflineLayout(m)
        if (layout) {
            Layouts[m.index] := layout
            for key in Monitors_CandidateKeys(m)
                returnedKeys[key] := m.index
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
    try FocusMode_Rebuild()

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
    if (geometryChanged)
        FrameComp.Clear() ; EFB-Offsets sind pro Monitor/DPI gecacht

    ; --- Zurueckgekehrte Monitore: verdraengte Fenster zurueckholen -------------
    returned := 0
    moved := Map()
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
                moved[hwnd] := true
                returned += 1
            }
            catch Error as e {
                LogException(e, "Monitors_ApplyChange: returning displaced window failed")
            }
        }
        for hwnd in delDisp {
            MonitorsDisplaced.Delete(hwnd)
            if (MonitorsPendingOrphans.Has(hwnd))
                MonitorsPendingOrphans.Delete(hwnd)
        }
    }

    ; --- Verwaiste Fenster: nach Karenz dort einsortieren, wo Windows sie hingelegt hat
    if (orphans.Length)
        Monitors_QueueOrphans(orphans)

    ; --- Geometrie neu anwenden (auch bei reiner Aufloesungs-/Workarea-Aenderung)
    if (geometryChanged || returned) {
        for m in Monitors.list {
            if (!Layouts.Has(m.index))
                continue
            try {
                ReapplySubtree(m.index, Layouts[m.index].root, moved)
            }
            catch Error as e {
                LogException(e, "Monitors_ApplyChange: ReapplySubtree failed")
            }
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
    LogInfo(Format("Monitors_ApplyChange: done; monitors={}, geometryChanged={}, gone={}, orphans={}, returned={}, parkedLayouts={}", Monitors.count, geometryChanged, gone, orphans.Length, returned, MonitorsOffline.Count))
    ShowTrayTip(Format("Monitore: {} erkannt", Monitors.count), 1500)
}

; --- Verwaiste Fenster (Monitor verschwunden) ---------------------------------

; Merkt verdraengte Fenster vor und sortiert sie nach der Karenzzeit ein. Kommt
; der Monitor vorher zurueck (Wake, Dock), wandern sie direkt in ihre alte Area
; und werden nie zwischendurch auf dem Restmonitor gestapelt.
Monitors_QueueOrphans(hwnds) {
    global MonitorsPendingOrphans, MonitorsOrphanGraceMs
    for hwnd in hwnds
        MonitorsPendingOrphans[hwnd] := true
    try {
        SetTimer(Monitors_ReassignOrphans, -MonitorsOrphanGraceMs)
        LogInfo(Format("Monitors_QueueOrphans: {} windows wait {} ms for their monitor", MonitorsPendingOrphans.Count, MonitorsOrphanGraceMs))
    }
    catch Error as e {
        LogException(e, "Monitors_QueueOrphans: SetTimer failed")
        Monitors_ReassignOrphans()
    }
}

; Fenster wartet noch auf die Rueckkehr seines Monitors (AutoSnap laesst es in Ruhe).
Monitors_IsOrphanPending(hwnd) {
    global MonitorsPendingOrphans
    return MonitorsPendingOrphans.Has(hwnd)
}

Monitors_ReassignOrphans(*) {
    global MonitorsPendingOrphans, MonitorsApplyBusy, MonitorsOrphanGraceMs, Monitors, Layouts, WinToLeaf
    if (!MonitorsPendingOrphans.Count)
        return
    if (MonitorsApplyBusy || StateGet("DisplayChangePending", false)) {
        try SetTimer(Monitors_ReassignOrphans, -MonitorsOrphanGraceMs)
        return
    }
    hwnds := []
    for hwnd in MonitorsPendingOrphans
        hwnds.Push(hwnd)
    MonitorsPendingOrphans.Clear()

    leafRects := []
    for m in Monitors.list {
        if (!Layouts.Has(m.index))
            continue
        for leafId, _ in Layout_AllLeafRects(m.index)
            leafRects.Push({ mon:m.index, leaf:leafId, rect:GetLeafRectPx(m.index, leafId) })
    }
    reassigned := 0
    for hwnd in hwnds {
        if (WinToLeaf.Has(hwnd))
            continue ; inzwischen zurueckgeholt oder manuell gesnappt
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
            LogException(e, "Monitors_ReassignOrphans: snapping orphan failed")
        }
    }
    LogInfo(Format("Monitors_ReassignOrphans: {} of {} windows reassigned", reassigned, hwnds.Length))
    if (reassigned) {
        try WindowPills_Invalidate()
        SnappedWindows_ScheduleWrite()
    }
}
