; =========================
; App/Tray/State Funktionen
; =========================

; Schaltet Hotkeys und relevante Timer pausiert/aktiv (Toggle).
TogglePause() {
    global ScriptPaused
    newState := !ScriptPaused
    ScriptPaused := newState
    try {
        Suspend(newState)
    }
    catch Error as e {
        LogError("TogglePause: Suspend failed")
    }
    ; Timer steuern: Active-Highlight und AutoSnap-NewWindows
    try {
        SetTimer(UpdateActiveHighlight, newState ? 0 : 150)
    }
    catch Error as e {
        LogError("TogglePause: SetTimer(UpdateActiveHighlight) failed")
    }
    try {
        SetTimer(AutoSnap_NewlyStartedWindows, newState ? 0 : 2000)
    }
    catch Error as e {
        LogError("TogglePause: SetTimer(AutoSnap_NewlyStartedWindows) failed")
    }
    if (newState)
        HideHighlight()
    ShowTrayTip(newState ? "Pausiert" : "Aktiv", 1200)
    LogInfo(Format("TogglePause: {}", newState ? "paused" : "resumed"))
    UpdateTrayTooltip()
}

; Liefert den Monitorindex des aktuell aktiven Fensters (Fallback 1).
GetCurrentMonitorIndex() {
    win := GetActiveWindow()
    if (win) {
        mi := GetMonitorIndexAndArea(win.hwnd)
        return mi.index
    }
    return 1
}

; Initialisiert das Tray-Icon und setzt den Tooltip.
InitTrayIcon() {
    ico := A_ScriptDir "\WinSnap.ico"
    try {
        if (FileExist(ico))
            TraySetIcon(ico)
        else
            TraySetIcon("imageres.dll", 202)
    }
    catch Error as e {
        try {
            TraySetIcon("shell32.dll", 44)
        }
        catch Error as e {
            LogError("InitTrayIcon: TraySetIcon fallback failed")
        }
    }
    UpdateTrayTooltip()
}

; Aktualisiert den Tray-Tooltip basierend auf dem Pausenstatus.
UpdateTrayTooltip() {
    global ScriptPaused
    tip := ScriptPaused ? "WinSnap - Pausiert" : "WinSnap - Aktiv"
    try {
        A_IconTip := tip
    }
    catch Error as e {
        LogError("UpdateTrayTooltip: setting tooltip failed")
    }
}

; Zeigt einen TrayTip fuer eine begrenzte Zeit und blendet ihn danach aus.
ShowTrayTip(msg, ms := 1500, icon := "") {
    try {
        if (icon != "")
            TrayTip "WinSnap", msg, icon
        else
            TrayTip "WinSnap", msg
    }
    catch Error as e {
        LogError("ShowTrayTip: TrayTip failed")
    }
    try {
        if (ms > 0)
            SetTimer(ShowTrayTip_Hide, -ms)
    }
    catch Error as e {
        LogError("ShowTrayTip: SetTimer failed")
    }
}

; Blendet den aktuell angezeigten TrayTip aus.
ShowTrayTip_Hide() {
    try {
        TrayTip()
    }
    catch Error as e {
        LogError("ShowTrayTip_Hide: TrayTip hide failed")
    }
}
