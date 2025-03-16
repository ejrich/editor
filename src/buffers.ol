draw_buffers() {
    // TODO Implement
    if buffers.length == 1 {
        buffer := buffers[0];
        render_text(buffer.contents, 17, vec3(-0.99, 0.96), vec4(1.0, 1.0, 1.0, 1.0));
    }
}

bool open_file_buffer(string path) {
    found, file := read_file(path, allocate);
    if !found return false;

    buffer: FileBuffers = {
        relative_path = path;
        contents = file;
    }
    array_insert(&buffers, buffer, allocate, reallocate);

    return true;
}

struct FileBuffers {
    relative_path: string;
    contents: string;
    // TODO Store lines instead of whole file
}

buffers: Array<FileBuffers>;
