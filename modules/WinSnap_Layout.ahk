; =========================
; Layout (Grid) – Baum pro Monitor
; =========================
Layout_Ensure(mon) {
    global Layouts
    needsReset := false
    if (!Layouts.Has(mon)) {
        needsReset := true
    } else {
        layout := Layouts[mon]
        if (!layout.HasOwnProp("nodes") || !IsObject(layout.nodes))
            needsReset := true
        else if (!layout.nodes.Has(layout.root))
            needsReset := true
    }
    if (!needsReset)
        return
    nodes := Map()
    nodes[1] := { id:1, parent:0, split:"", frac:0.5, a:0, b:0 }  ; root unsplittet
    Layouts[mon] := { root:1, next:2, nodes:nodes }
    Layout_SaveAll()
}

Layout_Node(mon, id) {
    global Layouts
    Layout_Ensure(mon)
    if (!Layouts.Has(mon))
        return 0
    nodes := Layouts[mon].nodes
    return nodes.Has(id) ? nodes[id] : 0
}

Layout_IsLeaf(mon, id) {
    global Layouts
    Layout_Ensure(mon)
    if (!Layouts.Has(mon))
        return false
    nodes := Layouts[mon].nodes
    if (!nodes.Has(id))
        return false
    n := nodes[id]
    return (n.split = "")
}

Layout_SplitLeaf(mon, leafId, orient) {
    global Layouts
    Layout_Ensure(mon)
    n := Layouts[mon].nodes[leafId]
    if (n.split != "")
        return
    idA := Layouts[mon].next
    idB := idA + 1
    Layouts[mon].next := idB + 1
    Layouts[mon].nodes[idA] := { id:idA, parent:leafId, split:"", frac:0.5, a:0, b:0 }
    Layouts[mon].nodes[idB] := { id:idB, parent:leafId, split:"", frac:0.5, a:0, b:0 }
    n.split := (orient = "v") ? "v" : "h"
    n.frac  := 0.5
    n.a := idA
    n.b := idB
    Layout_SaveAll()
}

Layout_NodeRect(mon, nodeId) {
    global Layouts
    Layout_Ensure(mon)
    monInfo := GetMonitorWork(mon)
    rect := { L:monInfo.left, T:monInfo.top, R:monInfo.right, B:monInfo.bottom }
    if (!Layouts.Has(mon))
        return rect
    nodes := Layouts[mon].nodes
    if (!nodes.Has(nodeId))
        nodeId := Layouts[mon].root
    if (!nodes.Has(nodeId))
        return rect

    path := []
    cur := nodeId
    rootId := Layouts[mon].root
    while (cur != rootId) {
        if (!nodes.Has(cur))
            break
        parent := nodes[cur].parent
        if (parent = 0 || !nodes.Has(parent))
            break
        path.InsertAt(1, { parent: parent, child: cur })
        cur := parent
    }

    for step in path {
        p := nodes[step.parent]
        if (p.split = "v") {
            midX := rect.L + Round((rect.R - rect.L) * p.frac)
            rect := (step.child = p.a)
                ? { L:rect.L, T:rect.T, R:midX, B:rect.B }
                : { L:midX, T:rect.T, R:rect.R, B:rect.B }
        } else if (p.split = "h") {
            midY := rect.T + Round((rect.B - rect.T) * p.frac)
            rect := (step.child = p.a)
                ? { L:rect.L, T:rect.T, R:rect.R, B:midY }
                : { L:rect.L, T:midY, R:rect.R, B:rect.B }
        }
    }
    return rect
}

ApplySnapGap(rect) {
    global SnapGap
    gap := Max(0, SnapGap)
    if (gap <= 0)
        return rect
    leftGap := Floor(gap / 2)
    rightGap := gap - leftGap
    topGap := leftGap
    bottomGap := rightGap
    rect.L += leftGap
    rect.T += topGap
    rect.R -= rightGap
    rect.B -= bottomGap
    if (rect.R <= rect.L)
        rect.R := rect.L + 1
    if (rect.B <= rect.T)
        rect.B := rect.T + 1
    return rect
}

GetLeafRect(mon, leafId) {
    rect := Layout_NodeRect(mon, leafId)
    return ApplySnapGap(rect)
}

Layout_AllLeafRects(mon) {
    global Layouts
    Layout_Ensure(mon)
    if (!Layouts.Has(mon))
        return Map()
    out := Map()
    for id, n in Layouts[mon].nodes {
        if (n.split = "")
            out[id] := Layout_NodeRect(mon, id)
    }
    return out
}

Layout_FindLeafAtPoint(mon, x, y) {
    global Layouts
    Layout_Ensure(mon)
    if (!Layouts.Has(mon))
        return 0
    rect := GetMonitorWork(mon)
    nodes := Layouts[mon].nodes
    rootId := Layouts[mon].root
    if (!nodes.Has(rootId))
        return 0
    id := rootId
    loop {
        if (!nodes.Has(id))
            return rootId
        n := nodes[id]
        if (n.split = "")
            return id
        if (n.split = "v") {
            midX := rect.left + Round((rect.right - rect.left) * n.frac)
            if (x < midX) {
                id := n.a ? n.a : rootId
                rect := { left:rect.left, top:rect.top, right:midX, bottom:rect.bottom }
            } else {
                id := n.b ? n.b : rootId
                rect := { left:midX, top:rect.top, right:rect.right, bottom:rect.bottom }
            }
        } else {
            midY := rect.top + Round((rect.bottom - rect.top) * n.frac)
            if (y < midY) {
                id := n.a ? n.a : rootId
                rect := { left:rect.left, top:rect.top, right:rect.right, bottom:midY }
            } else {
                id := n.b ? n.b : rootId
                rect := { left:rect.left, top:midY, right:rect.right, bottom:rect.bottom }
            }
        }
    }
}

Layout_RemoveLeaf(mon, leafId) {
    global Layouts
    Layout_Ensure(mon)
    nodes := Layouts[mon].nodes
    if (!nodes.Has(leafId))
        return 0
    leaf := nodes[leafId]
    if (leaf.parent = 0)
        return 0
    parentId := leaf.parent
    parent := nodes[parentId]
    siblingId := (parent.a = leafId) ? parent.b : parent.a
    sibling := nodes[siblingId]
    grandId := parent.parent

    if (grandId = 0) {
        Layouts[mon].root := siblingId
        sibling.parent := 0
    } else {
        grand := nodes[grandId]
        if (grand.a = parentId)
            grand.a := siblingId
        else if (grand.b = parentId)
            grand.b := siblingId
        nodes[grandId] := grand
        sibling.parent := grandId
    }

    nodes.Delete(leafId)
    nodes.Delete(parentId)
    nodes[siblingId] := sibling
    Layouts[mon].nodes := nodes
    Layout_SaveAll()
    return siblingId
}

FindNeighborLeaf(mon, leafId, dir) {
    rects := Layout_AllLeafRects(mon)
    if (!rects.Has(leafId))
        return 0
    cur := rects[leafId]
    tol := 2
    bestId := 0
    bestScore := -99999
    for id, r in rects {
        if (id = leafId)
            continue
        if (dir = "left" && Abs(r.R - cur.L) <= tol) {
            overlap := Min(r.B, cur.B) - Max(r.T, cur.T)
            if (overlap > 0 && overlap > bestScore)
                bestScore := overlap, bestId := id
        } else if (dir = "right" && Abs(r.L - cur.R) <= tol) {
            overlap := Min(r.B, cur.B) - Max(r.T, cur.T)
            if (overlap > 0 && overlap > bestScore)
                bestScore := overlap, bestId := id
        } else if (dir = "up" && Abs(r.B - cur.T) <= tol) {
            overlap := Min(r.R, cur.R) - Max(r.L, cur.L)
            if (overlap > 0 && overlap > bestScore)
                bestScore := overlap, bestId := id
        } else if (dir = "down" && Abs(r.T - cur.B) <= tol) {
            overlap := Min(r.R, cur.R) - Max(r.L, cur.L)
            if (overlap > 0 && overlap > bestScore)
                bestScore := overlap, bestId := id
        }
    }
    return bestId
}

Layout_LeavesUnder(mon, id) {
    global Layouts
    arr := []
    stack := [id]
    while (stack.Length) {
        nid := stack.Pop()
        n := Layouts[mon].nodes[nid]
        if (n.split = "")
            arr.Push(nid)
        else {
            stack.Push(n.a)
            stack.Push(n.b)
        }
    }
    return arr
}

IsDescendant(mon, needle, rootId) {
    global Layouts
    stack := [rootId]
    while (stack.Length) {
        id := stack.Pop()
        if (id = needle)
            return true
        n := Layouts[mon].nodes[id]
        if (n.split != "") {
            stack.Push(n.a)
            stack.Push(n.b)
        }
    }
    return false
}

ReapplySubtree(mon, nodeId) {
    global WinToLeaf, Layouts
    leaves := Layout_LeavesUnder(mon, nodeId)
    set := Map()
    for id in leaves
        set[id] := true
    for hwnd, info in WinToLeaf {
        if (info.mon = mon) && set.Has(info.leaf) {
            r := GetLeafRect(mon, info.leaf)
            MoveWindow(hwnd, r.L, r.T, r.R - r.L, r.B - r.T)
        }
    }
}

; =========================
; Layout Persistence (multi-monitor-safe)
; =========================
Layout_SaveAll() {
    global Layouts
    path := Layout_GetStoragePath()
    data := Layout_SerializeAll()
    try {
        layoutFile := FileOpen(path, "w", "UTF-8")
        if (layoutFile) {
            layoutFile.Write(jxon_dump(data, indent := 2))
            layoutFile.Close()
        }
    } catch {
        MsgBox "Layout_SaveAll(): Fehler beim Schreiben der Layout-Datei!"
    }
}

Layout_LoadAll() {
    global Layouts
    path := Layout_GetStoragePath()
    Layouts := Map()

    if (!FileExist(path)) {
        ; Wenn keine Datei existiert → Standardlayout für alle Monitore erstellen
        monCount := MonitorGetCount()
        Loop monCount {
            Layout_Ensure(A_Index)
        }
        return
    }

    try {
        text := FileRead(path, "UTF-8")
    } catch {
        MsgBox "Layout_LoadAll(): Fehler beim Lesen der Datei!"
        return
    }

    try {
        data := jxon_load(&text)
    } catch {
        MsgBox "Layout_LoadAll(): Fehler beim Parsen der Layout-JSON!"
        return
    }

    monCount := MonitorGetCount()

    ; Nur Monitore laden, die tatsächlich existieren
    for mon, layout in data {
        monIdx := Layout_ToInt(mon, 1)
        if (monIdx > monCount)
            continue  ; Monitor existiert nicht mehr
        nodes := Map()
        if (layout.HasOwnProp("nodes")) {
            for id, node in layout.nodes {
                nid := Layout_ToInt(id, 1)
                nodes[nid] := {
                    id: nid,
                    parent: Layout_ToInt(node.HasOwnProp("parent") ? node.parent : 0, 0),
                    split: node.HasOwnProp("split") ? node.split : "",
                    frac: node.HasOwnProp("frac") ? node.frac : 0.5,
                    a: Layout_ToInt(node.HasOwnProp("a") ? node.a : 0, 0),
                    b: Layout_ToInt(node.HasOwnProp("b") ? node.b : 0, 0)
                }
            }
        }
        Layouts[monIdx] := {
            root: Layout_ToInt(layout.HasOwnProp("root") ? layout.root : 1, 1),
            next: Layout_ToInt(layout.HasOwnProp("next") ? layout.next : (nodes.Count + 1), nodes.Count + 1),
            nodes: nodes
        }
    }

    ; Sicherstellen, dass alle angeschlossenen Monitore Layouts haben
    Loop monCount {
        if (!Layouts.Has(A_Index))
            Layout_Ensure(A_Index)
    }

    ; Nach dem Laden sicherstellen, dass keine "toten" Monitore existieren
    count := MonitorGetCount()
    for mon in Layouts {
        if (mon > count) {
            Layouts.Delete(mon)
        }
    }

}

Layout_SerializeAll() {
    global Layouts
    data := Map()
    for mon, layout in Layouts {
        nodes := Map()
        for id, node in layout.nodes {
            nodeMap := Map()
            nodeMap["parent"] := node.parent
            nodeMap["split"] := node.split
            nodeMap["frac"] := node.frac
            nodeMap["a"] := node.a
            nodeMap["b"] := node.b
            nodes[String(id)] := nodeMap
        }
        layoutMap := Map()
        layoutMap["root"] := layout.root
        layoutMap["next"] := layout.next
        layoutMap["nodes"] := nodes
        data[String(mon)] := layoutMap
    }
    return data
}

Layout_ToInt(value, default := 0) {
    try {
        return Integer(value)
    }
    catch {
        return default
    }
}

Layout_GetStoragePath() {
    return A_ScriptDir "\WinSnap_layouts.json"
}


; Window Leaf Assignments speichern/laden
SaveLeafAssignment(mon, leafId, hwnd) {
    global Layouts
    Layout_Ensure(mon)

    exe := WinGetProcessName("ahk_id " hwnd)
    title := WinGetTitle("ahk_id " hwnd)
    if (!exe || !title)
        return

    ; Initialisiere assignments-Array falls nicht vorhanden
    if (!Layouts[mon].HasOwnProp("assignments"))
        Layouts[mon].assignments := []

    assignments := Layouts[mon].assignments

    ; Duplikate entfernen
    for i, entry in assignments {
        if (entry.exe = exe && entry.title = title) {
            assignments.RemoveAt(i)
            break
        }
    }

    assignments.Push({leaf:leafId, exe:exe, title:title})

    Layout_SaveAll()
}

AutoSnap_AssignedWindows() {
    global Layouts
    for mon, layout in Layouts {
        if (!layout.HasOwnProp("assignments"))
            continue

        for entry in layout.assignments {
            if (!entry.HasOwnProp("exe") || !entry.HasOwnProp("title") || !entry.HasOwnProp("leaf"))
                continue

            try {
                ; Nach Fenster suchen, das zu exe UND title passt
                WinGetList &list
                for hwnd in list {
                    WinGetProcessName &winExe, "ahk_id " hwnd
                    WinGetTitle &winTitle, "ahk_id " hwnd

                    if (winExe = entry.exe && winTitle = entry.title) {
                        r := GetLeafRect(mon, entry.leaf)
                        WinGetPos &x, &y, &w, &h, "ahk_id " hwnd
                        if (Abs(r.L - x) > 5 || Abs(r.T - y) > 5)
                            LeafAttachWindow(hwnd, mon, entry.leaf, false)
                        break
                    }
                }
            } catch {
                ; Ignorieren, falls Fehler
            }
        }
    }
}

FindWindow(exe, title := "") {
    idList := WinGetList()
    for hwnd in idList {
        try {
            thisExe := WinGetProcessName("ahk_id " hwnd)
            thisTitle := WinGetTitle("ahk_id " hwnd)
            if (thisExe = exe && (title = "" || InStr(thisTitle, title)))
                return hwnd
        }
    }
    return 0
}

AutoSnap_NewlyStartedWindows() {
    global Layouts
    for mon, layout in Layouts {
        if (!layout.HasOwnProp("assignments"))
            continue

        for entry in layout.assignments {
            hwnd := FindWindow(entry.exe, entry.title)
            if (hwnd) {
                try {
                    x := y := w := h := 0
                    WinGetPos &x, &y, &w, &h, "ahk_id " hwnd
                    if (x < 10 && y < 10) {
                        ; Snap to assigned leaf
                        SnapWindowToLeaf(hwnd, mon, entry.leaf)
                    }
                }
            }
        }
    }
}

SnapWindowToLeaf(hwnd, mon, leafId) {
    rect := GetLeafRect(mon, leafId)
    MoveWindow(hwnd, rect.L, rect.T, rect.R - rect.L, rect.B - rect.T)
    ; Beim AutoSnap nicht die Auswahl/Highlight ändern
    LeafAttachWindow(hwnd, mon, leafId, false)
}



Layout_LoadAll()

; Nach dem Laden des Layouts:
SetTimer(AutoSnap_AssignedWindows, -100)

; Prüft regelmäßig auf neue Fenster, die einsortiert werden sollen
SetTimer(AutoSnap_NewlyStartedWindows, 2000)

