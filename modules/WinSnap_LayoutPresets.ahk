; =========================
; Layout-Presets (Ctrl+Alt+Win+Taste)
; =========================
; Zentrale Tabelle aller Presets. Hotkeys, Layout-Overlay und Hotkey-Overlay
; greifen auf diese Liste zu, damit Beschreibung, Vorschau und Verhalten
; immer zusammenpassen.
;   key         : Taste hinter Ctrl+Alt+Win (und im Layout-Overlay ohne Modifier)
;   name        : kurzer Name
;   desc        : Beschreibung fuer Overlays
;   cols        : Spaltengewichte (Layout_SetMonitorColumns)
;   quad        : true = 2x2-Quadranten
;   allMonitors : true = Preset auf alle Monitore anwenden
;   sameAs      : Preset-Kennung, unter der die Fensterzuordnung gemerkt wird
;                 ("0" baut dieselbe Struktur wie "2" und teilt sich dessen Gedaechtnis)

global LayoutPresets := [
    { key:"1", name:"Vollbild",      desc:"ein Bereich",              cols:[1],       quad:false, allMonitors:false, sameAs:"" },
    { key:"2", name:"50 / 50",       desc:"zwei Spalten",             cols:[1, 1],    quad:false, allMonitors:false, sameAs:"" },
    { key:"3", name:"33 / 33 / 33",  desc:"drei Spalten",             cols:[1, 1, 1], quad:false, allMonitors:false, sameAs:"" },
    { key:"4", name:"Quadranten",    desc:"2 x 2",                    cols:[],        quad:true,  allMonitors:false, sameAs:"" },
    { key:"5", name:"25 / 50 / 25",  desc:"breite Mitte",             cols:[1, 2, 1], quad:false, allMonitors:false, sameAs:"" },
    { key:"6", name:"20 / 60 / 20",  desc:"sehr breite Mitte",        cols:[1, 3, 1], quad:false, allMonitors:false, sameAs:"" },
    { key:"7", name:"70 / 30",       desc:"Haupt + Seite",            cols:[7, 3],    quad:false, allMonitors:false, sameAs:"" },
    { key:"0", name:"50 / 50",       desc:"auf allen Monitoren",      cols:[1, 1],    quad:false, allMonitors:true,  sameAs:"2" }
]

; Liefert das Preset zur Taste (String "0".."9") oder 0.
LayoutPreset_Get(key) {
    global LayoutPresets
    key := String(key)
    for p in LayoutPresets {
        if (p.key = key)
            return p
    }
    return 0
}

; Wendet das Preset auf einen Monitor an (mon = 0: Monitor des aktiven Fensters).
; Presets mit allMonitors ignorieren mon. Danach werden die Fenster in ihre
; Areas eingesammelt (wie bisher bei den Hotkeys).
LayoutPreset_Apply(key, mon := 0) {
    p := LayoutPreset_Get(key)
    if (!p) {
        LogWarn(Format("LayoutPreset_Apply: unknown preset '{}'", key))
        return false
    }
    try {
        LayoutOverlay_Hide()
    }
    catch Error as e {
        LogException(e, "LayoutPreset_Apply: LayoutOverlay_Hide failed")
    }
    if (p.allMonitors) {
        count := MonitorGetCount()
        Loop count {
            m := A_Index
            LayoutPreset_ApplyToMonitor(p, m)
        }
        label := Format("{} on all monitors", p.name)
    } else {
        if (!mon)
            mon := GetCurrentMonitorIndex()
        if (!Monitors_IsValid(mon)) {
            LogWarn(Format("LayoutPreset_Apply: monitor {} not valid", mon))
            return false
        }
        LayoutPreset_ApplyToMonitor(p, mon)
        label := Format("{} on mon={}", p.name, mon)
    }
    try {
        CollectWindowsInAllLeaves()
    }
    catch Error as e {
        LogException(e, "LayoutPreset_Apply: CollectWindowsInAllLeaves failed")
    }
    LogInfo(Format("Preset: {} + collect", label))
    return true
}

; Baut das Layout eines einzelnen Monitors gemaess Preset.
; Vorher wird die Fensterzuordnung des bisherigen Presets gemerkt, danach die
; gemerkte Zuordnung des neuen Presets wiederhergestellt (PresetMemory).
LayoutPreset_ApplyToMonitor(p, mon) {
    memKey := (p.sameAs != "") ? p.sameAs : p.key
    oldKey := Layout_GetPreset(mon)
    if (oldKey != "") {
        try {
            PresetMemory_Snapshot(mon, oldKey)
        }
        catch Error as e {
            LogException(e, "LayoutPreset_ApplyToMonitor: PresetMemory_Snapshot failed")
        }
    }
    if (p.quad) {
        Layout_SetMonitorQuadrants(mon)
    } else if (p.cols.Length <= 1) {
        Layout_ResetMonitor(mon)
    } else {
        Layout_SetMonitorColumns(mon, p.cols)
    }
    Layout_SetPreset(mon, memKey)
    try {
        PresetMemory_Restore(mon, memKey)
    }
    catch Error as e {
        LogException(e, "LayoutPreset_ApplyToMonitor: PresetMemory_Restore failed")
    }
}

; Liefert die Vorschau-Rechtecke eines Presets, normiert auf 0..1, in der
; Reihenfolge der Area-Nummerierung (Layout_LeafOrder: a vor b).
; Die Spaltenbreiten werden wie in Layout_SetMonitorColumns ueber ClampFrac
; begrenzt, damit die Vorschau dem spaeteren Layout entspricht.
LayoutPreset_PreviewRects(p) {
    rects := []
    if (p.quad) {
        rects.Push({ L:0.0, T:0.0, R:0.5, B:0.5 })
        rects.Push({ L:0.5, T:0.0, R:1.0, B:0.5 })
        rects.Push({ L:0.0, T:0.5, R:0.5, B:1.0 })
        rects.Push({ L:0.5, T:0.5, R:1.0, B:1.0 })
        return rects
    }
    cols := p.cols
    if (cols.Length <= 1) {
        rects.Push({ L:0.0, T:0.0, R:1.0, B:1.0 })
        return rects
    }
    total := 0.0
    for v in cols
        total += v
    if (total <= 0)
        total := 1.0
    ; Wie Layout_SetMonitorColumns: der Rest wird jeweils am Anteil frac geteilt.
    left := 0.0
    width := 1.0
    remaining := total
    i := 1
    while (i <= cols.Length - 1) {
        frac := ClampFrac(cols[i] / remaining)
        w := width * frac
        rects.Push({ L:left, T:0.0, R:left + w, B:1.0 })
        left += w
        width -= w
        remaining -= cols[i]
        i += 1
    }
    rects.Push({ L:left, T:0.0, R:1.0, B:1.0 })
    return rects
}

; Liefert die aktuellen Areas eines Monitors als normierte Rechtecke (0..1),
; inklusive globaler Area-Nummer (wie Alt+Shift+O / Win+Ctrl+Zahl).
; Rueckgabe: Array aus { L,T,R,B, no }
Layout_CurrentPreviewRects(mon) {
    out := []
    if (!Monitors_IsValid(mon))
        return out
    Layout_Ensure(mon)
    ; Globale Nummer: Areas der Monitore davor mitzaehlen
    offset := 0
    Loop (mon - 1) {
        m := A_Index
        try {
            Layout_Ensure(m)
            offset += Layout_LeafOrder(m).Length
        }
        catch Error as e {
            LogException(e, "Layout_CurrentPreviewRects: counting leaves failed")
        }
    }
    work := GetMonitorWork(mon)
    mw := Max(1, work.right - work.left)
    mh := Max(1, work.bottom - work.top)
    no := offset
    for id in Layout_LeafOrder(mon) {
        no += 1
        r := Layout_NodeRect(mon, id)
        out.Push({
            L:(r.L - work.left) / mw,
            T:(r.T - work.top) / mh,
            R:(r.R - work.left) / mw,
            B:(r.B - work.top) / mh,
            no:no
        })
    }
    return out
}
