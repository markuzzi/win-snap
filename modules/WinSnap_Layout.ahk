; =========================
; Layout (Grid) – Baum pro Monitor
; =========================
; Initialisiert die Layout-Struktur fuer den Monitor, falls noetig.
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
    LogInfo(Format("Layout_Ensure: initialized layout for monitor {}", mon))
}

; Liefert den Knoteneintrag (Map) fuer id auf dem Monitor.
Layout_Node(mon, id) {
    global Layouts
    Layout_Ensure(mon)
    if (!Layouts.Has(mon))
        return 0
    nodes := Layouts[mon].nodes
    return nodes.Has(id) ? nodes[id] : 0
}

; Prueft, ob der Knoten ein Leaf (keine weitere Teilung) ist.
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

; Teilt ein Leaf in zwei Kinder (orient = "v" oder "h").
Layout_SplitLeaf(mon, leafId, orient) {
    global Layouts
    Layout_Ensure(mon)
    n := Layouts[mon].nodes[leafId]
    if (n.split != "")
        return
    LogInfo(Format("Layout_SplitLeaf: mon={}, leaf={}, orient={} -> split", mon, leafId, orient))
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

; Berechnet das Rechteck eines Knotens anhand des Split-Baums.
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

; Wendet den globalen Abstand (SnapGap) auf ein Rechteck an.
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

; Liefert das Leaf-Rechteck inkl. SnapGap und optionalem oberen Reservebereich
; für Fenster-Pills (wenn aktiviert).
GetLeafRect(mon, leafId) {
    rect := Layout_NodeRect(mon, leafId)
    rect := ApplySnapGap(rect)
    ; Reserve oberhalb der Area einziehen, wenn Pills aktiv sind
    try {
        global WindowPillsEnabled, WindowPillsReserve, WindowPillsReserveAllLeaves, WindowPillsReserveDefaultPx
        if (IsSet(WindowPillsEnabled) && WindowPillsEnabled) {
            res := 0
            key := mon ":" leafId
            if (IsSet(WindowPillsReserve) && (WindowPillsReserve is Map) && WindowPillsReserve.Has(key))
                res := WindowPillsReserve[key]
            else if (IsSet(WindowPillsReserveAllLeaves) && WindowPillsReserveAllLeaves && IsSet(WindowPillsReserveDefaultPx))
                res := WindowPillsReserveDefaultPx
            if (res > 0) {
                rect.T += Round(res)
                if (rect.B <= rect.T)
                    rect.B := rect.T + 1
            }
        }
    }
    catch Error as e {
        LogError("GetLeafRect: failed to apply pills top reserve")
    }
    return rect
}

; Liefert eine Map aller Leaf-Rechtecke des Monitors.
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

; Findet das Leaf, das den Punkt (x,y) enthaelt.
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

; Entfernt ein Leaf und promoted das Geschwister; gibt dessen Id zurueck.
Layout_RemoveLeaf(mon, leafId) {
    global Layouts
    Layout_Ensure(mon)
    nodes := Layouts[mon].nodes
    if (!nodes.Has(leafId))
        return 0
    LogInfo(Format("Layout_RemoveLeaf: mon={}, leaf={} -> remove", mon, leafId))
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
    LogInfo(Format("Layout_RemoveLeaf: mon={}, leaf={} -> promoted {}", mon, leafId, siblingId))
    return siblingId
}

; Findet das benachbarte Leaf in der angegebenen Richtung.
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

; Sammelt alle Leaf-Ids unterhalb des Knotens id.
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

; Prueft, ob needle ein Nachfahre von rootId ist.
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

; Findet den naechsten Vorfahren (Split-Knoten mit Achse axis), dessen andere
; Seite den zweiten Leaf enthaelt. Trennt also exakt die Grenze zwischen leafA
; und leafB entlang der Achse.
Layout_FindAxisSplitBetweenLeaves(mon, leafA, leafB, axis) {
    global Layouts
    Layout_Ensure(mon)
    nodes := Layouts[mon].nodes
    if (!nodes.Has(leafA) || !nodes.Has(leafB))
        return 0
    cur := leafA
    while (true) {
        n := nodes[cur]
        if (n.parent = 0)
            break
        pid := n.parent
        p := nodes[pid]
        if ((axis = "v" && p.split = "v") || (axis = "h" && p.split = "h")) {
            sibling := (p.a = cur) ? p.b : p.a
            if (IsDescendant(mon, leafB, sibling))
                return pid
        }
        cur := pid
    }
    return 0
}

; Wendet die aktuellen Rechtecke auf alle Fenster des Teilbaums erneut an.
ReapplySubtree(mon, nodeId) {
    global WinToLeaf, Layouts, SuppressMoveHighlight
    wasSuppressed := (IsSet(SuppressMoveHighlight) && SuppressMoveHighlight)
    SuppressMoveHighlight := true
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
    SuppressMoveHighlight := wasSuppressed
    LogDebug(Format("ReapplySubtree: mon={}, node={}, leaves={} windows reapplied", mon, nodeId, leaves.Length))

    try {
        WindowPills_Invalidate()
    }
    catch Error as e {
        LogException(e, "Layout_SelectFirstLeaf: WindowPills_Invalidate failed")
    }
}

; =========================
; Layout Persistence (multi-monitor-safe)
; =========================
; Speichert alle Layouts als JSON-Datei (multi-monitor-safe).
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
    LogInfo(Format("Layout_SaveAll: saved to {}", path))
}

; Laedt alle Layouts aus der JSON-Datei oder initialisiert Defaults.
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
        LogInfo("Layout_LoadAll: no file found, initialized defaults")
        return
    }

    try {
        text := FileRead(path, "UTF-8")
    } catch {
        MsgBox "Layout_LoadAll(): Fehler beim Lesen der Datei!"
        LogInfo("Layout_LoadAll: read failed")
        return
    }

    try {
        data := jxon_load(&text)
    } catch {
        MsgBox "Layout_LoadAll(): Fehler beim Parsen der Layout-JSON!"
        LogInfo("Layout_LoadAll: parse failed")
        return
    }

    monCount := MonitorGetCount()

    ; Nur Monitore laden, die tatsächlich existieren
    for mon, layout in data {
        monIdx := Layout_ToInt(mon, 1)
        if (monIdx > monCount)
            continue  ; Monitor existiert nicht mehr
        nodes := Map()
        if (IsObject(layout) && layout.Has("nodes")) {
            for id, node in layout["nodes"] {
                nid := Layout_ToInt(id, 1)
                nodes[nid] := {
                    id: nid,
                    parent: Layout_ToInt(node.Has("parent") ? node["parent"] : 0, 0),
                    split: node.Has("split") ? node["split"] : "",
                    frac: node.Has("frac") ? node["frac"] : 0.5,
                    a: Layout_ToInt(node.Has("a") ? node["a"] : 0, 0),
                    b: Layout_ToInt(node.Has("b") ? node["b"] : 0, 0)
                }
            }
        }
        Layouts[monIdx] := {
            root: Layout_ToInt(layout.Has("root") ? layout["root"] : 1, 1),
            next: Layout_ToInt(layout.Has("next") ? layout["next"] : (nodes.Count + 1), nodes.Count + 1),
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

    ; Anzahl SnapAreas (Leaf-Knoten) pro Monitor ins Log schreiben
    for mon, layout in Layouts {
        leafCount := 0
        try {
            if (IsObject(layout) && layout.HasOwnProp("nodes") && IsObject(layout.nodes)) {
                for id, node in layout.nodes {
                    if (node.split = "")
                        leafCount += 1
                }
            }
        }
        LogInfo(Format("Layout_LoadAll: Loaded {} snapAreas for monitor {}", leafCount, mon))
    }

    LogInfo(Format("Layout_LoadAll: loaded layouts for {} monitors", Layouts.Count))
}

; Serialisiert die Layouts in eine Map-Struktur fuer JSON.
Layout_SerializeAll() {
    global Layouts
    data := Map()
    for mon, layout in Layouts {
        if (!IsObject(layout) || !layout.HasOwnProp("nodes") || !IsObject(layout.nodes))
            continue
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

; Konvertiert einen Wert in Integer mit Default bei Fehler.
Layout_ToInt(value, default := 0) {
    try {
        return Integer(value)
    }
    catch Error as e {
        return default
    }
}

; Pfad zur Layout-JSON-Datei im Script-Verzeichnis.
Layout_GetStoragePath() {
    return A_ScriptDir "\WinSnap_layouts.json"
}

; Pfad zur AutoSnap-Blacklist-Datei im Script-Verzeichnis.
BlackList_GetStoragePath() {
    return A_ScriptDir "\WinSnap_BlackList.json"
}

; Laedt die AutoSnap-Blacklist aus JSON.
BlackList_Load() {
    global AutoSnapBlackList
    path := BlackList_GetStoragePath()
    AutoSnapBlackList := Map()
    if (!FileExist(path))
        return
    try {
        text := FileRead(path, "UTF-8")
        data := jxon_load(&text)
    } catch {
        LogInfo("BlackList_Load: failed to read or parse file")
        return
    }
    if !(data is Map)
        return
    ; Keys werden unverändert übernommen (z.B. "exe:foo|class:Bar").
    for key, flag in data {
        if (!key || !flag)
            continue
        AutoSnapBlackList[key] := true
    }
}

; Speichert die aktuelle AutoSnap-Blacklist als JSON.
BlackList_Save() {
    global AutoSnapBlackList
    path := BlackList_GetStoragePath()
    if (!IsSet(AutoSnapBlackList) || !(AutoSnapBlackList is Map))
        AutoSnapBlackList := Map()
    data := Map()
    for exe, flag in AutoSnapBlackList {
        if (flag)
            data[exe] := true
    }
    try {
        f := FileOpen(path, "w", "UTF-8")
        if (f) {
            f.Write(jxon_dump(data, indent := 2))
            f.Close()
        }
    } catch {
        MsgBox "BlackList_Save(): Fehler beim Schreiben der BlackList-Datei!"
    }
    LogInfo(Format("BlackList_Save: saved to {}", path))
}

; Bestimmt, ob eine EXE/Klasse-Kombination vom AutoSnap ausgeschlossen ist.
; Es wird nur gematcht, wenn sowohl exe als auch className vorhanden sind.
IsBlacklistedExe(exe, className := "") {
    global AutoSnapBlackList
    if (!IsSet(AutoSnapBlackList) || !(AutoSnapBlackList is Map))
        AutoSnapBlackList := Map()
    ; Nur Kombinationen zählen: beide müssen gesetzt sein.
    if (!exe || !className)
        return false
    key := "exe:" . StrLower(exe) . "|class:" . className
    return AutoSnapBlackList.Has(key)
}


; Window Leaf Assignments speichern/laden
; Speichert eine Zuordnung (exe+title) fuer ein Leaf des Monitors.
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
    LogInfo(Format("SaveLeafAssignment: mon={}, leaf={}, exe={}, title={} -> saved", mon, leafId, exe, title))
}

; Snappt bekannte (zugeordnete) Fenster an ihr Leaf, falls noetig.
AutoSnap_AssignedWindows() {
    global Layouts
    for mon, layout in Layouts {
        if (!IsObject(layout) || !layout.HasOwnProp("assignments"))
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
                        if (Abs(r.L - x) > 5 || Abs(r.T - y) > 5) {
                            LeafAttachWindow(hwnd, mon, entry.leaf, false)
                            LogInfo(Format("AutoSnap_AssignedWindows: attach hwnd={} to mon={}, leaf={}", hwnd, mon, entry.leaf))
                        }
                        break
                    }
                }
            } catch {
                ; Ignorieren, falls Fehler
            }
        }
    }
}

; Sucht ein Fensterhandle nach Prozessname und optional Titelteil.
FindWindow(exe, title := "") {
    idList := WinGetList()
    for hwnd in idList {
        try {
            thisExe := WinGetProcessName("ahk_id " hwnd)
            thisTitle := WinGetTitle("ahk_id " hwnd)
            if (thisExe = exe && (title = "" || InStr(thisTitle, title)))
                return hwnd
        }
        catch Error as e {
            LogError("FindWindow: query failed")
        }
    }
    return 0
}

; Auto-Snap fuer Fenster:
; - Alle nicht geblacklisteten Fenster werden einer SnapArea zugeordnet.
; - Neue Fenster ohne Leaf-Zuordnung werden in die aktuell aktive SnapArea gesnappt.
; - Bereits zugeordnete Fenster werden bei Bedarf in ihr Leaf zurueckgesetzt (z.B. nach Restore).
AutoSnap_NewlyStartedWindows() {
    global Layouts, WinToLeaf

    ; Aktive SnapArea (Monitor + Leaf) bestimmen
    ctx := ApplyManualNavigation(GetLeafNavigationContext())
    if (!ctx.mon) {
        if (MonitorGetCount() = 0)
            return
        ctx.mon := 1
    }
    Layout_Ensure(ctx.mon)
    if (!ctx.leaf) {
        sel := GetSelectedLeaf(ctx.mon)
        ctx.leaf := sel ? sel : Layouts[ctx.mon].root
    }
    if (!ctx.leaf)
        return
    if (!Layouts[ctx.mon].nodes.Has(ctx.leaf))
        ctx.leaf := Layouts[ctx.mon].root

    targetMon := ctx.mon
    targetLeaf := ctx.leaf

    ; Alle Fenster durchgehen und passend einsortieren
    try {
        all := WinGetList()
    } catch Error as e {
        LogException(e, "AutoSnap_NewlyStartedWindows: WinGetList failed")
        return
    }

    for hwnd in all {
        if (!IsCollectibleSnapWindow(hwnd))
            continue

        ; Prozessname/Klasse ermitteln und ggf. Blacklist pruefen
        try {
            exe := WinGetProcessName("ahk_id " hwnd)
        } catch {
            exe := ""
        }
        try {
            className := WinGetClass("ahk_id " hwnd)
        } catch {
            className := ""
        }
        if ((exe || className) && IsBlacklistedExe(exe, className))
            continue

        ; Bereits einem Leaf zugeordnet? -> sicherstellen, dass es in seinem Leaf liegt.
        if (WinToLeaf.Has(hwnd)) {
            info := WinToLeaf[hwnd]
            mon := info.mon
            leaf := info.leaf
            Layout_Ensure(mon)
            r := GetLeafRectPx(mon, leaf)
            try {
                WinGetPos &x, &y, &w, &h, "ahk_id " hwnd
            } catch {
                continue
            }
            cx := x + (w / 2)
            cy := y + (h / 2)
            if (cx < r.L || cx > r.R || cy < r.T || cy > r.B) {
                SnapWindowToLeaf(hwnd, mon, leaf)
            }
            continue
        }

        ; Noch keinem Leaf zugeordnet -> in die aktive SnapArea einsortieren.
        SnapWindowToLeaf(hwnd, targetMon, targetLeaf)
    }
}

; Bewegt ein Fenster in das Ziel-Leaf und aktualisiert das Mapping.
SnapWindowToLeaf(hwnd, mon, leafId) {
    rect := GetLeafRect(mon, leafId)
    MoveWindow(hwnd, rect.L, rect.T, rect.R - rect.L, rect.B - rect.T)
    ; Beim AutoSnap nicht die Auswahl/Highlight ändern
    LeafAttachWindow(hwnd, mon, leafId, false)
    LogInfo(Format("SnapWindowToLeaf: hwnd={} -> mon={}, leaf={}", hwnd, mon, leafId))
}



Layout_LoadAll()
BlackList_Load()

; Nach dem Laden des Layouts:
SetTimer(AutoSnap_AssignedWindows, -100)

; Prüft regelmäßig auf neue Fenster, die einsortiert werden sollen
; SetTimer(AutoSnap_NewlyStartedWindows, 2000)


; =========================
; Layout Presets (per monitor)
; =========================

; Loescht Leaf-/Fensterzuordnungen und Auswahlinfos fuer den Monitor.
Layout_ClearMonitorState(mon) {
    global LeafWindows, WinToLeaf, CurrentLeafSelection, CurrentHighlight
    delKeys := []
    for key in LeafWindows {
        try {
            parts := StrSplit(key, ":")
            if (parts.Length >= 1 && Integer(parts[1]) = mon)
                delKeys.Push(key)
        }
    }
    for k in delKeys
        LeafWindows.Delete(k)
    delHwnd := []
    for hwnd, info in WinToLeaf {
        if (info.mon = mon)
            delHwnd.Push(hwnd)
    }
    for h in delHwnd
        WinToLeaf.Delete(h)
    try {
        if (CurrentLeafSelection.Has(mon))
            CurrentLeafSelection.Delete(mon)
    }
    ; Manuelle Navigation und ggf. aktives Highlight fr diesen Monitor zurcksetzen
    try {
        ManualNav_Clear(mon)
    }
    catch Error as e {
        LogError("Layout_ResetMonitor: ManualNav_Clear failed")
    }
    try {
        if (CurrentHighlight.mon = mon)
            HideHighlight()
    }

    try {
        SnappedWindows_ScheduleWrite()
    }
    catch Error as e {
        LogException(e, "Layout_ClearMonitorState: SnappedWindows_ScheduleWrite failed")
    }
}

; Setzt das Layout eines Monitors zurueck und waehlt das erste Leaf.
Layout_ResetMonitor(mon) {
    global Layouts
    if (Layouts.Has(mon))
        Layouts.Delete(mon)
    Layout_Ensure(mon)
    Layout_ClearMonitorState(mon)
    LogInfo(Format("Layout_ResetMonitor: mon={}", mon))
    Layout_SelectFirstLeaf(mon)
}

; Preset: Erzeugt Spaltenlayout gem. Gewichten fracs.
Layout_SetMonitorColumns(mon, fracs) {
    global Layouts
    if !(fracs is Array)
        return
    Layout_ResetMonitor(mon)
    root := Layouts[mon].root
    total := 0.0
    for v in fracs
        total += v
    if (total <= 0)
        total := 1.0
    remaining := total
    curLeaf := root
    i := 1
    while (i <= fracs.Length - 1) {
        share := fracs[i] / remaining
        Layout_SplitLeaf(mon, curLeaf, "v")
        n := Layouts[mon].nodes[curLeaf]
        n.frac := ClampFrac(share)
        Layouts[mon].nodes[curLeaf] := n
        nextLeaf := n.b
        remaining -= fracs[i]
        curLeaf := nextLeaf
        i += 1
    }
    Layout_SaveAll()
    LogInfo(Format("Layout_SetMonitorColumns: mon={}, cols={}", mon, fracs.Length))
    Layout_SelectFirstLeaf(mon)
}

; Preset: Erzeugt 2x2-Quadrantenlayout fuer den Monitor.
Layout_SetMonitorQuadrants(mon) {
    global Layouts
    Layout_ResetMonitor(mon)
    root := Layouts[mon].root
    Layout_SplitLeaf(mon, root, "h")
    nr := Layouts[mon].nodes[root]
    nr.frac := ClampFrac(0.5)
    Layouts[mon].nodes[root] := nr
    top := nr.a
    Layout_SplitLeaf(mon, top, "v")
    nt := Layouts[mon].nodes[top]
    nt.frac := ClampFrac(0.5)
    Layouts[mon].nodes[top] := nt
    bottom := nr.b
    Layout_SplitLeaf(mon, bottom, "v")
    nb := Layouts[mon].nodes[bottom]
    nb.frac := ClampFrac(0.5)
    Layouts[mon].nodes[bottom] := nb
    Layout_SaveAll()
    LogInfo(Format("Layout_SetMonitorQuadrants: mon={}", mon))
    Layout_SelectFirstLeaf(mon)
}

; Wählt ein stabiles erstes Leaf (links oben) für den Monitor
; Waehlt das links-oben gelegene erste Leaf aus.
Layout_SelectFirstLeaf(mon) {
    Layout_Ensure(mon)
    rects := Layout_AllLeafRects(mon)
    if (rects.Count = 0)
        return
    bestId := 0
    bestL := 10**9, bestT := 10**9
    for id, r in rects {
        px := ToPixelRect(mon, r)
        if (px.L < bestL) || (px.L = bestL && px.T < bestT) {
            bestL := px.L
            bestT := px.T
            bestId := id
        }
    }
    if (bestId)
        SelectLeaf(mon, bestId, "manual")

    try {
        WindowPills_Invalidate()
    }
    catch Error as e {
        LogException(e, "Layout_SelectFirstLeaf: WindowPills_Invalidate failed")
    }
}
