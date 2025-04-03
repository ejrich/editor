enum EditMode {
    Normal;
    Insert;
    Visual;
    VisualLine;
    VisualBlock;
}

edit_mode: EditMode;

struct VisualModeData {
    line: u32;
    cursor: u32;
}

visual_mode_data: VisualModeData;

enum KeyCommand {
    None;
    FindChar;
    UntilChar;
    GoTo;
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

reset_key_command() {
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

u32 get_repeats() {
    if key_command.repeats > 0
        return key_command.repeats;

    return 1;
}

bool handle_key_command(PressState state, KeyCode code, ModCode mod, string char) {
    if char.length == 0
        return false;

    switch key_command.command {
        case KeyCommand.FindChar; {
            find_character_in_line(!key_command.shifted, false, char);
            reset_key_command();
            return true;
        }
        case KeyCommand.UntilChar; {
            find_character_in_line(!key_command.shifted, true, char);
            reset_key_command();
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
    target_mode: EditMode;
    switch mod {
        case ModCode.Shift;
            target_mode = EditMode.VisualLine;
        case ModCode.Control;
            target_mode = EditMode.VisualBlock;
        default;
            target_mode = EditMode.Visual;
    }

    if target_mode == edit_mode {
        edit_mode = EditMode.Normal;
    }
    else {
        if edit_mode == EditMode.Normal {
            buffer_window := get_current_window();
            if buffer_window {
                visual_mode_data = {
                    line = buffer_window.line;
                    cursor = buffer_window.cursor;
                }
            }
        }

        edit_mode = target_mode;
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

[keybind, no_repeat]
bool substitute(PressState state, ModCode mod) {
    // TODO Properly implement
    edit_mode = EditMode.Insert;
    return true;
}

[keybind, no_repeat]
bool move_up(PressState state, ModCode mod) {
    line_changes := get_repeats();
    move_line(true, key_command.command == KeyCommand.GoTo, line_changes);
    return true;
}

[keybind, no_repeat]
bool move_down(PressState state, ModCode mod) {
    line_changes := get_repeats();
    move_line(false, key_command.command == KeyCommand.GoTo, line_changes);
    return true;
}

[keybind, no_repeat]
bool move_left(PressState state, ModCode mod) {
    if mod & ModCode.Control {
        switch_to_buffer(SelectedWindow.Left);
    }
    else {
        cursor_changes := get_repeats();
        move_cursor(true, cursor_changes);
    }
    return true;
}

[keybind, no_repeat]
bool move_right(PressState state, ModCode mod) {
    if mod & ModCode.Control {
        switch_to_buffer(SelectedWindow.Right);
    }
    else {
        cursor_changes := get_repeats();
        move_cursor(false, cursor_changes);
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

[keybind, no_repeat]
bool start_of_line(PressState state, ModCode mod) {
    move_to_line_boundary(false, false, key_command.command == KeyCommand.GoTo);
    return true;
}

[keybind, no_repeat]
bool start_of_line_text(PressState state, ModCode mod) {
    move_to_line_boundary(false, true, false);
    return true;
}

[keybind, no_repeat]
bool end_of_line(PressState state, ModCode mod) {
    move_to_line_boundary(true, false, key_command.command == KeyCommand.GoTo);
    return true;
}

[keybind, no_repeat]
bool next_line(PressState state, ModCode mod) {
    line_changes := get_repeats();
    move_line(false, false, line_changes, true);
    return true;
}

[keybind, no_repeat]
bool previous_line(PressState state, ModCode mod) {
    line_changes := get_repeats();
    move_line(true, false, line_changes, true);
    return true;
}

[keybind]
bool begin_sentence(PressState state, ModCode mod) {
    move_block(false, false);
    return true;
}

[keybind]
bool end_sentence(PressState state, ModCode mod) {
    move_block(true, false);
    return true;
}

[keybind]
bool begin_paragraph(PressState state, ModCode mod) {
    move_block(false, true);
    return true;
}

[keybind]
bool end_paragraph(PressState state, ModCode mod) {
    move_block(true, true);
    return true;
}

[keybind, no_repeat]
bool go_to(PressState state, ModCode mod) {
    if mod & ModCode.Shift {
        go_to_line(-1);
    }
    else if key_command.command == KeyCommand.GoTo {
        go_to_line(0);
    }
    else {
        set_key_command(KeyCommand.GoTo, ModCode.None);
    }
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
