; =========================
; Hotkey Overlay (Ctrl+Alt+#)
; =========================
; Zweispaltige Uebersicht aller Shortcuts. Eintraege mit ">" sind klickbar und
; fuehren die Funktion direkt aus (das Overlay schliesst sich dabei). Das
; Fenster aktiviert sich nicht (WS_EX_NOACTIVATE), damit Funktionen wie
; "Fenster einsammeln" weiter das zuvor aktive Fenster sehen.

; items: klickbare Zeilen in Reihenfolge (linke Spalte, dann rechte); sel: Index der Auswahl
global HotkeyOverlay := { gui:"", shown:false, toggleMode:false, items:[], sel:0 }

global HotkeyOverlayColumnWidth := 500   ; logische px pro Spalte
global HotkeyOverlayRowHeight := 19
global HotkeyOverlayKeyWidth := 26       ; Zeichen fuer die Tastenspalte (Monospace)
global HotkeyOverlayActionColor := "9CDCFE"
global HotkeyOverlaySelectColor := "2A5C8A" ; Hintergrund der per Pfeiltasten gewaehlten Zeile
global HotkeyOverlayOpacity := 235

; Liefert die Spalten (Array aus Sektionen) mit allen Eintraegen.
; Eintrag: { keys, desc, action } - action = Func/BoundFunc oder "".
; Sektion: { title, items }
HotkeyOverlay_Columns() {
    global LayoutPresets
    left := []
    right := []

    sec := { title:"Fenster bewegen && Groesse", items:[] }
    sec.items.Push({ keys:"Win+Pfeile",            desc:"Fenster durchs Grid bewegen (Auto-Split)", action:"" })
    sec.items.Push({ keys:"Win+Ctrl+Up/Down",      desc:"vertikal bewegen (Legacy)", action:"" })
    sec.items.Push({ keys:"Win+Ctrl+1..9, 0",      desc:"Fenster in Snap-Area Nr. (Alt+Shift+O)", action:"" })
    sec.items.Push({ keys:"Win+Shift+Up",          desc:"maximieren (Pills nach hinten)", action:MaximizeActiveWindow })
    sec.items.Push({ keys:"Win+Shift+Down",        desc:"Restore, zurueck in alte Snap-Area", action:RestoreActiveWindow })
    sec.items.Push({ keys:"Win+Shift+Left/Right",  desc:"ueber Nachbar-Area links/rechts erweitern", action:"" })
    sec.items.Push({ keys:"Win+Ctrl+Shift+Up/Down", desc:"ueber Nachbar-Area oben/unten erweitern", action:"" })
    sec.items.Push({ keys:"Ctrl+Shift+Up/Down",    desc:"Fenster innerhalb der Area wechseln", action:"" })
    sec.items.Push({ keys:"Win+1..9",              desc:"n-tes Fenster der Area (ab 2 Fenstern)", action:"" })
    left.Push(sec)

    sec := { title:"Snap-Areas", items:[] }
    sec.items.Push({ keys:"Alt+Pfeile",            desc:"Snap-Area wechseln (oberstes Fenster)", action:"" })
    sec.items.Push({ keys:"Win+Space",             desc:"Fenster-Suche fuer aktuelle Area", action:WindowSearch_Open })
    sec.items.Push({ keys:"Alt+Shift+Plus",        desc:"Area vertikal teilen", action:SplitCurrentLeaf.Bind("v") })
    sec.items.Push({ keys:"Alt+Shift+Minus",       desc:"Area horizontal teilen", action:SplitCurrentLeaf.Bind("h") })
    sec.items.Push({ keys:"Alt+Shift+Pfeile",      desc:"Grenze der Split-Gruppe verschieben", action:"" })
    sec.items.Push({ keys:"Alt+Backspace/Delete",  desc:"aktuelle Snap-Area loeschen", action:DeleteCurrentSnapArea })
    sec.items.Push({ keys:"Alt+Shift+O",           desc:"alle Snap-Areas mit Nummern zeigen", action:ShowAllSnapAreasHotkey })
    sec.items.Push({ keys:"Alt+Shift+A",           desc:"Fenster in aktiver Area einsammeln", action:CollectWindowsInActiveLeaf })
    sec.items.Push({ keys:"Ctrl+Alt+Win+A",        desc:"Fenster in allen Areas einsammeln", action:CollectWindowsInAllLeaves })
    left.Push(sec)

    sec := { title:"Maus mit Alt", items:[] }
    sec.items.Push({ keys:"Alt+Linksklick ziehen",  desc:"Fenster unter der Maus verschieben", action:"" })
    sec.items.Push({ keys:"Alt+Rechtsklick ziehen", desc:"Fenstergroesse aendern (Ecke je Start)", action:"" })
    sec.items.Push({ keys:"Alt+Rad runter/XButton2", desc:"Fenster unter der Maus minimieren", action:"" })
    sec.items.Push({ keys:"Ctrl+Alt+Win+Plus/Minus", desc:"Transparenz aktives Fenster +/-15", action:"" })
    sec.items.Push({ keys:"Alt+Win+Mausrad",        desc:"Transparenz aktives Fenster +/-15", action:"" })
    left.Push(sec)

    sec := { title:"Modi && System", items:[] }
    sec.items.Push({ keys:"Ctrl+Alt+#",            desc:"diese Uebersicht (Esc schliesst)", action:"" })
    sec.items.Push({ keys:"Ctrl+Alt+Win+#",        desc:"Layout-Uebersicht mit Vorschau", action:LayoutOverlay_Toggle })
    sec.items.Push({ keys:"Ctrl+Alt+H",            desc:"Highlight der aktiven Area an/aus", action:ToggleHighlight })
    sec.items.Push({ keys:"Ctrl+Alt+W",            desc:"Fenster-Pills an/aus", action:WindowPills_Toggle })
    sec.items.Push({ keys:"Ctrl+Alt+F",            desc:"Focus Mode (inaktive abdunkeln)", action:FocusMode_Toggle })
    sec.items.Push({ keys:"Ctrl+Alt+Z",            desc:"Zen Mode (inaktive ausblenden)", action:ZenMode_Toggle })
    sec.items.Push({ keys:"Ctrl+Alt+B",            desc:"AutoSnap-Blacklist fuer aktives Fenster", action:ToggleBlacklistForActiveWindow })
    sec.items.Push({ keys:"Ctrl+Alt+P",            desc:"Script pausieren/fortsetzen", action:TogglePause })
    sec.items.Push({ keys:"Ctrl+Alt+R",            desc:"Script neu laden", action:HotkeyOverlay_Reload })
    sec.items.Push({ keys:"Ctrl+Alt+Win+Q",        desc:"Script beenden", action:"" })
    right.Push(sec)

    sec := { title:"Layout-Presets (aktueller Monitor)", items:[] }
    for p in LayoutPresets {
        sec.items.Push({ keys:"Ctrl+Alt+Win+" p.key, desc:p.name " - " p.desc, action:LayoutPreset_Apply.Bind(p.key) })
    }
    right.Push(sec)

    sec := { title:"Fenster-Suche (wenn offen)", items:[] }
    sec.items.Push({ keys:"Up/Down",               desc:"Auswahl bewegen", action:"" })
    sec.items.Push({ keys:"Enter / Esc",           desc:"Fenster in Area holen / schliessen", action:"" })
    right.Push(sec)

    return { left:left, right:right }
}

; Reload als eigene Funktion, damit sie im Overlay gebunden werden kann.
HotkeyOverlay_Reload(*) {
    Reload()
}

; Baut die Overlay-GUI (zwei Spalten, klickbare Zeilen).
HotkeyOverlay_Init() {
    global HotkeyOverlay, HotkeyOverlayColumnWidth, HotkeyOverlayRowHeight, HotkeyOverlayOpacity
    if (HotkeyOverlay.gui)
        return
    g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000 +DPIScale")
    g.BackColor := "Black"
    margin := 20
    colW := HotkeyOverlayColumnWidth
    colGap := 20

    g.SetFont("s16 cWhite Bold", "Segoe UI")
    g.AddText(Format("x{} y{} w{} h30", margin, margin, colW * 2 + colGap), "WinSnap " WinSnapVersion " - Shortcuts")
    g.SetFont("s9 cSilver", "Segoe UI")
    g.AddText(Format("x{} y{} w{} h18", margin, margin + 32, colW * 2 + colGap),
        "> Zeilen: Pfeiltasten + Enter oder Klick fuehren die Funktion direkt aus  -  Esc schliesst")

    cols := HotkeyOverlay_Columns()
    HotkeyOverlay.items := []
    HotkeyOverlay.sel := 0
    yStart := margin + 60
    yLeft := HotkeyOverlay_AddColumn(g, margin, yStart, colW, cols.left, 1)
    yRight := HotkeyOverlay_AddColumn(g, margin + colW + colGap, yStart, colW, cols.right, 2)

    totalW := margin * 2 + colW * 2 + colGap
    totalH := Max(yLeft, yRight) + margin
    HotkeyOverlay.gui := g
    HotkeyOverlay.w := totalW
    HotkeyOverlay.h := totalH
    try {
        WinSetTransparent(HotkeyOverlayOpacity, g)
    }
    catch Error as e {
        LogError("HotkeyOverlay_Init: WinSetTransparent failed")
    }
}

; Fuegt eine Spalte mit Sektionen ein; liefert die y-Position nach dem letzten Eintrag.
HotkeyOverlay_AddColumn(g, x, y, w, sections, colIdx) {
    global HotkeyOverlay, HotkeyOverlayRowHeight, HotkeyOverlayKeyWidth, HotkeyOverlayActionColor
    rowH := HotkeyOverlayRowHeight
    first := true
    for sec in sections {
        if (!first)
            y += 8
        first := false
        g.SetFont("s10 cWhite Bold", "Segoe UI")
        g.AddText(Format("x{} y{} w{} h20", x, y, w), sec.title)
        y += 22
        for item in sec.items {
            clickable := IsObject(item.action)
            prefix := clickable ? "> " : "  "
            text := prefix Format("{:-" HotkeyOverlayKeyWidth "}", item.keys) item.desc
            if (clickable) {
                g.SetFont("s10 c" HotkeyOverlayActionColor, "Consolas")
                ctrl := g.AddText(Format("x{} y{} w{} h{} +0x0100 BackgroundTrans", x, y, w, rowH), text)
                HotkeyOverlay.items.Push({ ctrl:ctrl, action:item.action, col:colIdx, y:y })
                ctrl.OnEvent("Click", HotkeyOverlay_OnClick.Bind(HotkeyOverlay.items.Length))
            } else {
                g.SetFont("s10 cWhite", "Consolas")
                g.AddText(Format("x{} y{} w{} h{} BackgroundTrans", x, y, w, rowH), text)
            }
            y += rowH
        }
    }
    return y
}

; Klick auf eine Zeile: Eintrag auswaehlen und ausfuehren.
HotkeyOverlay_OnClick(idx, *) {
    HotkeyOverlay_Select(idx)
    HotkeyOverlay_Confirm()
}

; Markiert den Eintrag idx (1..n) als ausgewaehlt und hebt die alte Markierung auf.
HotkeyOverlay_Select(idx) {
    global HotkeyOverlay, HotkeyOverlaySelectColor, HotkeyOverlayActionColor
    items := HotkeyOverlay.items
    if (!items.Length)
        return
    if (idx < 1)
        idx := items.Length
    else if (idx > items.Length)
        idx := 1
    old := HotkeyOverlay.sel
    if (old >= 1 && old <= items.Length && old != idx)
        HotkeyOverlay_Paint(items[old].ctrl, false)
    HotkeyOverlay_Paint(items[idx].ctrl, true)
    HotkeyOverlay.sel := idx
}

; Zeichnet eine Zeile als ausgewaehlt (Hintergrundbalken, weisser Text) oder normal.
HotkeyOverlay_Paint(ctrl, selected) {
    global HotkeyOverlaySelectColor, HotkeyOverlayActionColor
    try {
        if (selected) {
            ctrl.Opt("+Background" HotkeyOverlaySelectColor)
            ctrl.SetFont("s10 cWhite Bold", "Consolas")
        } else {
            ctrl.Opt("+BackgroundTrans")
            ctrl.SetFont("s10 c" HotkeyOverlayActionColor, "Consolas")
        }
        ctrl.Redraw()
    }
    catch Error as e {
        LogException(e, "HotkeyOverlay_Paint failed")
    }
}

; Pfeil hoch/runter: naechsten/vorherigen klickbaren Eintrag waehlen (mit Umlauf).
HotkeyOverlay_MoveSelection(delta) {
    global HotkeyOverlay
    if (!HotkeyOverlay.items.Length)
        return
    sel := HotkeyOverlay.sel ? HotkeyOverlay.sel : (delta > 0 ? 0 : 1)
    HotkeyOverlay_Select(sel + delta)
}

; Pfeil links/rechts: in die andere Spalte springen, auf die Zeile mit der naechsten y-Position.
HotkeyOverlay_SwitchColumn() {
    global HotkeyOverlay
    items := HotkeyOverlay.items
    if (!items.Length)
        return
    sel := HotkeyOverlay.sel ? HotkeyOverlay.sel : 1
    cur := items[sel]
    targetCol := (cur.col = 1) ? 2 : 1
    best := 0
    bestDist := 999999
    for i, it in items {
        if (it.col != targetCol)
            continue
        d := Abs(it.y - cur.y)
        if (d < bestDist) {
            bestDist := d
            best := i
        }
    }
    if (best)
        HotkeyOverlay_Select(best)
}

; Enter: ausgewaehlten Eintrag ausfuehren (Overlay schliesst sich vorher).
HotkeyOverlay_Confirm() {
    global HotkeyOverlay
    items := HotkeyOverlay.items
    sel := HotkeyOverlay.sel
    if (sel < 1 || sel > items.Length)
        return
    action := items[sel].action
    HotkeyOverlay_Hide(true)
    HotkeyOverlay.toggleMode := false
    try {
        action.Call()
    }
    catch Error as e {
        LogException(e, "HotkeyOverlay_Confirm: action failed")
    }
}

; Zeigt das Overlay zentriert auf dem Monitor des aktiven Fensters an.
HotkeyOverlay_Show() {
    global HotkeyOverlay
    try {
        LayoutOverlay_Hide()
    }
    catch Error as e {
    }
    HotkeyOverlay_Init()
    mon := GetCurrentMonitorIndex()
    area := GetMonitorWork(mon)
    w := HotkeyOverlay.HasOwnProp("w") ? HotkeyOverlay.w : 1060
    h := HotkeyOverlay.HasOwnProp("h") ? HotkeyOverlay.h : 600
    ; Show erwartet bei +DPIScale logische Einheiten.
    scale := A_ScreenDPI / 96.0
    x := area.left + ((area.right - area.left) - w * scale) / 2
    y := area.top  + ((area.bottom - area.top) - h * scale) / 3
    try {
        HotkeyOverlay.gui.Show(Format("NA x{} y{} w{} h{}", Round(x / scale), Round(y / scale), w, h))
        try {
            HotkeyOverlay_ApplyRounded(HotkeyOverlay.gui)
        }
        catch Error as e {
            LogError("HotkeyOverlay_Show: ApplyRounded failed")
        }
        HotkeyOverlay.shown := true
        ; Auswahl auf den ersten Eintrag setzen, damit Enter sofort funktioniert
        if (!HotkeyOverlay.sel)
            HotkeyOverlay_Select(1)
        LogInfo("HotkeyOverlay_Show")
    }
    catch Error as e {
        LogError("HotkeyOverlay_Show: move/show failed")
    }
}

; Blendet das Overlay aus (oder ignoriert bei Toggle-Modus, falls nicht erzwungen).
HotkeyOverlay_Hide(force := false) {
    global HotkeyOverlay
    if (!HotkeyOverlay.gui)
        return
    if (!force && HotkeyOverlay.toggleMode)
        return
    try {
        HotkeyOverlay.gui.Hide()
    }
    catch Error as e {
        LogError("HotkeyOverlay_Hide: hide failed")
    }
    HotkeyOverlay.shown := false
    LogInfo("HotkeyOverlay_Hide")
}

; Schaltet die Anzeige des Overlays an/aus.
HotkeyOverlay_Toggle() {
    global HotkeyOverlay
    if (HotkeyOverlay.shown) {
        HotkeyOverlay_Hide(true)
        HotkeyOverlay.toggleMode := false
    } else {
        HotkeyOverlay_Show()
        HotkeyOverlay.toggleMode := true
    }
}

; Rundet die Fensterecken per DWM-Attribut (Win11) oder Region (Fallback).
HotkeyOverlay_ApplyRounded(gui) {
    if (!gui)
        return
    hwnd := gui.Hwnd
    ; Prefer DWM: DWMWA_WINDOW_CORNER_PREFERENCE = 33, DWMWCP_ROUND = 2
    pref := Buffer(4, 0)
    NumPut("Int", 2, pref)
    try {
        DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "int", 33, "ptr", pref, "int", 4, "int")
        return
    }
    catch Error as e {
        LogError("HotkeyOverlay_ApplyRounded failed with DwmSetWindowAttribute")
    }
    ; Fallback: apply rounded region
    try {
        gui.GetPos(, , &w, &h)
        radius := 20
        rgn := DllCall("CreateRoundRectRgn", "int", 0, "int", 0, "int", w, "int", h, "int", radius, "int", radius, "ptr")
        if (rgn)
            DllCall("SetWindowRgn", "ptr", hwnd, "ptr", rgn, "int", true)
    }
    catch Error as e {
        LogError("HotkeyOverlay_ApplyRounded failed with CreateRoundRectRgn and SetWindowRgn")
    }
}
