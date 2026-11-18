; =========================
; Layout-Overlay (Ctrl+Alt+Win+#)
; =========================
; Zeigt das aktuelle Layout des Monitors (mit Area-Nummern) und alle
; Layout-Presets als Mini-Vorschau. Solange das Overlay sichtbar ist, wendet
; die blosse Preset-Taste (1..7, 0) oder ein Klick auf eine Kachel das Layout
; an; Esc schliesst. Das Overlay aktiviert sich nicht (WS_EX_NOACTIVATE),
; damit das aktive Fenster und damit der "aktuelle Monitor" erhalten bleiben.

; tiles: Preset-Kacheln in Anzeigereihenfolge { key, cells, cap, sub, col, row }; sel: Index der Auswahl
global LayoutOverlay := { gui:"", shown:false, mon:0, tiles:[], sel:0, cols:4 }

global LayoutOverlayTileWidth := 180      ; Breite einer Vorschau-Kachel (logische px)
global LayoutOverlayCellGap := 3          ; Abstand zwischen Areas in der Vorschau
global LayoutOverlayPresetColor := "2F6FBF"
global LayoutOverlayCurrentColor := "1E8C7A"
global LayoutOverlaySelectColor := "5AA9F0"     ; Areas der per Pfeiltasten gewaehlten Kachel
global LayoutOverlaySelectCaptionColor := "2A5C8A" ; Hintergrund der Beschriftung der Auswahl
global LayoutOverlayOpacity := 230

; Schaltet das Overlay an/aus.
LayoutOverlay_Toggle() {
    global LayoutOverlay
    if (LayoutOverlay.shown)
        LayoutOverlay_Hide()
    else
        LayoutOverlay_Show()
}

; Baut das Overlay fuer den Monitor des aktiven Fensters neu auf und zeigt es.
LayoutOverlay_Show() {
    global LayoutOverlay, LayoutPresets, LayoutOverlayTileWidth, LayoutOverlayOpacity
    try {
        HotkeyOverlay_Hide(true)
    }
    catch Error as e {
    }
    LayoutOverlay_Destroy()

    mon := GetCurrentMonitorIndex()
    if (!Monitors_IsValid(mon))
        mon := 1
    LayoutOverlay.mon := mon
    area := GetMonitorWork(mon)
    mw := Max(1, area.right - area.left)
    mh := Max(1, area.bottom - area.top)

    tileW := LayoutOverlayTileWidth
    tileH := Max(70, Min(130, Round(tileW * mh / mw)))
    margin := 20
    colGap := 24
    cols := 4

    g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000 +DPIScale")
    g.BackColor := "Black"
    g.MarginX := margin
    g.MarginY := margin

    ; Titel + Hinweis
    g.SetFont("s16 cWhite Bold", "Segoe UI")
    g.AddText(Format("x{} y{} w{} h30", margin, margin, cols * tileW + (cols - 1) * colGap), Format("Snap-Layouts - Monitor {}", mon))
    g.SetFont("s9 cSilver", "Segoe UI")
    g.AddText(Format("x{} y{} w{} h18", margin, margin + 32, cols * tileW + (cols - 1) * colGap),
        "Taste 1..7 / 0 oder Klick wendet das Layout an  -  Ctrl+Alt+Win+Taste jederzeit  -  Esc schliesst")

    ; Aktuelles Layout
    y := margin + 60
    g.SetFont("s10 cWhite Bold", "Segoe UI")
    g.AddText(Format("x{} y{} w{} h20", margin, y, tileW * 2), "Aktuelles Layout")
    y += 24
    curRects := []
    try {
        curRects := Layout_CurrentPreviewRects(mon)
    }
    catch Error as e {
        LogException(e, "LayoutOverlay_Show: Layout_CurrentPreviewRects failed")
    }
    labels := []
    for r in curRects
        labels.Push(String(r.no))
    LayoutOverlay_AddTile(g, margin, y, tileW, tileH, curRects, labels, LayoutOverlayCurrentColor, "")
    g.SetFont("s9 cSilver", "Consolas")
    infoX := margin + tileW + colGap
    infoW := cols * tileW + (cols - 1) * colGap - tileW - colGap
    g.AddText(Format("x{} y{} w{} h18", infoX, y, infoW), "Win+Ctrl+Nr      aktives Fenster in Area Nr verschieben")
    g.AddText(Format("x{} y{} w{} h18", infoX, y + 20, infoW), "Win+Nr           n-tes Fenster der aktiven Area (ab 2 Fenstern)")
    g.AddText(Format("x{} y{} w{} h18", infoX, y + 40, infoW), "Alt+Shift+O      Area-Nummern kurz auf dem Bildschirm zeigen")
    g.AddText(Format("x{} y{} w{} h18", infoX, y + 60, infoW), "Alt+Shift+Plus/Minus   aktive Area vertikal / horizontal teilen")
    y += tileH + 24

    ; Presets
    g.SetFont("s10 cWhite Bold", "Segoe UI")
    g.AddText(Format("x{} y{} w{} h20", margin, y, tileW * 3), "Presets (Ctrl+Alt+Win+Taste, aktueller Monitor)")
    y += 24
    idx := 0
    rowH := tileH + 44
    LayoutOverlay.tiles := []
    LayoutOverlay.sel := 0
    LayoutOverlay.cols := cols
    for p in LayoutPresets {
        col := Mod(idx, cols)
        row := idx // cols
        x := margin + col * (tileW + colGap)
        ty := y + row * rowH
        rects := LayoutPreset_PreviewRects(p)
        labels := []
        Loop rects.Length
            labels.Push(String(A_Index))
        cells := LayoutOverlay_AddTile(g, x, ty, tileW, tileH, rects, labels, LayoutOverlayPresetColor, p.key)
        g.SetFont("s10 cWhite Bold", "Segoe UI")
        cap := g.AddText(Format("x{} y{} w{} h18 Center +0x0100", x, ty + tileH + 4, tileW), "Ctrl+Alt+Win+" p.key)
        cap.OnEvent("Click", LayoutOverlay_OnTileClick.Bind(p.key))
        g.SetFont("s9 cSilver", "Segoe UI")
        sub := g.AddText(Format("x{} y{} w{} h18 Center +0x0100", x, ty + tileH + 22, tileW), p.name "  (" p.desc ")")
        sub.OnEvent("Click", LayoutOverlay_OnTileClick.Bind(p.key))
        LayoutOverlay.tiles.Push({ key:p.key, cells:cells, cap:cap, sub:sub, col:col, row:row })
        idx += 1
    }
    rows := (idx + cols - 1) // cols
    totalW := margin * 2 + cols * tileW + (cols - 1) * colGap
    totalH := y + rows * rowH + margin - 4

    LayoutOverlay.gui := g
    try {
        WinSetTransparent(LayoutOverlayOpacity, g)
    }
    catch Error as e {
        LogError("LayoutOverlay_Show: WinSetTransparent failed")
    }

    ; Mittig auf dem Monitor; Show erwartet bei +DPIScale logische Einheiten.
    scale := A_ScreenDPI / 96.0
    x := area.left + (mw - totalW * scale) / 2
    yPos := area.top + (mh - totalH * scale) / 3
    try {
        g.Show(Format("NA x{} y{} w{} h{}", Round(x / scale), Round(yPos / scale), totalW, totalH))
        try {
            HotkeyOverlay_ApplyRounded(g)
        }
        catch Error as e {
            LogError("LayoutOverlay_Show: ApplyRounded failed")
        }
        LayoutOverlay.shown := true
        ; Erste Kachel vorwaehlen, damit Enter sofort funktioniert
        LayoutOverlay_Select(1)
        LogInfo(Format("LayoutOverlay_Show: mon={}, areas={}", mon, curRects.Length))
    }
    catch Error as e {
        LogException(e, "LayoutOverlay_Show: Show failed")
        LayoutOverlay_Destroy()
    }
}

; Zeichnet eine Vorschau-Kachel: jede Area als farbiges Rechteck mit Label.
; key != "" macht die Kachel klickbar (wendet das Preset an).
; Rueckgabe: Array der Area-Controls (fuer die Auswahlmarkierung).
LayoutOverlay_AddTile(g, x, y, w, h, rects, labels, color, key) {
    global LayoutOverlayCellGap
    gap := LayoutOverlayCellGap
    cells := []
    if (rects.Length = 0) {
        g.SetFont("s9 cGray", "Segoe UI")
        g.AddText(Format("x{} y{} w{} h{} Center +0x200 Background333333", x, y, w, h), "kein Layout")
        return cells
    }
    g.SetFont("s11 cWhite Bold", "Segoe UI")
    idx := 0
    for r in rects {
        idx += 1
        cx := x + Round(r.L * w)
        cy := y + Round(r.T * h)
        cw := Round((r.R - r.L) * w) - gap
        ch := Round((r.B - r.T) * h) - gap
        if (r.R >= 0.999)
            cw += gap
        if (r.B >= 0.999)
            ch += gap
        cw := Max(4, cw)
        ch := Max(4, ch)
        label := (labels.Length >= idx) ? labels[idx] : ""
        opts := Format("x{} y{} w{} h{} Center +0x200 +0x0100 Background{}", cx, cy, cw, ch, color)
        ctrl := g.AddText(opts, label)
        if (key != "")
            ctrl.OnEvent("Click", LayoutOverlay_OnTileClick.Bind(key))
        cells.Push(ctrl)
    }
    return cells
}

; Markiert die Kachel idx (1..n) als ausgewaehlt und hebt die alte Markierung auf.
LayoutOverlay_Select(idx) {
    global LayoutOverlay
    tiles := LayoutOverlay.tiles
    if (!tiles.Length)
        return
    if (idx < 1)
        idx := tiles.Length
    else if (idx > tiles.Length)
        idx := 1
    old := LayoutOverlay.sel
    if (old >= 1 && old <= tiles.Length && old != idx)
        LayoutOverlay_Paint(tiles[old], false)
    LayoutOverlay_Paint(tiles[idx], true)
    LayoutOverlay.sel := idx
}

; Zeichnet eine Kachel als ausgewaehlt (hellere Areas, Beschriftung mit Balken) oder normal.
LayoutOverlay_Paint(tile, selected) {
    global LayoutOverlayPresetColor, LayoutOverlaySelectColor, LayoutOverlaySelectCaptionColor
    try {
        cellColor := selected ? LayoutOverlaySelectColor : LayoutOverlayPresetColor
        for c in tile.cells {
            c.Opt("+Background" cellColor)
            c.Redraw()
        }
        if (selected) {
            tile.cap.Opt("+Background" LayoutOverlaySelectCaptionColor)
            tile.sub.Opt("+Background" LayoutOverlaySelectCaptionColor)
            tile.sub.SetFont("s9 cWhite", "Segoe UI")
        } else {
            ; Hintergrund explizit auf die GUI-Farbe setzen (BackgroundDefault waere Dialog-Grau)
            tile.cap.Opt("+BackgroundBlack")
            tile.sub.Opt("+BackgroundBlack")
            tile.sub.SetFont("s9 cSilver", "Segoe UI")
        }
        tile.cap.Redraw()
        tile.sub.Redraw()
    }
    catch Error as e {
        LogException(e, "LayoutOverlay_Paint failed")
    }
}

; Pfeiltasten: Auswahl im Kachelraster bewegen (dx = -1/1 Spalte, dy = -1/1 Zeile, mit Umlauf).
LayoutOverlay_MoveSelection(dx, dy) {
    global LayoutOverlay
    tiles := LayoutOverlay.tiles
    if (!tiles.Length)
        return
    cols := LayoutOverlay.cols
    sel := LayoutOverlay.sel ? LayoutOverlay.sel : 1
    rows := (tiles.Length + cols - 1) // cols
    cur := tiles[sel]
    col := cur.col
    row := cur.row
    if (dx != 0) {
        ; Links/Rechts: innerhalb der Zeile, am Rand in die naechste/vorherige Zeile
        idx := sel + dx
        LayoutOverlay_Select(idx)
        return
    }
    if (dy != 0) {
        row := Mod(row + dy + rows, rows)
        idx := row * cols + col + 1
        if (idx > tiles.Length)
            idx := tiles.Length
        LayoutOverlay_Select(idx)
    }
}

; Enter: ausgewaehltes Preset anwenden.
LayoutOverlay_Confirm() {
    global LayoutOverlay
    tiles := LayoutOverlay.tiles
    sel := LayoutOverlay.sel
    if (sel < 1 || sel > tiles.Length)
        return
    LayoutOverlay_Pick(tiles[sel].key)
}

; Klick auf eine Preset-Kachel: Preset auf dem Overlay-Monitor anwenden.
LayoutOverlay_OnTileClick(key, *) {
    LayoutOverlay_Pick(key)
}

; Preset-Taste / Klick waehrend das Overlay sichtbar ist.
LayoutOverlay_Pick(key) {
    global LayoutOverlay
    mon := LayoutOverlay.mon
    LayoutOverlay_Hide()
    try {
        LayoutPreset_Apply(key, mon)
    }
    catch Error as e {
        LogException(e, "LayoutOverlay_Pick: LayoutPreset_Apply failed")
    }
}

; Blendet das Overlay aus und gibt die GUI frei.
LayoutOverlay_Hide() {
    global LayoutOverlay
    if (!LayoutOverlay.shown && !LayoutOverlay.gui)
        return
    LayoutOverlay_Destroy()
    LogInfo("LayoutOverlay_Hide")
}

LayoutOverlay_Destroy() {
    global LayoutOverlay
    if (LayoutOverlay.gui) {
        try {
            LayoutOverlay.gui.Destroy()
        }
        catch Error as e {
            LogError("LayoutOverlay_Destroy: Destroy failed")
        }
    }
    LayoutOverlay.gui := ""
    LayoutOverlay.shown := false
}
