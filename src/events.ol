handle_window_resize() {
    log("Window resized to %x%\n", settings.window_width, settings.window_height);
    if !graphics_initialized return;

    recreate_swap_chain();
    resize_font_glyphs();
    resize_buffers();
}

handle_key_event(PressState state, KeyCode code, ModCode mod, string char) {
    // log("Key % is % with mod %!\n", code, state, mod);

    if state & PressState.Down {
        if edit_mode == EditMode.Insert {
            switch code {
                case KeyCode.Backspace; {
                    delete_from_cursor(true);
                    return;
                }
                case KeyCode.Tab; {
                    tab_array: Array<u8>[settings.tab_size];
                    each space in tab_array {
                        space = ' ';
                    }
                    tab_string: string = { length = tab_array.length; data = tab_array.data; }
                    add_text_to_line(tab_string);
                    return;
                }
                case KeyCode.Enter; {
                    add_new_line(false, true);
                    return;
                }
                case KeyCode.Delete; {
                    delete_from_cursor(false);
                    return;
                }
            }

            if cast(u32, code) >= ' ' && char.length > 0 {
                add_text_to_line(char);
                return;
            }
        }

        if handle_command_press(state, code, mod, char) return;

        if handle_key_command(state, code, mod, char) return;

        switch code {
            case KeyCode.Escape; {
                if mod & ModCode.Shift {
                    signal_shutdown();
                    return;
                }
            }
            case KeyCode.Zero; {
                if mod == ModCode.None && key_command.repeats > 0 {
                    add_repeats(code);
                    return;
                }
            }
            case KeyCode.One;
            case KeyCode.Two;
            case KeyCode.Three;
            case KeyCode.Four;
            case KeyCode.Five;
            case KeyCode.Six;
            case KeyCode.Seven;
            case KeyCode.Eight;
            case KeyCode.Nine; {
                if mod == ModCode.None {
                    add_repeats(code);
                    return;
                }
            }
            case KeyCode.ForwardSlash; {
                if (state & PressState.Held) != PressState.Held {
                    start_search_mode();
                    return;
                }
            }
            case KeyCode.Colon; {
                if (state & PressState.Held) != PressState.Held {
                    start_command_mode();
                    return;
                }
            }
            case KeyCode.F12; {
                if (state & PressState.Held) != PressState.Held {
                    toggle_performance_stats(mod == ModCode.Control);
                    return;
                }
            }
            case KeyCode.Up; {
                move_up(mod);
                return;
            }
            case KeyCode.Down; {
                move_down(mod);
                return;
            }
            case KeyCode.Left; {
                move_left(mod);
                return;
            }
            case KeyCode.Right; {
                move_right(mod);
                return;
            }
        }

        handle_keybind_event(code, mod);
    }
}

handle_mouse_move(float x, float y) {
    // log("Mouse location %, %\n", x, y);
}

handle_mouse_scroll(ScrollDirection direction, ModCode mod) {
    // log("Scrolling % with mod %\n", direction, mod);
    handle_buffer_scroll(direction);
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
    Exclamation  = 0x21;
    Quotation    = 0x22;
    Pound        = 0x23;
    Dollar       = 0x24;
    Percent      = 0x25;
    Ampersand    = 0x26;
    Apostrophe   = 0x27;
    OpenParen    = 0x28;
    CloseParen   = 0x29;
    Star         = 0x2A;
    Plus         = 0x2B;
    Comma        = 0x2C;
    Minus        = 0x2D;
    Period       = 0x2E;
    ForwardSlash = 0x2F;
    Colon        = 0x3A;
    Semicolon    = 0x3B;
    LessThan     = 0x3C;
    Equals       = 0x3D;
    GreaterThan  = 0x3E;
    Question     = 0x3F;
    At           = 0x40;
    OpenBracket  = 0x5B;
    BackSlash    = 0x5C;
    CloseBracket = 0x5D;
    Caret        = 0x5E;
    Underscore   = 0x5F;
    Tick         = 0x60;
    OpenBrace    = 0x7B;
    Pipe         = 0x7C;
    CloseBrace   = 0x7D;
    Tilde        = 0x7E;

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
