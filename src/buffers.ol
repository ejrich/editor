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
            lines := render_line(line_string, x, y, line_number, digits, cursor, line_max_x, available_lines_to_render);
            y -= global_font_config.line_height * lines;
            available_lines_to_render -= lines;
        }
        line = line.next;
        line_number++;
    }

    // Render the file information
    {
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
            if file.length > 0 {
                line := allocate_line();
                buffer = { line_count = 1; lines = line; }

                each i in file.length {
                    char := file[i];
                    if char == '\n' {
                        next_line := allocate_line();
                        buffer.line_count++;
                        line.next = next_line;
                        next_line.previous = line;
                        line = next_line;
                    }
                    else {
                        assert(line.length < line_buffer_length);
                        line.data[line.length++] = char;
                    }
                }

                calculate_line_digits(&buffer);
            }
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

move_line(bool up, u32 line_changes = 1) {
    switch current_window {
        case SelectedWindow.Left;
            move_buffer_line(&left_window, up, line_changes);
        case SelectedWindow.Right;
            move_buffer_line(&right_window, up, line_changes);
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

move_buffer_line(BufferWindow* window, bool up, u32 line_changes = 1) {
    if window.buffer_index < 0 {
        window.line = 0;
        window.start_line = 0;
        return;
    }

    if up window.line -= line_changes;
    else  window.line += line_changes;

    buffer := buffers[window.buffer_index];

    window.line = clamp(window.line, 0, buffer.line_count - 1);
    window.start_line = clamp(window.start_line, 0, window.line);
    adjust_start_line(window);
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

        if rendered_lines_after_current >= settings.scroll_offset {
            while starting_line != null && rendered_lines + settings.scroll_offset > global_font_config.max_lines {
                window.start_line++;
                rendered_lines -= calculate_rendered_lines(buffer.line_count_digits, starting_line.length, full_width);
                starting_line = starting_line.next;
            }
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
