draw_buffers() {
    // TODO Implement
    if buffers.length == 1 {
        buffer := buffers[0];

        if !is_font_ready(settings.font_size) return;

        line := buffer.lines;
        position := vec3(-0.99, 0.96);
        while line != null && position.y > -1.0 {
            line_string: string = { length = line.length; data = line.data.data; }
            position = render_line(line_string, settings.font_size, position, vec4(1.0, 1.0, 1.0, 1.0));
            line = line.next;
        }
    }
}

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

#private

BufferLine* allocate_line() {
    pointer := allocate(size_of(BufferLine) + line_buffer_length);
    line: BufferLine* = pointer;
    line.data.length = line_buffer_length;
    line.data.data = pointer + size_of(BufferLine);
    return line;
}
