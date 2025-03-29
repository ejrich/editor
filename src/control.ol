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
    if mod & ModCode.Control {
        switch_to_buffer(SelectedWindow.Left);
    }
    else {
        move_cursor(true);
    }
    return true;
}

[keybind]
bool move_right(PressState state, ModCode mod) {
    // TODO Properly implement with visual mode
    if mod & ModCode.Control {
        switch_to_buffer(SelectedWindow.Right);
    }
    else {
        move_cursor(false);
    }
    return true;
}

[keybind]
bool next_word(PressState state, ModCode mod) {
    move_to_start_of_word(true, (mod & ModCode.Shift) == ModCode.Shift);
    return true;
}

[keybind]
bool end_word(PressState state, ModCode mod) {
    // TODO Implement me
    return true;
}

[keybind]
bool previous_word(PressState state, ModCode mod) {
    move_to_start_of_word(false, (mod & ModCode.Shift) == ModCode.Shift);
    return true;
}

[keybind]
bool start_of_line(PressState state, ModCode mod) {
    move_to_line_boundary(false);
    return true;
}

[keybind]
bool end_of_line(PressState state, ModCode mod) {
    move_to_line_boundary(true);
    return true;
}

[keybind]
bool begin_paragraph(PressState state, ModCode mod) {
    move_paragraph(false);
    return true;
}

[keybind]
bool end_paragraph(PressState state, ModCode mod) {
    move_paragraph(true);
    return true;
}

[keybind]
bool go_to(PressState state, ModCode mod) {
    // TODO Implement me
    return true;
}

[keybind]
bool find_char(PressState state, ModCode mod) {
    // TODO Implement me
    return true;
}

[keybind]
bool until_char(PressState state, ModCode mod) {
    // TODO Implement me
    return true;
}
