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
    if window == null return;

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
            line_string: string = { length = line.length; data = line.data.data; }
            cursor, visual_start, visual_end := -1;

            if line_number == cursor_line {
                cursor = window.cursor;
                if line.length == 0
                    cursor = 0;
                else if cursor > line.length
                    cursor = line.length - 1;

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
            case EditMode.Insert; {
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

        if command_mode {
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
                else {
                    assert(line.length < line_buffer_length);
                    line.data[line.length++] = char;
                }
            }

            calculate_line_digits(&buffer);
        }

        array_insert(&buffers, buffer, allocate, reallocate);
        buffer_index = buffers.length - 1;
    }

    switch current_window {
        case SelectedWindow.Left;
            left_window.buffer_window = open_or_create_buffer_window(buffer_index, left_window.buffer_window);
        case SelectedWindow.Right;
            right_window.buffer_window = open_or_create_buffer_window(buffer_index, right_window.buffer_window);
    }
}

bool switch_to_buffer(SelectedWindow window) {
    if window == current_window return false;

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
        new_window.buffer_window = copy_buffer_window_stack(original_window.buffer_window);
        new_window.displayed = true;
    }

    current_window = window;
    return true;
}

swap_top_buffer() {
    editor_window: EditorWindow*;
    switch current_window {
        case SelectedWindow.Left;
            editor_window = &left_window;
        case SelectedWindow.Right;
            editor_window = &right_window;
    }

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
string get_visual_mode_selection() {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
        return empty_string;
    }

    str: string;
    if visual_mode_data.line == buffer_window.line {
        line := get_current_line(buffer, buffer_window.line);

        switch edit_mode {
            case EditMode.Visual;
            case EditMode.VisualBlock; {
                cursor := clamp(buffer_window.cursor, 0, line.length - 1);
                if visual_mode_data.cursor < cursor {
                    str = {
                        length = cursor - visual_mode_data.cursor + 1;
                        data = line.data.data + visual_mode_data.cursor;
                    }
                }
                else {
                    str = {
                        length = visual_mode_data.cursor - cursor + 1;
                        data = line.data.data + cursor;
                    }
                }
            }
            case EditMode.VisualLine;
                str = { length = line.length; data = line.data.data; }
        }

        allocate_strings(&str);
        return str;
    }

    start_line, start_cursor, end_line, end_cursor: u32;
    if visual_mode_data.line < buffer_window.line {
        start_line = visual_mode_data.line;
        start_cursor = visual_mode_data.cursor;
        end_line = buffer_window.line;
        end_cursor = buffer_window.cursor;
    }
    else {
        start_line = buffer_window.line;
        start_cursor = buffer_window.cursor;
        end_line = visual_mode_data.line;
        end_cursor = visual_mode_data.cursor;
    }

    if edit_mode == EditMode.VisualBlock {
        if visual_mode_data.cursor <= buffer_window.cursor {
            start_cursor = visual_mode_data.cursor;
            end_cursor = buffer_window.cursor;
        }
        else {
            start_cursor = buffer_window.cursor;
            end_cursor = visual_mode_data.cursor;
        }
    }

    line := get_current_line(buffer, start_line);

    line_number := start_line;
    current_line := line;
    while line_number <= end_line {
        switch edit_mode {
            case EditMode.Visual; {
                if line_number == start_line {
                    str.length += current_line.length - start_cursor + 1;
                }
                else if line_number == end_line {
                    str.length += end_cursor + 1;
                }
                else {
                    str.length += current_line.length + 1;
                }
            }
            case EditMode.VisualLine; {
                str.length += current_line.length + 1;
            }
            case EditMode.VisualBlock; {
                if start_cursor >= current_line.length {
                    str.length++;
                }
                else {
                    end := clamp(end_cursor, start_cursor, current_line.length - 1);
                    str.length += end - start_cursor + 1;
                    if line_number != end_line {
                        str.length++;
                    }
                }
            }
        }

        current_line = current_line.next;
        line_number++;
    }

    str.data = allocate(str.length);

    line_number = start_line;
    i: u32;
    while line_number <= end_line {
        switch edit_mode {
            case EditMode.Visual; {
                if line_number == start_line {
                    length := line.length - start_cursor;
                    memory_copy(str.data + i, line.data.data + start_cursor, length);
                    str.data[i + length] = '\n';
                    i += length + 1;
                }
                else if line_number == end_line {
                    memory_copy(str.data + i, line.data.data, end_cursor + 1);
                    i += end_cursor + 1;
                }
                else {
                    memory_copy(str.data + i, line.data.data, line.length);
                    str.data[i + line.length] = '\n';
                    i += line.length + 1;
                }
            }
            case EditMode.VisualLine; {
                memory_copy(str.data + i, line.data.data, line.length);
                str.data[i + line.length] = '\n';
                i += line.length + 1;
            }
            case EditMode.VisualBlock; {
                if start_cursor >= line.length {
                    str.data[i] = '\n';
                    i++;
                }
                else {
                    end := clamp(end_cursor, start_cursor, line.length - 1);
                    memory_copy(str.data + i, line.data.data + start_cursor, end - start_cursor + 1);
                    i += end - start_cursor + 1;
                    if line_number != end_line {
                        str.data[i] = '\n';
                        i++;
                    }
                }
            }
        }

        line = line.next;
        line_number++;
    }

    return str;
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
        line := get_current_line(buffer, buffer_window.line);

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
        line := get_current_line(buffer, buffer_window.line);
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

    line := get_current_line(buffer, buffer_window.line);
    if line == null || line.length == 0 {
        return;
    }

    if left {
        if cursor_changes > buffer_window.cursor {
            buffer_window.cursor = 0;
        }
        else if buffer_window.cursor >= line.length {
            buffer_window.cursor = line.length - cursor_changes - 1;
        }
        else {
            buffer_window.cursor -= cursor_changes;
        }
    }
    else {
        if buffer_window.cursor + cursor_changes >= line.length {
            buffer_window.cursor = line.length - 1;
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

    line := get_current_line(buffer, buffer_window.line);
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

    line := get_current_line(buffer, buffer_window.line);
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

    line := get_current_line(buffer, buffer_window.line);
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

    line := get_current_line(buffer, buffer_window.line);
    if line == null {
        return;
    }

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

find_character_in_line(bool forward, bool before, string char) {
    if char.length != 1 return;

    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
        return;
    }

    line := get_current_line(buffer, buffer_window.line);
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


// Data structures
struct FileBuffer {
    relative_path: string;
    line_count: u32;
    line_count_digits: u32;
    lines: BufferLine*;
}

line_buffer_length := 500; #const

struct BufferLine {
    length: u32;
    data: string;
    previous: BufferLine*;
    next: BufferLine*;
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

#private

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

BufferLine* allocate_line() {
    pointer := allocate(size_of(BufferLine) + line_buffer_length);
    line: BufferLine* = pointer;
    line.data.length = line_buffer_length;
    line.data.data = pointer + size_of(BufferLine);
    return line;
}

BufferWindow*, FileBuffer* get_current_window_and_buffer() {
    buffer_window := get_current_window();
    if buffer_window == null || buffer_window.buffer_index < 0 {
        return null, null;
    }

    return buffer_window, &buffers[buffer_window.buffer_index];
}

BufferLine* get_current_line(FileBuffer* buffer, u32 target_line) {
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

calculate_line_digits(FileBuffer* buffer) {
    digit_count: u32 = 1;
    value := 10;
    while value < buffer.line_count {
        value *= 10;
        digit_count++;
    }
    buffer.line_count_digits = digit_count;
}

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

adjust_start_line(BufferWindow* window) {
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
        rendered_lines += calculate_rendered_lines(max_chars, current_line.length);
        line_number++;
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
