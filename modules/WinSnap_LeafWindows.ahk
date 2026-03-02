; =========================
; Leaf-Window Lists
; =========================
; Bildet einen eindeutigen Key "mon:leaf" fuer Zuordnungs-Maps.
LeafKey(mon, leafId) {
    return mon ":" leafId
}

; --- Snapped Windows Status (JSON file) -----------------------------------
; Schreibt regelmaessig die aktuell gesnappten Fenster (inkl. Prozess/Klasse)
; in eine JSON-Datei, damit von aussen sichtbar ist, welche Fenster Pill-Status
; haben.
SnappedWindows_Init() {
    restored := 0
    try {
        restored := SnappedWindows_RestoreFromStatus()
        LogInfo(Format("SnappedWindows_Init: restored {} windows from status", restored))
    }
    catch Error as e {
        LogException(e, "SnappedWindows_Init: restore failed")
    }
    try {
        ; Retry once shortly after startup (some windows may not be ready immediately).
        SetTimer(SnappedWindows_RestoreDelayed, -700)
    }
    catch Error as e {
        LogException(e, "SnappedWindows_Init: delayed restore timer failed")
    }
    try {
        ; Persist current state after restore attempt(s).
        SnappedWindows_ScheduleWrite()
    }
    catch Error as e {
        LogException(e, "SnappedWindows_Init: schedule write failed")
    }
}

SnappedWindows_RestoreDelayed(*) {
    try {
        restored := SnappedWindows_RestoreFromStatus()
        if (restored > 0)
            LogInfo(Format("SnappedWindows_RestoreDelayed: restored {} additional windows", restored))
    }
    catch Error as e {
        LogException(e, "SnappedWindows_RestoreDelayed")
    }
}

SnappedWindows_RestoreFromStatus() {
    global SnappedWindowsStatusPath, WinToLeaf, Layouts
    entries := SnappedWindows_LoadStatus()
    if (!(entries is Array) || entries.Length = 0)
        return 0

    used := Map()
    for hwnd in WinToLeaf
        used[hwnd] := true

    unresolved := []
    restored := 0

    ; Pass 1: exact hwnd restore (with identity verification).
    for entry in entries {
        mon := SW_ToInt(SW_GetEntryValue(entry, "mon", 0), 0)
        leaf := SW_ToInt(SW_GetEntryValue(entry, "leaf", 0), 0)
        if (!mon || !leaf)
            continue
        Layout_Ensure(mon)
        if (!Layouts.Has(mon) || !Layouts[mon].nodes.Has(leaf))
            continue

        rawHwnd := SW_GetEntryValue(entry, "hwnd", 0)
        hwnd := SW_ToInt(rawHwnd, 0)
        proc := SW_GetEntryValue(entry, "process", "")
        className := SW_GetEntryValue(entry, "class", "")
        title := SW_GetEntryValue(entry, "title", "")

        if (hwnd && !used.Has(hwnd)) {
            valid := false
            try {
                valid := DllCall("IsWindow", "ptr", hwnd) && WinExist("ahk_id " hwnd)
            }
            catch Error as e {
                valid := false
            }
            if (valid && SnappedWindows_WindowMetaMatches(hwnd, proc, className, title)) {
                try {
                    SnapWindowToLeaf(hwnd, mon, leaf)
                    used[hwnd] := true
                    restored += 1
                    continue
                }
                catch Error as e {
                    LogException(e, "SnappedWindows_RestoreFromStatus: exact hwnd restore failed")
                }
            }
        }

        item := Map()
        item["mon"] := mon
        item["leaf"] := leaf
        item["process"] := proc
        item["class"] := className
        item["title"] := title
        unresolved.Push(item)
    }

    ; Pass 2: fallback by unique process/class/title identity among currently open windows.
    if (unresolved.Length > 0) {
        openRows := SnappedWindows_BuildOpenWindowIndex()
        for item in unresolved {
            hwnd := SnappedWindows_FindWindowByIdentity(item["process"], item["class"], item["title"], openRows, used)
            if (!hwnd)
                continue
            try {
                SnapWindowToLeaf(hwnd, item["mon"], item["leaf"])
                used[hwnd] := true
                restored += 1
            }
            catch Error as e {
                LogException(e, "SnappedWindows_RestoreFromStatus: fallback identity restore failed")
            }
        }
    }

    return restored
}

SnappedWindows_LoadStatus() {
    global SnappedWindowsStatusPath
    if (!IsSet(SnappedWindowsStatusPath) || SnappedWindowsStatusPath = "")
        SnappedWindowsStatusPath := A_ScriptDir "\WinSnap_SnappedWindows.json"
    if (!FileExist(SnappedWindowsStatusPath))
        return []
    try {
        text := FileRead(SnappedWindowsStatusPath, "UTF-8")
        if (!text || Trim(text) = "")
            return []
        data := jxon_load(&text)
    }
    catch Error as e {
        LogException(e, "SnappedWindows_LoadStatus")
        return []
    }
    if (data is Array)
        return data
    if (data is Map) {
        arr := []
        for _, entry in data
            arr.Push(entry)
        return arr
    }
    return []
}

SnappedWindows_WindowMetaMatches(hwnd, expectedProc := "", expectedClass := "", expectedTitle := "") {
    if (!hwnd)
        return false
    if (expectedProc != "") {
        try {
            if (WinGetProcessName("ahk_id " hwnd) != expectedProc)
                return false
        }
        catch Error as e {
            return false
        }
    }
    if (expectedClass != "") {
        try {
            if (WinGetClass("ahk_id " hwnd) != expectedClass)
                return false
        }
        catch Error as e {
            return false
        }
    }
    if (expectedTitle != "") {
        try {
            if (WinGetTitle("ahk_id " hwnd) != expectedTitle)
                return false
        }
        catch Error as e {
            return false
        }
    }
    return true
}

SnappedWindows_BuildOpenWindowIndex() {
    out := []
    ids := []
    try {
        ids := WinGetList()
    }
    catch Error as e {
        LogException(e, "SnappedWindows_BuildOpenWindowIndex: WinGetList failed")
        return out
    }

    for hwnd in ids {
        if (!IsCollectibleSnapWindow(hwnd))
            continue
        proc := "", className := "", title := ""
        try proc := WinGetProcessName("ahk_id " hwnd)
        try className := WinGetClass("ahk_id " hwnd)
        try title := WinGetTitle("ahk_id " hwnd)
        row := Map()
        row["hwnd"] := hwnd
        row["process"] := proc
        row["class"] := className
        row["title"] := title
        out.Push(row)
    }
    return out
}

SnappedWindows_FindWindowByIdentity(proc, className, title, openRows, used) {
    ; strictest -> loosest, only when unique
    hwnd := SnappedWindows_FindUniqueMatch(openRows, used, proc, className, title)
    if (hwnd)
        return hwnd
    if (proc != "" && className != "") {
        hwnd := SnappedWindows_FindUniqueMatch(openRows, used, proc, className, "")
        if (hwnd)
            return hwnd
    }
    if (proc != "" && title != "") {
        hwnd := SnappedWindows_FindUniqueMatch(openRows, used, proc, "", title)
        if (hwnd)
            return hwnd
    }
    if (className != "" && title != "") {
        hwnd := SnappedWindows_FindUniqueMatch(openRows, used, "", className, title)
        if (hwnd)
            return hwnd
    }
    if (proc != "") {
        hwnd := SnappedWindows_FindUniqueMatch(openRows, used, proc, "", "")
        if (hwnd)
            return hwnd
    }
    return 0
}

SnappedWindows_FindUniqueMatch(openRows, used, proc, className, title) {
    found := 0
    count := 0
    for row in openRows {
        hwnd := SW_ToInt(row["hwnd"], 0)
        if (!hwnd || used.Has(hwnd))
            continue
        if (proc != "" && row["process"] != proc)
            continue
        if (className != "" && row["class"] != className)
            continue
        if (title != "" && row["title"] != title)
            continue
        found := hwnd
        count += 1
        if (count > 1)
            return 0
    }
    return (count = 1) ? found : 0
}

SW_GetEntryValue(entry, key, defaultValue := "") {
    try {
        if (entry is Map)
            return entry.Has(key) ? entry[key] : defaultValue
        if (IsObject(entry) && entry.HasOwnProp(key))
            return entry.%key%
    }
    catch Error as e {
    }
    return defaultValue
}

SW_ToInt(value, defaultValue := 0) {
    try {
        return Integer(value)
    }
    catch Error as e {
        return defaultValue
    }
}

SnappedWindows_ScheduleWrite() {
    global SnappedWindowsWritePending
    if (!IsSet(SnappedWindowsWritePending))
        SnappedWindowsWritePending := false
    if (SnappedWindowsWritePending)
        return
    SnappedWindowsWritePending := true
    try {
        SetTimer(SnappedWindows_Flush, -50)
    }
    catch Error as e {
        SnappedWindowsWritePending := false
        LogException(e, "SnappedWindows_ScheduleWrite")
    }
}

SnappedWindows_Flush(*) {
    global SnappedWindowsWritePending
    SnappedWindowsWritePending := false
    SnappedWindows_WriteStatus()
}

SnappedWindows_WriteStatus() {
    global WinToLeaf, SnappedWindowsStatusPath
    if (!IsSet(SnappedWindowsStatusPath) || SnappedWindowsStatusPath = "")
        SnappedWindowsStatusPath := A_ScriptDir "\WinSnap_SnappedWindows.json"
    try {
        data := []
        for hwnd, info in WinToLeaf {
            valid := false
            try {
                valid := DllCall("IsWindow", "ptr", hwnd) && WinExist("ahk_id " hwnd)
            }
            catch Error as e {
                valid := false
            }
            if (!valid)
                continue
            exe := "", className := "", title := ""
            try {
                exe := WinGetProcessName("ahk_id " hwnd)
            }
            catch {
                exe := ""
            }
            try {
                className := WinGetClass("ahk_id " hwnd)
            }
            catch {
                className := ""
            }
            try {
                title := WinGetTitle("ahk_id " hwnd)
            }
            catch {
                title := ""
            }
            row := Map()
            row["hwnd"] := hwnd
            row["process"] := exe
            row["class"] := className
            row["title"] := title
            row["mon"] := info.mon
            row["leaf"] := info.leaf
            data.Push(row)
        }
        f := FileOpen(SnappedWindowsStatusPath, "w", "UTF-8")
        if (f) {
            f.Write(jxon_dump(data, indent := 2))
            f.Close()
        }
    }
    catch Error as e {
        LogException(e, "SnappedWindows_WriteStatus")
    }
}

; Entfernt ungueltige Fensterhandles aus der Leaf-Liste fuer key.
LeafCleanupList(key) {
    global LeafWindows
    if (!LeafWindows.Has(key))
        return
    arr := LeafWindows[key]
    idx := 1
    while (idx <= arr.Length) {
        hwnd := arr[idx]
        try {
            exists := DllCall("IsWindow", "ptr", hwnd) && WinExist("ahk_id " hwnd)
        } catch {
            exists := false
        }
        if (!exists)
            arr.RemoveAt(idx)
        else
            idx++
    }
    if (arr.Length = 0)
        LeafWindows.Delete(key)
}

; Haengt ein Fenster an ein Leaf an und aktualisiert Mapping/Selektion.
LeafAttachWindow(hwnd, mon, leafId, updateSelection := true) {
    global LeafWindows, WinToLeaf
    LogInfo(Format("LeafAttachWindow: hwnd={}, mon={}, leaf={}, updateSel={}", hwnd, mon, leafId, updateSelection))
    LeafDetachWindow(hwnd, false)
    key := LeafKey(mon, leafId)
    if (!LeafWindows.Has(key))
        LeafWindows[key] := []
    else
        LeafCleanupList(key)
    if (!LeafWindows.Has(key))
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
    if (updateSelection)
        SelectLeaf(mon, leafId, "auto")

    try {
        SaveLeafAssignment(mon, leafId, hwnd)
    }
    catch Error as e {
        LogException(e, "Fehler beim Speichern der Fenster-Zuordnung!")
    }

    ; Invalidate pills so overlay reflects new membership immediately
    try {
        WindowPills_Invalidate()
    }
    catch Error as e {
        LogException(e, "LeafAttachWindow: WindowPills_Invalidate failed")
    }

    SnappedWindows_ScheduleWrite()
}

; Loest ein Fenster von seinem Leaf; optional Mapping entfernen.
LeafDetachWindow(hwnd, removeMapping := false) {
    global LeafWindows, WinToLeaf
    if (!WinToLeaf.Has(hwnd))
        return
    LogInfo(Format("LeafDetachWindow: hwnd={}, removeMapping={} ", hwnd, removeMapping))
    info := WinToLeaf[hwnd]
    key := LeafKey(info.mon, info.leaf)
    if (LeafWindows.Has(key)) {
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
    if (removeMapping)
        WinToLeaf.Delete(hwnd)

    ; Invalidate pills so a closed/removed window disappears immediately
    try {
        WindowPills_Invalidate()
    }
    catch Error as e {
        LogException(e, "LeafDetachWindow: WindowPills_Invalidate failed")
    }

    SnappedWindows_ScheduleWrite()
}

; Bestimmt das oberste Fenster des Leafs (Z-Order, mit Bereinigung).
LeafGetTopWindow(mon, leafId) {
    global LeafWindows
    key := LeafKey(mon, leafId)
    if (!LeafWindows.Has(key))
        return 0
    arr := LeafWindows[key]
    ; Baue Lookup-Set für schnelle Prüfung
    lookup := Map()
    for hwnd in arr
        lookup[hwnd] := true

    ; Ermittle tatsächliche Z-Order über das System und wähle das oberste Fenster dieser Leaf
    top := 0
    try {
        osList := WinGetList()  ; Z-Order Reihenfolge (Top -> Bottom)
        for hwnd in osList {
            if (lookup.Has(hwnd)) {
                try {
                    if (DllCall("IsWindow", "ptr", hwnd) && WinExist("ahk_id " hwnd)) {
                        top := hwnd
                        break
                    }
                }
                catch Error as e {
                    ; ignore invalid handle
                }
            }
        }
    }
    catch Error as e {
        LogError("LeafGetTopWindow: WinGetList failed")
    }

    if (top) {
        LogDebug(Format("LeafGetTopWindow: mon={}, leaf={} -> top={} (z-order)", mon, leafId, top))
        return top
    }

    ; Fallback: Liste bereinigen und erstes gültiges nehmen
    idx := 1
    while (idx <= arr.Length) {
        hwnd := arr[idx]
        try {
            exists := DllCall("IsWindow", "ptr", hwnd) && WinExist("ahk_id " hwnd)
        } catch {
            exists := false
        }
        if (exists)
            return hwnd
        arr.RemoveAt(idx)
    }
    if (arr.Length = 0)
        LeafWindows.Delete(key)
    LogDebug(Format("LeafGetTopWindow: mon={}, leaf={} -> no valid hwnd", mon, leafId))
    return 0
}

; Liefert die bereinigte, geordnete Fensterliste eines Leafs.
LeafGetOrderedList(mon, leafId) {
    global LeafWindows
    key := LeafKey(mon, leafId)
    if (!LeafWindows.Has(key))
        return []
    LeafCleanupList(key)
    return LeafWindows.Has(key) ? LeafWindows[key] : []
}
