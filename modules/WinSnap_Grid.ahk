; =========================
; Snap / UnSnap / Grid-Navigation
; =========================


SnapToLeaf(hwnd, mon, leafId) {
    r := GetLeafRectPx(mon, leafId)
    MoveWindow(hwnd, r.L, r.T, r.R - r.L, r.B - r.T)
    LeafAttachWindow(hwnd, mon, leafId)
    ApplyLeafHighlight(mon, leafId)
}

MoveWindowIntoLeaf(hwnd, ctx) {
    if (!ctx || !ctx.mon || !ctx.leaf)
        return
    EnsureHistory(hwnd)
    SnapToLeaf(hwnd, ctx.mon, ctx.leaf)
}

EnsureHistory(hwnd) {
    global WinHistory
    if (WinHistory.Has(hwnd))
        return
    try {
        WinGetPos &x, &y, &w, &h, "ahk_id " hwnd
    } catch {
        return
    }
    WinHistory[hwnd] := { x:x, y:y, w:w, h:h }
}

UnSnapWindow(hwnd) {
    global WinHistory, LastDir
    if (WinHistory.Has(hwnd) && DllCall("IsWindow", "ptr", hwnd) && WinExist("ahk_id " hwnd)) {
        prev := WinHistory[hwnd]
        if (MoveWindow(hwnd, prev.x, prev.y, prev.w, prev.h)) {
            WinHistory.Delete(hwnd)
            if (LastDir.Has(hwnd))
                LastDir.Delete(hwnd)
            LeafDetachWindow(hwnd, true)
        }
    }
}

; >>> GridMove mit Auto-Split & „erstem Snap“
GridMove(dir) {
    global WinToLeaf, LastDir, Layouts
    win := GetActiveWindow()
    if (!win)
        return
    hwnd := win.hwnd
    monInfo := GetMonitorIndexAndArea(hwnd)
    mon := monInfo.index
    Layout_Ensure(mon)

    root := Layouts[mon].root
    cx := win.x + win.w/2
    cy := win.y + win.h/2

    ; --- Fenster noch nicht gesnappt ---
    if (!WinToLeaf.Has(hwnd)) {
        EnsureHistory(hwnd)

        ; Root ggf. automatisch splitten (damit Win+←/→/↑/↓ sofort snappen)
        if (Layout_IsLeaf(mon, root)) {
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
    if (next) {
        SnapToLeaf(hwnd, mon, next)
        SetLastDirection(hwnd, dir)
        return
    }

    ; --- Kein Nachbar-Leaf → versuche Nachbar-Monitor ---
    nextMon := FindNeighborMonitor(mon, dir)
    if (!nextMon)
        return

    Layout_Ensure(nextMon)
    nextLeaf := GetSelectedLeaf(nextMon)
    if (!nextLeaf)
        nextLeaf := Layouts[nextMon].root

    ; Fenster physisch auf den nächsten Monitor verschieben
    r := GetLeafRect(nextMon, nextLeaf)
    MoveWindow(hwnd, r.L, r.T, r.R - r.L, r.B - r.T)
    LeafDetachWindow(hwnd, true)
    LeafAttachWindow(hwnd, nextMon, nextLeaf)
    ApplyLeafHighlight(nextMon, nextLeaf)
    SetLastDirection(hwnd, dir)
}

; Für „erstes Snap“ (wenn noch nicht gesnappt): passende Leaf in Richtung wählen
PickLeafForUnsapped(mon, dir, cx, cy) {
    Layout_Ensure(mon)
    rects := Layout_AllLeafRects(mon)
    cands := []
    for id, r in rects {
        rr := ToPixelRect(mon, r) ; sicher in Pixel vergleichen
        if (dir = "left" || dir = "right") {
            if (cy >= rr.T && cy < rr.B)
                cands.Push({id:id, r:rr})
        } else {
            if (cx >= rr.L && cx < rr.R)
                cands.Push({id:id, r:rr})
        }
    }
    if (cands.Length = 0) {
        for id, r in rects
            cands.Push({id:id, r:ToPixelRect(mon, r)})
    }
    if (cands.Length = 0)
        return Layouts[mon].root

    bestId := cands[1].id
    if (dir = "left") {
        bestX := 10**9
        for o in cands
            if (o.r.L < bestX)
                bestX := o.r.L, bestId := o.id
    } else if (dir = "right") {
        bestX := -10**9
        for o in cands
            if (o.r.R > bestX)
                bestX := o.r.R, bestId := o.id
    } else if (dir = "up") {
        bestY := 10**9
        for o in cands
            if (o.r.T < bestY)
                bestY := o.r.T, bestId := o.id
    } else if (dir = "down") {
        bestY := -10**9
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
    if (!win)
        return
    hwnd := win.hwnd
    monInfo := GetMonitorIndexAndArea(hwnd)
    ctx := ApplyManualNavigation(GetLeafNavigationContext())
    mon := ctx.mon ? ctx.mon : monInfo.index
    Layout_Ensure(mon)

    leaf := ctx.leaf
    if (!leaf && WinToLeaf.Has(hwnd) && WinToLeaf[hwnd].mon = mon)
        leaf := WinToLeaf[hwnd].leaf
    if (!leaf) {
        EnsureHistory(hwnd)
        if (mon = monInfo.index) {
            cx := win.x + win.w/2, cy := win.y + win.h/2
            leaf := Layout_FindLeafAtPoint(mon, cx, cy)
        } else {
            leaf := Layouts[mon].root
        }
    }

    nBefore := Layout_Node(mon, leaf)
    if (!nBefore) {
        leaf := Layouts[mon].root
        nBefore := Layout_Node(mon, leaf)
        if (!nBefore)
            return
    }
    if (nBefore.split != "")
        return
    Layout_SplitLeaf(mon, leaf, orient)

    nAfter := Layout_Node(mon, leaf)   ; nun interner Knoten
    if (!nAfter)
        return
    leftOrTop := nAfter.a
    SelectLeaf(mon, leftOrTop, "manual")
    SnapToLeaf(hwnd, mon, leftOrTop)
    LastDir[hwnd] := (orient = "v") ? "left" : "top"
}

AdjustBoundaryForActive(whichArrow) {
    global SplitStep, Layouts
    ctx := ApplyManualNavigation(GetLeafNavigationContext())
    if (!ctx.mon || !ctx.leaf)
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
        if (leftOrTop)
            p.frac += (whichArrow="Right") ? +step : -step
        else
            p.frac += (whichArrow="Right") ? -step : +step
    } else {
        if (leftOrTop)
            p.frac += (whichArrow="Down") ? +step : -step
        else
            p.frac += (whichArrow="Down") ? -step : +step
    }
    p.frac := ClampFrac(p.frac)
    Layouts[mon].nodes[parent] := p

    ReapplySubtree(mon, parent)
    Layout_SaveAll()
}

SwitchSnapArea(dir) {
    global Layouts
    ctx := ApplyManualNavigation(GetLeafNavigationContext())
    if (!ctx.mon)
        return
    Layout_Ensure(ctx.mon)
    if (!ctx.leaf) {
        sel := GetSelectedLeaf(ctx.mon)
        if (sel)
            ctx.leaf := sel
        else
            ctx.leaf := Layouts[ctx.mon].root
    }
    if (!ctx.leaf)
        return
    neighbor := FindNeighborLeaf(ctx.mon, ctx.leaf, dir)
    if (neighbor) {
        SelectLeaf(ctx.mon, neighbor, "manual")
        target := LeafGetTopWindow(ctx.mon, neighbor)
        if (target)
            WinActivate "ahk_id " target
        else
            FlashLeafOutline(ctx.mon, neighbor)
        return
    }
    nextMon := FindNeighborMonitor(ctx.mon, dir)
    if (!nextMon)
        return
    Layout_Ensure(nextMon)
    leaf := GetSelectedLeaf(nextMon)
    if (!leaf)
        leaf := Layouts[nextMon].root
    SelectLeaf(nextMon, leaf, "manual")
    target := LeafGetTopWindow(nextMon, leaf)
    if (target)
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
    bestDist := 10**18
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
    if (!win)
        return
    hwnd := win.hwnd
    if (!WinToLeaf.Has(hwnd))
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
    if (WinExist("ahk_id " target))
        WinActivate "ahk_id " target
}

DeleteCurrentSnapArea() {
    global LeafWindows
    ctx := ApplyManualNavigation(GetLeafNavigationContext())
    if (!ctx.mon || !ctx.leaf)
        return
    Layout_Ensure(ctx.mon)
    rects := Layout_AllLeafRects(ctx.mon)
    if (rects.Count <= 1)
        return
    node := Layout_Node(ctx.mon, ctx.leaf)
    if (!node)
        return
    if (node.parent = 0)
        return
    parent := Layout_Node(ctx.mon, node.parent)
    if (!parent)
        return
    siblingId := (parent.a = ctx.leaf) ? parent.b : parent.a
    if (siblingId = 0)
        return
    arrCopy := []
    for hwnd in LeafGetOrderedList(ctx.mon, ctx.leaf)
        arrCopy.Push(hwnd)
    promoted := Layout_RemoveLeaf(ctx.mon, ctx.leaf)
    if (!promoted)
        return
    for hwnd in arrCopy {
        if (DllCall("IsWindow", "ptr", hwnd) && WinExist("ahk_id " hwnd))
            SnapToLeaf(hwnd, ctx.mon, siblingId)
    }
    key := LeafKey(ctx.mon, ctx.leaf)
    if (LeafWindows.Has(key))
        LeafWindows.Delete(key)
    ReapplySubtree(ctx.mon, siblingId)
    SelectLeaf(ctx.mon, siblingId, "manual")
    FlashLeafOutline(ctx.mon, siblingId)
}

ShowAllSnapAreasHotkey() {
    global OverlayColor, OverlayDuration
    count := MonitorGetCount()

    ; Erst alle Layouts sicherstellen (auch wenn JSON mehr Monitore kennt)
    Loop count {
        mon := A_Index
        Layout_Ensure(mon)
    }

    ; Für alle Monitore die SnapAreas anzeigen
    Loop count {
        mon := A_Index
        ShowAllSnapAreasForMonitor(mon)
    }
}


CollectWindowsInActiveLeaf() {
    global Layouts
    ctx := ApplyManualNavigation(GetLeafNavigationContext())
    if (!ctx.mon)
        return
    Layout_Ensure(ctx.mon)
    if (!ctx.leaf) {
        sel := GetSelectedLeaf(ctx.mon)
        ctx.leaf := sel ? sel : Layouts[ctx.mon].root
    }
    if (!ctx.leaf)
        return
    if (!Layouts[ctx.mon].nodes.Has(ctx.leaf))
        ctx.leaf := Layouts[ctx.mon].root
    rect := GetLeafRectPx(ctx.mon, ctx.leaf)
    ids := WinGetList()
    collected := 0
    for hwnd in ids {
        if (!IsCollectibleSnapWindow(hwnd))
            continue
        if (!WindowCenterInsideRect(hwnd, rect))
            continue
        EnsureHistory(hwnd)
        SnapToLeaf(hwnd, ctx.mon, ctx.leaf)
        collected += 1
    }
    SelectLeaf(ctx.mon, ctx.leaf, "manual")
    FlashLeafOutline(ctx.mon, ctx.leaf)
    if (collected > 0) {
        top := LeafGetTopWindow(ctx.mon, ctx.leaf)
        if (top)
            WinActivate "ahk_id " top
    }
}

IsCollectibleSnapWindow(hwnd) {
    static scriptPid := DllCall("GetCurrentProcessId")
    if (!hwnd)
        return false
    if (!DllCall("IsWindow", "ptr", hwnd) || !WinExist("ahk_id " hwnd))
        return false
    try {
        pid := WinGetPID("ahk_id " hwnd)
    } catch {
        pid := 0
    }
    if (pid = scriptPid)
        return false
    try {
        className := WinGetClass("ahk_id " hwnd)
    } catch {
        className := ""
    }
    if (className = "Shell_TrayWnd" || className = "MultitaskingViewFrame" || className = "Progman")
        return false
    try {
        style := WinGetStyle("ahk_id " hwnd)
    } catch {
        style := 0
    }
    WS_VISIBLE := 0x10000000
    if (!(style & WS_VISIBLE))
        return false
    try {
        mm := WinGetMinMax("ahk_id " hwnd)
    } catch {
        mm := 0
    }
    if (mm = -1)
        return false
    return true
}

WindowCenterInsideRect(hwnd, rect) {
    if (!hwnd)
        return false
    try {
        WinGetPos &x, &y, &w, &h, "ahk_id " hwnd
    } catch {
        return false
    }
    if (w <= 0 || h <= 0)
        return false
    cx := x + (w / 2)
    cy := y + (h / 2)
    return (cx >= rect.L && cx <= rect.R && cy >= rect.T && cy <= rect.B)
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
