enum EditMode {
    Normal;
    Insert;
    Visual;
    VisualLine;
    VisualBlock;
}

edit_mode: EditMode;

[keybind]
bool normal_mode(PressState state, ModCode mod) {
    edit_mode = EditMode.Normal;
    return true;
}

[keybind]
bool visual_mode(PressState state, ModCode mod) {
    switch mod {
        case ModCode.Shift;
            edit_mode = EditMode.VisualLine;
        case ModCode.Control;
            edit_mode = EditMode.VisualBlock;
        default;
            edit_mode = EditMode.Visual;
    }
    return true;
}

[keybind]
bool insert(PressState state, ModCode mod) {
    // TODO Properly implement
    edit_mode = EditMode.Insert;
    return true;
}

[keybind]
bool append(PressState state, ModCode mod) {
    // TODO Properly implement
    edit_mode = EditMode.Insert;
    return true;
}

[keybind]
bool substitute(PressState state, ModCode mod) {
    // TODO Properly implement
    edit_mode = EditMode.Insert;
    return true;
}

[keybind]
bool move_up(PressState state, ModCode mod) {
    // TODO Properly implement with visual mode
    move_line(true);
    return true;
}

[keybind]
bool move_down(PressState state, ModCode mod) {
    // TODO Properly implement with visual mode
    move_line(false);
    return true;
}

[keybind]
bool move_left(PressState state, ModCode mod) {
    // TODO Properly implement with visual mode
    move_cursor(true);
    return true;
}

[keybind]
bool move_right(PressState state, ModCode mod) {
    // TODO Properly implement with visual mode
    move_cursor(false);
    return true;
}
