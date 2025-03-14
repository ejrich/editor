struct Window {
    handle: void*;
    window: u64;
    graphics_context: void*;
}

window: Window;

display_width: u32;
display_height: u32;

init_display() {
    #if os == OS.Linux {
        XInitThreads();
        window.handle = XOpenDisplay(null);

        return_window: u64;
        root_x, root_y, win_x, win_y: s32;
        mask: u32;
        root_window := XDefaultRootWindow(window.handle);
        XQueryPointer(window.handle, root_window, &return_window, &return_window, &root_x, &root_y, &win_x, &win_y, &mask);

        monitor_count: s32;
        monitors := XRRGetMonitors(window.handle, root_window, 1, &monitor_count);

        each i in monitor_count {
            monitor := monitors[i];
            if root_x >= monitor.x && root_x < (monitor.x + monitor.width) && root_y >= monitor.y && root_y < (monitor.y + monitor.height) {
                display_width = monitor.width;
                display_height = monitor.height;
                break;
            }
        }

        XRRFreeMonitors(monitors);
    }
    else #if os == OS.Windows {
        SetProcessDPIAware();
        display_width = GetSystemMetrics(0 /* SM_CXSCREEN */);
        display_height = GetSystemMetrics(1 /* SM_CYSCREEN */);
    }
}

create_window() {
    #if os == OS.Linux {
        screen := XDefaultScreen(window.handle);
        black := XBlackPixel(window.handle, screen);
        white := XWhitePixel(window.handle, screen);

        default_window := XDefaultRootWindow(window.handle);
        x_win := XCreateSimpleWindow(window.handle, default_window, 0, 0, settings.window_width, settings.window_height, 0, white, black);

        name: XTextProperty;
        XStringListToTextProperty(&application_name.data, 1, &name);

        size_hints: XSizeHints = {
            flags = 0x1;
            min_width = settings.window_width; max_width = settings.window_width;
            min_height = settings.window_height; max_height = settings.window_height;
        }
        wm_hints: XWMHints = { flags = 0x3; input = 1; }
        XSetWMProperties(window.handle, x_win, &name, null, null, 0, &size_hints, &wm_hints, null);

        XSelectInput(window.handle, x_win, XInputMasks.AllEventMask);

        gc := XCreateGC(window.handle, x_win, 0, null);

        XSetBackground(window.handle, gc, white);
        XSetForeground(window.handle, gc, black);

        XClearWindow(window.handle, x_win);
        XMapRaised(window.handle, x_win);

        XSync(window.handle, false);

        window = { window = x_win; graphics_context = gc; }
    }
    else #if os == OS.Windows {
        hinstance := GetModuleHandleA(null);
        window_class: WNDCLASSEXA = {
            cbSize = size_of(WNDCLASSEXA);
            style = WindowClassStyle.CS_VREDRAW | WindowClassStyle.CS_HREDRAW;
            lpfnWndProc = handle_window_inputs;
            hInstance = hinstance;
            hCursor = LoadCursorA(null, 32512);
            hbrBackground = CreateSolidBrush(0);
            lpszClassName = application_name.data;
        }
        RegisterClassExA(&window_class);

        window.handle = CreateWindowExA(0, application_name, application_name, WindowStyle.WS_OVERLAPPEDWINDOW | WindowStyle.WS_VISIBLE, CW_USEDEFAULT, CW_USEDEFAULT, settings.window_width, settings.window_height, null, null, hinstance, null);
        SetWindowPos(window.handle, null, 0, 0, settings.window_width, settings.window_height, SWPFlags.SWP_FRAMECHANGED);

        margins: MARGINS = {
            cxLeftWidth = -1;
            cxRightWidth = -1;
            cyTopHeight = -1;
            cyBottomHeight = -1;
        }
        hr := DwmExtendFrameIntoClientArea(window.handle, &margins);
    }

    log("Opened window of size %x% with handle %\n", settings.window_width, settings.window_height, window.handle);
}

close_window() {
    #if os == OS.Linux {
        XFreeGC(window.handle, window.graphics_context);
        XDestroyWindow(window.handle, window.window);
        // XCloseDisplay(window.handle);
    }
    else #if os == OS.Windows {
        CloseWindow(window.handle);
    }

    log("Window % closed\n", window.handle);
}


// Poll new events from the window and dispatch the necessary event handlers
handle_inputs() {
    #if os == OS.Linux {
        next_key_is_held := false;
        event: XEvent;

        while XPending(window.handle) {
            XNextEvent(window.handle, &event);

            switch event.type {
                case XEventType.KeyPress; {
                    state := PressState.Down;
                    if next_key_is_held {
                        next_key_is_held = false;
                        state |= PressState.Held;
                    }

                    keysym := XLookupKeysym(&event.xkey, 0);
                    key_code := convert_keycode(keysym);
                    mod_code := convert_modcode(event.xkey.state);

                    char: CArray<u8>[4]; // Allow utf-8
                    c := XLookupString(&event.xkey, &char, 4, null, null);
                    str: string = { length = c; data = &char; }

                    handle_key_event(state, key_code, mod_code, str);
                }
                case XEventType.KeyRelease; {
                    if XEventsQueued(window.handle, QueuedAfterReading) {
                        next_event: XEvent;
                        XPeekEvent(window.handle, &next_event);

                        if next_event.type == XEventType.KeyPress && next_event.xkey.time == event.xkey.time && next_event.xkey.keycode == event.xkey.keycode {
                            next_key_is_held = true;
                            continue;
                        }
                    }

                    keysym := XLookupKeysym(&event.xkey, 0);
                    key_code := convert_keycode(keysym);
                    mod_code := convert_modcode(event.xkey.state);
                    str: string;

                    handle_key_event(PressState.Up, key_code, mod_code, str);
                }
                case XEventType.ButtonPress; {
                    mod_code := convert_modcode(event.xbutton.state);
                    if event.xbutton.button == 4 {
                        handle_mouse_scroll(ScrollDirection.Up, mod_code);
                    }
                    else if event.xbutton.button == 5 {
                        handle_mouse_scroll(ScrollDirection.Down, mod_code);
                    }
                    else if event.xbutton.button > 7 {
                        mouse_button := cast(MouseButton, event.xbutton.button - 4);
                        x, y := convert_coordinates(event.xbutton.x, event.xbutton.y);
                        handle_mouse_button(PressState.Down, mouse_button, mod_code, x, y);
                    }
                    else if event.xbutton.button <= 3 {
                        mouse_button := cast(MouseButton, event.xbutton.button);
                        x, y := convert_coordinates(event.xbutton.x, event.xbutton.y);
                        handle_mouse_button(PressState.Down, mouse_button, mod_code, x, y);
                    }
                }
                case XEventType.ButtonRelease; {
                    mod_code := convert_modcode(event.xbutton.state);
                    if event.xbutton.button > 7 {
                        mouse_button := cast(MouseButton, event.xbutton.button - 4);
                        x, y := convert_coordinates(event.xbutton.x, event.xbutton.y);
                        handle_mouse_button(PressState.Up, mouse_button, mod_code, x, y);
                    }
                    else if event.xbutton.button <= 3 {
                        mouse_button := cast(MouseButton, event.xbutton.button);
                        x, y := convert_coordinates(event.xbutton.x, event.xbutton.y);
                        handle_mouse_button(PressState.Up, mouse_button, mod_code, x, y);
                    }
                }
                case XEventType.MotionNotify; {
                    x, y := convert_coordinates(event.xmotion.x, event.xmotion.y);
                    handle_mouse_move(x, y);
                }
                case XEventType.ConfigureNotify;
                    if settings.window_width != event.xconfigure.width || settings.window_height != event.xconfigure.height {
                        resize_window(event.xconfigure.width, event.xconfigure.height);
                    }
            }
        }
    }
    else #if os == OS.Windows {
        message: MSG;

        while PeekMessageA(&message, null, 0, 0, RemoveMsg.PM_REMOVE) {
            if message.message == MessageType.WM_QUIT {
                signal_shutdown();
                return;
            }

            TranslateMessage(&message);
            DispatchMessageA(&message);
        }
    }
}

float, float get_cursor_position() {
    x, y: float;
    #if os == OS.Linux {
        root_x, root_y, win_x, win_y: s32;
        mask: u32;
        return_window: u64;
        XQueryPointer(window.handle, window.window, &return_window, &return_window, &root_x, &root_y, &win_x, &win_y, &mask);
        x, y = convert_coordinates(win_x, win_y);
    }
    else #if os == OS.Windows {
        point: POINT;
        GetCursorPos(&point);
        x, y = convert_coordinates(point.x, point.y);
    }

    return x, y;
}

#private

resize_window(u32 width, u32 height) {
    settings = { window_width = width; window_height = height; }
    handle_window_resize();
}

float, float convert_coordinates(int x, int y) {
    width_scale := cast(float, settings.window_width / 2);
    x_pos := (x - width_scale) / width_scale;

    height_scale := cast(float, settings.window_height / 2);
    y_pos := (height_scale - y) / height_scale;

    return x_pos, y_pos;
}

#if os == OS.Linux {
    #import X11

    KeyCode convert_keycode(u64 keysym) {
        if (keysym & 0xFF00) == 0 {
            return cast(KeyCode, keysym);
        }

        if keysym >= XK_F1 && keysym <= XK_F12 return cast(KeyCode, keysym - 0xFEBE);

        switch keysym {
            case XK_BackSpace; return KeyCode.Backspace;
            case XK_Tab;       return KeyCode.Tab;
            case XK_Return;    return KeyCode.Enter;
            case XK_Escape;    return KeyCode.Escape;
            case XK_Left;      return KeyCode.Left;
            case XK_Up;        return KeyCode.Up;
            case XK_Right;     return KeyCode.Right;
            case XK_Down;      return KeyCode.Down;
            case XK_Shift_L;
            case XK_Shift_R;
                return KeyCode.Shift;
            case XK_Control_L;
            case XK_Control_R;
                return KeyCode.Control;
            case XK_Alt_L;
            case XK_Alt_R;
                return KeyCode.Alt;
            case XK_Delete;    return KeyCode.Delete;
        }

        return KeyCode.Unhandled;
    }

    ModCode convert_modcode(ModState mod) {
        mod_code: ModCode;

        if mod & ModState.ShiftMask   mod_code |= ModCode.Shift;
        if mod & ModState.ControlMask mod_code |= ModCode.Control;
        if mod & ModState.Mod1Mask    mod_code |= ModCode.Alt;

        return mod_code;
    }
}
else #if os == OS.Windows {
    key_state: Array<u8>[256];

    s64 handle_window_inputs(Handle* handle, MessageType message, u64 wParam, s64 lParam) {
        result: s64 = 0;

        switch message {
            case MessageType.WM_CLOSE; signal_shutdown();
            case MessageType.WM_NCCALCSIZE; {
                if wParam != 0 {
                    size_params := cast(NCCALCSIZE_PARAMS*, *cast(void**, &lParam));
                    rect := &size_params.rgrc[0];
                    rect.left = rect.left + 1;
                    rect.top = rect.top + 1;
                    rect.right = rect.right - 1;
                    rect.bottom = rect.bottom - 1;
                }
            }
            case MessageType.WM_KEYDOWN;
            case MessageType.WM_SYSKEYDOWN; {
                state := PressState.Down;
                if lParam & 0x40000000 state |= PressState.Held;

                key_code := convert_keycode(wParam);
                mod_code := convert_modcode(lParam);

                GetKeyboardState(key_state.data);
                char: CArray<u8>[2];
                c := ToAscii(wParam, 0, key_state.data, &char, 0);
                str: string = { length = c; data = &char; }

                handle_key_event(state, key_code, mod_code, str);
            }
            case MessageType.WM_KEYUP;
            case MessageType.WM_SYSKEYUP; {
                key_code := convert_keycode(wParam);
                mod_code := convert_modcode(lParam);
                str: string;

                handle_key_event(PressState.Up, key_code, mod_code, str);
            }
            case MessageType.WM_LBUTTONDOWN;
                mouse_button(PressState.Down, MouseButton.Left, wParam, lParam);
            case MessageType.WM_LBUTTONUP;
                mouse_button(PressState.Up, MouseButton.Left, wParam, lParam);
            case MessageType.WM_MBUTTONDOWN;
                mouse_button(PressState.Down, MouseButton.Middle, wParam, lParam);
            case MessageType.WM_MBUTTONUP;
                mouse_button(PressState.Up, MouseButton.Middle, wParam, lParam);
            case MessageType.WM_RBUTTONDOWN;
                mouse_button(PressState.Down, MouseButton.Right, wParam, lParam);
            case MessageType.WM_RBUTTONUP;
                mouse_button(PressState.Up, MouseButton.Right, wParam, lParam);
            case MessageType.WM_XBUTTONDOWN; {
                button := (wParam & 0xFFFF0000) >> 16;
                wParam &= 0xFFFF;
                mouse_button(PressState.Down, cast(MouseButton, 3 + button), wParam, lParam);
            }
            case MessageType.WM_XBUTTONUP; {
                button := (wParam & 0xFFFF0000) >> 16;
                wParam &= 0xFFFF;
                mouse_button(PressState.Up, cast(MouseButton, 3 + button), wParam, lParam);
            }
            case MessageType.WM_MOUSEWHEEL;
                mouse_scroll(ScrollDirection.Down, ScrollDirection.Up, wParam);
            case MessageType.WM_MOUSEHWHEEL;
                mouse_scroll(ScrollDirection.Left, ScrollDirection.Right, wParam);
            case MessageType.WM_MOUSEMOVE; {
                x := lParam & 0xFFFF;
                y := (lParam & 0xFFFF0000) >> 16;
                x_pos, y_pos := convert_coordinates(x, y);
                handle_mouse_move(x_pos, y_pos);
            }
            case MessageType.WM_SIZE; {
                width: u32 = lParam & 0xFFFF;
                height: u32 = (lParam & 0xFFFF0000) >> 16;
                resize_window(width, height);
            }
            default;
                result = DefWindowProcA(handle, message, wParam, lParam);
        }

        return result;
    }

    mouse_button(PressState state, MouseButton button, u64 wParam, s64 lParam) {
        x := lParam & 0xFFFF;
        y := (lParam & 0xFFFF0000) >> 16;
        x_pos, y_pos := convert_coordinates(x, y);
        mod_code := convert_mouse_modcode(wParam);
        handle_mouse_button(state, button, mod_code, x_pos, y_pos);
    }

    mouse_scroll(ScrollDirection negative, ScrollDirection positive, u64 wParam) {
        mod_code := convert_mouse_modcode(wParam);
        if wParam & 0x80000000
            handle_mouse_scroll(negative, mod_code);
        else
            handle_mouse_scroll(positive, mod_code);
    }

    KeyCode convert_keycode(u8 char) {
        if char >= 'A' && char <= 'Z'
            return cast(KeyCode, char + 0x20);

        if char >= '0' && char <= '9'
            return cast(KeyCode, char);

        if char >= VK_F1 && char <= VK_F12
            return cast(KeyCode, char + 0x90);

        switch char {
            case VK_CONTROL;    return KeyCode.Control;
            case VK_SHIFT;      return KeyCode.Shift;
            case VK_MENU;       return KeyCode.Alt;
            case VK_UP;         return KeyCode.Up;
            case VK_DOWN;       return KeyCode.Down;
            case VK_LEFT;       return KeyCode.Left;
            case VK_RIGHT;      return KeyCode.Right;
            case VK_OEM_1;      return KeyCode.Semicolon;
            case VK_OEM_PLUS;   return KeyCode.Equals;
            case VK_OEM_COMMA;  return KeyCode.Comma;
            case VK_OEM_MINUS;  return KeyCode.Minus;
            case VK_OEM_PERIOD; return KeyCode.Period;
            case VK_OEM_2;      return KeyCode.ForwardSlash;
            case VK_OEM_3;      return KeyCode.Tick;
            case VK_OEM_4;      return KeyCode.OpenBracket;
            case VK_OEM_5;      return KeyCode.BackSlash;
            case VK_OEM_6;      return KeyCode.CloseBracket;
            case VK_OEM_7;      return KeyCode.Apostrophe;
            case VK_BACK;       return KeyCode.Backspace;
            case VK_TAB;        return KeyCode.Tab;
            case VK_RETURN;     return KeyCode.Enter;
            case VK_SPACE;      return KeyCode.Space;
            case VK_DELETE;     return KeyCode.Delete;
            case VK_ESCAPE;     return KeyCode.Escape;
        }

        return KeyCode.Unhandled;
    }

    ModCode convert_modcode(u64 lParam) {
        mod_code: ModCode;

        if lParam & 0x20000000         mod_code |= ModCode.Alt;
        if GetKeyState(VK_SHIFT) < 0   mod_code |= ModCode.Shift;
        if GetKeyState(VK_CONTROL) < 0 mod_code |= ModCode.Control;

        return mod_code;
    }

    ModCode convert_mouse_modcode(u64 wParam) {
        mod := cast(MouseButtonMod, wParam);
        mod_code: ModCode;

        if mod & MouseButtonMod.MK_SHIFT   mod_code |= ModCode.Shift;
        if mod & MouseButtonMod.MK_CONTROL mod_code |= ModCode.Control;
        if GetKeyState(VK_MENU) < 0        mod_code |= ModCode.Alt;

        return mod_code;
    }
}
