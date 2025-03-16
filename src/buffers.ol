// Buffer rendering
draw_buffers() {
    if left_window.displayed {
        // TODO Reserve space and draw boundaries
        if left_window.buffer_index >= 0 {
            position := vec3(-0.99, 0.96);
            draw_buffer_window(&left_window, position, !right_window.displayed);
        }
    }

    if right_window.displayed {
        // TODO Reserve space and draw boundaries
        if right_window.buffer_index >= 0 {
            position := vec3(0.01, 0.96);
            if !left_window.displayed {
                position.x = -0.99;
            }
            draw_buffer_window(&right_window, position, !left_window.displayed);
        }
    }
}

draw_buffer_window(BufferWindow* window, Vector3 position, bool full_width) {
    if !is_font_ready(settings.font_size) return;

    buffer := buffers[window.buffer_index];
    start_line := clamp(window.start_line, 0, buffer.line_count);
    line := buffer.lines;
    line_number := 1;
    while line != null && position.y > -1.0 {
        if line_number > start_line {
            line_string: string = { length = line.length; data = line.data.data; }
            position = render_line(line_string, settings.font_size, position, vec4(1.0, 1.0, 1.0, 1.0));
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
        move_buffer_line(&left_window, direction == ScrollDirection.Up);
    }
    else if right_window.displayed && (!left_window.displayed || x > 0.0) {
        move_buffer_line(&right_window, direction == ScrollDirection.Up);
    }
}

struct FileBuffer {
    relative_path: string;
    line_count: u32;
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

move_buffer_line(BufferWindow* window, bool up) {
    if window.buffer_index < 0 {
        window.line = 0;
        window.start_line = 0;
    }
    else {
        if up window.start_line -= 1;
        else  window.start_line += 1;

        buffer := buffers[window.buffer_index];
        window.start_line = clamp(window.start_line, 0, buffer.line_count);
    }
}
