; =========================
; Snap / UnSnap / Grid-Navigation
; =========================

SnapToLeaf(hwnd, mon, leafId) {
    r := GetLeafRect(mon, leafId)
    MoveWindow(hwnd, r.L, r.T, r.R - r.L, r.B - r.T)
    LeafAttachWindow(hwnd, mon, leafId)
}

MoveWindowIntoLeaf(hwnd, ctx) {
    if !ctx || !ctx.mon || !ctx.leaf
        return
    EnsureHistory(hwnd)
    SnapToLeaf(hwnd, ctx.mon, ctx.leaf)
}

EnsureHistory(hwnd) {
    global WinHistory
    if WinHistory.Has(hwnd)
        return
    WinGetPos &x, &y, &w, &h, "ahk_id " hwnd
    WinHistory[hwnd] := { x:x, y:y, w:w, h:h }
}

UnSnapWindow(hwnd) {
    global WinHistory, LastDir
    if WinHistory.Has(hwnd) && WinExist("ahk_id " hwnd) {
        prev := WinHistory[hwnd]
        if MoveWindow(hwnd, prev.x, prev.y, prev.w, prev.h) {
            WinHistory.Delete(hwnd)
            if LastDir.Has(hwnd)
                LastDir.Delete(hwnd)
            LeafDetachWindow(hwnd, true)
        }
    }
}

; >>> GridMove mit Auto-Split & „erstem Snap“
GridMove(dir) {
    global WinToLeaf, LastDir, Layouts
    win := GetActiveWindow()
    if !win
        return
    hwnd := win.hwnd
    monInfo := GetMonitorIndexAndArea(hwnd)
    mon := monInfo.index
    Layout_Ensure(mon)

    root := Layouts[mon].root
    cx := win.x + win.w/2
    cy := win.y + win.h/2

    ; --- Fenster noch nicht gesnappt ---
    if !WinToLeaf.Has(hwnd) {
        EnsureHistory(hwnd)

        ; Root ggf. automatisch splitten (damit Win+←/→/↑/↓ sofort snappen)
        if Layout_IsLeaf(mon, root) {
            if (dir = "left" || dir = "right")
                Layout_SplitLeaf(mon, root, "v")
            else if (dir = "up" || dir = "down")
                Layout_SplitLeaf(mon, root, "h")
        }

        target := PickLeafForUnsapped(mon, dir, cx, cy)
        SnapToLeaf(hwnd, mon, target)

        SetLastDirection(hwnd, dir)
        return
    }

    ; --- Fenster ist gesnappt → Nachbar suchen ---
    curLeaf := WinToLeaf[hwnd].leaf
    next := FindNeighborLeaf(mon, curLeaf, dir)
    if next {
        SnapToLeaf(hwnd, mon, next)
        SetLastDirection(hwnd, dir)
    }
}

; Für „erstes Snap“ (wenn noch nicht gesnappt): passende Leaf in Richtung wählen
PickLeafForUnsapped(mon, dir, cx, cy) {
    rects := Layout_AllLeafRects(mon)
    cands := []
    for id, r in rects {
        if (dir = "left" || dir = "right") {
            if (cy >= r.T && cy < r.B)
                cands.Push({id:id, r:r})
        } else {
            if (cx >= r.L && cx < r.R)
                cands.Push({id:id, r:r})
        }
    }
    if (cands.Length = 0) {
        for id, r in rects
            cands.Push({id:id, r:r})
    }

    bestId := cands[1].id
    if (dir = "left") {
        global MAX_X := 1_000_000_000
        bestX := MAX_X
        for o in cands
            if (o.r.L < bestX)
                bestX := o.r.L, bestId := o.id
    } else if (dir = "right") {
        global MIN_X := -1_000_000_000
        bestX := MIN_X
        for o in cands
            if (o.r.R > bestX)
                bestX := o.r.R, bestId := o.id
    } else if (dir = "up") {
        global MAX_Y := 1_000_000_000
        bestY := MAX_Y
        for o in cands
            if (o.r.T < bestY)
                bestY := o.r.T, bestId := o.id
    } else if (dir = "down") {
        global MIN_Y := -1_000_000_000
        bestY := MIN_Y
        for o in cands
            if (o.r.B > bestY)
                bestY := o.r.B, bestId := o.id
    }
    return bestId
}

; =========================
; Splitten & Grenze justieren
; =========================
SplitCurrentLeaf(orient) {
    global WinToLeaf, Layouts, LastDir
    ; orient = "v" (links/rechts) oder "h" (oben/unten)
    win := GetActiveWindow()
    if !win
        return
    hwnd := win.hwnd
    monInfo := GetMonitorIndexAndArea(hwnd)
    ctx := ApplyManualNavigation(GetLeafNavigationContext())
    mon := ctx.mon ? ctx.mon : monInfo.index
    Layout_Ensure(mon)

    leaf := ctx.leaf
    if (!leaf && WinToLeaf.Has(hwnd) && WinToLeaf[hwnd].mon = mon)
        leaf := WinToLeaf[hwnd].leaf
    if !leaf {
        EnsureHistory(hwnd)
        if (mon = monInfo.index) {
            cx := win.x + win.w/2, cy := win.y + win.h/2
            leaf := Layout_FindLeafAtPoint(mon, cx, cy)
        } else {
            leaf := Layouts[mon].root
        }
    }

    nBefore := Layout_Node(mon, leaf)
    if (nBefore.split != "")
        return
    Layout_SplitLeaf(mon, leaf, orient)

    nAfter := Layout_Node(mon, leaf)   ; nun interner Knoten
    leftOrTop := nAfter.a
    SelectLeaf(mon, leftOrTop, "manual")
    SnapToLeaf(hwnd, mon, leftOrTop)
    LastDir[hwnd] := (orient = "v") ? "left" : "top"
}

AdjustBoundaryForActive(whichArrow) {
    global SplitStep, Layouts
    ctx := ApplyManualNavigation(GetLeafNavigationContext())
    if !ctx.mon || !ctx.leaf
        return
    mon := ctx.mon
    leaf := ctx.leaf

    ; passenden Elternknoten (gleiche Achse) finden
    nodeId := leaf
    axis := (whichArrow="Left" || whichArrow="Right") ? "v" : "h"
    parent := 0
    while true {
        n := Layouts[mon].nodes[nodeId]
        if (n.parent = 0)
            break
        p := Layouts[mon].nodes[n.parent]
        if ((axis="v" && p.split="v") || (axis="h" && p.split="h")) {
            parent := n.parent
            break
        }
        nodeId := n.parent
    }
    if (parent = 0)
        return

    p := Layouts[mon].nodes[parent]
    leftOrTop := IsDescendant(mon, leaf, p.a)  ; liegt Leaf auf linker/oberer Seite?

    step := SplitStep
    if (axis = "v") {
        if leftOrTop
            p.frac += (whichArrow="Right") ? +step : -step
        else
            p.frac += (whichArrow="Right") ? -step : +step
    } else {
        if leftOrTop
            p.frac += (whichArrow="Down") ? +step : -step
        else
            p.frac += (whichArrow="Down") ? -step : +step
    }
    p.frac := ClampFrac(p.frac)
    Layouts[mon].nodes[parent] := p

    ReapplySubtree(mon, parent)
}

SwitchSnapArea(dir) {
    global Layouts
    ctx := ApplyManualNavigation(GetLeafNavigationContext())
    if !ctx.mon
        return
    Layout_Ensure(ctx.mon)
    if !ctx.leaf {
        sel := GetSelectedLeaf(ctx.mon)
        if sel
            ctx.leaf := sel
        else
            ctx.leaf := Layouts[ctx.mon].root
    }
    if !ctx.leaf
        return
    neighbor := FindNeighborLeaf(ctx.mon, ctx.leaf, dir)
    if neighbor {
        SelectLeaf(ctx.mon, neighbor, "manual")
        target := LeafGetTopWindow(ctx.mon, neighbor)
        if target
            WinActivate "ahk_id " target
        else
            FlashLeafOutline(ctx.mon, neighbor)
        return
    }
    nextMon := FindNeighborMonitor(ctx.mon, dir)
    if !nextMon
        return
    Layout_Ensure(nextMon)
    leaf := GetSelectedLeaf(nextMon)
    if !leaf
        leaf := Layouts[nextMon].root
    SelectLeaf(nextMon, leaf, "manual")
    target := LeafGetTopWindow(nextMon, leaf)
    if target
        WinActivate "ahk_id " target
    else
        FlashLeafOutline(nextMon, leaf)
}

FindNeighborMonitor(mon, dir) {
    cur := GetMonitorWork(mon)
    curCX := (cur.left + cur.right) / 2
    curCY := (cur.top + cur.bottom) / 2
    vx := 0, vy := 0
    if (dir = "left")
        vx := -1
    else if (dir = "right")
        vx := 1
    else if (dir = "up")
        vy := -1
    else if (dir = "down")
        vy := 1
    if (vx = 0 && vy = 0)
        return 0
    count := MonitorGetCount()
    best := 0
    bestScore := -1
    global MAX_DIST := 1_000_000_000_000_000_000
    bestDist := MAX_DIST
    Loop count {
        idx := A_Index
        if (idx = mon)
            continue
        other := GetMonitorWork(idx)
        ocx := (other.left + other.right) / 2
        ocy := (other.top + other.bottom) / 2
        dx := ocx - curCX
        dy := ocy - curCY
        dist := Sqrt(dx*dx + dy*dy)
        if (dist = 0)
            continue
        proj := (vx * dx + vy * dy) / dist
        if (proj <= 0)
            continue
        if (proj > bestScore || (Abs(proj - bestScore) < 0.0001 && dist < bestDist)) {
            bestScore := proj
            bestDist := dist
            best := idx
        }
    }
    return best
}

CycleWindowInLeaf(direction) {
    global WinToLeaf
    win := GetActiveWindow()
    if !win
        return
    hwnd := win.hwnd
    if !WinToLeaf.Has(hwnd)
        return
    info := WinToLeaf[hwnd]
    arr := LeafGetOrderedList(info.mon, info.leaf)
    if (arr.Length <= 1)
        return
    idx := 0
    Loop arr.Length {
        if (arr[A_Index] = hwnd) {
            idx := A_Index
            break
        }
    }
    if (idx = 0)
        return
    if (direction = "next")
        idx := (idx = arr.Length) ? 1 : idx + 1
    else
        idx := (idx = 1) ? arr.Length : idx - 1
    target := arr[idx]
    if WinExist("ahk_id " target)
        WinActivate "ahk_id " target
}

DeleteCurrentSnapArea() {
    global LeafWindows
    ctx := ApplyManualNavigation(GetLeafNavigationContext())
    if !ctx.mon || !ctx.leaf
        return
    Layout_Ensure(ctx.mon)
    rects := Layout_AllLeafRects(ctx.mon)
    if (rects.Count <= 1)
        return
    node := Layout_Node(ctx.mon, ctx.leaf)
    if (node.parent = 0)
        return
    parent := Layout_Node(ctx.mon, node.parent)
    siblingId := (parent.a = ctx.leaf) ? parent.b : parent.a
    if (siblingId = 0)
        return
    arrCopy := []
    for hwnd in LeafGetOrderedList(ctx.mon, ctx.leaf)
        arrCopy.Push(hwnd)
    promoted := Layout_RemoveLeaf(ctx.mon, ctx.leaf)
    if !promoted
        return
    for hwnd in arrCopy {
        if WinExist("ahk_id " hwnd)
            SnapToLeaf(hwnd, ctx.mon, siblingId)
    }
    key := LeafKey(ctx.mon, ctx.leaf)
    if LeafWindows.Has(key)
        LeafWindows.Delete(key)
    ReapplySubtree(ctx.mon, siblingId)
    SelectLeaf(ctx.mon, siblingId, "manual")
    FlashLeafOutline(ctx.mon, siblingId)
}

ShowAllSnapAreasHotkey() {
    ctx := ApplyManualNavigation(GetLeafNavigationContext())
    if !ctx.mon
        return
    ShowAllSnapAreasForMonitor(ctx.mon)
}

SetLastDirection(hwnd, dir) {
    global LastDir
    if (dir = "left" || dir = "right")
        LastDir[hwnd] := dir
    else if (dir = "up")
        LastDir[hwnd] := "top"
    else if (dir = "down")
        LastDir[hwnd] := "bottom"
}
