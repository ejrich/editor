record_change() {
    // TODO Implement
}

apply_changes(bool forward, u32 changes) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
        return;
    }

    // TODO Implement
}

struct Change {
    insert_new_lines: bool;
    overwrite: bool;
    start_line: u32;
    end_line: u32;
    value: string;
}
