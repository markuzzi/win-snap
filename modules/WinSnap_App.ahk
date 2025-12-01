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

; Initialisiert einen Shell-Hook, um Fenster-Ereignisse (Creation/Activation) zu empfangen
; und AutoSnap direkt auszul��sen (statt nur per Timer-Polling).
InitShellHook() {
    global ShellHookMsg
    try {
        ; Script-Fenster fǬr Shell-Hook registrieren
        DllCall("RegisterShellHookWindow", "ptr", A_ScriptHwnd)
        ShellHookMsg := DllCall("RegisterWindowMessage", "str", "SHELLHOOK", "uint")
        OnMessage(ShellHookMsg, ShellMessage_Handler)
        LogInfo("InitShellHook: shell hook registered")
    }
    catch Error as e {
        LogException(e, "InitShellHook failed")
    }
}

; Handler fǬr Shell-Hook-Messages.
; Reagiert auf Fenster-Erstellung, -Zerstörung und -Aktivierung.
ShellMessage_Handler(wParam, lParam, msg, hwnd) {
    ; HSHELL_WINDOWCREATED = 1, HSHELL_WINDOWDESTROYED = 2, HSHELL_WINDOWACTIVATED = 4
    try {
        if (wParam = 1 || wParam = 4) {
            AutoSnap_NewlyStartedWindows()
        } else if (wParam = 2) {
            ; Fenster wurde zerstört -> ggf. aus Leaf-Listen entfernen,
            ; damit Pills und Layout sofort stimmen.
            LeafDetachWindow(lParam, true)
        }
    }
    catch Error as e {
        LogException(e, "ShellMessage_Handler")
    }
    return 0
}

; Toggle: aktives Fenster auf AutoSnap-Blacklist setzen oder wieder entfernen.
ToggleBlacklistForActiveWindow() {
    global AutoSnapBlackList
    win := GetActiveWindow()
    if (!win)
        return
    hwnd := win.hwnd

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
    if (!exe && !className)
        return

    if (!IsSet(AutoSnapBlackList) || !(AutoSnapBlackList is Map))
        AutoSnapBlackList := Map()

    exeKey := exe ? "exe:" . StrLower(exe) : ""
    classKey := className ? "class:" . className : ""
    comboKey := (exeKey && classKey) ? exeKey . "|class:" . className : ""

    ; Kombination exe+class ist ma�Ygeblich; alte Einzel-Keys werden nur zum Aufr��umen berǬcksichtigt.
    isBlack := false
    if (comboKey && AutoSnapBlackList.Has(comboKey))
        isBlack := true
    if (!isBlack && exeKey && AutoSnapBlackList.Has(exeKey))
        isBlack := true
    if (!isBlack && classKey && AutoSnapBlackList.Has(classKey))
        isBlack := true

    if (isBlack) {
        if (comboKey && AutoSnapBlackList.Has(comboKey))
            AutoSnapBlackList.Delete(comboKey)
        if (exeKey && AutoSnapBlackList.Has(exeKey))
            AutoSnapBlackList.Delete(exeKey)
        if (classKey && AutoSnapBlackList.Has(classKey))
            AutoSnapBlackList.Delete(classKey)
        try BlackList_Save()
        ShowTrayTip("AutoSnap Blacklist entfernt: " . exe " (" . className . ")", 1500)
        MsgBox("AutoSnap Blacklist-Eintrag entfernt: " . exe " (" . className . ")")
        LogInfo(Format("ToggleBlacklistForActiveWindow: removed exe={}, class={}", exe, className))
    } else {
        if (comboKey)
            AutoSnapBlackList[comboKey] := true
        try BlackList_Save()
        ShowTrayTip("AutoSnap Blacklist hinzugefuegt: " . exe " (" . className . ")", 1500)
        MsgBox("AutoSnap Blacklist-Eintrag hinzugefuegt: " . exe " (" . className . ")")
        LogInfo(Format("ToggleBlacklistForActiveWindow: added exe={}, class={}", exe, className))
    }
}

