; =========================
; Fenster-Suchdialog (Alt+Space)
; =========================
InitWindowSearchGui() {
    global WindowSearch
    if WindowSearch.gui
        return
    g := Gui("+AlwaysOnTop -Caption +ToolWindow +Border")
    g.MarginX := 12
    g.MarginY := 12
    g.BackColor := "0x202020"
    edit := g.AddEdit("w420 vSearchInput")
    list := g.AddListBox("w420 h220")
    edit.OnEvent("Change", WindowSearch_OnInput)
    list.OnEvent("DoubleClick", WindowSearch_OnConfirm)
    g.OnEvent("Escape", (*) => WindowSearch_Close())
    g.OnEvent("Close", (*) => WindowSearch_Close())
    WindowSearch.gui := g
    WindowSearch.edit := edit
    WindowSearch.list := list
}

BuildWindowCandidateList() {
    global WindowSearch
    arr := []
    ids := WinGetList()
    exclusion := WindowSearch.gui ? WindowSearch.gui.Hwnd : 0
    for hwnd in ids {
        if (hwnd = exclusion)
            continue
        if !WinExist("ahk_id " hwnd)
            continue
        title := Trim(WinGetTitle("ahk_id " hwnd))
        class := ""
        try class := WinGetClass("ahk_id " hwnd)
        if (class = "Shell_TrayWnd" || class = "MultitaskingViewFrame")
            continue
        proc := ""
        try proc := WinGetProcessName("ahk_id " hwnd)
        if (title = "")
            title := "[Ohne Titel]"
        display := title
        if (proc != "")
            display .= "   [" proc "]"
        arr.Push({ hwnd:hwnd, title:title, proc:proc, display:display, search:StrLower(title " " proc) })
    }
    return arr
}

WindowSearch_Open() {
    global WindowSearch
    if WindowSearch.active {
        WindowSearch_Close()
        return
    }
    ctx := ApplyManualNavigation(GetLeafNavigationContext())
    if !ctx.mon || !ctx.leaf
        return
    InitWindowSearchGui()
    WindowSearch.ctx := ctx
    WindowSearch.items := BuildWindowCandidateList()
    WindowSearch.filtered := []
    WindowSearch.active := true
    WindowSearch.edit.Value := ""
    WindowSearch_Update("")
    Layout_Ensure(ctx.mon)
    rect := GetLeafRect(ctx.mon, ctx.leaf)
    WindowSearch.gui.Show("AutoSize")
    WindowSearch.gui.GetPos(, , &guiW, &guiH)
    if (!guiW) {
        guiW := 420  ; fallback to default width if GetPos failed
    }
    gx := rect.L + ((rect.R - rect.L) - guiW) / 2
    gy := rect.T + 40
    WindowSearch.gui.Move(Round(gx), Round(gy))
    WindowSearch.gui.Show()
    WindowSearch.edit.Focus()
}

WindowSearch_Close() {
    global WindowSearch
    if !WindowSearch.gui
        return
    WindowSearch.gui.Hide()
    WindowSearch.active := false
}

WindowSearch_OnInput(ctrl, *) {
    WindowSearch_Update(ctrl.Value)
}

WindowSearch_MoveSelection(delta) {
    global WindowSearch
    if (!WindowSearch.filtered.Length)
        return
    lb := WindowSearch.list
    current := lb.Value
    if (current < 1)
        current := 1
    current += delta
    if (current < 1)
        current := WindowSearch.filtered.Length
    else if (current > WindowSearch.filtered.Length)
        current := 1
    lb.Value := current
}

WindowSearch_Update(term := "") {
    global WindowSearch
    if !WindowSearch.gui
        return
    termLower := StrLower(Trim(term))
    list := WindowSearch.list
    list.Delete()
    filtered := []
    for item in WindowSearch.items {
        score := WindowSearch_Score(termLower, item.search)
        if (termLower = "" || score > -9999) {
            filtered.Push({ hwnd:item.hwnd, title:item.title, proc:item.proc, display:item.display, search:item.search, score:score })
        }
    }
    if (termLower != "")
        filtered := ArraySort(filtered, WindowSearch_CompareScore)
    else
        filtered := ArraySort(filtered, WindowSearch_CompareTitle)
    WindowSearch.filtered := filtered
    if (filtered.Length = 0) {
        list.Add(["Keine Fenster gefunden"])
        list.Value := 0
    } else {
        items := []
        for item in filtered
            items.Push(item.display)
        list.Add(items)
        list.Value := 1
    }
}

WindowSearch_Score(termLower, searchText) {
    if (termLower = "")
        return 0
    pos := InStr(searchText, termLower)
    if (pos)
        return 1000 - pos
    score := 0
    idx := 1
    Loop Parse termLower {
        ch := A_LoopField
        found := InStr(SubStr(searchText, idx), ch)
        if !found
            return -10000
        score -= (found - 1) + (idx - 1)
        idx += found
    }
    return score
}

WindowSearch_OnConfirm(*) {
    WindowSearch_Confirm()
}

WindowSearch_CompareScore(a, b, *) {
    if (a.score > b.score)
        return -1
    if (a.score < b.score)
        return 1
    return WindowSearch_CompareTitle(a, b, 0)
}

WindowSearch_CompareTitle(a, b, *) {
    ta := WindowSearch_ItemTitle(a)
    tb := WindowSearch_ItemTitle(b)
    cmp := StrCompare(ta, tb, True)
    if (cmp < 0)
        return -1
    if (cmp > 0)
        return 1
    return 0
}

ArraySort(arr, compareFn) {
    arr := arr.Clone()
    n := arr.Length
    if (n < 2)
        return arr
    for i, _ in arr {
        for j, _ in arr {
            if (j <= i)
                continue
            if (compareFn(arr[i], arr[j], 0) > 0) {
                tmp := arr[i]
                arr[i] := arr[j]
                arr[j] := tmp
            }
        }
    }
    return arr
}

WindowSearch_ItemTitle(item) {
    if IsObject(item) && item.HasOwnProp("title")
        return item.title
    return String(item)
}

WindowSearch_Confirm() {
    global WindowSearch
    if (!WindowSearch.filtered.Length)
        return
    idx := WindowSearch.list.Value
    if (idx <= 0 || idx > WindowSearch.filtered.Length)
        idx := 1
    item := WindowSearch.filtered[idx]
    ctx := WindowSearch.ctx
    if !ctx.mon || !ctx.leaf
        return
    WindowSearch_Close()
    if WinExist("ahk_id " item.hwnd) {
        SelectLeaf(ctx.mon, ctx.leaf, "manual")
        MoveWindowIntoLeaf(item.hwnd, ctx)
        WinActivate "ahk_id " item.hwnd
    }
}
