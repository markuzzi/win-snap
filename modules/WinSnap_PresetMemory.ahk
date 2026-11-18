; =========================
; Preset-Gedaechtnis: Fensterzuordnung je Monitor und Layout-Preset
; =========================
; Beim Wechsel von Preset A nach B wird fuer A gemerkt, welches Fenster in
; welcher Area-Nummer lag (Reihenfolge wie Layout_LeafOrder). Wird A spaeter
; wieder angewendet, wandern die Fenster zurueck in ihre alten Areas. Die
; Zuordnung bleibt auch erhalten, wenn nur Grenzen verschoben werden
; (Alt+Shift+Pfeile); erst Split/Loeschen einer Area macht aus dem Layout ein
; freies Layout ohne Preset (Layout_SplitLeaf / Layout_RemoveLeaf setzen
; preset := "").
; Persistenz: WinSnap_PresetAssignments.json (monKey -> presetKey -> Eintraege
; mit hwnd + Prozess/Klasse/Titel, damit auch nach einem Neustart per Identitaet
; zugeordnet werden kann).

global PresetMemory := Map()   ; monKey -> Map(presetKey -> [Map(area, hwnd, process, class, title), ...])
global PresetMemoryPath := A_ScriptDir "\WinSnap_PresetAssignments.json"
global PresetMemoryWritePending := false

; --- Preset-Kennung am Layout ------------------------------------------------

; Liefert das Preset, mit dem das Layout des Monitors gebaut wurde ("" = frei).
Layout_GetPreset(mon) {
    global Layouts
    if (!Layouts.Has(mon))
        return ""
    layout := Layouts[mon]
    if (IsObject(layout) && layout.HasOwnProp("preset"))
        return String(layout.preset)
    return ""
}

; Setzt die Preset-Kennung am Layout des Monitors und speichert.
Layout_SetPreset(mon, key) {
    global Layouts
    if (!Layouts.Has(mon))
        return
    Layouts[mon].preset := String(key)
    Layout_ScheduleSave()
}

; --- Snapshot / Restore --------------------------------------------------------

; Merkt sich die aktuelle Fensterzuordnung des Monitors unter presetKey.
PresetMemory_Snapshot(mon, presetKey) {
    global PresetMemory
    if (presetKey = "" || !Monitors_IsValid(mon))
        return 0
    monKey := PresetMemory_MonKey(mon)
    entries := []
    area := 0
    for leafId in Layout_LeafOrder(mon) {
        area += 1
        list := []
        try {
            list := LeafGetOrderedList(mon, leafId)
        }
        catch Error as e {
            LogException(e, "PresetMemory_Snapshot: LeafGetOrderedList failed")
            continue
        }
        for hwnd in list {
            ident := 0
            try {
                ident := BlackList_GetWindowIdentity(hwnd)
            }
            catch Error as e {
                ident := 0
            }
            if (!ident)
                continue
            entry := Map()
            entry["area"] := area
            entry["hwnd"] := hwnd
            entry["process"] := ident.exe
            entry["class"] := ident.className
            entry["title"] := ident.title
            entries.Push(entry)
        }
    }
    if (!PresetMemory.Has(monKey))
        PresetMemory[monKey] := Map()
    PresetMemory[monKey][String(presetKey)] := entries
    PresetMemory_ScheduleWrite()
    LogInfo(Format("PresetMemory_Snapshot: mon={}, preset={}, windows={}", mon, presetKey, entries.Length))
    return entries.Length
}

; Stellt die gemerkte Zuordnung fuer presetKey auf dem Monitor wieder her.
; Fenster werden zuerst ueber ihr hwnd (mit Identitaetspruefung), sonst ueber
; Prozess/Klasse/Titel gefunden. Fenster, die inzwischen auf einem anderen
; Monitor gesnappt sind, bleiben dort.
PresetMemory_Restore(mon, presetKey) {
    global PresetMemory, WinToLeaf
    if (presetKey = "" || !Monitors_IsValid(mon))
        return 0
    monKey := PresetMemory_MonKey(mon)
    if (!PresetMemory.Has(monKey) || !PresetMemory[monKey].Has(String(presetKey)))
        return 0
    entries := PresetMemory[monKey][String(presetKey)]
    if (!(entries is Array) || entries.Length = 0)
        return 0
    order := Layout_LeafOrder(mon)
    openRows := SnappedWindows_BuildOpenWindowIndex()
    used := Map()
    restored := 0
    for entry in entries {
        area := SW_ToInt(SW_GetEntryValue(entry, "area", 0), 0)
        if (area < 1 || area > order.Length)
            continue
        proc := SW_GetEntryValue(entry, "process", "")
        className := SW_GetEntryValue(entry, "class", "")
        title := SW_GetEntryValue(entry, "title", "")
        hwnd := SW_ToInt(SW_GetEntryValue(entry, "hwnd", 0), 0)
        valid := false
        if (hwnd && !used.Has(hwnd)) {
            try {
                valid := DllCall("IsWindow", "ptr", hwnd) && WinExist("ahk_id " hwnd)
                    && SnappedWindows_WindowMetaMatches(hwnd, proc, className, "")
            }
            catch Error as e {
                valid := false
            }
        }
        if (!valid)
            hwnd := SnappedWindows_FindWindowByIdentity(proc, className, title, openRows, used)
        if (!hwnd)
            continue
        used[hwnd] := true
        if (WinToLeaf.Has(hwnd) && WinToLeaf[hwnd].mon != mon)
            continue
        if (!IsCollectibleSnapWindow(hwnd))
            continue
        try {
            EnsureHistory(hwnd)
            SnapToLeaf(hwnd, mon, order[area])
            restored += 1
        }
        catch Error as e {
            LogException(e, "PresetMemory_Restore: SnapToLeaf failed")
        }
    }
    LogInfo(Format("PresetMemory_Restore: mon={}, preset={}, restored {} of {}", mon, presetKey, restored, entries.Length))
    return restored
}

PresetMemory_MonKey(mon) {
    key := ""
    try {
        key := Monitors_KeyFromIndex(mon)
    }
    catch Error as e {
        key := ""
    }
    return (key != "") ? key : "index:" mon
}

; --- Persistenz ----------------------------------------------------------------

PresetMemory_Load() {
    global PresetMemory, PresetMemoryPath
    PresetMemory := Map()
    if (!FileExist(PresetMemoryPath))
        return
    try {
        text := FileRead(PresetMemoryPath, "UTF-8")
        if (!text || Trim(text) = "")
            return
        data := jxon_load(&text)
    }
    catch Error as e {
        LogException(e, "PresetMemory_Load")
        return
    }
    if (!(data is Map))
        return
    count := 0
    for monKey, presets in data {
        if (!(presets is Map))
            continue
        PresetMemory[monKey] := Map()
        for presetKey, entries in presets {
            if (entries is Array) {
                PresetMemory[monKey][String(presetKey)] := entries
                count += 1
            }
        }
    }
    LogInfo(Format("PresetMemory_Load: {} preset assignments loaded", count))
}

PresetMemory_ScheduleWrite() {
    global PresetMemoryWritePending
    if (PresetMemoryWritePending)
        return
    PresetMemoryWritePending := true
    try {
        SetTimer(PresetMemory_Flush, -100)
    }
    catch Error as e {
        PresetMemoryWritePending := false
        LogException(e, "PresetMemory_ScheduleWrite")
    }
}

PresetMemory_Flush(*) {
    global PresetMemory, PresetMemoryPath, PresetMemoryWritePending
    PresetMemoryWritePending := false
    try {
        f := FileOpen(PresetMemoryPath, "w", "UTF-8")
        if (f) {
            f.Write(jxon_dump(PresetMemory, indent := 2))
            f.Close()
        }
    }
    catch Error as e {
        LogException(e, "PresetMemory_Flush: write failed")
    }
}
