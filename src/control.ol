enum EditMode {
    Normal;
    Insert;
    BlockInsert;
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
    Replace;
    ScrollTo;
    Quit;
}

struct KeyCommandData {
    command: KeyCommand;
    can_reset := true;
    shifted: bool;
    repeats: u32;
}

key_command: KeyCommandData;

set_key_command(KeyCommand command, ModCode mod) {
    reset_post_movement_command();

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

    result := false;

    switch key_command.command {
        case KeyCommand.FindChar; {
            find_character_in_line(!key_command.shifted, false, char);
            result = true;
        }
        case KeyCommand.UntilChar; {
            find_character_in_line(!key_command.shifted, true, char);
            result = true;
        }
        case KeyCommand.GoTo; {
            switch code {
                case KeyCode.C; {
                    change_selected_line_commenting();
                    result = true;
                }
            }
        }
        case KeyCommand.Replace; {
            replace_characters(char[0]);
            edit_mode = EditMode.Normal;
            result = true;
        }
        case KeyCommand.ScrollTo; {
            switch code {
                case KeyCode.T;
                    scroll_to_position(ScrollTo.Top);
                case KeyCode.Z;
                    scroll_to_position(ScrollTo.Middle);
                case KeyCode.B;
                    scroll_to_position(ScrollTo.Bottom);
            }

            result = true;
        }
        case KeyCommand.Quit; {
            switch code {
                case KeyCode.Q; {
                    close_window(false);
                }
                case KeyCode.Z; {
                    close_window(true);
                }
            }

            result = true;
        }
    }

    if result {
        reset_key_command();
    }

    return result;
}

enum PostMovementCommand {
    None;
    Change;
    Delete;
    Copy;
}

struct PostMovementCommandData {
    command: PostMovementCommand;
    start_line: u32;
    start_cursor: u32;
    changed_by_line: bool;
    include_end_cursor: bool;
}

post_movement_command: PostMovementCommandData;

set_post_movement_command(PostMovementCommand command) {
    reset_key_command();

    line, cursor := get_current_position();
    post_movement_command = {
        command = command;
        start_line = line;
        start_cursor = cursor;
        changed_by_line = false;
        include_end_cursor = false;
    }
}

handle_post_movement_command() {
    if post_movement_command.command == PostMovementCommand.None {
        return;
    }

    line, cursor := get_current_position();
    if post_movement_command.start_line == line && post_movement_command.start_cursor == cursor {
        return;
    }

    switch post_movement_command.command {
        case PostMovementCommand.Change; {
            if post_movement_command.changed_by_line {
                delete_lines(post_movement_command.start_line, line, false);
            }
            else {
                delete_selected(post_movement_command.start_line, post_movement_command.start_cursor, line, cursor, post_movement_command.include_end_cursor);
            }
            start_insert_mode(true);
        }
        case PostMovementCommand.Delete; {
            if post_movement_command.changed_by_line {
                delete_lines(post_movement_command.start_line, line, true);
            }
            else {
                delete_selected(post_movement_command.start_line, post_movement_command.start_cursor, line, cursor, post_movement_command.include_end_cursor);
            }
        }
        case PostMovementCommand.Copy; {
            if post_movement_command.changed_by_line {
                if line < post_movement_command.start_line {
                    copy_lines(line, post_movement_command.start_line);
                }
                else {
                    copy_lines(post_movement_command.start_line, line);
                }
            }
            else {
                copy_selected(post_movement_command.start_line, post_movement_command.start_cursor, line, cursor);
            }
        }
    }

    reset_post_movement_command();
}

reset_post_movement_command() {
    post_movement_command = {
        command = PostMovementCommand.None;
        start_line = 0;
        start_cursor = 0;
        changed_by_line = false;
        include_end_cursor = false;
    }
}

// Editing keybinds
[keybind, no_repeat]
command(ModCode mod) {
    start_command_mode();
}

[keybind, no_repeat]
search(ModCode mod) {
    start_search_mode();
}

[keybind, no_repeat]
normal_mode(ModCode mod) {
    record_change(pending_changes);
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

    reset_key_command();
    reset_post_movement_command();
}

[keybind, no_repeat]
insert(ModCode mod) {
    if mod & ModCode.Shift {
        switch edit_mode {
            case EditMode.Visual;
            case EditMode.VisualLine;
                move_to_visual_mode_boundary(false);
            case EditMode.VisualBlock; {
                init_block_insert_mode();
                move_to_visual_mode_boundary(false);
                start_block_insert_mode();
                return;
            }
            default;
                move_to_line_boundary(false, true, false);
        }
    }
    start_insert_mode(false);
}

[keybind, no_repeat]
append(ModCode mod) {
    if mod & ModCode.Shift {
        switch edit_mode {
            case EditMode.Visual;
            case EditMode.VisualLine;
                move_to_visual_mode_boundary(true);
            case EditMode.VisualBlock; {
                init_block_insert_mode();
                move_to_visual_mode_boundary(true);
                start_block_insert_mode();
                return;
            }
            default;
                move_to_line_boundary(true, false, false);
        }
    }
    start_insert_mode(true, 1);
}

[keybind, no_repeat]
substitute(ModCode mod) {
    if (mod & ModCode.Shift) == ModCode.Shift || edit_mode == EditMode.VisualLine {
        delete_lines(false);
    }
    else if edit_mode == EditMode.VisualBlock {
        init_block_insert_mode();
        delete_selected();
        start_block_insert_mode();
        return;
    }
    else {
        delete_selected();
    }

    start_insert_mode(true);
}

[keybind, no_repeat]
open_line(ModCode mod) {
    add_new_line((mod & ModCode.Shift) == ModCode.Shift);
    start_insert_mode(true);
}

[keybind, no_repeat]
change(ModCode mod) {
    if edit_mode == EditMode.Normal {
        if mod & ModCode.Shift {
            clear_remaining_line();
        }
        else {
            set_post_movement_command(PostMovementCommand.Change);
            return;
        }
    }
    else {
        if (mod & ModCode.Shift) == ModCode.Shift || edit_mode == EditMode.VisualLine {
            delete_lines(false);
        }
        else if edit_mode == EditMode.VisualBlock {
            init_block_insert_mode();
            delete_selected();
            start_block_insert_mode();
            return;
        }
        else {
            delete_selected();
        }
    }

    start_insert_mode(true);
}

[keybind, no_repeat]
delete_char(ModCode mod) {
    if edit_mode == EditMode.Normal {
        repeats := get_repeats();
        delete_cursor((mod & ModCode.Shift) == ModCode.Shift, repeats);
    }
    else {
        if (mod & ModCode.Shift) == ModCode.Shift || edit_mode == EditMode.VisualLine {
            delete_lines(true);
        }
        else {
            delete_selected();
        }

        edit_mode = EditMode.Normal;
    }
}

[keybind, no_repeat]
indent(ModCode mod) {
    indentations := get_repeats();
    change_indentation(true, indentations);
}

[keybind, no_repeat]
unindent(ModCode mod) {
    indentations := get_repeats();
    change_indentation(false, indentations);
}

[keybind, no_repeat]
delete(ModCode mod) {
    if edit_mode == EditMode.Normal {
        if mod & ModCode.Shift {
            clear_remaining_line();
            reset_post_movement_command();
        }
        else if post_movement_command.command == PostMovementCommand.Delete {
            line_changes := get_repeats();
            delete_lines(post_movement_command.start_line, post_movement_command.start_line + line_changes - 1, true);
            reset_post_movement_command();
        }
        else {
            set_post_movement_command(PostMovementCommand.Delete);
        }
    }
    else {
        if (mod & ModCode.Shift) == ModCode.Shift || edit_mode == EditMode.VisualLine {
            delete_lines(true);
        }
        else {
            delete_selected();
        }

        edit_mode = EditMode.Normal;
    }
}

[keybind, no_repeat]
replace(ModCode mod) {
    if mod & ModCode.Shift {
        start_replace_mode();
    }
    else {
        set_key_command(KeyCommand.Replace, mod);
    }
}

[keybind, no_repeat]
copy(ModCode mod) {
    if edit_mode == EditMode.Normal {
        if mod & ModCode.Shift {
            copy_remaining_line();
            reset_post_movement_command();
        }
        else if post_movement_command.command == PostMovementCommand.Copy {
            line_changes := get_repeats();
            copy_lines(post_movement_command.start_line, post_movement_command.start_line + line_changes - 1);
            reset_post_movement_command();
        }
        else {
            set_post_movement_command(PostMovementCommand.Copy);
        }
    }
    else {
        if (mod & ModCode.Shift) == ModCode.Shift || edit_mode == EditMode.VisualLine {
            copy_selected_lines();
        }
        else {
            copy_selected();
        }

        edit_mode = EditMode.Normal;
    }
}

[keybind, no_repeat]
paste(ModCode mod) {
    reset_key_command();
    reset_post_movement_command();

    if edit_mode == EditMode.Normal {
        paste_by_cursor((mod & ModCode.Shift) == ModCode.Shift);
    }
    else {
        paste_over_selected();
        edit_mode = EditMode.Normal;
    }
}

[keybind, no_repeat]
scroll_to(ModCode mod) {
    set_key_command(KeyCommand.ScrollTo, mod);
}

[keybind, no_repeat]
quit(ModCode mod) {
    set_key_command(KeyCommand.Quit, mod);
}

// Movement keybinds
[keybind, no_repeat]
move_up(ModCode mod) {
    if edit_mode == EditMode.BlockInsert {
        edit_mode = EditMode.Insert;
    }

    post_movement_command.changed_by_line = true;
    line_changes := get_repeats();
    move_line(true, key_command.command == KeyCommand.GoTo, line_changes);
}

[keybind, no_repeat]
move_down(ModCode mod) {
    if edit_mode == EditMode.BlockInsert {
        edit_mode = EditMode.Insert;
    }

    line_changes := get_repeats();
    if mod & ModCode.Shift {
        join_lines(line_changes);
    }
    else {
        post_movement_command.changed_by_line = true;
        move_line(false, key_command.command == KeyCommand.GoTo, line_changes);
    }
}

[keybind, no_repeat]
move_left(ModCode mod) {
    if mod == (ModCode.Shift | ModCode.Control) {
        switch_or_focus_buffer(SelectedWindow.Left);
    }
    else if mod & ModCode.Control {
        switch_to_buffer(SelectedWindow.Left);
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
    }
    else if mod & ModCode.Control {
        switch_to_buffer(SelectedWindow.Right);
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
    post_movement_command.include_end_cursor = true;
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
syntax_match(ModCode mod) {
    move_to_syntax_match();
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
    post_movement_command.include_end_cursor = true;
    set_key_command(KeyCommand.FindChar, mod);
}

[keybind, no_repeat]
until_char(ModCode mod) {
    post_movement_command.include_end_cursor = true;
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

    reset_key_command();
    reset_post_movement_command();
}

[keybind, no_repeat]
jump_back(ModCode mod) {
    jumps := get_repeats();
    go_to_jump(false, jumps);
}

[keybind, no_repeat]
jump_forward(ModCode mod) {
    jumps := get_repeats();
    go_to_jump(true, jumps);
}

[keybind, no_repeat]
undo(ModCode mod) {
    changes := get_repeats();
    apply_changes(false, changes);
}

[keybind, no_repeat]
redo(ModCode mod) {
    changes := get_repeats();
    apply_changes(true, changes);
}
