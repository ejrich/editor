draw_buffers() {
    // TODO Implement
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
