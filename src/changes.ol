Change* create_change(BufferLine* line, u32 line_number, u32 cursor) {
    change := new<Change>();
    change.old = {
        start_line = line_number;
        end_line = line_number;
        cursor = cursor;
        cursor_line = line_number;
    }

    if line.length {
        change.old.value = {
            length = line.length;
            data = line.data.data;
        }
        allocate_strings(&change.old.value);
    }

    return change;
}

record_change(Change* change) {
    // TODO Implement
}

apply_changes(bool forward, u32 changes) {
    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null {
        return;
    }

    // TODO Determine which current change to use
    if buffer.change_list == null return;

    line, cursor: u32;
    if forward {
        each i in changes {
            if buffer.current_change.next == null
                break;
            buffer.current_change = buffer.current_change.next;

            apply_change(buffer, buffer.current_change.old, buffer.current_change.new);
            line = buffer.current_change.new.cursor_line;
            cursor = buffer.current_change.new.cursor;
        }
    }
    else {
        each i in changes {
            apply_change(buffer, buffer.current_change.new, buffer.current_change.old);
            line = buffer.current_change.old.cursor_line;
            cursor = buffer.current_change.old.cursor;

            if buffer.current_change.previous == null
                break;
            buffer.current_change = buffer.current_change.previous;
        }
    }

    set_current_location(buffer_window.buffer_index, line, cursor);
}

apply_change(FileBuffer* buffer, ChangeValue change_from, ChangeValue change_to) {
    value_lines := split_string(change_to.value);

    if change_from.start_line < 0 {
        // TODO Implement
    }
    else if change_to.start_line < 0 {
        // TODO Implement
    }
    else {
        if change_from.start_line == change_to.start_line {
            if change_from.end_line == change_to.end_line {
                line := get_buffer_line(buffer, change_to.start_line);
                each i in change_to.end_line - change_to.end_line + 1 {
                    value_line := value_lines[i];
                    line.length = value_line.length;
                    if value_line.length {
                        memory_copy(line.data.data, value_line.data, value_line.length);
                    }

                    line = line.next;
                }
            }
            else {
                // TODO Implement
            }
        }
    }
}

struct Change {
    insert_new_lines: bool;
    old: ChangeValue;
    new: ChangeValue;
    next: Change*;
    previous: Change*;
}

struct ChangeValue {
    start_line: s32;
    end_line: s32;
    cursor: u32;
    cursor_line: u32;
    value: string;
}

pending_changes: Change*;

test_change: Change = {
    old = {
        start_line = 0;
        end_line = 0;
        cursor = 3;
        cursor_line = 0;
        value = "Hello world";
    }
    new = {
        start_line = 0;
        end_line = 0;
        cursor = 6;
        cursor_line = 0;
        value = "Hello world 123456789";
    }
}

/*
hello world => '' - 'hello world'
{
    insert_new_lines: false;
    previous_start_line: 100;
    previous_end_line: 100;
    previous_value: '';
    new_start_line: 100;
    new_end_line: 100;
    new_value: 'hello world';
}

undo:
    - insert_new_lines == false, so change line 100 only
    - Set the line to ''

undo:
    - insert_new_lines == false, so change line 100 only
    - Set the line to 'hello world'
*/
