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
        draw_buffer_window(&left_window, -1.0, current_window == SelectedWindow.Left, !right_window.displayed);
    }

    if right_window.displayed {
        x := 0.0;
        if !left_window.displayed {
            x = -1.0;
        }
        draw_buffer_window(&right_window, x, current_window == SelectedWindow.Right, !left_window.displayed);
    }

    draw_command();
}

draw_buffer_window(BufferWindow* window, float x, bool selected, bool full_width) {
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

    // Render the file text
    line := buffer.lines;
    line_number: u32 = 1;
    line_cursor: u32;
    available_lines_to_render := global_font_config.max_lines;

    while line != null && available_lines_to_render > 0 {
        if line_number > start_line {
            line_string: string = { length = line.length; data = line.data.data; }
            cursor := -1;
            if line_number == cursor_line {
                cursor = window.cursor;
                if line.length == 0
                    cursor = 0;
                else if cursor > line.length
                    cursor = line.length - 1;

                line_cursor = cursor;
            }
            lines := render_line(line_string, x, y, line_number, digits, cursor, selected, line_max_x, available_lines_to_render);
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
            left_window.buffer_index = buffer_index;
        case SelectedWindow.Right;
            right_window.buffer_index = buffer_index;
    }
}

switch_to_buffer(SelectedWindow window) {
    if window == current_window return;

    original_window, new_window: BufferWindow*;
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
        *new_window = *original_window;
    }

    current_window = window;
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


// Event handlers
handle_buffer_scroll(ScrollDirection direction) {
    x, y := get_cursor_position();

    if left_window.displayed && (!right_window.displayed || x < 0.0) {
        scroll_buffer(&left_window, direction == ScrollDirection.Up);
    }
    else if right_window.displayed && (!left_window.displayed || x > 0.0) {
        scroll_buffer(&right_window, direction == ScrollDirection.Up);
    }
}

resize_buffers() {
    if left_window.displayed
        adjust_start_line(&left_window);
    if right_window.displayed
        adjust_start_line(&right_window);
}

go_to_line(u32 line) {
    switch current_window {
        case SelectedWindow.Left;
            go_to_buffer_line(&left_window, line);
        case SelectedWindow.Right;
            go_to_buffer_line(&right_window, line);
    }
}

move_line(bool up, u32 line_changes = 1, bool move_to_first = false) {
    switch current_window {
        case SelectedWindow.Left;
            move_buffer_line(&left_window, up, line_changes, move_to_first);
        case SelectedWindow.Right;
            move_buffer_line(&right_window, up, line_changes, move_to_first);
    }
}

move_cursor(bool left, u32 cursor_changes = 1) {
    switch current_window {
        case SelectedWindow.Left;
            move_buffer_cursor(&left_window, left, cursor_changes);
        case SelectedWindow.Right;
            move_buffer_cursor(&right_window, left, cursor_changes);
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

move_to_line_boundary(bool end, bool soft_boundary = false) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
        return;
    }

    line := get_current_line(buffer, buffer_window.line);
    if line == null {
        return;
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
    displayed: bool;
    cursor: u32;
    line: u32;
    start_line: u32;
    buffer_index := -1;
}

left_window: BufferWindow = { displayed = true; }
right_window: BufferWindow;

enum SelectedWindow {
    Left;
    Right;
}

current_window: SelectedWindow;

#private

BufferLine* allocate_line() {
    pointer := allocate(size_of(BufferLine) + line_buffer_length);
    line: BufferLine* = pointer;
    line.data.length = line_buffer_length;
    line.data.data = pointer + size_of(BufferLine);
    return line;
}

BufferWindow*, FileBuffer* get_current_window_and_buffer() {
    buffer_window: BufferWindow*;
    switch current_window {
        case SelectedWindow.Left;
            buffer_window = &left_window;
        case SelectedWindow.Right;
            buffer_window = &right_window;
    }

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
    full_width := left_window.displayed ^ right_window.displayed;
    rendered_lines := calculate_rendered_lines(buffer.line_count_digits, current_line.length, full_width);
    while current_line != null && line_number != window.line {
        current_line = current_line.next;
        rendered_lines += calculate_rendered_lines(buffer.line_count_digits, current_line.length, full_width);
        line_number++;
    }

    if !up {
        if rendered_lines <= settings.scroll_offset {
            while current_line.next != null && rendered_lines <= settings.scroll_offset {
                window.line++;
                current_line = current_line.next;
                rendered_lines += calculate_rendered_lines(buffer.line_count_digits, starting_line.length, full_width);
            }
        }
        return;
    }

    if rendered_lines + settings.scroll_offset > global_font_config.max_lines && current_line != null {
        // Check that there are more lines to scroll to
        end_line := current_line.next;
        rendered_lines_after_current: u32;
        while end_line != null {
            rendered_lines_after_current += calculate_rendered_lines(buffer.line_count_digits, end_line.length, full_width);
            end_line = end_line.next;

            if rendered_lines + rendered_lines_after_current > global_font_config.max_lines {
                break;
            }
        }

        if rendered_lines + rendered_lines_after_current > global_font_config.max_lines {
            while current_line != null && rendered_lines + settings.scroll_offset > global_font_config.max_lines {
                window.line--;
                rendered_lines -= calculate_rendered_lines(buffer.line_count_digits, current_line.length, full_width);
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

move_buffer_line(BufferWindow* window, bool up, u32 line_changes, bool move_to_first) {
    if window.buffer_index < 0 {
        window.line = 0;
        window.start_line = 0;
        return;
    }

    if up window.line -= line_changes;
    else  window.line += line_changes;

    buffer := &buffers[window.buffer_index];

    window.line = clamp(window.line, 0, buffer.line_count - 1);
    adjust_start_line(window);

    if move_to_first {
        line := get_current_line(buffer, window.line);
        if line != null {
            cursor := 0;
            while cursor < line.length {
                char := line.data[cursor];
                if !is_whitespace(char) {
                    break;
                }

                cursor++;
            }

            window.cursor = cursor;
        }
    }
}

move_buffer_cursor(BufferWindow* window, bool left, u32 cursor_changes = 1) {
    if window.buffer_index < 0 {
        window.line = 0;
        window.start_line = 0;
        return;
    }

    buffer := buffers[window.buffer_index];
    line := buffer.lines;
    line_number := 0;
    while line != null && line_number != window.line {
        line = line.next;
        line_number++;
    }

    if line == null || line.length == 0 return;

    if left {
        if cursor_changes > window.cursor {
            window.cursor = 0;
        }
        else if window.cursor >= line.length {
            window.cursor = line.length - cursor_changes - 1;
        }
        else {
            window.cursor -= cursor_changes;
        }
    }
    else {
        if window.cursor + cursor_changes >= line.length {
            window.cursor = line.length - 1;
        }
        else {
            window.cursor += cursor_changes;
        }
    }
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
    full_width := left_window.displayed ^ right_window.displayed;
    rendered_lines := calculate_rendered_lines(buffer.line_count_digits, current_line.length, full_width);
    while current_line != null && line_number != window.line {
        current_line = current_line.next;
        rendered_lines += calculate_rendered_lines(buffer.line_count_digits, current_line.length, full_width);
        line_number++;
    }

    if rendered_lines <= settings.scroll_offset {
        while starting_line.previous != null && rendered_lines <= settings.scroll_offset {
            window.start_line--;
            starting_line = starting_line.previous;
            rendered_lines += calculate_rendered_lines(buffer.line_count_digits, starting_line.length, full_width);
        }
    }
    else if rendered_lines + settings.scroll_offset > global_font_config.max_lines && current_line != null {
        // Check that there are more lines to scroll to
        end_line := current_line.next;
        rendered_lines_after_current: u32;
        while end_line != null {
            rendered_lines_after_current += calculate_rendered_lines(buffer.line_count_digits, end_line.length, full_width);
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
            rendered_lines -= calculate_rendered_lines(buffer.line_count_digits, starting_line.length, full_width);
            starting_line = starting_line.next;
        }
    }
}

u32 calculate_rendered_lines(u32 digits, u32 line_length, bool full_width) {
    max_chars := global_font_config.max_chars_per_line;
    if full_width max_chars = global_font_config.max_chars_per_line_full;

    max_chars -= digits + 1;
    lines := line_length / max_chars + 1;

    return lines;
}
