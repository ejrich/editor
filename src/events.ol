handle_window_resize() {
    log("Window resized to %x%\n", settings.window_width, settings.window_height);
    if !graphics_initialized return;

    recreate_swap_chain();
    resize_font_glyphs();
}

handle_key_event(PressState state, KeyCode code, ModCode mod, string char) {
    // log("Key % is % with mod %!\n", code, state, mod);

    if state & PressState.Down {
        #if DEVELOPER {
            if handle_command_prompt_press(state, code, mod, char) return;
        }

        if code == KeyCode.Escape {
            if mod & ModCode.Shift signal_shutdown();
            return;
        }

        switch code {
            case KeyCode.F12; {
                if (state & PressState.Held) != PressState.Held {
                    toggle_performance_stats(mod == ModCode.Control);
                    return;
                }
            }
            case KeyCode.Tick; {
                #if DEVELOPER {
                    if (state & PressState.Held) != PressState.Held {
                        toggle_command_prompt();
                        return;
                    }
                }
            }
        }
    }

    handle_keybind_event(code, state, mod);
}

handle_mouse_move(float x, float y) {
    // log("Mouse location %, %\n", x, y);
}

handle_mouse_scroll(ScrollDirection direction, ModCode mod) {
    // log("Scrolling % with mod %\n", direction, mod);
}

handle_mouse_button(PressState state, MouseButton button, ModCode mod, float x, float y) {
    // log("Mouse button % is % with mod % at (%, %)\n", button, state, mod, x, y);

    if state == PressState.Down {
    }
    else if state == PressState.Up {
    }
}

[flags]
enum PressState {
    Down = 0x1;
    Held = 0x2;
    Up   = 0x4;
}

enum ScrollDirection {
    Up;
    Down;
    Left;
    Right;
}

enum KeyCode {
    Unhandled;

    // Numbers
    Zero  = 0x30;
    One   = 0x31;
    Two   = 0x32;
    Three = 0x33;
    Four  = 0x34;
    Five  = 0x35;
    Six   = 0x36;
    Seven = 0x37;
    Eight = 0x38;
    Nine  = 0x39;

    // Letters
    A = 0x61;
    B = 0x62;
    C = 0x63;
    D = 0x64;
    E = 0x65;
    F = 0x66;
    G = 0x67;
    H = 0x68;
    I = 0x69;
    J = 0x6A;
    K = 0x6B;
    L = 0x6C;
    M = 0x6D;
    N = 0x6E;
    O = 0x6F;
    P = 0x70;
    Q = 0x71;
    R = 0x72;
    S = 0x73;
    T = 0x74;
    U = 0x75;
    V = 0x76;
    W = 0x77;
    X = 0x78;
    Y = 0x79;
    Z = 0x7A;

    // Characters
    Apostrophe   = 0x27;
    Comma        = 0x2C;
    Minus        = 0x2D;
    Period       = 0x2E;
    ForwardSlash = 0x2F;
    Semicolon    = 0x3B;
    Equals       = 0x3D;
    OpenBracket  = 0x5B;
    BackSlash    = 0x5C;
    CloseBracket = 0x5D;
    Tick         = 0x60;

    // Function Row
    Escape = 0x1B;
    F1     = 0x100;
    F2     = 0x101;
    F3     = 0x102;
    F4     = 0x103;
    F5     = 0x104;
    F6     = 0x105;
    F7     = 0x106;
    F8     = 0x107;
    F9     = 0x108;
    F10    = 0x109;
    F11    = 0x10A;
    F12    = 0x10B;

    // Modifier Keys
    Control  = 0x110;
    Shift    = 0x111;
    Alt      = 0x112;

    // Whitespace
    Backspace = 0x8;
    Tab       = 0x9;
    Enter     = 0xD;
    Space     = 0x20;
    Delete    = 0xFF;

    // Directions
    Up    = 0x120;
    Down  = 0x121;
    Left  = 0x122;
    Right = 0x123;
}

[flags]
enum ModCode {
    None    = 0;
    Shift   = 0x1;
    Control = 0x2;
    Alt     = 0x4;
}

enum MouseButton {
    Left    = 1;
    Middle  = 2;
    Right   = 3;
    Button4 = 4;
    Button5 = 5;
}
