; =========================
; Focus Mode (inaktive Fenster abdunkeln)
; =========================
; Pro Monitor liegt ein dunkles, klick-durchlaessiges Topmost-Overlay ueber dem
; Arbeitsbereich. Aus dessen Fensterregion werden Loecher fuer das aktive Fenster,
; dessen Popups (Menues, Tooltips, Dropdowns) und die eigenen WinSnap-GUIs
; (Pills, Highlight, Suche) ausgeschnitten. Alles andere liegt unter dem Overlay
; und erscheint abgedunkelt. Fremde Fenster werden dabei nie angefasst.
; Zen Mode ist derselbe Mechanismus mit voller Deckkraft: inaktive Fenster sind
; komplett ausgeblendet, nur das aktive Fenster, seine Popups und die WinSnap-GUIs
; (Pills) bleiben sichtbar.

global Focus := {
    enabled: false,
    mode: "focus",      ; "focus" (abdunkeln) | "zen" (ausblenden)
    guis: Map(),        ; mon -> { gui, L, T, R, B, key, shown }
    timerOn: false,
    suspended: false,   ; waehrend Pause / Monitorwechsel
    lastKey: "",
    lastGoodHoles: [],  ; letzte gueltige Loecher (fuer Taskleiste/Desktop als Vordergrund)
    ownPid: 0
}

; Schaltet den Focus Mode um (Hotkey / Tray). mode = "focus" | "zen".
; Laeuft bereits der andere Modus, wird nur umgeschaltet statt abgeschaltet.
FocusMode_Toggle(mode := "focus") {
    global Focus
    if (Focus.enabled && Focus.mode = mode)
        FocusMode_Disable()
    else
        FocusMode_Enable(mode)
    label := (mode = "zen") ? "Zen Mode" : "Focus Mode"
    ShowTrayTip(Focus.enabled ? label " an" : label " aus", 1200)
    return Focus.enabled
}

; Zen Mode: wie Focus Mode, aber inaktive Fenster komplett ausgeblendet.
ZenMode_Toggle() {
    return FocusMode_Toggle("zen")
}

; Startet den Focus/Zen Mode aus der App-Startup-Sequenz, falls per Config aktiviert.
FocusMode_Start() {
    global FocusModeEnabled, ZenModeEnabled
    try {
        if (IsSet(ZenModeEnabled) && ZenModeEnabled)
            FocusMode_Enable("zen")
        else if (IsSet(FocusModeEnabled) && FocusModeEnabled)
            FocusMode_Enable()
    }
    catch Error as e {
        LogException(e, "FocusMode_Start failed")
    }
}

FocusMode_Enable(mode := "focus") {
    global Focus
    if (mode != "zen")
        mode := "focus"
    if (Focus.enabled) {
        if (Focus.mode != mode) {
            Focus.mode := mode
            Focus_ApplyAppearance()
            LogInfo("FocusMode: switched to " mode)
        }
        return
    }
    Focus.enabled := true
    Focus.mode := mode
    Focus.suspended := false
    Focus.lastKey := ""
    Focus.ownPid := DllCall("GetCurrentProcessId", "uint")
    try {
        Focus_EnsureGuis()
    }
    catch Error as e {
        LogException(e, "FocusMode_Enable: Focus_EnsureGuis failed")
    }
    Focus_SetTimer(true)
    Focus_Tick()
    LogInfo("FocusMode: enabled (" mode ")")
}

FocusMode_Disable() {
    global Focus
    if (!Focus.enabled)
        return
    Focus.enabled := false
    Focus_SetTimer(false)
    Focus_DestroyGuis()
    LogInfo("FocusMode: disabled")
}

FocusMode_IsEnabled() {
    global Focus
    return !!Focus.enabled
}

; Aktueller Modus ("focus" | "zen") oder "" wenn aus.
FocusMode_Current() {
    global Focus
    return Focus.enabled ? Focus.mode : ""
}

; Deckkraft und Farbe fuer den aktuellen Modus.
Focus_Appearance() {
    global Focus, FocusModeOpacity, FocusModeColor, ZenModeOpacity, ZenModeColor
    if (Focus.mode = "zen") {
        opacity := (IsSet(ZenModeOpacity) && ZenModeOpacity > 0) ? Min(255, ZenModeOpacity) : 255
        color := (IsSet(ZenModeColor) && ZenModeColor != "") ? ZenModeColor : "Black"
    } else {
        opacity := (IsSet(FocusModeOpacity) && FocusModeOpacity > 0) ? Min(255, FocusModeOpacity) : 120
        color := (IsSet(FocusModeColor) && FocusModeColor != "") ? FocusModeColor : "Black"
    }
    return { opacity:opacity, color:color }
}

; Wendet Deckkraft/Farbe des aktuellen Modus auf alle bestehenden Overlays an.
Focus_ApplyAppearance() {
    global Focus
    ap := Focus_Appearance()
    for mon, st in Focus.guis {
        try {
            st.gui.BackColor := ap.color
            WinSetTransparent(ap.opacity, st.gui)
        }
        catch Error as e {
            LogException(e, "Focus_ApplyAppearance failed")
        }
    }
}

; Pause/Resume aus TogglePause: Overlays verstecken, Zustand "enabled" behalten.
FocusMode_OnPause(paused) {
    global Focus
    if (!Focus.enabled)
        return
    Focus.suspended := !!paused
    if (paused) {
        Focus_SetTimer(false)
        Focus_HideAll()
    } else {
        Focus.lastKey := ""
        Focus_SetTimer(true)
        Focus_Tick()
    }
}

; Nach Monitor-Hotplug: Overlays passend zur neuen Konfiguration neu aufbauen.
FocusMode_Rebuild() {
    global Focus
    if (!Focus.enabled)
        return
    Focus_DestroyGuis()
    Focus.lastKey := ""
    Focus.lastGoodHoles := []
    try {
        Focus_EnsureGuis()
    }
    catch Error as e {
        LogException(e, "FocusMode_Rebuild: Focus_EnsureGuis failed")
    }
    Focus_Tick()
}

Focus_SetTimer(on) {
    global Focus, FocusModeInterval
    interval := (IsSet(FocusModeInterval) && FocusModeInterval > 0) ? FocusModeInterval : 60
    try {
        SetTimer(Focus_Tick, on ? interval : 0)
        Focus.timerOn := !!on
    }
    catch Error as e {
        LogException(e, "Focus_SetTimer failed")
    }
}

; Legt pro Monitor ein Overlay ueber den Arbeitsbereich an (Taskleiste bleibt frei).
Focus_EnsureGuis() {
    global Focus
    ap := Focus_Appearance()
    opacity := ap.opacity
    color := ap.color
    count := MonitorGetCount()
    Loop count {
        mon := A_Index
        if (Focus.guis.Has(mon))
            continue
        wa := GetMonitorWork(mon)
        w := Max(1, wa.right - wa.left)
        h := Max(1, wa.bottom - wa.top)
        ; WS_EX_LAYERED | WS_EX_TRANSPARENT -> klick-durchlaessig, nie aktivierbar
        g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80020 -DPIScale")
        g.BackColor := color
        ; Zuerst versteckt anlegen, Region/Position setzt der Tick
        g.Show(Format("NA Hide x{} y{} w{} h{}", wa.left, wa.top, w, h))
        try {
            WinSetTransparent(opacity, g)
        }
        catch Error as e {
            LogException(e, "Focus_EnsureGuis: WinSetTransparent failed")
        }
        Focus.guis[mon] := { gui:g, L:wa.left, T:wa.top, R:wa.right, B:wa.bottom, key:"", shown:false }
        LogDebug(Format("Focus_EnsureGuis: overlay for mon={} ({},{})-({},{})", mon, wa.left, wa.top, wa.right, wa.bottom))
    }
}

Focus_DestroyGuis() {
    global Focus
    for mon, st in Focus.guis {
        try {
            st.gui.Destroy()
        }
        catch Error as e {
            LogException(e, "Focus_DestroyGuis: Destroy failed")
        }
    }
    Focus.guis := Map()
}

Focus_HideAll() {
    global Focus
    for mon, st in Focus.guis {
        if (!st.shown)
            continue
        try {
            st.gui.Hide()
        }
        catch Error as e {
            LogException(e, "Focus_HideAll: Hide failed")
        }
        st.shown := false
        st.key := ""
    }
}

; Liefert true fuer Shell-Fenster (Taskleiste, Desktop, Startmenue), bei denen die
; letzten Loecher stehen bleiben sollen statt alles abzudunkeln.
Focus_IsShellWindow(hwnd) {
    cls := ""
    try {
        cls := WinGetClass("ahk_id " hwnd)
    }
    catch Error as e {
        return false
    }
    static shellClasses := Map(
        "Shell_TrayWnd", true, "Shell_SecondaryTrayWnd", true,
        "Progman", true, "WorkerW", true,
        "Windows.UI.Core.CoreWindow", true, "XamlExplorerHostIslandWindow", true,
        "TaskListThumbnailWnd", true, "MultitaskingViewFrame", true
    )
    return shellClasses.Has(cls)
}

; Sichtbares Rechteck (DWM Extended Frame Bounds, sonst WinGetPos). 0 bei Fehler.
Focus_WindowRect(hwnd) {
    try {
        buf := Buffer(16, 0)
        hr := DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "int", 9, "ptr", buf, "uint", 16, "int")
        if (hr = 0) {
            l := NumGet(buf, 0, "Int"), t := NumGet(buf, 4, "Int")
            r := NumGet(buf, 8, "Int"), b := NumGet(buf, 12, "Int")
            if (r > l && b > t)
                return { L:l, T:t, R:r, B:b }
        }
    }
    catch Error as e {
    }
    try {
        WinGetPos &x, &y, &w, &h, "ahk_id " hwnd
        if (w > 0 && h > 0)
            return { L:x, T:y, R:x + w, B:y + h }
    }
    catch Error as e {
    }
    return 0
}

; Sammelt alle Fenster, die nicht abgedunkelt werden sollen:
;  - aktives Fenster
;  - Fenster, deren Root-Owner das aktive Fenster ist (Dialoge, Menues, Tooltips)
;  - rahmenlose Popups desselben Threads (Dropdowns, Combo-Listen, IME)
;  - eigene WinSnap-GUIs (Pills, Highlight, Suche, Hotkey-Overlay)
; Rueckgabe: Array aus { L,T,R,B, hwnd, rgn } (rgn = Fensterregion in Screen-Koordinaten oder 0)
Focus_CollectHoles(active) {
    global Focus
    holes := []
    activeThread := 0
    try {
        activeThread := DllCall("GetWindowThreadProcessId", "ptr", active, "ptr", 0, "uint")
    }
    catch Error as e {
        activeThread := 0
    }
    ownGuis := Map()
    for mon, st in Focus.guis
        ownGuis[st.gui.Hwnd] := true

    ids := []
    try {
        ids := WinGetList()
    }
    catch Error as e {
        LogException(e, "Focus_CollectHoles: WinGetList failed")
        ids := [active]
    }
    pidBuf := Buffer(4, 0)
    for hwnd in ids {
        if (ownGuis.Has(hwnd))
            continue
        isOwn := false
        isRelated := (hwnd = active)
        if (!isRelated) {
            tid := 0
            try {
                tid := DllCall("GetWindowThreadProcessId", "ptr", hwnd, "ptr", pidBuf, "uint")
            }
            catch Error as e {
                tid := 0
            }
            pid := NumGet(pidBuf, 0, "UInt")
            if (pid = Focus.ownPid) {
                isOwn := true
            } else if (tid && tid = activeThread) {
                ; Gleicher Thread: Owner-Kette oder rahmenloses Popup
                rootOwner := 0
                try {
                    rootOwner := DllCall("GetAncestor", "ptr", hwnd, "uint", 3, "ptr") ; GA_ROOTOWNER
                }
                catch Error as e {
                    rootOwner := 0
                }
                if (rootOwner = active) {
                    isRelated := true
                } else {
                    style := 0
                    try {
                        style := WinGetStyle("ahk_id " hwnd)
                    }
                    catch Error as e {
                        style := 0
                    }
                    ; WS_POPUP ohne WS_CAPTION -> Menue/Dropdown/Tooltip
                    if ((style & 0x80000000) && !(style & 0x00C00000))
                        isRelated := true
                }
            } else {
                ; Anderer Thread, aber vom aktiven Fenster besessen (z.B. Dialoge aus Worker-Threads)
                rootOwner := 0
                try {
                    rootOwner := DllCall("GetAncestor", "ptr", hwnd, "uint", 3, "ptr")
                }
                catch Error as e {
                    rootOwner := 0
                }
                if (rootOwner && rootOwner = active)
                    isRelated := true
            }
        }
        if (!isOwn && !isRelated)
            continue
        ; Minimiert oder gecloakt -> kein Loch
        try {
            if (DllCall("IsIconic", "ptr", hwnd))
                continue
        }
        catch Error as e {
        }
        if (WinIsCloaked(hwnd))
            continue
        rect := Focus_WindowRect(hwnd)
        if (!rect)
            continue
        hole := { L:rect.L, T:rect.T, R:rect.R, B:rect.B, hwnd:hwnd, rgn:0 }
        if (isOwn) {
            ; Eigene GUIs koennen eine Fensterregion haben (Pill-Rundung, Highlight-Ring):
            ; exakt uebernehmen, damit z.B. das Innere des Rings abgedunkelt bleibt.
            try {
                WinGetPos &wx, &wy, &ww, &wh, "ahk_id " hwnd
                rgn := DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", 0, "Int", 0, "Ptr")
                res := DllCall("GetWindowRgn", "Ptr", hwnd, "Ptr", rgn, "Int")
                if (res != 0) { ; != ERROR
                    DllCall("OffsetRgn", "Ptr", rgn, "Int", wx, "Int", wy, "Int")
                    hole.rgn := rgn
                    hole.L := wx, hole.T := wy, hole.R := wx + ww, hole.B := wy + wh
                } else {
                    DllCall("DeleteObject", "Ptr", rgn)
                }
            }
            catch Error as e {
            }
        }
        holes.Push(hole)
    }
    return holes
}

Focus_FreeHoles(holes) {
    for hole in holes {
        if (hole.rgn) {
            try DllCall("DeleteObject", "Ptr", hole.rgn)
            hole.rgn := 0
        }
    }
}

Focus_HolesKey(holes) {
    key := ""
    for hole in holes
        key .= hole.hwnd ":" hole.L "," hole.T "," hole.R "," hole.B ";"
    return key
}

; Timer-Tick: Loecher berechnen und Overlay-Regionen aktualisieren.
Focus_Tick(*) {
    global Focus, DragSnap
    if (!Focus.enabled || Focus.suspended)
        return
    if (StateGet("DisplayChangePending", false))
        return
    try {
        if (IsSet(DragSnap) && DragSnap.active)
            return
    }
    catch Error as e {
    }
    try {
        Focus_TickInner()
    }
    catch Error as e {
        LogException(e, "Focus_Tick")
    }
}

Focus_TickInner() {
    global Focus
    active := 0
    try {
        active := WinGetID("A")
    }
    catch Error as e {
        active := 0
    }
    if (!active || !DllCall("IsWindow", "ptr", active))
        active := 0

    holes := []
    if (active && !Focus_IsShellWindow(active)) {
        holes := Focus_CollectHoles(active)
        ; Letzte Loecher ohne GDI-Regionen merken (Regionen werden unten freigegeben)
        keep := []
        for hole in holes
            keep.Push({ L:hole.L, T:hole.T, R:hole.R, B:hole.B, hwnd:hole.hwnd, rgn:0 })
        Focus.lastGoodHoles := keep
    } else {
        ; Taskleiste/Desktop/Startmenue im Vordergrund: letzte Loecher beibehalten,
        ; sonst flackert beim Klick auf die Taskleiste alles dunkel.
        for hole in Focus.lastGoodHoles {
            if (DllCall("IsWindow", "ptr", hole.hwnd) && !DllCall("IsIconic", "ptr", hole.hwnd))
                holes.Push({ L:hole.L, T:hole.T, R:hole.R, B:hole.B, hwnd:hole.hwnd, rgn:0 })
        }
    }

    key := Focus_HolesKey(holes)
    if (key = Focus.lastKey) {
        Focus_FreeHoles(holes)
        return
    }
    Focus.lastKey := key

    for mon, st in Focus.guis
        Focus_ApplyMonitor(mon, st, holes)
    Focus_FreeHoles(holes)
}

; Setzt die Region eines Monitor-Overlays: Arbeitsbereich minus Loecher.
; Deckt ein Loch den ganzen Arbeitsbereich (maximiert/Vollbild), wird das Overlay versteckt.
Focus_ApplyMonitor(mon, st, holes) {
    w := st.R - st.L
    h := st.B - st.T
    if (w <= 0 || h <= 0)
        return

    ; Nur Loecher, die den Monitor beruehren
    onMon := []
    coversAll := false
    for hole in holes {
        if (hole.R <= st.L || hole.L >= st.R || hole.B <= st.T || hole.T >= st.B)
            continue
        if (!hole.rgn && hole.L <= st.L && hole.T <= st.T && hole.R >= st.R && hole.B >= st.B) {
            coversAll := true
            break
        }
        onMon.Push(hole)
    }

    if (coversAll) {
        if (st.shown) {
            try st.gui.Hide()
            st.shown := false
            st.key := ""
        }
        return
    }

    monKey := ""
    for hole in onMon
        monKey .= hole.hwnd ":" hole.L "," hole.T "," hole.R "," hole.B ";"
    if (st.shown && st.key = monKey)
        return
    st.key := monKey

    rgn := DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", w, "Int", h, "Ptr")
    if (!rgn) {
        LogError("Focus_ApplyMonitor: CreateRectRgn failed")
        return
    }
    for hole in onMon {
        if (hole.rgn) {
            ; Fensterregion liegt in Screen-Koordinaten -> in Overlay-Koordinaten verschieben
            tmp := DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", 0, "Int", 0, "Ptr")
            DllCall("CombineRgn", "Ptr", tmp, "Ptr", hole.rgn, "Ptr", 0, "Int", 5) ; RGN_COPY
            DllCall("OffsetRgn", "Ptr", tmp, "Int", -st.L, "Int", -st.T, "Int")
            DllCall("CombineRgn", "Ptr", rgn, "Ptr", rgn, "Ptr", tmp, "Int", 4) ; RGN_DIFF
            DllCall("DeleteObject", "Ptr", tmp)
        } else {
            cl := Max(0, hole.L - st.L), ct := Max(0, hole.T - st.T)
            cr := Min(w, hole.R - st.L), cb := Min(h, hole.B - st.T)
            if (cr <= cl || cb <= ct)
                continue
            tmp := DllCall("CreateRectRgn", "Int", cl, "Int", ct, "Int", cr, "Int", cb, "Ptr")
            DllCall("CombineRgn", "Ptr", rgn, "Ptr", rgn, "Ptr", tmp, "Int", 4) ; RGN_DIFF
            DllCall("DeleteObject", "Ptr", tmp)
        }
    }

    ; SetWindowRgn uebernimmt die Region (nicht mehr selbst freigeben)
    ok := DllCall("SetWindowRgn", "Ptr", st.gui.Hwnd, "Ptr", rgn, "Int", st.shown)
    if (!ok) {
        LogError("Focus_ApplyMonitor: SetWindowRgn failed")
        DllCall("DeleteObject", "Ptr", rgn)
        return
    }
    if (!st.shown) {
        try {
            st.gui.Show(Format("NA x{} y{} w{} h{}", st.L, st.T, w, h))
            st.shown := true
        }
        catch Error as e {
            LogException(e, "Focus_ApplyMonitor: Show failed")
        }
    }
}
