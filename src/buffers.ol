// Buffer rendering
draw_buffers() {
    if !is_font_ready(settings.font_size) return;

    workspace := get_workspace();

    bottom_window, bottom_focused := get_bottom_window(workspace);

    if workspace.left_window.displayed && workspace.right_window.displayed {
        draw_divider(bottom_window == null);
    }

    if workspace.left_window.displayed {
        draw_buffer_window(workspace, workspace.left_window.buffer_window, -1.0, workspace.current_window == SelectedWindow.Left && !bottom_focused, !workspace.right_window.displayed, false);
    }

    if workspace.right_window.displayed {
        x := 0.0;
        if !workspace.left_window.displayed {
            x = -1.0;
        }
        draw_buffer_window(workspace, workspace.right_window.buffer_window, x, workspace.current_window == SelectedWindow.Right && !bottom_focused, !workspace.left_window.displayed, false);
    }

    if bottom_window {
        draw_buffer_window(workspace, bottom_window, -1.0, bottom_focused, true, true);
    }

    draw_command();
}

draw_divider(bool full_height) {
    divider_quad: QuadInstanceData = {
        color = appearance.font_color;
        flags = QuadFlags.Solid;
        width = 1.0 / settings.window_width;
    }

    if full_height {
        divider_quad = {
            position = { y = global_font_config.divider_y; }
            height = global_font_config.divider_height;
        }
    }
    else {
        divider_quad = {
            position = { y = global_font_config.divider_y_with_bottom_window; }
            height = global_font_config.divider_height_with_bottom_window;
        }
    }

    draw_quad(&divider_quad, 1);
}

draw_buffer_window(Workspace* workspace, BufferWindow* window, float x, bool selected, bool full_width, bool is_run_window) {
    if window == null {
        window = &scratch_window;
    }

    line_max_x := x + 1.0;
    if full_width line_max_x += 1.0;

    initial_y := 1.0 - global_font_config.first_line_offset;

    max_lines, _ := determine_max_lines_and_scroll_offset(window);
    if is_run_window {
        initial_y -= global_font_config.line_height * (global_font_config.max_lines_with_bottom_window + 1);
    }

    info_quad: QuadInstanceData = {
        color = appearance.current_line_color;
        position = {
            x = (x + line_max_x) / 2;
            y = initial_y - max_lines * global_font_config.line_height + global_font_config.block_y_offset;
            z = 0.2;
        }
        flags = QuadFlags.Solid;
        width = line_max_x - x;
        height = global_font_config.line_height;
    }

    draw_quad(&info_quad, 1);

    buffer: Buffer;
    if window.buffer_index >= 0 {
        buffer = workspace.buffers[window.buffer_index];
    }
    else if window.static_buffer {
        buffer = *window.static_buffer;
    }
    else {
        return;
    }

    if appearance.background_color.w != 1.0 {
        line_background_quad: QuadInstanceData = {
            color = {
                x = appearance.background_color.x;
                y = appearance.background_color.y;
                z = appearance.background_color.z;
                w = 1.0;
            }
            position = {
                x = x + global_font_config.quad_advance * buffer.line_count_digits / 2.0;
                y = initial_y + global_font_config.first_line_offset - global_font_config.line_height * max_lines / 2.0 - global_font_config.line_height;
                z = 0.4;
            }
            flags = QuadFlags.Solid;
            width = global_font_config.quad_advance * buffer.line_count_digits;
            height = global_font_config.line_height * max_lines;
        }

        draw_quad(&line_background_quad, 1);
    }

    line := buffer.lines;
    line_number: u32 = 1;
    line_cursor: u32;
    cursor_line: u32 = clamp(window.line, 0, buffer.line_count - 1) + 1;
    available_lines_to_render := max_lines;
    y := initial_y;

    if window.hex_view {
        byte_line: Array<u8>[bytes_per_line];

        bytes := 0;
        byte_column := 0;
        cursor_column := -1;
        while line != null && available_lines_to_render > 0 {
            line_has_cursor := false;
            if line_number == cursor_line {
                line_has_cursor = true;
                line_cursor = clamp(window.cursor, 0, line.length);
            }

            if line.length {
                each i in clamp(line.length, 0, line_buffer_length) {
                    if !add_byte_to_line(line.data.data[i], &bytes, byte_line, &byte_column, x, &y, &available_lines_to_render, window.start_byte, line_has_cursor && i == line_cursor, &cursor_column)
                        break;
                }

                child := line.child;
                start := line_buffer_length;
                while child != null && available_lines_to_render > 0 {
                    each i in child.length {
                        if !add_byte_to_line(child.data.data[i], &bytes, byte_line, &byte_column, x, &y, &available_lines_to_render, window.start_byte, line_has_cursor && i + start == line_cursor, &cursor_column)
                            break;
                    }

                    child = child.next;
                    start += line_buffer_length;
                }
            }

            if line.next {
                add_byte_to_line('\n', &bytes, byte_line, &byte_column, x, &y, &available_lines_to_render, window.start_byte, line_has_cursor && line_cursor == line.length, &cursor_column);
            }

            line = line.next;
            line_number++;
        }

        if available_lines_to_render > 0 && byte_column > 0 {
            draw_byte_line(bytes, byte_line, byte_column, cursor_column, x, y);
        }
    }
    else {
        start_line := clamp(window.start_line, 0, buffer.line_count - 1);
        digits := buffer.line_count_digits;

        visual_start_line, visual_end_line := -1;
        if selected {
            switch edit_mode {
                case EditMode.Visual;
                case EditMode.VisualLine;
                case EditMode.VisualBlock; {
                    visual_start_line = visual_mode_data.line + 1;
                    visual_end_line = cursor_line;
                    if cursor_line <= visual_mode_data.line {
                        visual_start_line = cursor_line;
                        visual_end_line = visual_mode_data.line + 1;
                    }
                }
            }
        }

        // Render the file text
        render_line_state := init_render_line_state(&buffer);
        while line != null && available_lines_to_render > 0 {
            if line_number > start_line {
                cursor, visual_start, visual_end := -1;

                if window == get_terminal_window(workspace) &&
                    !workspace.terminal_data.running &&
                    workspace.terminal_data.writing &&
                    line_number == workspace.terminal_data.command_line_index + 1 {
                    cursor = workspace.terminal_data.command_write_cursor;
                }
                else if line_number == cursor_line ||
                    (edit_mode == EditMode.BlockInsert &&
                    line_number >= (block_insert_data.start_line + 1) &&
                    line_number <= (block_insert_data.end_line + 1)) {
                    cursor = window.cursor;

                    if line.length == 0 {
                        if edit_mode == EditMode.BlockInsert && cursor > 0 {
                            cursor = -1;
                        }
                        else {
                            cursor = 0;
                        }
                    }
                    else if cursor >= line.length {
                        if edit_mode == EditMode.BlockInsert {
                            cursor = -1;
                        }
                        else if edit_mode != EditMode.Normal {
                            cursor = line.length;
                        }
                        else {
                            cursor = line.length - 1;
                        }
                    }

                    line_cursor = cursor;
                }

                if line_number >= visual_start_line && line_number <= visual_end_line {
                    visual_start = 0;
                    visual_end = line.length - 1;
                    switch edit_mode {
                        case EditMode.Visual; {
                            if visual_start_line == visual_end_line {
                                if cursor > visual_mode_data.cursor {
                                    visual_start = visual_mode_data.cursor;
                                    visual_end = cursor;
                                }
                                else {
                                    visual_start = cursor;
                                    visual_end = visual_mode_data.cursor;
                                }
                            }
                            else if line_number == visual_start_line {
                                if cursor == -1 {
                                    visual_start = visual_mode_data.cursor;
                                }
                                else {
                                    visual_start = cursor;
                                }
                            }
                            else if line_number == visual_end_line {
                                if cursor == -1 {
                                    visual_end = visual_mode_data.cursor;
                                }
                                else {
                                    visual_end = cursor;
                                }
                            }
                        }
                        case EditMode.VisualBlock; {
                            if window.cursor > visual_mode_data.cursor {
                                visual_start = visual_mode_data.cursor;
                                visual_end = window.cursor;
                            }
                            else {
                                visual_start = window.cursor;
                                visual_end = visual_mode_data.cursor;
                            }
                        }
                    }
                }

                lines := render_line(&render_line_state, line, x, y, line_number, digits, cursor, selected, line_max_x, available_lines_to_render, visual_start, visual_end);
                y -= global_font_config.line_height * lines;
                available_lines_to_render -= lines;
            }
            else {
                evaluate_line_without_rendering(&render_line_state, line, line_number);
            }

            line = line.next;
            line_number++;
        }
    }

    // Render the file information
    y = initial_y - global_font_config.line_height * max_lines;
    highlight_color: Vector4;
    if selected {
        mode_string := empty_string;
        switch edit_mode {
            case EditMode.Normal; {
                highlight_color = appearance.normal_mode_color;
                mode_string = " NORMAL ";
            }
            case EditMode.Insert;
            case EditMode.BlockInsert; {
                highlight_color = appearance.insert_mode_color;
                mode_string = " INSERT ";
            }
            case EditMode.Visual; {
                highlight_color = appearance.visual_mode_color;
                mode_string = " VISUAL ";
            }
            case EditMode.VisualLine; {
                highlight_color = appearance.visual_mode_color;
                mode_string = " V-LINE ";
            }
            case EditMode.VisualBlock; {
                highlight_color = appearance.visual_mode_color;
                mode_string = " V-BLOCK ";
            }
        }

        if current_command_mode == CommandMode.Command {
            mode_string = " COMMAND ";
        }

        if workspace.terminal_data.writing {
            highlight_color = appearance.insert_mode_color;
            mode_string = " TERMINAL ";
        }

        if window.hex_view {
            highlight_color = appearance.normal_mode_color;
            mode_string = " HEX ";
        }

        render_text(mode_string, settings.font_size, x, y, appearance.font_color, highlight_color);
        x += mode_string.length * global_font_config.quad_advance;
    }

    title := buffer.relative_path;
    if buffer.title != null {
        title = buffer.title();
    }

    render_text(title, settings.font_size, x + global_font_config.quad_advance, y, appearance.font_color, vec4());

    render_text(settings.font_size, line_max_x, y, appearance.font_color, highlight_color, " %/% % ", TextAlignment.Right, cursor_line, buffer.line_count, line_cursor + 1);
}

// Opening buffers with files
BufferWindow* open_file_buffer(string path, bool allocate_path) {
    buffer_index := -1;
    workspace := get_workspace();

    each buffer, i in workspace.buffers {
        if buffer.relative_path == path {
            buffer_index = i;
            break;
        }
    }

    if buffer_index < 0 {
        if allocate_path {
            allocate_strings(&path);
        }

        buffer: Buffer = {
            path_allocated = allocate_path;
            relative_path = path;
            syntax = get_syntax_for_file(path);
        }

        found, file := read_file(path, temp_allocate);
        if found {
            line := allocate_line();
            buffer = { line_count = 1; lines = line; }

            tab := create_empty_string(settings.tab_size);

            add_new_line := false;
            each i in file.length {
                char := file[i];
                if add_new_line {
                    next_line := allocate_line();
                    buffer.line_count++;
                    line.next = next_line;
                    next_line.previous = line;
                    line = next_line;
                    add_new_line = false;
                }

                if char == '\n' {
                    add_new_line = true;
                }
                else if char == '\t' {
                    add_text_to_line(line, tab, line.length);
                }
                else {
                    char_string: string = { length = 1; data = &char; }
                    add_text_to_line(line, char_string, line.length);
                }
            }

            calculate_line_digits(&buffer);
        }

        array_insert(&workspace.buffers, buffer, allocate, reallocate);
        buffer_index = workspace.buffers.length - 1;
    }

    buffer_window: BufferWindow*;
    switch workspace.current_window {
        case SelectedWindow.Left; {
            record_jump(workspace.left_window.buffer_window);
            workspace.left_window.buffer_window = open_or_create_buffer_window(buffer_index, workspace.left_window.buffer_window);
            buffer_window = workspace.left_window.buffer_window;
        }
        case SelectedWindow.Right; {
            record_jump(workspace.right_window.buffer_window);
            workspace.right_window.buffer_window = open_or_create_buffer_window(buffer_index, workspace.right_window.buffer_window);
            buffer_window = workspace.right_window.buffer_window;
        }
    }
    workspace.bottom_window_selected = false;

    return buffer_window;
}

switch_or_focus_buffer(SelectedWindow window) {
    workspace := get_workspace();

    if window != workspace.current_window {
        switch_to_buffer(window);
        return;
    }

    switch window {
        case SelectedWindow.Left; {
            workspace.right_window.displayed = false;
        }
        case SelectedWindow.Right; {
            workspace.left_window.displayed = false;
        }
    }
}

switch_to_buffer(SelectedWindow window) {
    workspace := get_workspace();
    if window == workspace.current_window return;

    original_window, new_window: EditorWindow*;
    switch window {
        case SelectedWindow.Left; {
            original_window = &workspace.right_window;
            new_window = &workspace.left_window;
        }
        case SelectedWindow.Right; {
            original_window = &workspace.left_window;
            new_window = &workspace.right_window;
        }
    }

    assert(original_window != null && new_window != null);

    if !new_window.displayed {
        if new_window.buffer_window == null
            new_window.buffer_window = copy_buffer_window_stack(original_window.buffer_window);
        new_window.displayed = true;
    }

    reset_key_command();
    reset_post_movement_command();
    edit_mode = EditMode.Normal;
    workspace.bottom_window_selected = false;

    workspace.current_window = window;
}

toggle_bottom_buffer_selection(bool selected) {
    workspace := get_workspace();
    if get_run_window(workspace) != null || get_terminal_window(workspace) != null {
        workspace.bottom_window_selected = selected;
    }
}

swap_top_buffer() {
    workspace := get_workspace();
    editor_window: EditorWindow*;
    switch workspace.current_window {
        case SelectedWindow.Left;
            editor_window = &workspace.left_window;
        case SelectedWindow.Right;
            editor_window = &workspace.right_window;
    }

    record_jump(editor_window.buffer_window);

    if editor_window.buffer_window != null && editor_window.buffer_window.next != null {
        swap_from := editor_window.buffer_window;
        swap_to := editor_window.buffer_window.next;

        if swap_to.next {
            swap_to.next.previous = swap_from;
        }

        swap_from.next = swap_to.next;
        swap_from.previous = swap_to;
        swap_to.next = swap_from;
        swap_to.previous = null;

        editor_window.buffer_window = swap_to;
    }
}

set_current_location(s32 buffer_index, u32 line, u32 cursor) {
    workspace := get_workspace();

    buffer_window: BufferWindow*;
    switch workspace.current_window {
        case SelectedWindow.Left; {
            workspace.left_window.buffer_window = open_or_create_buffer_window(buffer_index, workspace.left_window.buffer_window);
            buffer_window = workspace.left_window.buffer_window;
        }
        case SelectedWindow.Right; {
            workspace.right_window.buffer_window = open_or_create_buffer_window(buffer_index, workspace.right_window.buffer_window);
            buffer_window = workspace.right_window.buffer_window;
        }
    }

    buffer_window.line = line;
    buffer_window.cursor = cursor;
    adjust_start_line(buffer_window);
}

close_window(bool save) {
    workspace := get_workspace();

    editor_window, other_window: EditorWindow*;
    switch workspace.current_window {
        case SelectedWindow.Left; {
            editor_window = &workspace.left_window;
            other_window = &workspace.right_window;
            workspace.current_window = SelectedWindow.Right;
        }
        case SelectedWindow.Right; {
            editor_window = &workspace.right_window;
            other_window = &workspace.left_window;
            workspace.current_window = SelectedWindow.Left;
        }
    }

    clear_jumps(&editor_window.current_jump);

    buffer_window := editor_window.buffer_window;
    while buffer_window {
        if save {
            save_buffer(buffer_window.buffer_index);
        }

        next := buffer_window.next;
        free_allocation(buffer_window);
        buffer_window = next;
    }

    editor_window.buffer_window = null;
    editor_window.displayed = false;

    if !other_window.displayed {
        result := close_current_workspace(true, true);
        if result == CloseWorkspaceResult.NoWorkspacesActive {
            signal_shutdown();
        }
    }
}

// Saving buffers to a file
bool, u32, u32, string save_buffer(int buffer_index) {
    workspace := get_workspace();
    if buffer_index < 0 || buffer_index >= workspace.buffers.length
        return true, 0, 0, empty_string;

    lines_written, bytes_written: u32;
    buffer := &workspace.buffers[buffer_index];
    buffer.has_changes = false;

    create_directories_recursively(buffer.relative_path);
    opened, file := open_file(buffer.relative_path, FileFlags.Create);
    if !opened return false, 0, 0, buffer.relative_path;

    defer close_file(file);

    line := buffer.lines;
    while line {
        // Trim the whitespace from the current line
        if trim_line(line) {
            // If the line is now empty, find the next line that is not empty
            //   If there is not a next line, free the remaining lines and break
            //   If there is a next line, go to that line and zero out the lines on the way
            next_line_with_text := get_next_line_with_text(line);
            if next_line_with_text {
                while line != next_line_with_text {
                    write_to_file(file, '\n');
                    lines_written++;
                    bytes_written++;
                    line = line.next;
                }
            }
            else {
                next_line := line.next;
                line.next = null;

                if line.previous != null {
                    line.previous.next = null;
                    free_allocation(line);
                    buffer.line_count--;
                }

                while next_line {
                    next_next_line := next_line.next;
                    free_allocation(next_line);
                    next_line = next_next_line;
                    buffer.line_count--;
                }

                calculate_line_digits(buffer);
                break;
            }
        }
        // Write the line to the file, and go to the next
        else {
            write_buffer_to_file(file, line.data.data, line.length);
            write_to_file(file, '\n');
            lines_written++;
            bytes_written += line.length + 1;
            line = line.next;
        }
    }

    return true, lines_written, bytes_written, buffer.relative_path;
}

// Visual mode helpers
u32, u32 get_visual_start_and_end_lines(BufferWindow* buffer_window) {
    start_line, end_line: u32;
    if visual_mode_data.line > buffer_window.line {
        start_line = buffer_window.line;
        end_line = visual_mode_data.line;
    }
    else {
        start_line = visual_mode_data.line;
        end_line = buffer_window.line;
    }

    return start_line, end_line;
}

u32, u32 get_visual_start_and_end_cursors(BufferWindow* buffer_window) {
    start_cursor, end_cursor: u32;
    if visual_mode_data.cursor > buffer_window.cursor {
        start_cursor = buffer_window.cursor;
        end_cursor = visual_mode_data.cursor;
    }
    else {
        start_cursor = visual_mode_data.cursor;
        end_cursor = buffer_window.cursor;
    }

    return start_cursor, end_cursor;
}

move_to_visual_mode_boundary(bool end) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
        return;
    }

    _: u32;
    switch edit_mode {
        case EditMode.Visual; {
            if buffer_window.line == visual_mode_data.line {
                if end {
                    if buffer_window.cursor < visual_mode_data.cursor {
                        buffer_window.cursor = visual_mode_data.cursor;
                    }
                }
                else {
                    if visual_mode_data.cursor < buffer_window.cursor {
                        buffer_window.cursor = visual_mode_data.cursor;
                    }
                }
            }
            else if end {
                if buffer_window.line < visual_mode_data.line {
                    buffer_window.line = visual_mode_data.line;
                    buffer_window.cursor = visual_mode_data.cursor;
                }
            }
            else if visual_mode_data.line < buffer_window.line {
                buffer_window.line = visual_mode_data.line;
                buffer_window.cursor = visual_mode_data.cursor;
            }
        }
        case EditMode.VisualLine; {
            if end {
                _, buffer_window.line = get_visual_start_and_end_lines(buffer_window);
                line := get_buffer_line(buffer, buffer_window.line);
                buffer_window.cursor = line.length;
            }
            else {
                buffer_window.line, _ = get_visual_start_and_end_lines(buffer_window);
                buffer_window.cursor = 0;
            }
        }
        case EditMode.VisualBlock; {
            start_line, end_line := get_visual_start_and_end_lines(buffer_window);
            start_cursor, end_cursor := get_visual_start_and_end_cursors(buffer_window);
            if end {
                buffer_window.line = end_line;
                buffer_window.cursor = end_cursor + 1;
            }
            else {
                buffer_window.line = start_line;
                buffer_window.cursor = start_cursor;
            }
        }
    }

    adjust_start_line(buffer_window);
}

string get_selected_text() {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
        return empty_string;
    }

    start_line, end_line := get_visual_start_and_end_lines(buffer_window);
    result: string;

    if start_line == end_line {
        line := get_buffer_line(buffer, start_line);
        if edit_mode == EditMode.VisualLine {
            result = { length = line.length; data = line.data.data; }
        }
        else {
            start_cursor, end_cursor := get_visual_start_and_end_cursors(buffer_window);
            result = {
                length = end_cursor - start_cursor + 1;
                data = line.data.data + start_cursor;
            }
        }
    }

    return result;
}

copy_selected_lines() {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
        return;
    }

    start_line, end_line := get_visual_start_and_end_lines(buffer_window);
    copy_lines(buffer_window, buffer, start_line, end_line);
}

copy_lines(u32 start_line, u32 end_line) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
        return;
    }

    copy_lines(buffer_window, buffer, start_line, end_line);
}

copy_lines(BufferWindow* buffer_window, Buffer* buffer, u32 start_line, u32 end_line) {
    line := get_buffer_line(buffer, start_line);
    copy_string: string;

    current_line := line;
    line_number := start_line;
    while line_number <= end_line {
        copy_string.length += current_line.length;

        if line_number != end_line {
            copy_string.length++;
        }

        current_line = current_line.next;
        line_number++;
    }

    copy_string.data = allocate(copy_string.length);

    current_line = line;
    line_number = start_line;
    i := 0;
    while line_number <= end_line {
        i = copy_line_into_buffer(copy_string.data, current_line, i);

        if line_number != end_line {
            copy_string[i] = '\n';
            i++;
        }

        current_line = current_line.next;
        line_number++;
    }

    save_string_to_clipboard(copy_string, ClipboardMode.Lines);
}

copy_selected() {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
        return;
    }

    buffer_window.line = clamp(buffer_window.line, 0, buffer.line_count - 1);

    switch edit_mode {
        case EditMode.Visual; {
            copy_selected(buffer_window, buffer, buffer_window.line, buffer_window.cursor, visual_mode_data.line, visual_mode_data.cursor);
        }
        case EditMode.VisualBlock; {
            start_line, end_line := get_visual_start_and_end_lines(buffer_window);
            start_cursor, end_cursor := get_visual_start_and_end_cursors(buffer_window);
            copy_block(buffer, start_line, start_cursor, end_line, end_cursor);
        }
    }
}

copy_block(Buffer* buffer, u32 start_line, u32 start_cursor, u32 end_line, u32 end_cursor) {
    copy_string: string;

    line := get_buffer_line(buffer, start_line);
    current_line := line;
    line_number := start_line;
    while line_number <= end_line {
        copy_string.length += end_cursor - start_cursor + 1;
        if line_number != end_line {
            copy_string.length++;
        }

        current_line = current_line.next;
        line_number++;
    }

    copy_string.data = allocate(copy_string.length);

    current_line = line;
    line_number = start_line;
    i: u32;
    while line_number <= end_line {
        if start_cursor >= current_line.length {
            // Fill with only spaces
            each j in start_cursor..end_cursor {
                copy_string[i++] = ' ';
            }
        }
        else {
            line_end := clamp(end_cursor, 0, current_line.length - 1);
            i = copy_line_into_buffer(copy_string.data, current_line, i, start_cursor, line_end);

            // Fill if necessary
            each j in end_cursor - line_end {
                copy_string[i++] = ' ';
            }
        }

        if line_number != end_line {
            copy_string.data[i++] = '\n';
        }

        current_line = current_line.next;
        line_number++;
    }

    save_string_to_clipboard(copy_string, ClipboardMode.Block);
}

copy_remaining_line() {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
        return;
    }

    buffer_window.line = clamp(buffer_window.line, 0, buffer.line_count - 1);
    copy_selected(buffer_window, buffer, buffer_window.line, buffer_window.cursor, buffer_window.line, 0xFFFFFFF);
}

copy_selected(u32 line_1, u32 cursor_1, u32 line_2, u32 cursor_2) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
        return;
    }

    copy_selected(buffer_window, buffer, line_1, cursor_1, line_2, cursor_2);
}

copy_selected(BufferWindow* buffer_window, Buffer* buffer, u32 line_1, u32 cursor_1, u32 line_2, u32 cursor_2, bool include_end = true) {
    copy_string: string;

    if line_1 == line_2 {
        line := get_buffer_line(buffer, line_1);

        if line.length {
            start_cursor, end_cursor: u32;
            if cursor_1 < cursor_2 {
                start_cursor = clamp(cursor_1, 0, line.length - 1);
                end_cursor = clamp(cursor_2, 0, line.length - 1);
            }
            else {
                start_cursor = clamp(cursor_2, 0, line.length - 1);
                end_cursor = clamp(cursor_1, 0, line.length - 1);
            }

            if include_end end_cursor++;

            copy_length := end_cursor - start_cursor;
            copy_string = { length = copy_length; data = allocate(copy_length); }
            copy_line_into_buffer(copy_string.data, line, 0, start_cursor, end_cursor - 1);
        }
    }
    else {
        start_line_number, start_cursor, end_line_number, end_cursor: u32;
        if line_1 < line_2 {
            start_line_number = line_1;
            end_line_number = line_2;
        }
        else {
            start_line_number = line_2;
            end_line_number = line_1;
        }

        start_line := get_buffer_line(buffer, start_line_number);
        end_line := get_buffer_line(buffer, end_line_number);

        if line_1 < line_2 {
            if start_line.length
                start_cursor = clamp(cursor_1, 0, start_line.length - 1);
            if end_line.length
                end_cursor = clamp(cursor_2, 0, end_line.length - 1);
        }
        else {
            if start_line.length
                start_cursor = clamp(cursor_2, 0, start_line.length - 1);
            if end_line.length
                end_cursor = clamp(cursor_1, 0, end_line.length - 1);
        }

        current_line := start_line;
        line_number := start_line_number;
        while line_number++ <= end_line_number {
            if current_line == start_line {
                copy_string.length += current_line.length - start_cursor + 1;
            }
            else if current_line == end_line {
                copy_string.length += end_cursor;
                if include_end copy_string.length++;
            }
            else {
                copy_string.length += current_line.length + 1;
            }

            current_line = current_line.next;
        }

        copy_string.data = allocate(copy_string.length);

        current_line = start_line;
        line_number = start_line_number;
        i: u32;
        while line_number++ <= end_line_number {
            if current_line == start_line {
                i = copy_line_into_buffer(copy_string.data, current_line, i, start_cursor);
                copy_string.data[i++] = '\n';
            }
            else if current_line == end_line {
                if !include_end end_cursor--;
                i = copy_line_into_buffer(copy_string.data, current_line, i, 0, end_cursor);
            }
            else {
                i = copy_line_into_buffer(copy_string.data, current_line, i);
                copy_string.data[i++] = '\n';
            }

            current_line = current_line.next;
        }
    }

    save_string_to_clipboard(copy_string, ClipboardMode.Normal);
}

u32 copy_line_into_buffer(u8* buffer, BufferLine* line, u32 index, u32 start = 0, s32 end = -1) {
    if end == -1 {
        end = line.length - 1;
    }

    if end < line_buffer_length {
        copy_length := end - start + 1;
        memory_copy(buffer + index, line.data.data + start, copy_length);
        index += copy_length;
    }
    else {
        assert(line.child != null);

        start_line := start / line_buffer_length;

        // Copy from the parent line if specified
        if start_line == 0 {
            copy_length := line_buffer_length - start;
            memory_copy(buffer + index, line.data.data + start, copy_length);
            index += copy_length;
        }

        // Get the starting child line
        child := line.child;
        current_child := 1;
        while current_child < start_line {
            child = child.next;
            current_child++;
        }

        end_line := end / line_buffer_length;
        while current_child <= end_line {
            line_start_index := current_child * line_buffer_length;
            copy_start: u32 = 0;
            if start > line_start_index {
                copy_start = line_buffer_length - (start - line_start_index);
            }

            line_end_index := (current_child + 1) * line_buffer_length - 1;
            copy_end: u32 = line_buffer_length - 1;
            if end < line_end_index {
                copy_end = end - line_start_index;
            }

            copy_length := copy_end - copy_start + 1;
            memory_copy(buffer + index, child.data.data + start, copy_length);

            index += copy_length;

            child = child.next;
            current_child++;
        }
    }

    return index;
}

paste_by_cursor(bool before, u32 paste_count) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null || buffer.read_only || buffer_window.hex_view {
        return;
    }

    buffer_window.line = clamp(buffer_window.line, 0, buffer.line_count - 1);
    paste_clipboard(buffer_window, buffer, before, false, paste_count, false);
}

paste_over_selected(u32 paste_count) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null || buffer.read_only || buffer_window.hex_view {
        return;
    }

    switch edit_mode {
        case EditMode.VisualLine; {
            start_line, end_line := get_visual_start_and_end_lines(buffer_window);
            begin_change(buffer, start_line, end_line, buffer_window.cursor, buffer_window.line);
            delete_lines(buffer_window, buffer, start_line, end_line, false, false, false);
            paste_clipboard(buffer_window, buffer, true, true, paste_count, true);
        }
        case EditMode.Visual; {
            start_line, end_line := get_visual_start_and_end_lines(buffer_window);
            if clipboard.mode == ClipboardMode.Block {
                end_line += clipboard.value_lines - 1;
            }
            begin_change(buffer, start_line, end_line, buffer_window.cursor, buffer_window.line);

            delete_selected(false);
            if clipboard.mode == ClipboardMode.Lines {
                line := get_buffer_line(buffer, buffer_window.line);
                add_new_line(buffer_window, buffer, line, false, true);
                buffer_window.line--;
            }
            paste_clipboard(buffer_window, buffer, clipboard.mode != ClipboardMode.Lines, false, paste_count, true, 1);
        }
        case EditMode.VisualBlock; {
            if clipboard.mode == ClipboardMode.Normal && clipboard.value_lines == 1 {
                start_line, end_line := get_visual_start_and_end_lines(buffer_window);
                start_cursor, end_cursor := get_visual_start_and_end_cursors(buffer_window);

                begin_change(buffer, start_line, end_line, buffer_window.cursor, buffer_window.line);

                line := get_buffer_line(buffer, start_line);
                each _ in start_line..end_line {
                    if start_cursor < line.length {
                        delete_from_line(line, start_cursor, end_cursor);
                        cursor := start_cursor;
                        each i in paste_count {
                            cursor = add_text_to_line(line, clipboard.value, cursor);
                        }
                    }
                    line = line.next;
                }

                record_change(buffer, start_line, end_line, buffer_window.cursor, buffer_window.line);
            }
            else {
                start_line, end_line := get_visual_start_and_end_lines(buffer_window);
                begin_change(buffer, start_line, end_line, buffer_window.cursor, buffer_window.line);
                delete_selected(false);
                buffer_window.line = start_line;

                paste_clipboard(buffer_window, buffer, clipboard.mode != ClipboardMode.Lines, false, paste_count, true, end_line - start_line);
            }
        }
    }
}

paste_clipboard(BufferWindow* buffer_window, Buffer* buffer, bool before, bool over_lines, u32 paste_count, bool change_recorded, u32 additional_lines_to_record = 0) {
    recording_start_line, recording_end_line := buffer_window.line;
    line := get_buffer_line(buffer, buffer_window.line);

    clipboard_lines: Array<string>[clipboard.value_lines];
    current_line := 0;
    clipboard_lines[current_line] = { length = 0; data = clipboard.value.data; }
    each i in clipboard.value.length {
        if clipboard.value[i] == '\n' {
            current_line++;
            if current_line < clipboard_lines.length {
                clipboard_lines[current_line] = {
                    length = 0;
                    data = clipboard.value.data + i + 1;
                }
            }
        }
        else {
            clipboard_lines[current_line].length++;
        }
    }

    switch clipboard.mode {
        case ClipboardMode.Normal; {
            if !change_recorded {
                begin_change(buffer, buffer_window.line, buffer_window.line, buffer_window.cursor, buffer_window.line);
            }

            if clipboard_lines.length == 1 {
                clipboard_line := clipboard_lines[0];
                start_cursor: u32;
                if line.length {
                    buffer_window.cursor = clamp(buffer_window.cursor, 0, line.length - 1);
                    start_cursor = buffer_window.cursor;
                    if !before start_cursor++;
                }

                each i in paste_count {
                    start_cursor = add_text_to_line(line, clipboard_line, start_cursor);
                }
                buffer_window.cursor = start_cursor - 1;
            }
            else {
                if line.length {
                    buffer_window.cursor = clamp(buffer_window.cursor, 0, line.length - 1);
                    if !before buffer_window.cursor++;
                    start_cursor := buffer_window.cursor;

                    end_line := add_new_line(buffer_window, buffer, line, false, true);

                    last_line := paste_lines(buffer_window, buffer, line, clipboard_lines, paste_count, start_cursor, true);

                    if last_line.length
                        buffer_window.cursor = last_line.length - 1;
                    else
                        buffer_window.cursor = 0;

                    merge_lines(buffer, last_line, end_line, last_line.length, 0, false);
                    buffer_window.line--;
                }
                else {
                    last_line := paste_lines(buffer_window, buffer, line, clipboard_lines, paste_count, wrap = true);
                    if last_line.length
                        buffer_window.cursor = last_line.length - 1;
                    else
                        buffer_window.cursor = 0;
                }

                recording_end_line = buffer_window.line;
                if edit_mode == EditMode.VisualBlock {
                    recording_end_line += additional_lines_to_record;
                }
                adjust_start_line(buffer_window);
            }
        }
        case ClipboardMode.Lines; {
            if !change_recorded {
                begin_change(buffer, -1, 0, buffer_window.cursor, buffer_window.line);
            }
            if !over_lines {
                if !before && edit_mode == EditMode.Normal {
                    recording_start_line++;
                }
                line = add_new_line(buffer_window, buffer, line, before, false);
            }
            paste_lines(buffer_window, buffer, line, clipboard_lines, paste_count);
            recording_end_line = buffer_window.line + additional_lines_to_record;
        }
        case ClipboardMode.Block; {
            if over_lines {
                paste_lines(buffer_window, buffer, line, clipboard_lines, paste_count);
                recording_end_line = buffer_window.line;
            }
            else {
                if !before buffer_window.cursor++;

                recording_end_line += clipboard_lines.length - 1;

                if !change_recorded {
                    end_line := clamp(recording_end_line, 0, buffer.line_count - 1);
                    begin_change(buffer, recording_start_line, end_line, buffer_window.cursor, buffer_window.line);
                }

                each clipboard_line, i in clipboard_lines {
                    cursor := buffer_window.cursor;
                    each paste in paste_count {
                        cursor = add_text_to_line(line, clipboard_line, cursor, true);
                    }

                    if line.next {
                        line = line.next;
                    }
                    else if i < clipboard_lines.length - 1 {
                        line = add_new_line(buffer_window, buffer, line, false, false);
                    }
                }
            }
        }
    }

    record_change(buffer, recording_start_line, recording_end_line, buffer_window.cursor, buffer_window.line);

    calculate_line_digits(buffer);
    adjust_start_line(buffer_window);
}

BufferLine* paste_lines(BufferWindow* buffer_window, Buffer* buffer, BufferLine* line, Array<string> clipboard_lines, u32 paste_count, u32 cursor = 0, bool wrap = false) {
    each paste in paste_count {
        each clipboard_line, i in clipboard_lines {
            add_text_to_line(line, clipboard_line, cursor);
            cursor = 0;

            if i < clipboard_lines.length - 1 {
                line = add_new_line(buffer_window, buffer, line, false, false);
            }
        }

        if paste < paste_count - 1 {
            if wrap {
                cursor = line.length;
            }
            else {
                line = add_new_line(buffer_window, buffer, line, false, false);
            }
        }
    }

    return line;
}

// Insert mode functions
start_insert_mode(bool allow_eol, s32 change = 0) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null || buffer.read_only || buffer_window.hex_view {
        return;
    }

    reset_key_command();
    reset_post_movement_command();
    edit_mode = EditMode.Insert;

    buffer_window.line = clamp(buffer_window.line, 0, buffer.line_count - 1);
    line := get_buffer_line(buffer, buffer_window.line);

    if line.length == 0 {
        buffer_window.cursor = 0;
    }
    else if allow_eol {
        buffer_window.cursor = clamp(cast(s32, buffer_window.cursor) + change, 0, line.length);
    }
    else {
        buffer_window.cursor = clamp(cast(s32, buffer_window.cursor) + change, 0, line.length - 1);
    }

    begin_insert_mode_change(line, buffer_window.line, buffer_window.cursor);
}

end_insert_mode() {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null || buffer.read_only || buffer_window.hex_view {
        return;
    }

    record_insert_mode_change(buffer, buffer_window.line, buffer_window.cursor);
}

add_text_to_end_of_buffer(Buffer* buffer, string value, bool parse_escape_codes) {
    line := get_buffer_line(buffer, buffer.line_count - 1);
    text: string = { data = value.data; }

    each i in value.length {
        char := value[i];
        // TODO Handle escape codes
        if char == '\n' {
            if text.length {
                add_text_to_line(line, text, line.length);
            }

            line = add_new_line(null, buffer, line, false, false);
            calculate_line_digits(buffer);

            text = { length = 0; data = value.data + i + 1; }
        }
        else if char != '\r' {
            text.length++;
        }
    }

    if text.length {
        add_text_to_line(line, text, line.length);
    }

    calculate_line_digits(buffer);
}

add_text_to_line(string text) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null || buffer.read_only || buffer_window.hex_view {
        return;
    }

    line := get_buffer_line(buffer, buffer_window.line);
    buffer_window.cursor = add_text_to_line(line, text, buffer_window.cursor);
}

u32 add_text_to_line(BufferLine* line, string text, u32 cursor = 0, bool fill = false, bool clear = false) {
    if clear {
        // Free any child lines that extend past the new text length
        if text.length <= line_buffer_length {
            if line.child {
                free_child_lines(line.child);
                line.child = null;
            }
        }

        line.length = 0;
        return add_text_to_end_of_line(line, text);
    }

    if fill && cursor > line.length {
        fill_string := create_empty_string(cursor - line.length);
        add_text_to_end_of_line(line, fill_string);
    }

    new_cursor: u32;
    if line.length <= cursor {
        new_cursor = add_text_to_end_of_line(line, text);
    }
    else {
        new_length := line.length + text.length;
        if new_length <= line_buffer_length {
            each i in line.length - cursor {
                line.data[line.length + text.length - 1 - i] = line.data[line.length - 1 - i];
            }

            memory_copy(line.data.data + cursor, text.data, text.length);
        }
        else {
            // Allocate the additional blocks needed
            if line.child == null {
                line.child = allocate_line(line);
            }

            child := line.child;
            start_index := line_buffer_length;
            while start_index < new_length {
                remaining_length := new_length - start_index;
                if remaining_length <= line_buffer_length {
                    child.length = remaining_length;
                }
                else {
                    child.length = line_buffer_length;
                    if child.next == null {
                        child.next = allocate_line(line, child);
                    }
                }

                start_index += line_buffer_length;
                child = child.next;
            }

            // Move the existing line chars to the new position
            each i in line.length - cursor {
                char := get_char(line, line.length - 1 - i);
                set_char(line, line.length + text.length - 1 - i, char);
            }

            // Insert the new text
            each i in text.length {
                char := text[i];
                set_char(line, cursor + i, char);
            }
        }

        line.length = new_length;
        new_cursor = cursor + text.length;
    }

    return new_cursor;
}

u32 add_text_to_end_of_line(BufferLine* line, u8* data, u32 length) {
    line_string: string = { length = length; data = data; }
    return add_text_to_end_of_line(line, line_string);
}

u32 add_text_to_end_of_line(BufferLine* line, string text) {
    new_length := line.length + text.length;
    if new_length <= line_buffer_length {
        memory_copy(line.data.data + line.length, text.data, text.length);
    }
    else {
        current_child := line.length / line_buffer_length;

        text_start_index := 0;
        remaining := text.length;

        if line.length < line_buffer_length {
            copy_length := line_buffer_length - line.length;
            memory_copy(line.data.data + line.length, text.data, copy_length);
            text_start_index += copy_length;
            remaining -= copy_length;
        }

        if line.child == null {
            line.child = allocate_line(line);
        }

        child := line.child;
        while true {
            if child.length + remaining <= line_buffer_length {
                memory_copy(child.data.data + child.length, text.data + text_start_index, remaining);
                child.length += remaining;
                free_child_lines(child.next);
                child.next = null;
                break;
            }

            copy_length := line_buffer_length - child.length;
            memory_copy(child.data.data + child.length, text.data + text_start_index, copy_length);
            child.length = line_buffer_length;
            text_start_index += copy_length;
            remaining -= copy_length;

            if child.next == null {
                child.next = allocate_line(line, child);
            }

            child = child.next;
        }
    }

    line.length = new_length;
    return new_length;
}

// Block insert mode
struct BlockInsertData {
    start_line: u32;
    end_line: u32;
}

block_insert_data: BlockInsertData;

init_block_insert_mode() {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null || buffer.read_only || buffer_window.hex_view {
        return;
    }

    block_insert_data.start_line, block_insert_data.end_line = get_visual_start_and_end_lines(buffer_window);

    begin_block_insert_mode_change(buffer, block_insert_data.start_line, block_insert_data.end_line, buffer_window.cursor, buffer_window.line);
}

start_block_insert_mode() {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null || buffer.read_only || buffer_window.hex_view {
        return;
    }

    reset_key_command();
    reset_post_movement_command();
    edit_mode = EditMode.BlockInsert;

    buffer_window.line = block_insert_data.start_line;

    if block_insert_data.start_line == block_insert_data.end_line {
        edit_mode = EditMode.Insert;
    }
}

add_text_to_block(string text) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null || buffer.read_only || buffer_window.hex_view {
        return;
    }

    line_number := block_insert_data.start_line;
    line := get_buffer_line(buffer, line_number);

    new_cursor := buffer_window.cursor;
    while line != null && line_number <= block_insert_data.end_line {
        if buffer_window.cursor <= line.length {
            new_cursor = add_text_to_line(line, text, buffer_window.cursor);
        }

        line = line.next;
        line_number++;
    }

    buffer_window.cursor = new_cursor;
}

delete_from_cursor_block(bool back) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null || buffer.read_only || buffer_window.hex_view {
        return;
    }

    line_number := block_insert_data.start_line;
    line := get_buffer_line(buffer, line_number);

    new_cursor := buffer_window.cursor;
    while line != null && line_number <= block_insert_data.end_line {
        if back {
            if buffer_window.cursor == 0 {
                edit_mode = EditMode.Insert;

                if line.previous {
                    update_insert_mode_change(buffer, buffer_window.line - 1);
                    buffer_window.cursor = line.previous.length;
                    merge_lines(buffer, line.previous, line, line.previous.length, 0, false);
                    buffer_window.line--;
                }
                break;
            }
            else if buffer_window.cursor <= line.length {
                new_cursor = delete_from_line(line, buffer_window.cursor - 1, buffer_window.cursor, false);
            }
        }
        else {
            if buffer_window.cursor == line.length {
                edit_mode = EditMode.Insert;

                if line.next {
                    update_insert_mode_change(buffer, buffer_window.line, true);
                    merge_lines(buffer, line, line.next, line.length, 0, false);
                }
                break;
            }
            else if buffer_window.cursor <= line.length {
                delete_from_line(line, buffer_window.cursor, buffer_window.cursor + 1, false);
            }
        }

        line = line.next;
        line_number++;
    }

    buffer_window.cursor = new_cursor;
}

// Deletions
delete_lines(bool delete_all, bool record = false, bool inserting = false) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null || buffer.read_only || buffer_window.hex_view {
        return;
    }

    buffer_window.line = clamp(buffer_window.line, 0, buffer.line_count - 1);

    start_line, end_line: u32;
    switch edit_mode {
        case EditMode.Normal; {
            start_line = buffer_window.line;
            end_line = buffer_window.line;
        }
        case EditMode.Visual;
        case EditMode.VisualLine;
        case EditMode.VisualBlock; {
            start_line, end_line = get_visual_start_and_end_lines(buffer_window);
        }
    }

    if inserting {
        begin_insert_mode_change(buffer, start_line, end_line, buffer_window.cursor, buffer_window.line);
    }

    if record {
        begin_change(buffer, start_line, end_line, buffer_window.cursor, buffer_window.line);
    }

    delete_lines(buffer_window, buffer, start_line, end_line, delete_all);

    if record {
        record_change(buffer, -1, 0, buffer_window.cursor, buffer_window.line);
    }
}

delete_lines(u32 line_1, u32 line_2, bool delete_all, bool record = false, bool inserting = false) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null || buffer.read_only || buffer_window.hex_view {
        return;
    }

    start_line, end_line: u32;
    if line_1 > line_2 {
        start_line = line_2;
        end_line = line_1;
    }
    else {
        start_line = line_1;
        end_line = line_2;
    }

    if inserting {
        begin_insert_mode_change(buffer, start_line, end_line, buffer_window.cursor, buffer_window.line);
    }

    if record {
        begin_change(buffer, start_line, end_line, buffer_window.cursor, buffer_window.line);
    }

    delete_lines(buffer_window, buffer, start_line, end_line, delete_all);

    if record {
        record_change(buffer, -1, 0, buffer_window.cursor, buffer_window.line);
    }
}

delete_lines_in_range(Buffer* buffer, BufferLine* line, u32 count, bool delete_all = false) {
    start := line;
    new_next := line.next;

    each i in count {
        next := new_next.next;
        free_line_and_children(new_next);
        new_next = next;
        buffer.line_count--;
    }

    if delete_all {
        if start.previous == null {
            if new_next {
                buffer.lines = new_next;
                new_next.previous = null;
            }
            else {
                start.length = 0;
                start.next = null;
                buffer.line_count = 1;
                return;
            }
        }
        else {
            start.previous.next = new_next;
            if new_next {
                new_next.previous = start.previous;
            }
        }

        free_line_and_children(start);
        buffer.line_count--;
    }
    else {
        start.next = new_next;
        if new_next {
            new_next.previous = start;
        }
    }
}

delete_selected(bool copy = true, bool record = false, bool inserting = false) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null || buffer.read_only || buffer_window.hex_view {
        return;
    }

    buffer_window.line = clamp(buffer_window.line, 0, buffer.line_count - 1);

    switch edit_mode {
        case EditMode.Normal; {
            copy_string: string;
            line := get_buffer_line(buffer, buffer_window.line);

            if inserting {
                begin_insert_mode_change(line, buffer_window.line, buffer_window.cursor);
            }

            if record {
                begin_line_change(line, buffer_window.line, buffer_window.cursor);
            }

            if line.length {
                cursor := clamp(buffer_window.cursor, 0, line.length - 1);
                if copy {
                    copy_char: u8;
                    copy_line_into_buffer(&copy_char, line, 0, cursor, cursor);
                    copy_string = { length = 1; data = &copy_char; }
                    allocate_strings(&copy_string);
                }

                buffer_window.cursor = delete_from_line(line, cursor, cursor);
            }
            else {
                buffer_window.cursor = 0;
            }

            if record {
                record_line_change(buffer, line, buffer_window.line, buffer_window.cursor);
            }

            if copy {
                set_clipboard(copy_string);
            }
        }
        case EditMode.Visual; {
            delete_selected(buffer_window, buffer, buffer_window.line, buffer_window.cursor, visual_mode_data.line, visual_mode_data.cursor, true, copy, record, inserting);
        }
        case EditMode.VisualBlock; {
            start_line, end_line := get_visual_start_and_end_lines(buffer_window);
            start_cursor, end_cursor := get_visual_start_and_end_cursors(buffer_window);

            if record {
                begin_change(buffer, start_line, end_line, buffer_window.cursor, buffer_window.line);
            }

            if copy {
                copy_block(buffer, start_line, start_cursor, end_line, end_cursor);
            }

            line := get_buffer_line(buffer, start_line);
            each _ in start_line..end_line {
                delete_from_line(line, start_cursor, end_cursor);
                line = line.next;
            }

            buffer_window.cursor = start_cursor;

            if record {
                record_change(buffer, start_line, end_line, buffer_window.cursor, buffer_window.line);
            }
        }
    }
}

delete_selected(u32 line_1, u32 cursor_1, u32 line_2, u32 cursor_2, bool delete_end_cursor, bool record = false, bool inserting = false) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null || buffer.read_only || buffer_window.hex_view {
        return;
    }

    delete_selected(buffer_window, buffer, line_1, cursor_1, line_2, cursor_2, delete_end_cursor, true, record, inserting);
}

delete_selected(BufferWindow* buffer_window, Buffer* buffer, u32 line_1, u32 cursor_1, u32 line_2, u32 cursor_2, bool delete_end_cursor, bool copy, bool record, bool inserting) {
    if copy {
        copy_selected(buffer_window, buffer, line_1, cursor_1, line_2, cursor_2, delete_end_cursor);
    }

    if line_1 == line_2 {
        line := get_buffer_line(buffer, line_1);

        if inserting {
            begin_insert_mode_change(line, buffer_window.line, buffer_window.cursor);
        }

        if record {
            begin_line_change(line, line_1, buffer_window.cursor, buffer_window.line);
        }

        start_cursor, end_cursor: u32;
        if cursor_1 > cursor_2 {
            start_cursor = cursor_2;
            end_cursor = cursor_1;
        }
        else {
            start_cursor = cursor_1;
            end_cursor = cursor_2;
        }
        buffer_window.cursor = delete_from_line(line, start_cursor, end_cursor, delete_end_cursor);

        if record {
            record_line_change(buffer, line, line_1, buffer_window.cursor, buffer_window.line);
        }
    }
    else {
        start_line_number, start_cursor, end_line_number, end_cursor: u32;
        if line_1 < line_2 {
            start_line_number = line_1;
            end_line_number = line_2;
        }
        else {
            start_line_number = line_2;
            end_line_number = line_1;
        }

        if inserting {
            begin_insert_mode_change(buffer, start_line_number, end_line_number, buffer_window.cursor, buffer_window.line);
        }

        if record {
            begin_change(buffer, start_line_number, end_line_number, buffer_window.cursor, buffer_window.line);
        }

        start_line := get_buffer_line(buffer, start_line_number);
        end_line := get_buffer_line(buffer, end_line_number);

        if line_1 < line_2 {
            if start_line.length
                start_cursor = clamp(cursor_1, 0, start_line.length);
            if end_line.length
                end_cursor = clamp(cursor_2, 0, end_line.length);
        }
        else {
            if start_line.length
                start_cursor = clamp(cursor_2, 0, start_line.length);
            if end_line.length
                end_cursor = clamp(cursor_1, 0, end_line.length);
        }

        merge_lines(buffer, start_line, end_line, start_cursor, end_cursor, delete_end_cursor);
        buffer_window.line = start_line_number;
        buffer_window.cursor = start_cursor;

        adjust_start_line(buffer_window);

        if record {
            record_change(buffer, start_line_number, start_line_number, buffer_window.cursor, buffer_window.line);
        }
    }
}

clear_remaining_line(bool record = false, bool inserting = false) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null || buffer.read_only || buffer_window.hex_view {
        return;
    }

    buffer_window.line = clamp(buffer_window.line, 0, buffer.line_count - 1);
    line := get_buffer_line(buffer, buffer_window.line);

    if inserting {
        begin_insert_mode_change(line, buffer_window.line, buffer_window.cursor);
    }

    if record {
        begin_line_change(line, buffer_window.line, buffer_window.cursor);
    }

    if line.length == 0 {
        buffer_window.cursor = 0;
    }
    else {
        buffer_window.cursor = clamp(buffer_window.cursor, 0, line.length - 1);
        copy_selected(buffer_window, buffer, buffer_window.line, buffer_window.cursor, buffer_window.line, line.length - 1);
        line.length = buffer_window.cursor;
    }

    if record {
        record_line_change(buffer, line, buffer_window.line, buffer_window.cursor);
    }
}

delete_from_cursor(bool back) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null || buffer.read_only || buffer_window.hex_view {
        return;
    }

    line := get_buffer_line(buffer, buffer_window.line);

    if back {
        cursor := clamp(buffer_window.cursor, 0, line.length);
        if cursor == 0 {
            if line.previous {
                update_insert_mode_change(buffer, buffer_window.line - 1);
                buffer_window.cursor = line.previous.length;
                merge_lines(buffer, line.previous, line, line.previous.length, 0, false);
                buffer_window.line--;
            }
        }
        else {
            delete_length := 1;
            if is_whitespace_before_cursor(line, cursor) {
                delete_length = cursor % settings.tab_size;
                if delete_length == 0 {
                    delete_length = settings.tab_size;
                }
            }

            buffer_window.cursor = delete_from_line(line, cursor - delete_length, cursor, false);
        }
    }
    else {
        cursor := clamp(buffer_window.cursor, 0, line.length);
        if cursor == line.length {
            if line.next {
                update_insert_mode_change(buffer, buffer_window.line, true);
                buffer_window.cursor = cursor;
                merge_lines(buffer, line, line.next, line.length, 0, false);
            }
        }
        else {
            delete_from_line(line, cursor, cursor + 1, false);
        }
    }
}

delete_cursor(bool back, u32 cursor_changes) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null || buffer.read_only || buffer_window.hex_view {
        return;
    }

    buffer_window.line = clamp(buffer_window.line, 0, buffer.line_count - 1);
    line := get_buffer_line(buffer, buffer_window.line);
    begin_line_change(line, buffer_window.line, buffer_window.cursor);

    copy_string: string;

    if line.length == 0 {
        buffer_window.cursor = 0;
    }
    else {
        buffer_window.cursor = clamp(buffer_window.cursor, 0, line.length - 1);

        start, end: u32;
        if back {
            cursor_changes = clamp(cursor_changes, 0, buffer_window.cursor);
            start = buffer_window.cursor - cursor_changes;
            end = buffer_window.cursor;
        }
        else {
            start = buffer_window.cursor;
            end = buffer_window.cursor + cursor_changes;
        }

        copy_string = {
            length = end - start;
            data = line.data.data + start;
        }
        allocate_strings(&copy_string);

        buffer_window.cursor = delete_from_line(line, start, end, false);
    }

    set_clipboard(copy_string);

    record_line_change(buffer, line, buffer_window.line, buffer_window.cursor);
}

bool is_whitespace_before_cursor(BufferLine* line, u32 cursor) {
    each i in cursor {
        char := get_char(line, i);
        if char != ' ' {
            return false;
        }
    }

    return true;
}

u32 delete_from_line(BufferLine* line, u32 start, u32 end, bool delete_end_cursor = true) {
    if line.length == 0 {
        return 0;
    }

    if start >= line.length {
        return line.length;
    }

    if end >= line.length {
        line.length = start;
    }
    else {
        if delete_end_cursor {
            end++;
        }

        each i in line.length - end {
            char := get_char(line, end + i);
            set_char(line, start + i, char);
        }

        line.length -= end - start;
    }

    // Free unused child lines
    if line.length <= line_buffer_length {
        if line.child {
            free_child_lines(line.child);
            line.child = null;
        }
    }
    else {
        index := line_buffer_length;
        child := line.child;
        while true {
            if index + line_buffer_length >= line.length {
                child.length = line.length - index;
                free_child_lines(child.next);
                child.next = null;
                break;
            }

            child.length = line_buffer_length;
            index += line_buffer_length;
            child = child.next;
        }
    }

    return start;
}

join_lines(u32 lines) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null || buffer.read_only || buffer_window.hex_view {
        return;
    }

    buffer_window.line = clamp(buffer_window.line, 0, buffer.line_count - 1);

    start_line: u32;
    switch edit_mode {
        case EditMode.Normal; {
            start_line = buffer_window.line;
            if lines + start_line > buffer.line_count {
                lines = buffer.line_count - start_line;
            }
        }
        case EditMode.Visual;
        case EditMode.VisualLine;
        case EditMode.VisualBlock; {
            start, end := get_visual_start_and_end_lines(buffer_window);
            start_line = start;
            lines = end - start + 1;
            edit_mode = EditMode.Normal;
            buffer_window.line = start;
        }
    }

    begin_change(buffer, start_line, start_line + lines, buffer_window.cursor, buffer_window.line);

    line := get_buffer_line(buffer, start_line);
    while line.next != null && lines > 0 {
        merge_lines(buffer, line, line.next, line.length, 0, false, true);
        lines--;
    }

    record_line_change(buffer, line, start_line, buffer_window.cursor);
}

add_new_line(bool above, bool split = false, bool opening = false) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null || buffer.read_only || buffer_window.hex_view {
        return;
    }

    if edit_mode == EditMode.Insert {
        if !above
            update_insert_mode_change(buffer, buffer_window.line + 1);
    }

    if edit_mode == EditMode.BlockInsert {
        edit_mode = EditMode.Insert;
    }

    buffer_window.line = clamp(buffer_window.line, 0, buffer.line_count - 1);
    line := get_buffer_line(buffer, buffer_window.line);

    if opening {
        begin_open_line_change(line, buffer_window.line, buffer_window.cursor, above);
    }

    new_line := add_new_line(buffer_window, buffer, line, above, split);
    indent_line(buffer_window, new_line);

    calculate_line_digits(buffer);
    adjust_start_line(buffer_window);
}

BufferLine* add_new_line(BufferWindow* buffer_window, Buffer* buffer, BufferLine* line, bool above, bool split) {
    new_line := allocate_line();

    if above {
        if line.previous {
            line.previous.next = new_line;
            new_line.previous = line.previous;
            line.previous = new_line;
            new_line.next = line;
        }
        else {
            buffer.lines = new_line;
            new_line.next = line;
            line.previous = new_line;
        }
    }
    else {
        if split {
            assert(buffer_window != null);
            if buffer_window.cursor <= line.length {
                new_line_string: string = { length = line.length - buffer_window.cursor; data = line.data.data + buffer_window.cursor; }
                line.length = buffer_window.cursor;

                add_text_to_line(new_line, new_line_string);
                buffer_window.cursor = 0;
            }
        }
        if line.next {
            line.next.previous = new_line;
        }
        new_line.previous = line;
        new_line.next = line.next;
        line.next = new_line;

        if buffer_window {
            buffer_window.line++;
        }
    }

    buffer.line_count++;
    return new_line;
}

BufferLine* add_new_line(Buffer* buffer, BufferLine* line, u32 cursor) {
    new_line := allocate_line();

    if cursor <= line.length {
        new_line_string: string = { length = line.length - cursor; data = line.data.data + cursor; }
        line.length = cursor;

        add_text_to_line(new_line, new_line_string);
    }

    if line.next {
        line.next.previous = new_line;
    }
    new_line.previous = line;
    new_line.next = line.next;
    line.next = new_line;

    buffer.line_count++;
    return new_line;
}

change_indentation(bool indent, u32 indentations) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null || buffer.read_only || buffer_window.hex_view {
        return;
    }

    buffer_window.line = clamp(buffer_window.line, 0, buffer.line_count - 1);

    start_line, end_line: u32;
    switch edit_mode {
        case EditMode.Normal; {
            start_line = buffer_window.line;
            end_line = buffer_window.line;
        }
        case EditMode.Visual;
        case EditMode.VisualLine;
        case EditMode.VisualBlock; {
            start_line, end_line = get_visual_start_and_end_lines(buffer_window);
        }
    }

    begin_change(buffer, start_line, end_line, buffer_window.cursor, buffer_window.line);

    line := get_buffer_line(buffer, start_line);
    indent_size := settings.tab_size * indentations;
    each _ in start_line..end_line {
        if line == null
            break;

        if indent {
            indent_line(line, indent_size);
        }
        else {
            available_whitespace: u32;
            while available_whitespace < line.length {
                char := get_char(line, available_whitespace);
                if char != ' '
                    break;

                available_whitespace++;
            }

            if available_whitespace {
                if available_whitespace < indent_size {
                    indent_size = available_whitespace;
                }

                delete_from_line(line, 0, indent_size, false);
            }
        }

        line = line.next;
    }

    record_change(buffer, start_line, end_line, buffer_window.cursor, buffer_window.line);
}

replace_characters(u8 char) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null || buffer.read_only || buffer_window.hex_view {
        return;
    }

    buffer_window.line = clamp(buffer_window.line, 0, buffer.line_count - 1);

    switch edit_mode {
        case EditMode.Normal; {
            line := get_buffer_line(buffer, buffer_window.line);
            if line.length {
                buffer_window.cursor = clamp(buffer_window.cursor, 0, line.length - 1);
                replace_characters_in_line(line, char, buffer_window.cursor, buffer_window.cursor);
            }
        }
        case EditMode.Visual; {
            if buffer_window.line == visual_mode_data.line {
                line := get_buffer_line(buffer, buffer_window.line);

                if line.length {
                    buffer_window.cursor = clamp(buffer_window.cursor, 0, line.length - 1);
                    start_cursor, end_cursor := get_visual_start_and_end_cursors(buffer_window);
                    replace_characters_in_line(line, char, start_cursor, end_cursor);
                }
            }
            else {
                start_line_number, end_line_number := get_visual_start_and_end_lines(buffer_window);
                start_line := get_buffer_line(buffer, start_line_number);
                end_line := get_buffer_line(buffer, end_line_number);

                start_cursor, end_cursor: u32;
                if visual_mode_data.line > buffer_window.line {
                    if start_line.length
                        start_cursor = clamp(buffer_window.cursor, 0, start_line.length - 1);
                    end_cursor = visual_mode_data.cursor;
                }
                else {
                    start_cursor = visual_mode_data.cursor;
                    if end_line.length
                        end_cursor = clamp(buffer_window.cursor, 0, end_line.length - 1);
                }

                line_number := start_line_number;
                replace_characters_in_line(start_line, char, start_cursor, start_line.length - 1);
                start_line = start_line.next;
                line_number++;

                while line_number < end_line_number {
                    replace_characters_in_line(start_line, char, 0, start_line.length - 1);
                    start_line = start_line.next;
                    line_number++;
                }

                replace_characters_in_line(end_line, char, 0, end_cursor);
            }
        }
        case EditMode.VisualLine; {
            start_line, end_line := get_visual_start_and_end_lines(buffer_window);
            line := get_buffer_line(buffer, start_line);

            while start_line <= end_line {
                replace_characters_in_line(line, char, 0, line.length - 1);
                line = line.next;
                start_line++;
            }
        }
        case EditMode.VisualBlock; {
            start_line, end_line := get_visual_start_and_end_lines(buffer_window);
            start_cursor, end_cursor := get_visual_start_and_end_cursors(buffer_window);

            line := get_buffer_line(buffer, start_line);
            while start_line <= end_line {
                replace_characters_in_line(line, char, start_cursor, end_cursor);
                line = line.next;
                start_line++;
            }
        }
    }
}

replace_characters_in_line(BufferLine* line, u8 char, u32 start, u32 end) {
    i := start;
    while i < line.length && i <= end {
        set_char(line, i++, char);
    }
}

// Event handlers
handle_buffer_scroll(ScrollDirection direction) {
    x, y := get_cursor_position();
    workspace := get_workspace();

    if workspace.left_window.displayed && (!workspace.right_window.displayed || x < 0.0) {
        scroll_buffer(workspace, workspace.left_window.buffer_window, direction == ScrollDirection.Up);
    }
    else if workspace.right_window.displayed && (!workspace.left_window.displayed || x > 0.0) {
        scroll_buffer(workspace, workspace.right_window.buffer_window, direction == ScrollDirection.Up);
    }
}

enum ScrollTo {
    Top;
    Middle;
    Bottom;
}

scroll_to_position(ScrollTo scroll_position) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null || buffer_window.hex_view {
        return;
    }

    buffer_window.line = clamp(buffer_window.line, 0, buffer.line_count - 1);

    switch scroll_position {
        case ScrollTo.Top;
            buffer_window.start_line = buffer_window.line;
        case ScrollTo.Middle; {
            buffer_window.start_line = buffer_window.line;
            lines_to_offset, scroll_offset := determine_max_lines_and_scroll_offset(buffer_window);
            lines_to_offset /= 2;
            max_chars := calculate_max_chars_per_line(buffer_window, buffer.line_count_digits);

            line := get_buffer_line(buffer, buffer_window.line);
            while line.previous {
                line = line.previous;
                lines_rendered := calculate_rendered_lines(max_chars, line.length);
                if lines_rendered > lines_to_offset {
                    break;
                }

                lines_to_offset -= lines_rendered;
                buffer_window.start_line--;
            }
        }
        case ScrollTo.Bottom;
            buffer_window.start_line = 0;
    }

    adjust_start_line(buffer_window);
}

resize_buffers() {
    workspace := get_workspace();
    if workspace.left_window.displayed
        adjust_start_line(workspace.left_window.buffer_window);
    if workspace.right_window.displayed
        adjust_start_line(workspace.right_window.buffer_window);
}

go_to_line(s32 line) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
        return;
    }

    if !buffer_window.hex_view {
        record_jump(buffer_window);
    }

    if line < 0 {
        buffer_window.line = clamp(buffer.line_count + line, 0, buffer.line_count - 1);
    }
    else {
        buffer_window.line = clamp(line - 1, 0, buffer.line_count - 1);
    }

    if buffer_window.hex_view {
        adjust_start_byte(buffer_window, buffer);
    }
    else {
        adjust_start_line(buffer_window);
    }
}

u32 determine_max_lines() {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null {
        return global_font_config.max_lines_without_bottom_window;
    }

    max_lines, _ := determine_max_lines_and_scroll_offset(buffer_window);
    return max_lines;
}

move_line(bool up, bool with_wrap, u32 line_changes, bool move_to_first = false) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
        return;
    }

    buffer_window.line = clamp(buffer_window.line, 0, buffer.line_count - 1);

    if buffer_window.hex_view {
        line := get_buffer_line(buffer, buffer_window.line);
        byte_changes := line_changes * bytes_per_line;
        move_hex_view_cursor(buffer_window, buffer, line, up, byte_changes);
        return;
    }

    if with_wrap {
        max_chars := calculate_max_chars_per_line(buffer_window, buffer.line_count_digits);
        line := get_buffer_line(buffer, buffer_window.line);

        current_cursor := 0;
        if line.length > 1 {
            current_cursor = clamp(buffer_window.cursor, 0, line.length - 1);
        }

        column := current_cursor % max_chars;

        if up {
            while line_changes > 0 {
                if line.length <= max_chars || current_cursor - max_chars < 0 {
                    if line.previous == null {
                        break;
                    }

                    line = line.previous;
                    current_cursor = line.length / max_chars * max_chars + column;
                    buffer_window.line--;
                }
                else {
                    current_cursor -= max_chars;
                }

                line_changes--;
            }
        }
        else {
            while line_changes > 0 {
                if line.length <= max_chars || current_cursor + max_chars > line.length {
                    if line.next == null {
                        break;
                    }

                    line = line.next;
                    current_cursor = column;
                    buffer_window.line++;
                }
                else {
                    current_cursor += max_chars;
                }

                line_changes--;
            }
        }

        buffer_window.cursor = current_cursor;
    }
    else {
        if up buffer_window.line -= line_changes;
        else  buffer_window.line += line_changes;
    }

    buffer_window.line = clamp(buffer_window.line, 0, buffer.line_count - 1);
    adjust_start_line(buffer_window);

    if move_to_first {
        line := get_buffer_line(buffer, buffer_window.line);
        if line != null {
            cursor := 0;
            while cursor < line.length {
                char := get_char(line, cursor);
                if !is_whitespace(char) {
                    break;
                }

                cursor++;
            }

            buffer_window.cursor = cursor;
        }
    }
}

move_cursor(bool left, u32 cursor_changes) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
        return;
    }

    buffer_window.line = clamp(buffer_window.line, 0, buffer.line_count - 1);
    line := get_buffer_line(buffer, buffer_window.line);

    if buffer_window.hex_view {
        move_hex_view_cursor(buffer_window, buffer, line, left, cursor_changes);
        return;
    }

    if line.length == 0 {
        return;
    }

    if left {
        if cursor_changes > buffer_window.cursor {
            buffer_window.cursor = 0;
        }
        else if buffer_window.cursor >= line.length {
            if edit_mode != EditMode.Normal {
                buffer_window.cursor = line.length - cursor_changes;
            }
            else {
                buffer_window.cursor = line.length - cursor_changes - 1;
            }
        }
        else {
            buffer_window.cursor -= cursor_changes;
        }
    }
    else {
        if buffer_window.cursor + cursor_changes >= line.length {
            if edit_mode != EditMode.Normal {
                buffer_window.cursor = line.length;
            }
            else {
                buffer_window.cursor = line.length - 1;
            }
        }
        else {
            buffer_window.cursor += cursor_changes;
        }
    }
}

move_to_start_of_word(bool forward, bool full_word) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
        return;
    }

    line := get_buffer_line(buffer, buffer_window.line);
    if line == null {
        return;
    }

    if buffer_window.hex_view {
        move_hex_view_cursor(buffer_window, buffer, line, !forward, 1);
        return;
    }

    char: u8;
    is_whitespace := false;
    cursor: u32;
    if line.length == 0 {
        is_whitespace = true;
    }
    else {
        cursor = clamp(buffer_window.cursor, 0, line.length - 1);
        char = get_char(line, cursor);
        is_whitespace = is_whitespace(char);
    }

    if forward {
        if is_whitespace {
            move_to_next_non_whitespace(buffer_window, line, cursor + 1);
        }
        else {
            is_text := is_text_character(char);
            next_word_found, whitespace_found := false;
            while ++cursor < line.length {
                char = get_char(line, cursor);
                if is_whitespace(char) {
                    whitespace_found = true;
                }
                else if whitespace_found {
                    buffer_window.cursor = cursor;
                    next_word_found = true;
                    break;
                }
                else if !full_word && (is_text != is_text_character(char)) {
                    buffer_window.cursor = cursor;
                    next_word_found = true;
                    break;
                }
            }

            if !next_word_found && line.next != null {
                cursor = 0;
                line = line.next;
                buffer_window.line++;
                move_to_next_non_whitespace(buffer_window, line, cursor);
            }
        }
    }
    else {
        is_first := false;
        if !is_whitespace && cursor > 0 {
            is_text := is_text_character(char);
            previous_char := get_char(line, cursor - 1);
            if is_whitespace(previous_char) {
                is_first = true;
            }
            else {
                is_first = !full_word && (is_text != is_text_character(previous_char));
            }
        }

        // Go to the last non-whitespace character
        if is_whitespace || is_first || cursor == 0 {
            if cursor > 0 {
                cursor--;
            }
            else if line.previous {
                buffer_window.line--;
                line = line.previous;
                cursor = 0;
                if line.length > 0 {
                    cursor = line.length - 1;
                }
            }

            while true {
                char_found := false;
                if line.length > 0 {
                    while true {
                        char = get_char(line, cursor);
                        if !is_whitespace(char) {
                            char_found = true;
                            break;
                        }

                        if cursor == 0
                            break;

                        cursor--;
                    }
                }

                if char_found || line.previous == null
                    break;

                buffer_window.line--;
                line = line.previous;
                cursor = 0;
                if line.length > 0 {
                    cursor = line.length - 1;
                }
            }
        }

        // Move to the beginning of the word
        is_text := is_text_character(char);
        while true {
            if cursor == 0 {
                break;
            }

            previous_char := get_char(line, cursor - 1);
            if is_whitespace(previous_char) || !full_word && (is_text != is_text_character(previous_char)) {
                break;
            }

            cursor--;
        }

        buffer_window.cursor = cursor;
    }

    adjust_start_line(buffer_window);
}

move_to_end_of_word(bool full_word) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
        return;
    }

    line := get_buffer_line(buffer, buffer_window.line);
    if line == null {
        return;
    }

    if buffer_window.hex_view {
        move_hex_view_cursor(buffer_window, buffer, line, false, 1);
        return;
    }

    char: u8;
    is_whitespace, is_last := false;
    cursor: u32;
    if line.length == 0 {
        is_whitespace = true;
    }
    else {
        cursor = clamp(buffer_window.cursor, 0, line.length - 1);
        char = get_char(line, cursor);
        is_whitespace = is_whitespace(char);
    }

    if !is_whitespace && cursor < line.length - 1 {
        is_text := is_text_character(char);
        next_char := get_char(line, cursor + 1);
        if is_whitespace(next_char) {
            is_last = true;
        }
        else {
            is_last = !full_word && (is_text != is_text_character(next_char));
        }
    }

    // Go to the next non-whitespace character
    if is_whitespace || is_last || cursor == line.length - 1 {
        line = move_to_next_non_whitespace(buffer_window, line, cursor + 1);
    }

    // Move to the end of the word
    cursor = buffer_window.cursor;
    char = get_char(line, cursor);
    is_text := is_text_character(char);
    while cursor < line.length {
        if cursor + 1 == line.length {
            break;
        }

        next_char := get_char(line, cursor + 1);
        if is_whitespace(next_char) || !full_word && (is_text != is_text_character(next_char)) {
            break;
        }

        cursor++;
    }

    buffer_window.cursor = cursor;

    adjust_start_line(buffer_window);
}

move_to_line_boundary(bool end, bool soft_boundary, bool with_wrap) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
        return;
    }

    line := get_buffer_line(buffer, buffer_window.line);
    if line == null || buffer_window.hex_view {
        return;
    }

    if line.length <= 1 {
        buffer_window.cursor = 0;
        return;
    }

    if with_wrap {
        max_chars := calculate_max_chars_per_line(buffer_window, buffer.line_count_digits);
        current_cursor := clamp(buffer_window.cursor, 0, line.length - 1);

        if line.length > max_chars {
            cursor := 0;
            if end {
                while cursor <= current_cursor {
                    cursor += max_chars;
                }
                cursor--;
                cursor = clamp(cursor, 0, line.length - 1);
            }
            else {
                while cursor + max_chars < current_cursor {
                    cursor += max_chars;
                }
            }
            buffer_window.cursor = cursor;
            return;
        }
    }

    if end {
        buffer_window.cursor = line.length - 1;
    }
    else {
        cursor := 0;
        if soft_boundary {
            while cursor < line.length {
                char := get_char(line, cursor);
                if !is_whitespace(char) {
                    break;
                }

                cursor++;
            }
        }
        buffer_window.cursor = cursor;
    }
}

move_block(bool forward, bool paragraph) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
        return;
    }

    line := get_buffer_line(buffer, buffer_window.line);
    if line == null || buffer_window.hex_view {
        return;
    }

    record_jump(buffer_window);

    if paragraph {
        if line.length == 0 {
            if forward {
                while line.next != null && line.length == 0 {
                    buffer_window.line++;
                    line = line.next;
                }
            }
            else {
                while line.previous != null && line.length == 0 {
                    buffer_window.line--;
                    line = line.previous;
                }
            }
        }

        if forward {
            while line.next != null && line.length != 0 {
                buffer_window.line++;
                line = line.next;
            }
        }
        else {
            while line.previous != null && line.length != 0 {
                buffer_window.line--;
                line = line.previous;
            }
        }
    }
    else {
        if line.length == 0 {
            if forward {
                while line.next != null && line.length == 0 {
                    buffer_window.line++;
                    line = line.next;
                }
            }
            else {
                while line.previous != null && line.length == 0 {
                    buffer_window.line--;
                    line = line.previous;
                }

                while line.previous != null && line.previous.length != 0 {
                    buffer_window.line--;
                    line = line.previous;
                }
            }
        }
        else {
            if forward {
                while line.next != null && line.length != 0 {
                    buffer_window.line++;
                    line = line.next;
                }
            }
            else if line.previous != null && line.previous.length == 0 {
                buffer_window.line--;
                line = line.previous;
            }
            else {
                while line.previous != null && line.previous.length != 0 {
                    buffer_window.line--;
                    line = line.previous;
                }
            }
        }
    }

    buffer_window.cursor = 0;

    adjust_start_line(buffer_window);
}

move_to_syntax_match() {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null || buffer_window.hex_view {
        return;
    }

    line_number := clamp(buffer_window.line, 0, buffer.line_count - 1);
    line := get_buffer_line(buffer, line_number);

    if line.length == 0 return;

    cursor := clamp(buffer_window.cursor, 0, line.length - 1);

    match_char, complement_char: u8;
    forward: bool;
    while cursor < line.length {
        complement_char = get_char(line, cursor);
        switch complement_char {
            case '('; {
                match_char = ')';
                forward = true;
                break;
            }
            case ')'; {
                match_char = '(';
                forward = false;
                break;
            }
            case '['; {
                match_char = ']';
                forward = true;
                break;
            }
            case ']'; {
                match_char = '[';
                forward = false;
                break;
            }
            case '{'; {
                match_char = '}';
                forward = true;
                break;
            }
            case '}'; {
                match_char = '{';
                forward = false;
                break;
            }
        }

        cursor++;
    }

    if match_char == 0 return;

    found := false;
    nestings := 0;
    is_string := false;
    if forward {
        cursor++;
        while line {
            if line.length {
                each i in cursor..line.length - 1 {
                    char := get_char(line, i);
                    if char == '"' {
                        if i == 0 || get_char(line, i - 1) != '\\' {
                            is_string = !is_string;
                        }
                    }
                    else if !is_string {
                        if char == complement_char {
                            nestings++;
                        }
                        else if char == match_char {
                            if nestings > 0 {
                                nestings--;
                            }
                            else {
                                cursor = i;
                                found = true;
                                break;
                            }
                        }
                    }
                }
            }

            if found break;

            line = line.next;
            line_number++;
            cursor = 0;
        }
    }
    else {
        if cursor == 0 {
            line = line.previous;
            line_number--;

            if line {
                cursor = line.length;
            }
        }

        while line {
            if line.length {
                each i in cursor {
                    char := get_char(line, cursor - i - 1);
                    if char == '"' {
                        if i == cursor - 1 || get_char(line, cursor - i - 2) != '\\' {
                            is_string = !is_string;
                        }
                    }
                    else if !is_string {
                        if char == complement_char {
                            nestings++;
                        }
                        else if char == match_char {
                            if nestings > 0 {
                                nestings--;
                            }
                            else {
                                cursor -= i + 1;
                                found = true;
                                break;
                            }
                        }
                    }
                }
            }

            if found break;

            line = line.previous;
            line_number--;

            if line {
                cursor = line.length;
            }
        }
    }

    if found {
        record_jump(buffer_window);
        buffer_window.line = line_number;
        buffer_window.cursor = cursor;
        adjust_start_line(buffer_window);
    }
}

find_character_in_line(bool forward, bool before, string char) {
    if char.length != 1 return;

    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null || buffer_window.hex_view {
        return;
    }

    line := get_buffer_line(buffer, buffer_window.line);
    if line == null || line.length == 0 {
        return;
    }

    cursor := clamp(buffer_window.cursor, 0, line.length - 1);
    char_found := false;
    if forward {
        cursor++;
        while cursor < line.length {
            if get_char(line, cursor) == char[0] {
                char_found = true;
                break;
            }

            cursor++;
        }

        if before {
            cursor--;
        }
    }
    else if cursor > 0 {
        cursor--;
        while true {
            if get_char(line, cursor) == char[0] {
                char_found = true;
                break;
            }

            if cursor == 0
                break;

            cursor--;
        }

        if before {
            cursor++;
        }
    }

    if char_found {
        buffer_window.cursor = cursor;
    }
}

find_value_in_buffer(string value, bool next) {
    if value.length == 0 return;

    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
        return;
    }

    start_line := clamp(buffer_window.line, 0, buffer.line_count - 1);
    line := get_buffer_line(buffer, start_line);

    start_cursor := 0;
    if line.length
        start_cursor = clamp(buffer_window.cursor, 0, line.length - 1);

    cursor := start_cursor;
    line_number := start_line;
    found, wrapped := false;

    if next {
        cursor++;
        while true {
            // Only check if there are enough characters in the line to match the string
            while cursor + value.length <= line.length {
                if get_char(line, cursor) == value[0] {
                    matched := true;
                    each i in 1..value.length - 1 {
                        if get_char(line, cursor + i) != value[i] {
                            matched = false;
                            break;
                        }
                    }

                    if matched {
                        found = true;
                        break;
                    }
                }

                if wrapped && line_number == start_line && cursor == start_cursor {
                    break;
                }

                cursor++;
            }

            if found || (wrapped && line_number == start_line) {
                break;
            }

            if line.next {
                line = line.next;
                cursor = 0;
                line_number++;
            }
            else {
                wrapped = true;
                line = buffer.lines;
                cursor = 0;
                line_number = 0;
            }
        }
    }
    else {
        cursor--;
        while true {
            // Only check if there are enough characters in the line to match the string
            while line.length >= value.length && cursor >= value.length - 1 {
                if get_char(line, cursor) == value[value.length - 1] {
                    matched := true;
                    each i in 1..value.length - 1 {
                        if get_char(line, cursor - i) != value[value.length - 1 - i] {
                            matched = false;
                            break;
                        }
                    }

                    if matched {
                        cursor -= value.length - 1;
                        found = true;
                        break;
                    }
                }

                if wrapped && line_number == start_line && cursor == start_cursor {
                    break;
                }

                cursor--;
            }

            if found || (wrapped && line_number == start_line) {
                break;
            }

            if line.previous {
                line = line.previous;

                cursor = 0;
                if line.length {
                    cursor = line.length - 1;
                }
                line_number--;
            }
            else {
                wrapped = true;
                while line.next {
                    line = line.next;
                }

                cursor = 0;
                if line.length {
                    cursor = line.length - 1;
                }
                line_number = buffer.line_count - 1;
            }
        }
    }

    if found {
        record_jump(buffer_window);
        buffer_window.line = line_number;
        buffer_window.cursor = cursor;
        adjust_start_line(buffer_window);
    }
}

struct FindAndReplaceData {
    buffer_window: BufferWindow*;
    buffer: Buffer*;
    value: string;
    new_value: string;
    start_line: u32;
    start_cursor: u32;
    end_line: u32;
    end_cursor: u32;
    block: bool;
    line: BufferLine*;
    line_number: u32;
    cursor: u32;
    index: u32;
    end_index: u32;
}

find_and_replace_data: FindAndReplaceData;

bool begin_replace_value_in_buffer(string value, string new_value) {
    if value.length == 0 return false;

    find_and_replace_data.buffer_window, find_and_replace_data.buffer = get_current_window_and_buffer();
    if find_and_replace_data.buffer_window == null || find_and_replace_data.buffer == null || find_and_replace_data.buffer.read_only || find_and_replace_data.buffer_window.hex_view {
        return false;
    }

    find_and_replace_data.value = value;
    find_and_replace_data.new_value = new_value;
    find_and_replace_data.block = false;

    switch edit_mode {
        case EditMode.Visual; {
            if find_and_replace_data.buffer_window.line == visual_mode_data.line {
                find_and_replace_data.start_line = find_and_replace_data.buffer_window.line;
                find_and_replace_data.end_line = find_and_replace_data.buffer_window.line;
                if find_and_replace_data.buffer_window.cursor < visual_mode_data.cursor {
                    find_and_replace_data.start_cursor = find_and_replace_data.buffer_window.cursor;
                    find_and_replace_data.end_cursor = visual_mode_data.cursor;
                }
                else {
                    find_and_replace_data.start_cursor = visual_mode_data.cursor;
                    find_and_replace_data.end_cursor = find_and_replace_data.buffer_window.cursor;
                }
            }
            else if find_and_replace_data.buffer_window.line < visual_mode_data.line {
                find_and_replace_data.start_line = find_and_replace_data.buffer_window.line;
                find_and_replace_data.start_cursor = find_and_replace_data.buffer_window.cursor;
                find_and_replace_data.end_line = visual_mode_data.line;
                find_and_replace_data.end_cursor = visual_mode_data.cursor;
            }
            else {
                find_and_replace_data.start_line = visual_mode_data.line;
                find_and_replace_data.start_cursor = visual_mode_data.cursor;
                find_and_replace_data.end_line = find_and_replace_data.buffer_window.line;
                find_and_replace_data.end_cursor = find_and_replace_data.buffer_window.cursor;
            }
        }
        case EditMode.VisualLine; {
            find_and_replace_data.start_line, find_and_replace_data.end_line = get_visual_start_and_end_lines(find_and_replace_data.buffer_window);
            find_and_replace_data.start_cursor = 0;
            find_and_replace_data.end_cursor = 0xFFFFFFF;
        }
        case EditMode.VisualBlock; {
            find_and_replace_data.start_line, find_and_replace_data.end_line = get_visual_start_and_end_lines(find_and_replace_data.buffer_window);
            find_and_replace_data.start_cursor, find_and_replace_data.end_cursor = get_visual_start_and_end_cursors(find_and_replace_data.buffer_window);
            find_and_replace_data.block = true;
        }
        default; {
            find_and_replace_data.start_line = 0;
            find_and_replace_data.start_cursor = 0;
            find_and_replace_data.end_line = find_and_replace_data.buffer.line_count - 1;
            find_and_replace_data.end_cursor = 0xFFFFFFF;
        }
    }

    find_and_replace_data.line_number = find_and_replace_data.start_line;
    find_and_replace_data.cursor = find_and_replace_data.start_cursor;
    find_and_replace_data.index = find_and_replace_data.start_cursor;
    find_and_replace_data.line = get_buffer_line(find_and_replace_data.buffer, find_and_replace_data.line_number);
    set_end_index();

    return true;
}

bool find_next_value_in_buffer(bool move_cursor = true) {
    value_lines := split_string(find_and_replace_data.value);

    while find_and_replace_data.line != null && find_and_replace_data.line_number + value_lines.length - 1 <= find_and_replace_data.end_line {
        // Only check if there are enough characters in the line to match the string
        while find_and_replace_data.index + value_lines[0].length <= find_and_replace_data.end_index {
            if get_char(find_and_replace_data.line, find_and_replace_data.cursor) == find_and_replace_data.value[0] {
                matched := true;
                if value_lines.length == 1 {
                    each i in 1..find_and_replace_data.value.length - 1 {
                        if get_char(find_and_replace_data.line, find_and_replace_data.cursor + i) != find_and_replace_data.value[i] {
                            matched = false;
                            break;
                        }
                    }
                }
                else {
                    current_line := find_and_replace_data.line;
                    cursor := find_and_replace_data.cursor;
                    each line, i in value_lines {
                        if i < value_lines.length - 1 {
                            if current_line.length - cursor == line.length {
                                each j in line.length {
                                    if get_char(current_line, cursor + j) != line[j] {
                                        matched = false;
                                        break;
                                    }
                                }

                                if !matched {
                                    break;
                                }
                            }
                            else {
                                matched = false;
                                break;
                            }

                            current_line = current_line.next;
                            cursor = 0;
                        }
                        else {
                            each j in line.length {
                                if get_char(current_line, cursor + j) != line[j] {
                                    matched = false;
                                    break;
                                }
                            }
                        }
                    }
                }

                if matched {
                    if move_cursor {
                        find_and_replace_data.buffer_window.line = find_and_replace_data.line_number;
                        find_and_replace_data.buffer_window.cursor = find_and_replace_data.cursor;
                        adjust_start_line(find_and_replace_data.buffer_window);
                    }
                    return true;
                }
            }

            find_and_replace_data.cursor++;
            find_and_replace_data.index++;
        }

        find_and_replace_data.line = find_and_replace_data.line.next;
        find_and_replace_data.cursor = 0;
        find_and_replace_data.index = 0;
        find_and_replace_data.line_number++;

        if find_and_replace_data.block {
            find_and_replace_data.cursor = find_and_replace_data.start_cursor;
        }

        set_end_index();
    }

    return false;
}

set_end_index() {
    if find_and_replace_data.line {
        find_and_replace_data.end_index = find_and_replace_data.line.length;
        if (find_and_replace_data.block || find_and_replace_data.line_number == find_and_replace_data.end_line) && find_and_replace_data.end_cursor < find_and_replace_data.line.length {
            find_and_replace_data.end_index = find_and_replace_data.end_cursor + 1;
        }
    }
}

replace_value_in_buffer() {
    // Delete the current text
    lines := 1;
    each i in find_and_replace_data.value.length {
        if find_and_replace_data.value[i] == '\n' {
            lines++;
        }
    }

    line_number := find_and_replace_data.line_number;

    begin_change(find_and_replace_data.buffer, line_number, line_number + lines - 1, find_and_replace_data.cursor, line_number);

    if lines == 1 {
        delete_from_line(find_and_replace_data.line, find_and_replace_data.cursor, find_and_replace_data.cursor + find_and_replace_data.value.length, false);
        find_and_replace_data.index += find_and_replace_data.value.length;
    }
    else {
        last_delete_length := 0;
        line_to_merge := find_and_replace_data.line;
        each i in find_and_replace_data.value.length {
            if find_and_replace_data.value[i] == '\n' {
                last_delete_length = 0;
                line_to_merge = line_to_merge.next;
            }
            else {
                last_delete_length++;
            }
        }

        line_to_merge_length := line_to_merge.length;

        merge_lines(find_and_replace_data.buffer, find_and_replace_data.line, line_to_merge, find_and_replace_data.cursor, last_delete_length, false);

        find_and_replace_data.end_line -= lines - 1;

        find_and_replace_data.index = last_delete_length;
        find_and_replace_data.end_index = line_to_merge_length;
        if find_and_replace_data.line_number == find_and_replace_data.end_line && find_and_replace_data.end_cursor < line_to_merge_length {
            find_and_replace_data.end_index = find_and_replace_data.end_cursor + 1;
        }
    }

    // Replace with the new text
    new_lines := 1;
    each i in find_and_replace_data.new_value.length {
        if find_and_replace_data.new_value[i] == '\n' {
            new_lines++;
        }
    }

    if new_lines == 1 {
        add_text_to_line(find_and_replace_data.line, find_and_replace_data.new_value, find_and_replace_data.cursor);
        find_and_replace_data.cursor += find_and_replace_data.new_value.length;
    }
    else {
        new_value_lines: Array<string>[new_lines];
        index := 0;
        str: string = { data = find_and_replace_data.new_value.data; }
        each i in find_and_replace_data.new_value.length {
            if find_and_replace_data.new_value[i] == '\n' {
                new_value_lines[index++] = str;
                str = { length = 0; data = find_and_replace_data.new_value.data + i + 1; }
            }
            else {
                str.length++;
            }
        }
        new_value_lines[index++] = str;

        each line_text, i in new_value_lines {
            if line_text.length {
                add_text_to_line(find_and_replace_data.line, line_text, find_and_replace_data.cursor);
                find_and_replace_data.cursor += line_text.length;
            }

            if i < new_lines - 1 {
                find_and_replace_data.line = add_new_line(find_and_replace_data.buffer, find_and_replace_data.line, find_and_replace_data.cursor);
                find_and_replace_data.cursor = 0;
            }
        }

        find_and_replace_data.end_line += new_lines - 1;
        find_and_replace_data.line_number += new_lines - 1;
    }

    record_change(find_and_replace_data.buffer, line_number, line_number + new_lines - 1, find_and_replace_data.cursor, find_and_replace_data.line_number);
}

// Formatting specific functions
change_selected_line_commenting() {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null || buffer.read_only || buffer_window.hex_view || buffer.syntax == null || string_is_empty(buffer.syntax.single_line_comment) {
        return;
    }

    start_line, end_line: u32;
    switch edit_mode {
        case EditMode.Normal; {
            start_line = buffer_window.line;
            end_line = buffer_window.line;
        }
        case EditMode.Visual;
        case EditMode.VisualLine;
        case EditMode.VisualBlock; {
            start_line, end_line = get_visual_start_and_end_lines(buffer_window);
        }
    }

    begin_change(buffer, start_line, end_line, buffer_window.cursor, buffer_window.line);

    starting_line := get_buffer_line(buffer, start_line);
    comment_string := buffer.syntax.single_line_comment;

    // Determine whether to comment or uncomment the lines
    all_lines_commented := true;
    comment_cursor: u32 = 0xFFFFFFF;
    {
        line := starting_line;
        line_number := start_line;
        while line != null && line_number <= end_line {
            each i in line.length {
                if get_char(line, i) != ' ' {
                    has_comment := true;
                    if comment_string.length <= line.length - i {
                        each j in comment_string.length {
                            if get_char(line, i + j) != comment_string[j] {
                                has_comment = false;
                                break;
                            }
                        }
                    }

                    if i < comment_cursor {
                        comment_cursor = i;
                    }

                    if !has_comment {
                        all_lines_commented = false;
                    }

                    break;
                }
            }

            line = line.next;
            line_number++;
        }
    }

    if all_lines_commented {
        line := starting_line;
        line_number := start_line;
        while line != null && line_number <= end_line {
            each i in line.length {
                if get_char(line, i) != ' ' {
                    delete_length := comment_string.length;
                    if i + delete_length < line.length && get_char(line, i + delete_length) == ' ' {
                        delete_length++;
                    }

                    delete_from_line(line, i, i + delete_length, false);
                    break;
                }
            }

            line = line.next;
            line_number++;
        }
    }
    else {
        line := starting_line;
        line_number := start_line;
        while line != null && line_number <= end_line {
            if comment_cursor < line.length {
                add_text_to_line(line, comment_string, comment_cursor);
                add_text_to_line(line, " ", comment_cursor + comment_string.length);
            }

            line = line.next;
            line_number++;
        }
    }

    record_change(buffer, start_line, end_line, buffer_window.cursor, buffer_window.line);

    edit_mode = EditMode.Normal;
}

toggle_casing(bool upper) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null || buffer.read_only || buffer_window.hex_view {
        return;
    }

    start_line, end_line, start_cursor, end_cursor: u32;
    block := false;
    switch edit_mode {
        case EditMode.Normal; {
            start_line = buffer_window.line;
            end_line = buffer_window.line;
            start_cursor = buffer_window.cursor;
            end_cursor = buffer_window.cursor;
        }
        case EditMode.Visual; {
            if buffer_window.line == visual_mode_data.line {
                start_line = buffer_window.line;
                end_line = buffer_window.line;
                if buffer_window.cursor > visual_mode_data.cursor {
                    start_cursor = visual_mode_data.cursor;
                    end_cursor = buffer_window.cursor;
                }
                else {
                    start_cursor = buffer_window.cursor;
                    end_cursor = visual_mode_data.cursor;
                }
            }
            else if buffer_window.line > visual_mode_data.line {
                start_line = visual_mode_data.line;
                end_line = buffer_window.line;
                start_cursor = visual_mode_data.cursor;
                end_cursor = buffer_window.cursor;
            }
            else {
                start_line = buffer_window.line;
                end_line = visual_mode_data.line;
                start_cursor = buffer_window.cursor;
                end_cursor = visual_mode_data.cursor;
            }
        }
        case EditMode.VisualLine; {
            start_line, end_line = get_visual_start_and_end_lines(buffer_window);
            start_cursor = 0;
            end_cursor = 0xFFFFFFF;
        }
        case EditMode.VisualBlock; {
            start_line, end_line = get_visual_start_and_end_lines(buffer_window);
            start_cursor, end_cursor = get_visual_start_and_end_cursors(buffer_window);
            block = true;
        }
    }

    line_number := start_line;
    cursor := start_cursor;
    line := get_buffer_line(buffer, line_number);
    while line != null && line_number <= end_line {
        while cursor < line.length && ((!block && line_number != end_line) || cursor <= end_cursor) {
            char := get_char(line, cursor);
            if upper {
                if char >= 'a' && char <= 'z' {
                    set_char(line, cursor, char - 0x20);
                }
            }
            else if char >= 'A' && char <= 'Z' {
                set_char(line, cursor, char + 0x20);
            }

            cursor++;
        }

        line = line.next;
        line_number++;
        cursor = 0;
        if block {
            cursor = start_cursor;
        }
    }
}


// Data structures
struct Buffer {
    read_only: bool;
    has_changes: bool;
    path_allocated: bool;
    relative_path: string;
    title: GetBufferTitle;
    line_count: u32;
    line_count_digits: u32;
    lines: BufferLine*;
    last_change: Change*;
    next_change: Change*;
    syntax: Syntax*;
    escape_codes: EscapeCode*;
}

interface string GetBufferTitle()

free_buffer(Buffer* buffer, bool free_pointer = true, bool free_path = false) {
    if buffer == null return;

    line := buffer.lines;
    while line {
        next := line.next;
        free_line_and_children(line);
        line = next;
    }

    last := buffer.last_change;
    while last {
        new_last := last.previous;
        free_change(last);
        last = new_last;
    }

    next := buffer.next_change;
    while next {
        new_next := next.next;
        free_change(next);
        next = new_next;
    }

    if free_path && buffer.path_allocated {
        buffer.relative_path.length = 0;
        free_allocation(buffer.relative_path.data);
    }

    if free_pointer {
        free_allocation(buffer);
    }
}

line_buffer_length := 500; #const

struct BufferLine {
    allocated: bool;
    arena_index: u8;
    index: u16;
    length: u32;
    data: string;
    previous: BufferLine*;
    next: BufferLine*;
    parent: BufferLine*;
    child: BufferLine*;
}

struct EscapeCode {
    line: u32;
    column: u32;
    reset: bool;
    foreground_color: Vector4;
    background_color: Vector4;
    next: EscapeCode*;
}

open_buffers_list() {
    change_buffer_filter(empty_string);
    start_list_mode("Buffers", get_open_buffers, get_open_buffer_count, get_buffer, change_buffer_filter, open_buffer);
}

search_for_value_in_buffer() {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
        return;
    }

    line := get_buffer_line(buffer, buffer_window.line);
    if line == null || line.length == 0 {
        return;
    }

    cursor := clamp(buffer_window.cursor, 0, line.length - 1);
    cursor_char := get_char(line, cursor);
    if cursor_char == ' ' {
        return;
    }

    start_index := cursor;
    while start_index > 0 {
        if get_char(line, start_index - 1) == ' ' {
            break;
        }

        start_index--;
    }

    end_index := cursor;
    while end_index < line.length - 1 {
        if get_char(line, end_index + 1) == ' ' {
            break;
        }

        end_index++;
    }

    length := end_index - start_index + 1;
    search_buffer: Array<u8>[length];
    search: string = { length = length; data = search_buffer.data; }

    index := 0;
    each i in start_index..end_index {
        search[index++] = get_char(line, i);
    }

    open_search_list(search);
}

// Buffer and window functions
struct BufferWindow {
    cursor: u32;
    line: u32;
    start_line: u32;
    buffer_index := -1;
    hex_view: bool;
    start_byte: u32;
    previous: BufferWindow*;
    next: BufferWindow*;
    static_buffer: Buffer*;
}

struct EditorWindow {
    displayed: bool;
    buffer_window: BufferWindow*;
    current_jump: Jump*;
}

enum SelectedWindow {
    Left;
    Right;
}

BufferWindow* get_current_window() {
    workspace := get_workspace();

    editor_window: EditorWindow*;
    switch workspace.current_window {
        case SelectedWindow.Left;
            editor_window = &workspace.left_window;
        case SelectedWindow.Right;
            editor_window = &workspace.right_window;
    }

    bottom_window, bottom_focused := get_bottom_window(workspace);
    if bottom_focused && bottom_window != null {
        return bottom_window;
    }

    return editor_window.buffer_window;
}

BufferWindow*, bool get_bottom_window(Workspace* workspace) {
    run_window := get_run_window(workspace);
    if run_window {
        return run_window, workspace.bottom_window_selected;
    }

    terminal_window := get_terminal_window(workspace);
    if terminal_window {
        return terminal_window, workspace.bottom_window_selected;
    }

    return null, false;
}

BufferWindow*, Buffer* get_current_window_and_buffer() {
    buffer_window := get_current_window();
    if buffer_window {
        if buffer_window.buffer_index >= 0 {
            workspace := get_workspace();
            return buffer_window, &workspace.buffers[buffer_window.buffer_index];
        }

        if buffer_window.static_buffer {
            return buffer_window, buffer_window.static_buffer;
        }
    }

    return null, null;
}

BufferLine* get_buffer_line(Buffer* buffer, u32 target_line) {
    line_number: u32;
    target_line = clamp(target_line, 0, buffer.line_count - 1);
    line := buffer.lines;

    while line != null {
        if line_number == target_line {
            break;
        }

        line_number++;
        line = line.next;
    }

    return line;
}

u8 get_char(BufferLine* line, u32 index) {
    if index >= line.length return 0;

    if index < line_buffer_length {
        return line.data[index];
    }

    assert(line.child != null);

    index -= line_buffer_length;
    child := line.child;
    while index >= line_buffer_length {
        child = child.next;
        assert(child != null);
        index -= line_buffer_length;
    }

    return child.data[index];
}

set_char(BufferLine* line, u32 index, u8 char) {
    if index < line_buffer_length {
        line.data[index] = char;
        return;
    }

    assert(line.child != null);

    index -= line_buffer_length;
    child := line.child;
    while index >= line_buffer_length {
        child = child.next;
        assert(child != null);
        index -= line_buffer_length;
    }

    child.data[index] = char;
}

u32, u32 get_current_position() {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
        return 0, 0;
    }

    line_number: u32 = clamp(buffer_window.line, 0, buffer.line_count - 1);
    line := get_buffer_line(buffer, line_number);

    cursor: u32;
    if line.length
        cursor = clamp(buffer_window.cursor, 0, line.length - 1);

    return line_number, cursor;
}

adjust_start_line(BufferWindow* window) {
    if window == null return;

    if window.buffer_index < 0 && window.static_buffer == null {
        window.line = 0;
        window.start_line = 0;
        return;
    }

    max_lines, scroll_offset := determine_max_lines_and_scroll_offset(window);
    if scroll_offset > max_lines {
        window.start_line = window.line;
        return;
    }

    window.start_line = clamp(window.start_line, 0, window.line);

    buffer := window.static_buffer;
    if buffer == null {
        workspace := get_workspace();
        buffer = &workspace.buffers[window.buffer_index];
    }

    starting_line := buffer.lines;
    line_number := 0;
    while starting_line != null && line_number != window.start_line {
        starting_line = starting_line.next;
        line_number++;
    }

    if starting_line == null return;

    current_line := starting_line;
    max_chars := calculate_max_chars_per_line(window, buffer.line_count_digits);
    rendered_lines := calculate_rendered_lines(max_chars, current_line.length);
    while current_line != null && line_number != window.line {
        current_line = current_line.next;
        if current_line {
            rendered_lines += calculate_rendered_lines(max_chars, current_line.length);
            line_number++;
        }
    }

    if rendered_lines <= scroll_offset {
        while starting_line.previous != null && rendered_lines <= scroll_offset {
            window.start_line--;
            starting_line = starting_line.previous;
            rendered_lines += calculate_rendered_lines(max_chars, starting_line.length);
        }
    }
    else if rendered_lines + scroll_offset > max_lines && current_line != null {
        // Check that there are more lines to scroll to
        end_line := current_line.next;
        rendered_lines_after_current: u32;
        while end_line != null {
            rendered_lines_after_current += calculate_rendered_lines(max_chars, end_line.length);
            end_line = end_line.next;

            if rendered_lines_after_current >= scroll_offset {
                break;
            }
        }

        allowed_scroll_offset := scroll_offset;
        if rendered_lines_after_current < scroll_offset {
            allowed_scroll_offset = rendered_lines_after_current;
        }

        while starting_line != null && rendered_lines + allowed_scroll_offset > max_lines {
            window.start_line++;
            rendered_lines -= calculate_rendered_lines(max_chars, starting_line.length);
            starting_line = starting_line.next;
        }
    }
}

calculate_line_digits(Buffer* buffer) {
    digit_count: u32 = 1;
    value := 10;
    while value < buffer.line_count {
        value *= 10;
        digit_count++;
    }
    buffer.line_count_digits = digit_count;
}

bool is_whitespace(u8 char) {
    switch char {
        case ' ';
        case '\t';
        case '\r';
            return true;
    }

    return false;
}

#private

// Buffer list functions
Array<ListEntry> get_open_buffers() {
    return buffer_entries;
}

int get_open_buffer_count() {
    workspace := get_workspace();
    return workspace.buffers.length;
}

get_buffer(int thread, JobData data) {
    entry := cast(SelectedEntry*, data.pointer);
    key := entry.key;
    entry.can_free_buffer = false;

    workspace := get_workspace();
    each buffer in workspace.buffers {
        if buffer.relative_path == key {
            entry.buffer = &buffer;
            break;
        }
    }

    trigger_window_update();
}

change_buffer_filter(string filter) {
    workspace := get_workspace();
    if workspace.buffers.length > buffer_entries_reserved {
        while buffer_entries_reserved < workspace.buffers.length {
            buffer_entries_reserved += buffer_entries_block_size;
        }

        reallocate_array(&buffer_entries, buffer_entries_reserved);
    }

    if string_is_empty(filter) {
        buffer_entries.length = workspace.buffers.length;
        each buffer, i in workspace.buffers {
            buffer_entries[i] = {
                key = buffer.relative_path;
                display = buffer.relative_path;
            }
        }
    }
    else {
        buffer_entries.length = 0;
        each buffer in workspace.buffers {
            if string_contains(buffer.relative_path, filter) {
                buffer_entries[buffer_entries.length++] = {
                    key = buffer.relative_path;
                    display = buffer.relative_path;
                }
            }
        }
    }
}

open_buffer(string file) {
    open_file_buffer(file, false);
}

buffer_entries: Array<ListEntry>;
buffer_entries_reserved := 0;
buffer_entries_block_size := 10; #const

scratch_window: BufferWindow;

// Hex view functions
bytes_per_line := 16; #const

move_hex_view_cursor(BufferWindow* buffer_window, Buffer* buffer, BufferLine* line, bool left, int byte_changes) {
    buffer_window.cursor = clamp(buffer_window.cursor, 0, line.length);

    if left {
        while line != null && byte_changes > 0 {
            if buffer_window.cursor - byte_changes >= 0 {
                buffer_window.cursor -= byte_changes;
                byte_changes = 0;
            }
            else if line.previous {
                byte_changes -= buffer_window.cursor + 1;
                buffer_window.cursor = line.previous.length;
                buffer_window.line--;
            }
            else {
                byte_changes = 0;
            }

            line = line.previous;
        }
    }
    else {
        while line != null && byte_changes > 0 {
            if buffer_window.cursor + byte_changes <= line.length {
                buffer_window.cursor += byte_changes;
                byte_changes = 0;
            }
            else if line.next {
                byte_changes -= line.length - buffer_window.cursor + 1;
                buffer_window.cursor = 0;
                buffer_window.line++;
            }
            else {
                byte_changes = 0;
            }

            line = line.next;
        }
    }

    adjust_start_byte(buffer_window, buffer);
}

adjust_start_byte(BufferWindow* buffer_window, Buffer* buffer) {
    max_lines, _ := determine_max_lines_and_scroll_offset(buffer_window);
    max_bytes := max_lines * bytes_per_line;

    current_byte, current_line: u32;

    line := buffer.lines;
    while line != null {
        if current_line == buffer_window.line {
            if buffer_window.cursor > line.length {
                buffer_window.cursor = line.length;
                if line.next == null {
                    buffer_window.cursor--;
                }
            }
            current_byte += buffer_window.cursor;
            break;
        }
        else {
            current_byte += line.length + 1;
        }

        current_line++;
        line = line.next;
    }

    if buffer_window.start_byte > current_byte {
        while buffer_window.start_byte > current_byte {
            buffer_window.start_byte -= bytes_per_line;
        }
    }
    else if buffer_window.start_byte + max_bytes <= current_byte {
        while buffer_window.start_byte + max_bytes <= current_byte {
            buffer_window.start_byte += bytes_per_line;
        }
    }
}

bool add_byte_to_line(u8 byte, int* bytes, Array<u8> byte_line, int* byte_column, float x, float* y, u32* available_lines_to_render, u32 start_byte, bool cursor, int* cursor_column) {
    if *bytes < start_byte {
        *bytes = *bytes + 1;
        return true;
    }

    if *available_lines_to_render == 0
        return false;

    if *byte_column == byte_line.length {
        draw_byte_line(*bytes, byte_line, *byte_column, *cursor_column, x, *y);
        *available_lines_to_render = *available_lines_to_render - 1;
        *y = *y - global_font_config.line_height;
        *byte_column = 0;
        *cursor_column = -1;

        if *available_lines_to_render == 0
            return false;
    }

    if cursor {
        *cursor_column = *byte_column;
    }

    byte_line[*byte_column] = byte;
    *byte_column = *byte_column + 1;
    *bytes = *bytes + 1;
    return true;
}

draw_byte_line(int total_bytes, Array<u8> byte_line, int bytes_in_line, int cursor, float x, float y) {
    byte_string_buffer: Array<u8>[2];
    byte_string: string = { length = 2; data = byte_string_buffer.data; }

    start_byte := total_bytes - bytes_in_line;
    render_text(settings.font_size, x, y, appearance.font_color, vec4(), "0x%:", int_format(start_byte, 16, 8));
    x += global_font_config.quad_advance * 12;
    x_end := x + global_font_config.quad_advance * 3 * bytes_per_line;

    each i in bytes_in_line {
        byte := byte_line[i];
        byte_string[0] = to_hex_char((byte & 0xF0) >> 4);
        byte_string[1] = to_hex_char(byte & 0x0F);

        ascii_string: string = { length = 1; data = &byte; }
        if byte < ' ' || byte > '~' {
            byte = '.';
        }

        if i == cursor {
            render_text(byte_string, settings.font_size, x, y, appearance.cursor_font_color, appearance.cursor_color);
            render_text(ascii_string, settings.font_size, x_end, y, appearance.cursor_font_color, appearance.cursor_color);
        }
        else {
            render_text(byte_string, settings.font_size, x, y, appearance.font_color, vec4());
            render_text(ascii_string, settings.font_size, x_end, y, appearance.font_color, vec4());
        }

        x += global_font_config.quad_advance * 3;
        x_end += global_font_config.quad_advance;
    }
}

u8 to_hex_char(u8 value) {
    if value < 10 return value + '0';
    return value + '7';
}

// BufferWindow and Buffer support functions
BufferWindow* open_or_create_buffer_window(int buffer_index, BufferWindow* stack_top) {
    if stack_top != null && stack_top.buffer_index == buffer_index
        return stack_top;

    buffer_window := stack_top;
    while buffer_window {
        if buffer_window.buffer_index == buffer_index {
            if buffer_window.next {
                buffer_window.next.previous = buffer_window.previous;
            }
            if buffer_window.previous {
                buffer_window.previous.next = buffer_window.next;
            }

            buffer_window.next = stack_top;
            if stack_top {
                stack_top.previous = buffer_window;
            }

            return buffer_window;
        }

        buffer_window = buffer_window.next;
    }

    return allocate_buffer_window(buffer_index, stack_top);
}

BufferWindow* allocate_buffer_window(int buffer_index, BufferWindow* next) {
    buffer_window := new<BufferWindow>();
    buffer_window.buffer_index = buffer_index;
    buffer_window.next = next;
    if next {
        next.previous = buffer_window;
    }

    return buffer_window;
}

BufferWindow* copy_buffer_window_stack(BufferWindow* source) {
    if source == null return null;

    buffer_window := new<BufferWindow>();
    stack_top := buffer_window;
    while true {
        buffer_window.cursor = source.cursor;
        buffer_window.line = source.line;
        buffer_window.start_line = source.start_line;
        buffer_window.buffer_index = source.buffer_index;

        source = source.next;
        if source == null
            break;

        next := new<BufferWindow>();
        buffer_window.next = next;
        next.previous = buffer_window;
        buffer_window = next;
    }

    return stack_top;
}

BufferLine* move_to_next_non_whitespace(BufferWindow* window, BufferLine* line, u32 cursor) {
    while true {
        char_found := false;
        while cursor < line.length {
            char := get_char(line, cursor);
            if !is_whitespace(char) {
                char_found = true;
                break;
            }
            cursor++;
        }

        if char_found || line.next == null
            break;

        window.line++;
        cursor = 0;
        line = line.next;
    }

    window.cursor = cursor;
    return line;
}

// Removes whitespace from the end of line, returns true if the line is now empty
bool trim_line(BufferLine* line) {
    actual_length: u32;
    each i in line.length {
        char := get_char(line, i);
        if !is_whitespace(char) {
            actual_length = i + 1;
        }
    }

    line.length = actual_length;
    return actual_length == 0;
}

bool is_text_character(u8 char) {
    if char >= '0' && char <= '9'
        return true;

    if char >= 'A' && char <= 'Z'
        return true;

    if char >= 'a' && char <= 'z'
        return true;

    return char == '_';
}

BufferLine* get_next_line_with_text(BufferLine* line) {
    assert(line != null);

    line = line.next;
    while line {
        if !trim_line(line) {
            return line;
        }
        line = line.next;
    }

    return line;
}

// Functions for merging/deleting lines
merge_lines(Buffer* buffer, BufferLine* start_line, BufferLine* end_line, u32 end_start_line, u32 beginning_end_line, bool delete_end_cursor = true, bool joining = false) {
    start_line.length = end_start_line;
    if beginning_end_line < end_line.length {
        if joining {
            beginning_end_line = 0;
            while beginning_end_line < end_line.length {
                if get_char(end_line, beginning_end_line) != ' '
                    break;

                beginning_end_line++;
            }

            if end_line.length - beginning_end_line {
                add_text_to_end_of_line(start_line, " ");
                end_start_line++;
            }
        }
        else {
            if delete_end_cursor {
                beginning_end_line++;
            }
        }

        if end_start_line < start_line.length {
            delete_from_line(start_line, end_start_line, start_line.length - 1);
        }

        copy_length := end_line.length - beginning_end_line;
        if copy_length {
            if end_line.length <= line_buffer_length {
                add_text_to_end_of_line(start_line, end_line.data.data + beginning_end_line, copy_length);
            }
            else {
                if beginning_end_line < line_buffer_length {
                    copy_section := line_buffer_length - beginning_end_line;
                    add_text_to_end_of_line(start_line, end_line.data.data + beginning_end_line, copy_section);
                }

                child := end_line.child;
                index := line_buffer_length;
                while child {
                    if beginning_end_line <= index {
                        add_text_to_end_of_line(start_line, child.data.data, child.length);
                    }
                    else {
                        start := beginning_end_line - index;
                        copy_section := end_line.length - start;
                        add_text_to_end_of_line(start_line, child.data.data + start, copy_section);
                    }
                    child = child.next;
                    index += line_buffer_length;
                }
            }
        }
    }

    if start_line.next != end_line {
        line_to_free := start_line.next;
        while line_to_free != end_line {
            line_to_free = line_to_free.next;
            free_line_and_children(line_to_free.previous);
            buffer.line_count--;
        }
    }

    start_line.next = end_line.next;
    if start_line.next
        start_line.next.previous = start_line;

    free_line_and_children(end_line);
    buffer.line_count--;

    calculate_line_digits(buffer);
}

delete_lines(BufferWindow* buffer_window, Buffer* buffer, u32 start_line, u32 end_line, bool delete_all, bool indent = true, bool copy = true) {
    if copy {
        copy_lines(buffer_window, buffer, start_line, end_line);
    }

    line := get_buffer_line(buffer, start_line);
    if start_line == end_line {
        if delete_all {
            if line.previous == null {
                if line.next == null {
                    line.length = 0;
                    buffer_window.cursor = 0;
                    return;
                }
                else {
                    buffer.lines = line.next;
                    line.next.previous = null;
                }
            }
            else {
                line.previous.next = line.next;
                if line.next {
                    line.next.previous = line.previous;
                }
            }

            free_line_and_children(line);
            buffer.line_count--;

            calculate_line_digits(buffer);
            adjust_start_line(buffer_window);
        }
        else {
            line.length = 0;
            buffer_window.cursor = 0;
        }
    }
    else {
        buffer_window.line = start_line;
        if !delete_all {
            line.length = 0;
            buffer_window.cursor = 0;
        }

        delete_lines_in_range(buffer, line, end_line - start_line, delete_all);

        calculate_line_digits(buffer);
        adjust_start_line(buffer_window);
    }

    if !delete_all && indent {
        indent_line(buffer_window, line);
    }
}

// Formatting helpers
indent_line(BufferWindow* buffer_window, BufferLine* line) {
    indent_length := 0;
    parsing_indents := true;
    has_open_brace := false;

    line_to_copy_indentation := line.previous;
    while line_to_copy_indentation {
        if line_to_copy_indentation.length
            break;

        line_to_copy_indentation = line_to_copy_indentation.previous;
    }

    if line_to_copy_indentation == null {
        line_to_copy_indentation = line.next;
        while line_to_copy_indentation {
            if line_to_copy_indentation.length
                break;

            line_to_copy_indentation = line_to_copy_indentation.next;
        }
    }

    if line_to_copy_indentation {
        each i in line_to_copy_indentation.length {
            char := get_char(line_to_copy_indentation, i);
            if parsing_indents {
                if char == ' ' {
                    indent_length++;
                }
                else {
                    parsing_indents = false;
                }
            }
            else {
                if char == '{' {
                    has_open_brace = true;
                }
                else if has_open_brace && char == '}' {
                    has_open_brace = false;
                }
            }
        }
    }

    if has_open_brace
        indent_length += settings.tab_size;

    if indent_length {
        indent_line(line, indent_length);
        buffer_window.cursor = indent_length;
    }
}

indent_line(BufferLine* line, u32 indent_length) {
    indent_string := create_empty_string(indent_length);
    add_text_to_line(line, indent_string);
}

// Movement helpers
scroll_buffer(Workspace* workspace, BufferWindow* window, bool up, u32 line_changes = 3) {
    if window.buffer_index < 0 {
        window.line = 0;
        window.start_line = 0;
        return;
    }

    buffer := &workspace.buffers[window.buffer_index];
    if window.hex_view {
        window.line = clamp(window.line, 0, buffer.line_count - 1);
        line := get_buffer_line(buffer, window.line);
        byte_changes := line_changes * bytes_per_line;
        move_hex_view_cursor(window, buffer, line, up, byte_changes);
        return;
    }

    if up window.start_line -= line_changes;
    else  window.start_line += line_changes;

    window.start_line = clamp(window.start_line, 0, buffer.line_count - 1);
    window.line = clamp(window.line, window.start_line, buffer.line_count - 1);

    if window.hex_view {
        line := get_buffer_line(buffer, window.line);
        byte_changes := line_changes * bytes_per_line;
        move_hex_view_cursor(window, buffer, line, up, byte_changes);
        return;
    }

    max_lines, scroll_offset := determine_max_lines_and_scroll_offset(window);
    if scroll_offset > max_lines {
        window.line = window.start_line;
        return;
    }

    starting_line := buffer.lines;
    line_number := 0;
    while starting_line != null && line_number != window.start_line {
        starting_line = starting_line.next;
        line_number++;
    }

    current_line := starting_line;
    max_chars := calculate_max_chars_per_line(window, buffer.line_count_digits);
    rendered_lines := calculate_rendered_lines(max_chars, current_line.length);
    while current_line != null && line_number != window.line {
        current_line = current_line.next;
        rendered_lines += calculate_rendered_lines(max_chars, current_line.length);
        line_number++;
    }

    if !up {
        if rendered_lines <= scroll_offset {
            while current_line.next != null && rendered_lines <= scroll_offset {
                window.line++;
                current_line = current_line.next;
                rendered_lines += calculate_rendered_lines(max_chars, current_line.length);
            }
        }
        return;
    }

    if rendered_lines + scroll_offset > max_lines && current_line != null {
        // Check that there are more lines to scroll to
        end_line := current_line.next;
        rendered_lines_after_current: u32;
        while end_line != null {
            rendered_lines_after_current += calculate_rendered_lines(max_chars, end_line.length);
            end_line = end_line.next;

            if rendered_lines + rendered_lines_after_current > max_lines {
                break;
            }
        }

        if rendered_lines + rendered_lines_after_current > max_lines {
            while current_line != null && rendered_lines + scroll_offset > max_lines {
                window.line--;
                rendered_lines -= calculate_rendered_lines(max_chars, current_line.length);
                current_line = current_line.previous;
            }
        }
    }
}

u32 calculate_rendered_lines(u32 max_chars, u32 line_length) {
    lines := line_length / max_chars + 1;

    return lines;
}

u32 calculate_max_chars_per_line(BufferWindow* window, u32 digits) {
    workspace := get_workspace();

    both_windows_open := workspace.left_window.displayed && workspace.right_window.displayed;
    if !both_windows_open || window == get_run_window(workspace) || window == get_terminal_window(workspace) {
        return global_font_config.max_chars_per_line_full - digits - 1;
    }

    return global_font_config.max_chars_per_line - digits - 1;
}

u32, u32 determine_max_lines_and_scroll_offset(BufferWindow* buffer_window) {
    workspace := get_workspace();
    run_window := get_run_window(workspace);
    terminal_window := get_terminal_window(workspace);

    if run_window == null && terminal_window == null {
        return global_font_config.max_lines_without_bottom_window, settings.scroll_offset;
    }

    if run_window == buffer_window || terminal_window == buffer_window {
        return global_font_config.bottom_window_max_lines, settings.scroll_offset / 4;
    }

    return global_font_config.max_lines_with_bottom_window, settings.scroll_offset;
}
