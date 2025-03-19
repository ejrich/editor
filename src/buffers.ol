// Buffer rendering
draw_buffers() {
    if !is_font_ready(settings.font_size) return;

    if left_window.displayed {
        // TODO Reserve space and draw boundaries
        if left_window.buffer_index >= 0 {
            position := vec3(-0.99, 1.0 - line_height);
            draw_buffer_window(&left_window, position, !right_window.displayed);
        }
    }

    if right_window.displayed {
        // TODO Reserve space and draw boundaries
        if right_window.buffer_index >= 0 {
            position := vec3(0.01, 1.0 - line_height);
            if !left_window.displayed {
                position.x = -0.99;
            }
            draw_buffer_window(&right_window, position, !left_window.displayed);
        }
    }
}

draw_buffer_window(BufferWindow* window, Vector3 position, bool full_width) {
    line_max_x := position.x + 0.98;
    if full_width line_max_x += 1.0;

    buffer := buffers[window.buffer_index];
    start_line := clamp(window.start_line, 0, buffer.line_count - 1);
    cursor_line := clamp(window.line, 0, buffer.line_count - 1) + 1;
    digits := buffer.line_count_digits;

    line := buffer.lines;
    line_number: u32 = 1;
    while line != null && position.y > -1.0 {
        if line_number > start_line {
            line_string: string = { length = line.length; data = line.data.data; }
            cursor := -1;
            if line_number == cursor_line {
                cursor = window.cursor;
                if line.length == 0
                    cursor = 0;
                else if cursor > line.length
                    cursor = line.length - 1;
            }
            position.y = render_line(line_string, settings.font_size, position, vec4(1.0, 1.0, 1.0, 1.0), line_number, digits, cursor, line_max_x);
        }
        line = line.next;
        line_number++;
    }
}

// Opening buffers with files
open_file_buffer(string path) {
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

    switch current_window {
        case SelectedWindow.Left;
            left_window.buffer_index = buffers.length - 1;
        case SelectedWindow.Right;
            right_window.buffer_index = buffers.length - 1;
    }
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
    }
    else {
        if up {
            window.start_line -= line_changes;
            if window.line - window.start_line + settings.scroll_offset > max_lines {
                window.line = window.start_line + max_lines - settings.scroll_offset;
            }
        }
        else {
            window.start_line += line_changes;
            if window.start_line + settings.scroll_offset > window.line {
                window.line = window.start_line + settings.scroll_offset;
            }
        }

        buffer := buffers[window.buffer_index];
        window.start_line = clamp(window.start_line, 0, buffer.line_count - 1);
        window.line = clamp(window.line, 0, buffer.line_count - 1);
    }
}

move_buffer_line(BufferWindow* window, bool up, u32 line_changes = 1) {
    if window.buffer_index < 0 {
        window.line = 0;
        window.start_line = 0;
    }
    else {
        if up {
            window.line -= line_changes;
            if window.start_line + settings.scroll_offset > window.line {
                window.start_line = window.line - settings.scroll_offset;
            }
        }
        else {
            window.line += line_changes;
            if window.line - window.start_line + settings.scroll_offset > max_lines {
                window.start_line = window.line + settings.scroll_offset - max_lines;
            }
        }

        buffer := buffers[window.buffer_index];
        window.start_line = clamp(window.start_line, 0, buffer.line_count - 1);
        window.line = clamp(window.line, 0, buffer.line_count - 1);
    }
}

move_buffer_cursor(BufferWindow* window, bool left, u32 cursor_changes = 1) {
    if window.buffer_index < 0 {
        window.line = 0;
        window.start_line = 0;
    }
    else {
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
}
