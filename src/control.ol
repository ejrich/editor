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

// Editing keybinds
[keybind, no_repeat]
normal_mode(ModCode mod) {
    edit_mode = EditMode.Normal;
}

[keybind, no_repeat]
visual_mode(ModCode mod) {
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
            visual_mode_data.line, visual_mode_data.cursor = get_current_position();
            buffer_window := get_current_window();
            if buffer_window {
                buffer_window.line = visual_mode_data.line;
                buffer_window.cursor = visual_mode_data.cursor;
            }
        }

        edit_mode = target_mode;
    }
}

[keybind, no_repeat]
insert(ModCode mod) {
    if mod & ModCode.Shift {
        move_to_line_boundary(false, true, false);
    }
    start_insert_mode(false);
}

[keybind, no_repeat]
append(ModCode mod) {
    if mod & ModCode.Shift {
        move_to_line_boundary(true, false, false);
    }
    start_insert_mode(true, 1);
}

[keybind, no_repeat]
substitute(ModCode mod) {
    if (mod & ModCode.Shift) == ModCode.Shift || edit_mode == EditMode.VisualLine {
        delete_lines();
    }
    else {
        delete_selected();
    }

    start_insert_mode(true);
}

[keybind]
open_line(ModCode mod) {
    // TODO Implement
}

[keybind]
change(ModCode mod) {
    // TODO Implement
}

// Movement keybinds
[keybind, no_repeat]
move_up(ModCode mod) {
    line_changes := get_repeats();
    move_line(true, key_command.command == KeyCommand.GoTo, line_changes);
}

[keybind, no_repeat]
move_down(ModCode mod) {
    line_changes := get_repeats();
    move_line(false, key_command.command == KeyCommand.GoTo, line_changes);
}

[keybind, no_repeat]
move_left(ModCode mod) {
    if mod == (ModCode.Shift | ModCode.Control) {
        switch_or_focus_buffer(SelectedWindow.Left);
        edit_mode = EditMode.Normal;
    }
    else if mod & ModCode.Control {
        if switch_to_buffer(SelectedWindow.Left) {
            edit_mode = EditMode.Normal;
        }
    }
    else {
        cursor_changes := get_repeats();
        move_cursor(true, cursor_changes);
    }
}

[keybind, no_repeat]
move_right(ModCode mod) {
    if mod == (ModCode.Shift | ModCode.Control) {
        switch_or_focus_buffer(SelectedWindow.Right);
        edit_mode = EditMode.Normal;
    }
    else if mod & ModCode.Control {
        if switch_to_buffer(SelectedWindow.Right) {
            edit_mode = EditMode.Normal;
        }
    }
    else {
        cursor_changes := get_repeats();
        move_cursor(false, cursor_changes);
    }
}

[keybind]
next_word(ModCode mod) {
    move_to_start_of_word(true, (mod & ModCode.Shift) == ModCode.Shift);
}

[keybind]
end_word(ModCode mod) {
    move_to_end_of_word((mod & ModCode.Shift) == ModCode.Shift);
}

[keybind]
previous_word(ModCode mod) {
    move_to_start_of_word(false, (mod & ModCode.Shift) == ModCode.Shift);
}

[keybind, no_repeat]
start_of_line(ModCode mod) {
    move_to_line_boundary(false, false, key_command.command == KeyCommand.GoTo);
}

[keybind, no_repeat]
start_of_line_text(ModCode mod) {
    move_to_line_boundary(false, true, false);
}

[keybind, no_repeat]
end_of_line(ModCode mod) {
    move_to_line_boundary(true, false, key_command.command == KeyCommand.GoTo);
}

[keybind, no_repeat]
next_line(ModCode mod) {
    line_changes := get_repeats();
    move_line(false, false, line_changes, true);
}

[keybind, no_repeat]
previous_line(ModCode mod) {
    line_changes := get_repeats();
    move_line(true, false, line_changes, true);
}

[keybind]
begin_sentence(ModCode mod) {
    move_block(false, false);
}

[keybind]
end_sentence(ModCode mod) {
    move_block(true, false);
}

[keybind]
begin_paragraph(ModCode mod) {
    move_block(false, true);
}

[keybind]
end_paragraph(ModCode mod) {
    move_block(true, true);
}

[keybind, no_repeat]
screen_half_up(ModCode mod) {
    half_screen := global_font_config.max_lines / 2;
    move_line(true, true, half_screen);
}

[keybind, no_repeat]
screen_half_down(ModCode mod) {
    half_screen := global_font_config.max_lines / 2;
    move_line(false, true, half_screen);
}

[keybind, no_repeat]
go_to(ModCode mod) {
    if mod & ModCode.Shift {
        go_to_line(-1);
    }
    else if key_command.command == KeyCommand.GoTo {
        go_to_line(0);
    }
    else {
        set_key_command(KeyCommand.GoTo, ModCode.None);
    }
}

[keybind, no_repeat]
find_char(ModCode mod) {
    set_key_command(KeyCommand.FindChar, mod);
}

[keybind, no_repeat]
until_char(ModCode mod) {
    set_key_command(KeyCommand.UntilChar, mod);
}

[keybind]
find(ModCode mod) {
    show_current_search_result();
    value := get_current_search();
    find_value_in_buffer(value, (mod & ModCode.Shift) != ModCode.Shift);
}

// Buffer keybinds
[keybind, no_repeat]
swap_buffer(ModCode mod) {
    swap_top_buffer();
}
