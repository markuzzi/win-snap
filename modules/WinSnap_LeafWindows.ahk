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
    try {
        SnappedWindows_WriteStatus()
    }
    catch Error as e {
        LogException(e, "SnappedWindows_Init")
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
            data.Push({ hwnd:hwnd, process:exe, class:className, title:title, mon:info.mon, leaf:info.leaf })
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
