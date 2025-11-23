// Buffer rendering
draw_buffers() {
    if !is_font_ready(settings.font_size) return;

    if left_window.displayed && right_window.displayed {
        divider_quad: QuadInstanceData = {
            color = appearance.font_color;
            position = { y = global_font_config.divider_y; }
            flags = QuadFlags.Solid;
            width = 1.0 / settings.window_width;
            height = global_font_config.divider_height;
        }

        draw_quad(&divider_quad, 1);
    }

    if left_window.displayed {
        draw_buffer_window(left_window.buffer_window, -1.0, current_window == SelectedWindow.Left, !right_window.displayed);
    }

    if right_window.displayed {
        x := 0.0;
        if !left_window.displayed {
            x = -1.0;
        }
        draw_buffer_window(right_window.buffer_window, x, current_window == SelectedWindow.Right, !left_window.displayed);
    }

    draw_command();
}

draw_buffer_window(BufferWindow* window, float x, bool selected, bool full_width) {
    if window == null {
        window = &scratch_window;
    }

    line_max_x := x + 1.0;
    if full_width line_max_x += 1.0;

    y := 1.0 - global_font_config.first_line_offset;

    info_quad: QuadInstanceData = {
        color = appearance.current_line_color;
        position = { x = (x + line_max_x) / 2; y = y - global_font_config.max_lines * global_font_config.line_height + global_font_config.block_y_offset; z = 0.2; }
        flags = QuadFlags.Solid;
        width = line_max_x - x;
        height = global_font_config.line_height;
    }

    draw_quad(&info_quad, 1);

    if window.buffer_index < 0 return;

    buffer := buffers[window.buffer_index];
    line_background_quad: QuadInstanceData = {
        color = {
            x = appearance.background_color.x;
            y = appearance.background_color.y;
            z = appearance.background_color.z;
            w = 1.0;
        }
        position = {
            x = x + global_font_config.quad_advance * buffer.line_count_digits / 2.0;
            y = global_font_config.line_height;
            z = 0.4;
        }
        flags = QuadFlags.Solid;
        width = global_font_config.quad_advance * buffer.line_count_digits;
        height = global_font_config.line_height * global_font_config.max_lines;
    }

    draw_quad(&line_background_quad, 1);

    start_line := clamp(window.start_line, 0, buffer.line_count - 1);
    cursor_line := clamp(window.line, 0, buffer.line_count - 1) + 1;
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
    line := buffer.lines;
    line_number: u32 = 1;
    line_cursor: u32;
    available_lines_to_render := global_font_config.max_lines;

    while line != null && available_lines_to_render > 0 {
        if line_number > start_line {
            // TODO Handle long lines
            line_string: string = { length = line.length; data = line.data.data; }
            cursor, visual_start, visual_end := -1;

            if line_number == cursor_line ||
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

            lines := render_line(line_string, x, y, line_number, digits, cursor, selected, line_max_x, available_lines_to_render, visual_start, visual_end);
            y -= global_font_config.line_height * lines;
            available_lines_to_render -= lines;
        }
        line = line.next;
        line_number++;
    }

    // Render the file information
    y = 1.0 - global_font_config.first_line_offset - global_font_config.line_height * global_font_config.max_lines;
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

        render_text(mode_string, settings.font_size, x, y, appearance.font_color, highlight_color);
        x += mode_string.length * global_font_config.quad_advance;
    }

    render_text(buffer.relative_path, settings.font_size, x + global_font_config.quad_advance, y, appearance.font_color, vec4());

    render_text(settings.font_size, line_max_x, y, appearance.font_color, highlight_color, " %/% % ", TextAlignment.Right, cursor_line, buffer.line_count, line_cursor + 1);
}

// Opening buffers with files
open_file_buffer(string path) {
    buffer_index := -1;

    each buffer, i in buffers {
        if buffer.relative_path == path {
            buffer_index = i;
            break;
        }
    }

    if buffer_index < 0 {
        buffer: FileBuffer = {
            relative_path = path;
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

        array_insert(&buffers, buffer, allocate, reallocate);
        buffer_index = buffers.length - 1;
    }

    switch current_window {
        case SelectedWindow.Left; {
            record_jump(left_window.buffer_window);
            left_window.buffer_window = open_or_create_buffer_window(buffer_index, left_window.buffer_window);
        }
        case SelectedWindow.Right; {
            record_jump(right_window.buffer_window);
            right_window.buffer_window = open_or_create_buffer_window(buffer_index, right_window.buffer_window);
        }
    }
}

switch_or_focus_buffer(SelectedWindow window) {
    if window != current_window {
        switch_to_buffer(window);
        return;
    }

    switch window {
        case SelectedWindow.Left; {
            right_window.displayed = false;
        }
        case SelectedWindow.Right; {
            left_window.displayed = false;
        }
    }
}

switch_to_buffer(SelectedWindow window) {
    if window == current_window return;

    original_window, new_window: EditorWindow*;
    switch window {
        case SelectedWindow.Left; {
            original_window = &right_window;
            new_window = &left_window;
        }
        case SelectedWindow.Right; {
            original_window = &left_window;
            new_window = &right_window;
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

    current_window = window;
}

swap_top_buffer() {
    editor_window: EditorWindow*;
    switch current_window {
        case SelectedWindow.Left;
            editor_window = &left_window;
        case SelectedWindow.Right;
            editor_window = &right_window;
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
    buffer_window: BufferWindow*;
    switch current_window {
        case SelectedWindow.Left; {
            left_window.buffer_window = open_or_create_buffer_window(buffer_index, left_window.buffer_window);
            buffer_window = left_window.buffer_window;
        }
        case SelectedWindow.Right; {
            right_window.buffer_window = open_or_create_buffer_window(buffer_index, right_window.buffer_window);
            buffer_window = right_window.buffer_window;
        }
    }

    buffer_window.line = line;
    buffer_window.cursor = cursor;
    adjust_start_line(buffer_window);
}

close_window(bool save) {
    editor_window, other_window: EditorWindow*;
    switch current_window {
        case SelectedWindow.Left; {
            editor_window = &left_window;
            other_window = &left_window;
            current_window = SelectedWindow.Right;
        }
        case SelectedWindow.Right; {
            editor_window = &right_window;
            other_window = &right_window;
            current_window = SelectedWindow.Left;
        }
    }

    clear_jumps();

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
        signal_shutdown();
    }
}

// Saving buffers to a file
bool, u32, u32, string save_buffer(int buffer_index) {
    if buffer_index < 0 || buffer_index >= buffers.length
        return true, 0, 0, empty_string;

    lines_written, bytes_written: u32;
    buffer := &buffers[buffer_index];

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

copy_lines(BufferWindow* buffer_window, FileBuffer* buffer, u32 start_line, u32 end_line) {
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

copy_block(FileBuffer* buffer, u32 start_line, u32 start_cursor, u32 end_line, u32 end_cursor) {
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
        // TODO Handle long lines
        each j in start_cursor..end_cursor {
            if j >= current_line.length {
                copy_string[i] = ' ';
            }
            else {
                copy_string[i] = current_line.data[j];
            }
            i++;
        }

        if line_number != end_line {
            copy_string.data[i] = '\n';
            i++;
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

copy_selected(BufferWindow* buffer_window, FileBuffer* buffer, u32 line_1, u32 cursor_1, u32 line_2, u32 cursor_2, bool include_end = true) {
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
            // TODO Handle long lines
            if current_line == start_line {
                length := current_line.length - start_cursor;
                memory_copy(copy_string.data + i, current_line.data.data + start_cursor, length);
                copy_string.data[i + length] = '\n';
                i += length + 1;
            }
            else if current_line == end_line {
                memory_copy(copy_string.data + i, current_line.data.data, end_cursor);
                if include_end {
                    copy_string.data[i + end_cursor] = current_line.data[end_cursor];
                }
            }
            else {
                memory_copy(copy_string.data + i, current_line.data.data, current_line.length);
                copy_string.data[i + current_line.length] = '\n';
                i += current_line.length + 1;
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
                copy_end = end;
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
    if buffer_window == null || buffer == null {
        return;
    }

    buffer_window.line = clamp(buffer_window.line, 0, buffer.line_count - 1);
    paste_clipboard(buffer_window, buffer, before, false, paste_count, false);
}

paste_over_selected(u32 paste_count) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
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

paste_clipboard(BufferWindow* buffer_window, FileBuffer* buffer, bool before, bool over_lines, u32 paste_count, bool change_recorded, u32 additional_lines_to_record = 0) {
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

BufferLine* paste_lines(BufferWindow* buffer_window, FileBuffer* buffer, BufferLine* line, Array<string> clipboard_lines, u32 paste_count, u32 cursor = 0, bool wrap = false) {
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
    if buffer_window == null || buffer == null {
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
    if buffer_window == null || buffer == null {
        return;
    }

    record_insert_mode_change(buffer, buffer_window.line, buffer_window.cursor);
}

add_text_to_line(string text) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
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
        // TODO Handle long lines
        each i in line.length - cursor {
            line.data[line.length + text.length - 1 - i] = line.data[line.length - 1 - i];
        }

        memory_copy(line.data.data + cursor, text.data, text.length);
        line.length += text.length;
        new_cursor = cursor + text.length;
    }

    return new_cursor;
}

u32 add_text_to_end_of_line(BufferLine* line, string text) {
    new_length := line.length + text.length;
    if new_length <= line_buffer_length {
        memory_copy(line.data.data + line.length, text.data, text.length);
    }
    else {
        current_child := line.length / line_buffer_length;
        child_lines := (line.length + text.length) / line_buffer_length;

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
    if buffer_window == null || buffer == null {
        return;
    }

    block_insert_data.start_line, block_insert_data.end_line = get_visual_start_and_end_lines(buffer_window);

    begin_block_insert_mode_change(buffer, block_insert_data.start_line, block_insert_data.end_line, buffer_window.cursor, buffer_window.line);
}

start_block_insert_mode() {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
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
    if buffer_window == null || buffer == null {
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
    if buffer_window == null || buffer == null {
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
    if buffer_window == null || buffer == null {
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
    if buffer_window == null || buffer == null {
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

delete_lines_in_range(FileBuffer* buffer, BufferLine* line, u32 count, bool delete_all = false) {
    start := line;
    new_next := line.next;

    each i in count {
        next := new_next.next;
        free_line(new_next);
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

        free_line(start);
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
    if buffer_window == null || buffer == null {
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
    if buffer_window == null || buffer == null {
        return;
    }

    delete_selected(buffer_window, buffer, line_1, cursor_1, line_2, cursor_2, delete_end_cursor, true, record, inserting);
}

delete_selected(BufferWindow* buffer_window, FileBuffer* buffer, u32 line_1, u32 cursor_1, u32 line_2, u32 cursor_2, bool delete_end_cursor, bool copy, bool record, bool inserting) {
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
    if buffer_window == null || buffer == null {
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
        // TODO Handle long lines
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
    if buffer_window == null || buffer == null {
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
    if buffer_window == null || buffer == null {
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
        if line.data[i] != ' ' {
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
        // TODO Handle long lines
        return line.length;
    }

    if end >= line.length {
        // TODO Handle long lines
        line.length = start;
    }
    else {
        delete_length := end - start;
        if delete_end_cursor {
            end++;
            delete_length++;
        }

        // TODO Handle long lines
        memory_copy(line.data.data + start, line.data.data + end, line.length - delete_length);
        line.length -= delete_length;
    }

    return start;
}

join_lines(u32 lines) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
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
    if buffer_window == null || buffer == null {
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

BufferLine* add_new_line(BufferWindow* buffer_window, FileBuffer* buffer, BufferLine* line, bool above, bool split) {
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

        buffer_window.line++;
    }

    buffer.line_count++;
    return new_line;
}

BufferLine* add_new_line(FileBuffer* buffer, BufferLine* line, u32 cursor) {
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
    if buffer_window == null || buffer == null {
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
                if line.data[available_whitespace] != ' '
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
    if buffer_window == null || buffer == null {
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
        line.data[i++] = char;
    }
}

// Event handlers
handle_buffer_scroll(ScrollDirection direction) {
    x, y := get_cursor_position();

    if left_window.displayed && (!right_window.displayed || x < 0.0) {
        scroll_buffer(left_window.buffer_window, direction == ScrollDirection.Up);
    }
    else if right_window.displayed && (!left_window.displayed || x > 0.0) {
        scroll_buffer(right_window.buffer_window, direction == ScrollDirection.Up);
    }
}

enum ScrollTo {
    Top;
    Middle;
    Bottom;
}

scroll_to_position(ScrollTo scroll_position) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
        return;
    }

    buffer_window.line = clamp(buffer_window.line, 0, buffer.line_count - 1);

    switch scroll_position {
        case ScrollTo.Top;
            buffer_window.start_line = buffer_window.line;
        case ScrollTo.Middle; {
            buffer_window.start_line = buffer_window.line;
            lines_to_offset := global_font_config.max_lines / 2;
            max_chars := calculate_max_chars_per_line(buffer.line_count_digits);

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
    if left_window.displayed
        adjust_start_line(left_window.buffer_window);
    if right_window.displayed
        adjust_start_line(right_window.buffer_window);
}

go_to_line(s32 line) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
        return;
    }

    record_jump(buffer_window);

    if line < 0 {
        buffer_window.line = clamp(buffer.line_count + line, 0, buffer.line_count - 1);
    }
    else {
        buffer_window.line = clamp(line - 1, 0, buffer.line_count - 1);
    }

    adjust_start_line(buffer_window);
}

move_line(bool up, bool with_wrap, u32 line_changes, bool move_to_first = false) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
        return;
    }

    buffer_window.line = clamp(buffer_window.line, 0, buffer.line_count - 1);

    if with_wrap {
        max_chars := calculate_max_chars_per_line(buffer.line_count_digits);
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
                char := line.data[cursor];
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

    line := get_buffer_line(buffer, buffer_window.line);
    if line == null || line.length == 0 {
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

    char: u8;
    is_whitespace := false;
    cursor: u32;
    if line.length == 0 {
        is_whitespace = true;
    }
    else {
        cursor = clamp(buffer_window.cursor, 0, line.length - 1);
        char = line.data[cursor];
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
                char = line.data[cursor];
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
            previous_char := line.data[cursor - 1];
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
                        char = line.data[cursor];
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

            previous_char := line.data[cursor - 1];
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

    char: u8;
    is_whitespace, is_last := false;
    cursor: u32;
    if line.length == 0 {
        is_whitespace = true;
    }
    else {
        cursor = clamp(buffer_window.cursor, 0, line.length - 1);
        char = line.data[cursor];
        is_whitespace = is_whitespace(char);
    }

    if !is_whitespace && cursor < line.length - 1 {
        is_text := is_text_character(char);
        next_char := line.data[cursor + 1];
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
    char = line.data[cursor];
    is_text := is_text_character(char);
    while cursor < line.length {
        if cursor + 1 == line.length {
            break;
        }

        next_char := line.data[cursor + 1];
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
    if line == null {
        return;
    }

    if line.length <= 1 {
        buffer_window.cursor = 0;
        return;
    }

    if with_wrap {
        max_chars := calculate_max_chars_per_line(buffer.line_count_digits);
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
                char := line.data[cursor];
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
    if line == null {
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
    if buffer_window == null || buffer == null {
        return;
    }

    line_number := clamp(buffer_window.line, 0, buffer.line_count - 1);
    line := get_buffer_line(buffer, line_number);

    if line.length == 0 return;

    cursor := clamp(buffer_window.cursor, 0, line.length - 1);

    match_char, complement_char: u8;
    forward: bool;
    while cursor < line.length {
        complement_char = line.data[cursor];
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
                    char := line.data[i];
                    if char == '"' {
                        if i == 0 || line.data[i - 1] != '\\' {
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
                    char := line.data[cursor - i - 1];
                    if char == '"' {
                        if i == cursor - 1 || line.data[cursor - i - 2] != '\\' {
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
    if buffer_window == null || buffer == null {
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
            if line.data[cursor] == char[0] {
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
            if line.data[cursor] == char[0] {
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
                if line.data.data[cursor] == value[0] {
                    matched := true;
                    each i in 1..value.length - 1 {
                        if line.data.data[cursor + i] != value[i] {
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
                if line.data.data[cursor] == value[value.length - 1] {
                    matched := true;
                    each i in 1..value.length - 1 {
                        if line.data.data[cursor - i] != value[value.length - 1 - i] {
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
    buffer: FileBuffer*;
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
    if find_and_replace_data.buffer_window == null || find_and_replace_data.buffer == null {
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
            if find_and_replace_data.line.data.data[find_and_replace_data.cursor] == find_and_replace_data.value[0] {
                matched := true;
                if value_lines.length == 1 {
                    each i in 1..find_and_replace_data.value.length - 1 {
                        if find_and_replace_data.line.data.data[find_and_replace_data.cursor + i] != find_and_replace_data.value[i] {
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
                                    if current_line.data.data[cursor + j] != line[j] {
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
                                if current_line.data.data[cursor + j] != line[j] {
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
    if buffer_window == null || buffer == null {
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

    starting_line := get_buffer_line(buffer, start_line);
    comment_string := get_comment_string(buffer.relative_path);

    // Determine whether to comment or uncomment the lines
    all_lines_commented := true;
    comment_cursor: u32 = 0xFFFFFFF;
    {
        line := starting_line;
        line_number := start_line;
        while line != null && line_number <= end_line {
            each i in line.length {
                if line.data[i] != ' ' {
                    has_comment := true;
                    if comment_string.length <= line.length - i {
                        each j in comment_string.length {
                            if line.data[i + j] != comment_string[j] {
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
                if line.data[i] != ' ' {
                    delete_length := comment_string.length;
                    if i + delete_length < line.length && line.data[i + delete_length] == ' ' {
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

    edit_mode = EditMode.Normal;
}

string get_comment_string(string path) {
    extension: string;
    each i in path.length {
         if path[i] == '.' {
             extension = {
                 length = path.length - i - 1;
                 data = path.data + i + 1;
             }
         }
         else if path[i] == '/' {
             extension.length = 0;
         }
    }

    return "//";
}

toggle_casing(bool upper) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
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
            char := line.data[cursor];
            if upper {
                if char >= 'a' && char <= 'z' {
                    line.data[cursor] = char - 0x20;
                }
            }
            else if char >= 'A' && char <= 'Z' {
                line.data[cursor] = char + 0x20;
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
struct FileBuffer {
    relative_path: string;
    line_count: u32;
    line_count_digits: u32;
    lines: BufferLine*;
    last_change: Change*;
    next_change: Change*;
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

buffers: Array<FileBuffer>;

struct BufferWindow {
    cursor: u32;
    line: u32;
    start_line: u32;
    buffer_index := -1;
    previous: BufferWindow*;
    next: BufferWindow*;
}

struct EditorWindow {
    displayed: bool;
    buffer_window: BufferWindow*;
}

left_window: EditorWindow = { displayed = true; }
right_window: EditorWindow;

enum SelectedWindow {
    Left;
    Right;
}

current_window: SelectedWindow;

BufferWindow* get_current_window() {
    editor_window: EditorWindow*;
    switch current_window {
        case SelectedWindow.Left;
            editor_window = &left_window;
        case SelectedWindow.Right;
            editor_window = &right_window;
    }

    return editor_window.buffer_window;
}

BufferWindow*, FileBuffer* get_current_window_and_buffer() {
    buffer_window := get_current_window();
    if buffer_window == null || buffer_window.buffer_index < 0 {
        return null, null;
    }

    return buffer_window, &buffers[buffer_window.buffer_index];
}

BufferLine* get_buffer_line(FileBuffer* buffer, u32 target_line) {
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

    if window.buffer_index < 0 {
        window.line = 0;
        window.start_line = 0;
        return;
    }

    if settings.scroll_offset > global_font_config.max_lines {
        window.start_line = window.line;
        return;
    }

    window.start_line = clamp(window.start_line, 0, window.line);

    buffer := buffers[window.buffer_index];
    starting_line := buffer.lines;
    line_number := 0;
    while starting_line != null && line_number != window.start_line {
        starting_line = starting_line.next;
        line_number++;
    }

    if starting_line == null return;

    current_line := starting_line;
    max_chars := calculate_max_chars_per_line(buffer.line_count_digits);
    rendered_lines := calculate_rendered_lines(max_chars, current_line.length);
    while current_line != null && line_number != window.line {
        current_line = current_line.next;
        if current_line {
            rendered_lines += calculate_rendered_lines(max_chars, current_line.length);
            line_number++;
        }
    }

    if rendered_lines <= settings.scroll_offset {
        while starting_line.previous != null && rendered_lines <= settings.scroll_offset {
            window.start_line--;
            starting_line = starting_line.previous;
            rendered_lines += calculate_rendered_lines(max_chars, starting_line.length);
        }
    }
    else if rendered_lines + settings.scroll_offset > global_font_config.max_lines && current_line != null {
        // Check that there are more lines to scroll to
        end_line := current_line.next;
        rendered_lines_after_current: u32;
        while end_line != null {
            rendered_lines_after_current += calculate_rendered_lines(max_chars, end_line.length);
            end_line = end_line.next;

            if rendered_lines_after_current >= settings.scroll_offset {
                break;
            }
        }

        allowed_scroll_offset := settings.scroll_offset;
        if rendered_lines_after_current < settings.scroll_offset {
            allowed_scroll_offset = rendered_lines_after_current;
        }

        while starting_line != null && rendered_lines + allowed_scroll_offset > global_font_config.max_lines {
            window.start_line++;
            rendered_lines -= calculate_rendered_lines(max_chars, starting_line.length);
            starting_line = starting_line.next;
        }
    }
}

calculate_line_digits(FileBuffer* buffer) {
    digit_count: u32 = 1;
    value := 10;
    while value < buffer.line_count {
        value *= 10;
        digit_count++;
    }
    buffer.line_count_digits = digit_count;
}

#private

scratch_window: BufferWindow;

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
            char := line.data[cursor];
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
        if !is_whitespace(line.data[i]) {
            actual_length = i + 1;
        }
    }

    line.length = actual_length;
    return actual_length == 0;
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
merge_lines(FileBuffer* buffer, BufferLine* start_line, BufferLine* end_line, u32 end_start_line, u32 beginning_end_line, bool delete_end_cursor = true, bool joining = false) {
    start_line.length = end_start_line;
    if beginning_end_line < end_line.length {
        copy_length: u32;
        if joining {
            beginning_end_line = 0;
            while beginning_end_line < end_line.length {
                if end_line.data[beginning_end_line] != ' '
                    break;

                beginning_end_line++;
            }

            copy_length = end_line.length - beginning_end_line;
            if copy_length {
                start_line.data[start_line.length] = ' ';
                start_line.length++;
                end_start_line++;
            }
        }
        else {
            copy_length = end_line.length - beginning_end_line;
            if delete_end_cursor {
                copy_length--;
                beginning_end_line++;
            }
        }

        if copy_length {
            // TODO Handle long lines
            memory_copy(start_line.data.data + end_start_line, end_line.data.data + beginning_end_line, copy_length);
            start_line.length += copy_length;
        }
    }

    if start_line.next != end_line {
        line_to_free := start_line.next;
        while line_to_free != end_line {
            line_to_free = line_to_free.next;
            free_line(line_to_free.previous);
            buffer.line_count--;
        }
    }

    start_line.next = end_line.next;
    if start_line.next
        start_line.next.previous = start_line;

    free_line(end_line);
    buffer.line_count--;

    calculate_line_digits(buffer);
}

delete_lines(BufferWindow* buffer_window, FileBuffer* buffer, u32 start_line, u32 end_line, bool delete_all, bool indent = true, bool copy = true) {
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

            free_line(line);
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
            char := line_to_copy_indentation.data[i];
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
scroll_buffer(BufferWindow* window, bool up, u32 line_changes = 3) {
    if window.buffer_index < 0 {
        window.line = 0;
        window.start_line = 0;
        return;
    }

    if up window.start_line -= line_changes;
    else  window.start_line += line_changes;

    buffer := buffers[window.buffer_index];
    window.start_line = clamp(window.start_line, 0, buffer.line_count - 1);
    window.line = clamp(window.line, window.start_line, buffer.line_count - 1);

    if settings.scroll_offset > global_font_config.max_lines {
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
    max_chars := calculate_max_chars_per_line(buffer.line_count_digits);
    rendered_lines := calculate_rendered_lines(max_chars, current_line.length);
    while current_line != null && line_number != window.line {
        current_line = current_line.next;
        rendered_lines += calculate_rendered_lines(buffer.line_count_digits, current_line.length);
        line_number++;
    }

    if !up {
        if rendered_lines <= settings.scroll_offset {
            while current_line.next != null && rendered_lines <= settings.scroll_offset {
                window.line++;
                current_line = current_line.next;
                rendered_lines += calculate_rendered_lines(max_chars, starting_line.length);
            }
        }
        return;
    }

    if rendered_lines + settings.scroll_offset > global_font_config.max_lines && current_line != null {
        // Check that there are more lines to scroll to
        end_line := current_line.next;
        rendered_lines_after_current: u32;
        while end_line != null {
            rendered_lines_after_current += calculate_rendered_lines(max_chars, end_line.length);
            end_line = end_line.next;

            if rendered_lines + rendered_lines_after_current > global_font_config.max_lines {
                break;
            }
        }

        if rendered_lines + rendered_lines_after_current > global_font_config.max_lines {
            while current_line != null && rendered_lines + settings.scroll_offset > global_font_config.max_lines {
                window.line--;
                rendered_lines -= calculate_rendered_lines(max_chars, current_line.length);
                current_line = current_line.previous;
            }
        }
    }
}

go_to_buffer_line(BufferWindow* window, u32 line) {
    if window.buffer_index < 0 {
        window.line = 0;
        window.start_line = 0;
        return;
    }

    buffer := buffers[window.buffer_index];
    window.line = clamp(line - 1, 0, buffer.line_count - 1);
    adjust_start_line(window);
}

move_buffer_cursor(BufferWindow* window, bool left, u32 cursor_changes = 1) {
    if window.buffer_index < 0 {
        window.line = 0;
        window.start_line = 0;
        return;
    }

    buffer := buffers[window.buffer_index];
}

u32 calculate_rendered_lines(u32 max_chars, u32 line_length) {
    lines := line_length / max_chars + 1;

    return lines;
}

u32 calculate_max_chars_per_line(u32 digits) {
    full_width := left_window.displayed ^ right_window.displayed;

    if full_width {
        return global_font_config.max_chars_per_line_full - digits - 1;
    }

    return global_font_config.max_chars_per_line - digits - 1;
}
