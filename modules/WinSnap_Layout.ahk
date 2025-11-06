; =========================
; Layout (Grid) – Baum pro Monitor
; =========================
Layout_Ensure(mon) {
    global Layouts
    if Layouts.Has(mon)
        return
    nodes := Map()
    nodes[1] := { id:1, parent:0, split:"", frac:0.5, a:0, b:0 }  ; root unsplittet
    Layouts[mon] := { root:1, next:2, nodes:nodes }
}

Layout_Node(mon, id) {
    global Layouts
    return Layouts[mon].nodes[id]
}

Layout_IsLeaf(mon, id) {
    global Layouts
    n := Layouts[mon].nodes[id]
    return (n.split = "")
}

Layout_SplitLeaf(mon, leafId, orient) {
    global Layouts
    Layout_Ensure(mon)
    n := Layouts[mon].nodes[leafId]
    if (n.split != "")
        return  ; bereits gesplittet
    idA := Layouts[mon].next
    idB := idA + 1
    Layouts[mon].next := idB + 1
    Layouts[mon].nodes[idA] := { id:idA, parent:leafId, split:"", frac:0.5, a:0, b:0 }
    Layouts[mon].nodes[idB] := { id:idB, parent:leafId, split:"", frac:0.5, a:0, b:0 }
    n.split := (orient = "v") ? "v" : "h"
    n.frac  := 0.5
    n.a := idA, n.b := idB
}

; Rechteck für einen Node berechnen
Layout_NodeRect(mon, nodeId) {
    monInfo := GetMonitorWork(mon)
    rect := { L:monInfo.left, T:monInfo.top, R:monInfo.right, B:monInfo.bottom }

    global Layouts
    nodes := Layouts[mon].nodes

    ; Pfad von leaf zum Root (Root -> Leaf ablaufen)
    path := []
    cur := nodeId
    while (cur != Layouts[mon].root) {
        parent := nodes[cur].parent
        path.InsertAt(1, { parent: parent, child: cur })   ; vorne einfügen
        cur := parent
    }

    for step in path {
        p := nodes[step.parent]
        if (p.split = "v") {
            midX := rect.L + Round((rect.R - rect.L) * p.frac)
            if (step.child = p.a)
                rect := { L:rect.L, T:rect.T, R:midX, B:rect.B }    ; links
            else
                rect := { L:midX, T:rect.T, R:rect.R, B:rect.B }    ; rechts
        } else if (p.split = "h") {
            midY := rect.T + Round((rect.B - rect.T) * p.frac)
            if (step.child = p.a)
                rect := { L:rect.L, T:rect.T, R:rect.R, B:midY }    ; oben
            else
                rect := { L:rect.L, T:midY, R:rect.R, B:rect.B }    ; unten
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
    out := Map()
    for id, n in Layouts[mon].nodes {
        if (n.split = "")
            out[id] := Layout_NodeRect(mon, id)
    }
    return out
}

Layout_FindLeafAtPoint(mon, x, y) {
    global Layouts
    rect := GetMonitorWork(mon)
    id := Layouts[mon].root
    while true {
        n := Layouts[mon].nodes[id]
        if (n.split = "")
            return id
        if (n.split = "v") {
            midX := rect.left + Round((rect.right - rect.left) * n.frac)
            if (x < midX) {
                id := n.a
                rect := { left:rect.left, top:rect.top, right:midX, bottom:rect.bottom }
            } else {
                id := n.b
                rect := { left:midX, top:rect.top, right:rect.right, bottom:rect.bottom }
            }
        } else {
            midY := rect.top + Round((rect.bottom - rect.top) * n.frac)
            if (y < midY) {
                id := n.a
                rect := { left:rect.left, top:rect.top, right:rect.right, bottom:midY }
            } else {
                id := n.b
                rect := { left:rect.left, top:midY, right:rect.right, bottom:rect.bottom }
            }
        }
    }
}

Layout_RemoveLeaf(mon, leafId) {
    global Layouts
    Layout_Ensure(mon)
    nodes := Layouts[mon].nodes
    if !nodes.Has(leafId)
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
    return siblingId
}

; Nachbar-Leaf neben current in Richtung dir finden
FindNeighborLeaf(mon, leafId, dir) {
    rects := Layout_AllLeafRects(mon)
    if !rects.Has(leafId)
        return 0
    cur := rects[leafId]
    tol := 2

    bestId := 0
    bestScore := -99999

    for id, r in rects {
        if (id = leafId)
            continue
        if (dir = "left") {
            if (Abs(r.R - cur.L) <= tol) {
                overlap := Min(r.B, cur.B) - Max(r.T, cur.T)
                if (overlap > 0 && overlap > bestScore)
                    bestScore := overlap, bestId := id
            }
        } else if (dir = "right") {
            if (Abs(r.L - cur.R) <= tol) {
                overlap := Min(r.B, cur.B) - Max(r.T, cur.T)
                if (overlap > 0 && overlap > bestScore)
                    bestScore := overlap, bestId := id
            }
        } else if (dir = "up") {
            if (Abs(r.B - cur.T) <= tol) {
                overlap := Min(r.R, cur.R) - Max(r.L, cur.L)
                if (overlap > 0 && overlap > bestScore)
                    bestScore := overlap, bestId := id
            }
        } else if (dir = "down") {
            if (Abs(r.T - cur.B) <= tol) {
                overlap := Min(r.R, cur.R) - Max(r.L, cur.L)
                if (overlap > 0 && overlap > bestScore)
                    bestScore := overlap, bestId := id
            }
        }
    }
    return bestId
}

; =========================
; Iterative Helfer (ohne Closures)
; =========================
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

; =========================
; Reflow nur der betroffenen Split-Gruppe
; =========================
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
