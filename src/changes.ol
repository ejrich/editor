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

    line, cursor: u32;
    if forward {
        if buffer.next_change == null return;

        each i in changes {
            if buffer.next_change == null
                break;

            apply_change(buffer, buffer.next_change.old, buffer.next_change.new);
            line = buffer.next_change.new.cursor_line;
            cursor = buffer.next_change.new.cursor;

            buffer.last_change = buffer.next_change;
            buffer.next_change = buffer.next_change.next;
        }
    }
    else {
        if buffer.last_change == null return;

        each i in changes {
            if buffer.last_change == null
                break;

            apply_change(buffer, buffer.last_change.new, buffer.last_change.old);
            line = buffer.last_change.old.cursor_line;
            cursor = buffer.last_change.old.cursor;

            buffer.next_change = buffer.last_change;
            buffer.last_change = buffer.last_change.previous;
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
- Change list
When opening the buffers, there are initially no changes.
When trying to undo/redo in this state, nothing happens.

The changes are a linked list, and branches can be trimmed when the tree diverts.

After a change has been made, the last change is recorded to the buffer.
If this change is undone, the changes are applied to the file, and the last change is cleared, the next change is then set to the last change.

When redoing, the next change is applied and this is set to the last change.

Undoing is disabled when the last change is null, and redoing is disabled when the next change is null


- Example
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
