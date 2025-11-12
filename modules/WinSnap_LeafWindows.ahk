; =========================
; Leaf-Window Lists
; =========================
; Bildet einen eindeutigen Key "mon:leaf" fuer Zuordnungs-Maps.
LeafKey(mon, leafId) {
    return mon ":" leafId
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
        MsgBox "Fehler beim Speichern der Fenster-Zuordnung!"
    }

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
