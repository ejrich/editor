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

    // TODO Implement
    if buffer.change == null return;

    if forward {
        each i in changes {
            if buffer.change.next == null
                break;
            buffer.change = buffer.change.next;

        }
    }
    else {
        each i in changes {
            buffer.change = buffer.change.next;

            if buffer.change.previous == null
                break;
            buffer.change = buffer.change.previous;
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
    start_line: u32;
    end_line: u32;
    cursor: u32;
    cursor_line: u32;
    value: string;
}

pending_changes: Change*;

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
