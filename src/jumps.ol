record_jump(BufferWindow* buffer_window, FileBuffer* buffer, u32 line, u32 cursor) {
    // TODO Implement
}

go_to_jump(bool forward, u32 jumps) {
    // TODO Implement
}

#private

struct Jump {
    buffer: FileBuffer*;
    line: u32;
    cursor: u32;
    next: Jump*;
    previous: Jump*;
}

current_left_jump: Jump*;
current_right_jump: Jump*;
