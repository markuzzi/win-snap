; =========================
; Hotkey Overlay (ähnlich iPadOS Cmd-Hold)
; =========================

HotkeyOverlay := { gui:"", shown:false, toggleMode:false }

; Initialisiert die Overlay-GUI zur Anzeige der Shortcuts.
HotkeyOverlay_Init() {
    global HotkeyOverlay
    if (HotkeyOverlay.gui)
        return
    g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +DPIScale") ; click-through overlay
    g.BackColor := "Black"
    ; Transparenz
    try {
        WinSetTransparent(200, g) ; 0..255
    }
    catch {
        LogError("HotkeyOverlay_Init: WinSetTransparent failed")
    }
    ; Inhalte
    fontTitle := "s16 cWhite Bold"
    fontItem := "s12 cWhite"
    g.SetFont(fontTitle, "Segoe UI")
    g.AddText("xm ym", "WinSnap Shortcuts")
    ; Monospace for aligned columns
    g.SetFont(fontItem, "Consolas")
    ; Dynamischer Inhalt (Text statt Edit; BackgroundTrans wird hier unterstützt)
    txt := g.AddText("xm+0 y+6 w720 h420 BackgroundTrans")
    txt.Value := HotkeyOverlay_BuildText()
    HotkeyOverlay.gui := g
    HotkeyOverlay.text := txt
}

; Baut den anzuzeigenden Shortcut-Text fuer das Overlay zusammen.
HotkeyOverlay_BuildText() {
    ; Liste der Shortcuts und Bedeutung (kurz)
    lines := []
    lines.Push("Win+Left/Right/Up/Down         – Fenster in Grid bewegen")
    lines.Push("Win+Ctrl+Up/Down               – Vertikal bewegen (Legacy)")
    lines.Push("Win+Shift+Up                   – Vollbild / UnSnap")
    lines.Push("Win+Shift+Down                 – Minimieren")
    lines.Push("Alt+Left/Right/Up/Down         – Snap-Area wechseln")
    lines.Push("Alt+Space                      – Fenster-Suche öffnen")
    lines.Push("Alt+Backspace/Delete           – Aktuelle Snap-Area löschen")
    lines.Push("Alt+Shift+O                    – Alle Snap-Areas anzeigen")
    lines.Push("Alt+Shift+A                    – Fenster in aktiver Area einsammeln")
    lines.Push("Ctrl+Shift+Up/Down             – Fenster innerhalb Area wechseln")
    lines.Push("Alt+Shift+Plus / Numpad+       – Vertikal teilen")
    lines.Push("Alt+Shift+Minus / Numpad-      – Horizontal teilen")
    lines.Push("Alt+Shift+Pfeile               – Grenze der Split-Gruppe verschieben")
    lines.Push("Ctrl+Alt+H                     – Highlight an/aus")
    lines.Push("Ctrl+Alt+Shift+H               – Highlight ausblenden")
    lines.Push("Ctrl+Alt+P                     – Script pausieren/fortsetzen")
    lines.Push("Ctrl+Alt+Q                     – Script beenden")
    lines.Push("Ctrl+Alt+R                     – Script neu laden")
    lines.Push("Ctrl+Alt+W                     – Fenster-Pills anzeigen/verbergen")
    lines.Push("Win+Ctrl+Alt+<num>             – Switch Default Layouts")
    lines.Push("Win+Ctrl+Alt+0                 – Switch to Default 50/50 Layout")
    lines.Push("")
    lines.Push("Fenster-Suche:")
    lines.Push("  Up/Down/Enter/Esc            – Navigieren / Auswählen / Schließen")
    return StrJoin(lines, "`r`n")
}

; Aktualisiert den Text-Inhalt des Overlays.
HotkeyOverlay_UpdateText() {
    global HotkeyOverlay
    if (HotkeyOverlay.gui) {
        try {
            HotkeyOverlay.text.Value := HotkeyOverlay_BuildText()
        }
        catch {
            LogError("HotkeyOverlay_UpdateText: updating text failed")
        }
    }
}

; Zeigt das Overlay zentriert auf dem aktiven Monitor an.
HotkeyOverlay_Show() {
    global HotkeyOverlay
    HotkeyOverlay_Init()
    ; Overlay auf aktivem Monitor mittig anzeigen
    mon := 1
    win := GetActiveWindow()
    if (win) {
        monInfo := GetMonitorIndexAndArea(win.hwnd)
        mon := monInfo.index
    }
    area := GetMonitorWork(mon)
    try {
        HotkeyOverlay_UpdateText()
        HotkeyOverlay.gui.GetPos(, , &w, &h)
    } catch {
        w := 760, h := 400
    }
    x := area.left + ((area.right - area.left) - w) / 2
    y := area.top  + ((area.bottom - area.top) - h) / 3
    try {
        HotkeyOverlay.gui.Move(Round(x), Round(y))
        HotkeyOverlay.gui.Show()
        ; Apply rounded corners (best effort)
        try {
            HotkeyOverlay_ApplyRounded(HotkeyOverlay.gui)
        }
        catch {
            LogError("HotkeyOverlay_Show: ApplyRounded failed")
        }
        HotkeyOverlay.shown := true
        LogInfo("HotkeyOverlay_Show")
    }
    catch {
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
    catch {
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

; Round overlay corners via DWM (Win11) or window region (fallback)
; Rundet die Fensterecken per DWM-Attribut oder Region (Fallback).
HotkeyOverlay_ApplyRounded(gui) {
    if (!gui)
        return
    hwnd := gui.Hwnd
    ; Prefer DWM: DWMWA_WINDOW_CORNER_PREFERENCE = 33, DWMWCP_ROUND = 2
    pref := 2
    try {
        DllCall("dwmapi\\DwmSetWindowAttribute", "ptr", hwnd, "int", 33, "ptr", &pref, "int", 4, "int")
        return
    }
    catch {
        LogError("HotkeyOverlay_ApplyRounded failed with DwmSetWindowAttribute")
    }
    ; Fallback: apply rounded region
    try {
        gui.GetPos(, , &w, &h)
        radius := 20
        rgn := DllCall("gdi32\\CreateRoundRectRgn", "int", 0, "int", 0, "int", w, "int", h, "int", radius, "int", radius, "ptr")
        if (rgn)
            DllCall("user32\\SetWindowRgn", "ptr", hwnd, "ptr", rgn, "int", true)
    }
    catch {
        LogError("HotkeyOverlay_ApplyRounded failed with CreateRoundRectRgn and SetWindowRgn")
    }
}
