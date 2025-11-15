; =========================
; WinSnap_DragResize.ahk
; Logic functions used by hotkeys defined in WinSnap.ahk
; =========================

; Minimizes the window currently under the mouse cursor.
DR_MinimizeUnderMouse() {
     LogInfo("DR_MinimizeUnderMouse: invoked")
     try {
         MouseGetPos &mx, &my, &hwnd
         if (!hwnd)
             return
         if (DllCall("IsWindow", "ptr", hwnd) && WinExist("ahk_id " hwnd))
             WinMinimize "ahk_id " hwnd
     }
     catch Error as e {
         LogException(e, "DR_MinimizeUnderMouse failed")
     }
}

; Alt+LButton style drag-move loop (runs until LButton is released).
DR_StartAltDragMove() {
    LogInfo("DR_StartAltDragMove: begin")
    try {
        CoordMode "Mouse", "Screen"
        MouseGetPos &x0, &y0, &hwnd
        if (!hwnd)
            return
        WinGetPos &wx, &wy, &ww, &wh, "ahk_id " hwnd
        offX := x0 - wx
        offY := y0 - wy
        Loop {
            state := GetKeyState("LButton", "P") ? "D" : "U"
            if (state = "U")
                break
            MouseGetPos &x, &y
            ; Use raw WinMove here for smoothness during drag
            try {
                WinMove x - offX, y - offY, , , "ahk_id " hwnd
            }
            catch Error as e {
                LogException(e, "DR_StartAltDragMove: WinMove failed")
                break
            }
        }
    }
    catch Error as e {
        LogException(e, "DR_StartAltDragMove failed")
    }
    LogInfo("DR_StartAltDragMove: end")
}

; Alt+RButton style resize loop based on initial quadrant.
DR_StartAltDragResize() {
    LogInfo("DR_StartAltDragResize: begin")
    try {
        CoordMode "Mouse", "Screen"
        MouseGetPos &mx1, &my1, &hwnd
        if (!hwnd)
            return
        if (WinGetMinMax("ahk_id " hwnd))
            return
        WinGetPos &wx1, &wy1, &ww, &wh, "ahk_id " hwnd
        winLeft := (mx1 < wx1 + ww/2) ? 1 : -1
        winUp   := (my1 < wy1 + wh/2) ? 1 : -1
        Loop {
            btn := GetKeyState("RButton", "P") ? "D" : "U"
            if (btn = "U")
                break
            MouseGetPos &mx2, &my2
            ; refresh current window rect
            WinGetPos &wx1, &wy1, &ww, &wh, "ahk_id " hwnd
            dx := mx2 - mx1
            dy := my2 - my1
            nx := wx1 + (winLeft+1)/2 * dx
            ny := wy1 + (winUp+1)/2  * dy
            nw := ww - winLeft * dx
            nh := wh - winUp   * dy
            try {
                WinMove nx, ny, nw, nh, "ahk_id " hwnd
            }
            catch Error as e {
                LogException(e, "DR_StartAltDragResize: WinMove failed")
                break
            }
            mx1 := mx2, my1 := my2
        }
    }
    catch Error as e {
        LogException(e, "DR_StartAltDragResize failed")
    }
    LogInfo("DR_StartAltDragResize: end")
}

; Adjust transparency of the active window by a delta (-/+).
DR_AdjustActiveTransparency(delta) {
    try {
        hwnd := WinGetID("A")
    }
    catch Error as e {
        LogException(e, "DR_AdjustActiveTransparency: get active hwnd failed")
        return
    }
    if (!hwnd)
        return
    try {
        cur := WinGetTransparent("ahk_id " hwnd)
        if (cur = "")
            cur := (delta < 0) ? 255 : 0
        cur += delta
        if (cur < 0)
            cur := 0
        else if (cur > 255)
            cur := 255
        WinSetTransparent(cur, "ahk_id " hwnd)
        LogInfo(Format("DR_AdjustActiveTransparency: hwnd={}, new={}", hwnd, cur))
    }
    catch Error as e {
        LogException(e, "DR_AdjustActiveTransparency failed")
    }
}
