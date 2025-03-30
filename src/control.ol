enum EditMode {
    Normal;
    Insert;
    Visual;
    VisualLine;
    VisualBlock;
}

edit_mode: EditMode;

enum KeyCommand {
    None;
    FindChar;
    UntilChar;
}

struct KeyCommandData {
    command: KeyCommand;
    can_reset := true;
    shifted: bool;
    repeats: u32;
}

key_command: KeyCommandData;

set_key_command(KeyCommand command, ModCode mod) {
    key_command = {
        command = command;
        can_reset = false;
        shifted = (mod & ModCode.Shift) == ModCode.Shift;
        repeats = 0;
    }
}

reset_key_command(bool force = false) {
    if key_command.can_reset {
        key_command = {
            command = KeyCommand.None;
            shifted = false;
            repeats = 0;
        }
    }
    key_command.can_reset = true;
}

add_repeats(KeyCode code) {
    key_command.repeats *= 10;
    key_command.repeats += cast(u32, code) - '0';
}

bool handle_key_command(PressState state, KeyCode code, ModCode mod, string char) {
    if char.length == 0
        return false;

    switch key_command.command {
        case KeyCommand.FindChar; {
            find_character_in_line(!key_command.shifted, false, char);
            reset_key_command(true);
            return true;
        }
        case KeyCommand.UntilChar; {
            find_character_in_line(!key_command.shifted, true, char);
            reset_key_command(true);
            return true;
        }
    }

    return false;
}

[keybind, no_repeat]
bool normal_mode(PressState state, ModCode mod) {
    edit_mode = EditMode.Normal;
    return true;
}

[keybind, no_repeat]
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

[keybind, no_repeat]
bool insert(PressState state, ModCode mod) {
    // TODO Properly implement
    edit_mode = EditMode.Insert;
    return true;
}

[keybind, no_repeat]
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
    move_to_end_of_word((mod & ModCode.Shift) == ModCode.Shift);
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

[keybind, no_repeat]
bool go_to(PressState state, ModCode mod) {
    // TODO Implement me
    return true;
}

[keybind, no_repeat]
bool find_char(PressState state, ModCode mod) {
    set_key_command(KeyCommand.FindChar, mod);
    return true;
}

[keybind, no_repeat]
bool until_char(PressState state, ModCode mod) {
    set_key_command(KeyCommand.UntilChar, mod);
    return true;
}
