; =========================
; Leaf-Window Lists
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
        try {
            exists := DllCall("IsWindow", "ptr", hwnd) && WinExist("ahk_id " hwnd)
        } catch {
            exists := false
        }
        if !exists
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

    try {
        SaveLeafAssignment(mon, leafId, hwnd)
    }
    catch {
        MsgBox "Fehler beim Speichern der Fenster-Zuordnung!"
    }

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
        try {
            exists := DllCall("IsWindow", "ptr", hwnd) && WinExist("ahk_id " hwnd)
        } catch {
            exists := false
        }
        if exists
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
    return LeafWindows.Has(key) ? LeafWindows[key] : []
}
