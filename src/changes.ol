begin_change(FileBuffer* buffer, s32 start_line, u32 end_line, u32 cursor, u32 cursor_line) {
    value: ChangeValue = {
        start_line = start_line;
        end_line = end_line;
        cursor = cursor;
        cursor_line = cursor_line;
    }

    if start_line >= 0 {
        value.value = record_change_lines(buffer, start_line, end_line);
    }

    pending_changes = new<Change>();
    pending_changes.old = value;
}

record_change(FileBuffer* buffer, u32 start_line, u32 end_line, u32 cursor, u32 cursor_line) {
    assert(pending_changes != null);

    value: ChangeValue = {
        start_line = start_line;
        end_line = end_line;
        cursor = cursor;
        cursor_line = cursor_line;
        value = record_change_lines(buffer, start_line, end_line);
    }

    pending_changes.new = value;
    pending_changes.previous = buffer.last_change;

    if buffer.last_change
        buffer.last_change.next = pending_changes;
    buffer.last_change = pending_changes;

    // Free the next changes in the tree, as they have been overwritten by the new change
    next := buffer.next_change;
    while next {
        if next.old.value.length
            free_allocation(next.old.value.data);
        if next.new.value.length
            free_allocation(next.new.value.data);

        new_next := next.next;
        free_allocation(next);
        next = new_next;
    }

    buffer.next_change = null;
    pending_changes = null;
}

string record_change_lines(FileBuffer* buffer, u32 start_line, u32 end_line) {
    start := get_buffer_line(buffer, start_line);

    line := start;
    length := 0;
    each i in start_line..end_line {
        assert(line != null);
        length += line.length;
        if i < end_line
            length++;

        line = line.next;
    }

    recorded_lines: string = { length = length; data = allocate(length); }
    line = start;
    length = 0;
    each i in start_line..end_line {
        assert(line != null);
        memory_copy(recorded_lines.data + length, line.data.data, line.length);
        length += line.length;
        if i < end_line
            recorded_lines[length++] = '\n';

        line = line.next;
    }

    return recorded_lines;
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

            apply_change(buffer_window, buffer, buffer.next_change.old, buffer.next_change.new);
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

            apply_change(buffer_window, buffer, buffer.last_change.new, buffer.last_change.old);
            line = buffer.last_change.old.cursor_line;
            cursor = buffer.last_change.old.cursor;

            buffer.next_change = buffer.last_change;
            buffer.last_change = buffer.last_change.previous;
        }
    }

    set_current_location(buffer_window.buffer_index, line, cursor);
}

apply_change(BufferWindow* buffer_window, FileBuffer* buffer, ChangeValue change_from, ChangeValue change_to) {
    value_lines := split_string(change_to.value);

    if change_from.start_line < 0 {
        line := get_buffer_line(buffer, change_to.start_line);
        line = add_new_line(buffer_window, buffer, line, true, false);

        paste_lines(buffer_window, buffer, line, value_lines, 1);
    }
    else if change_to.start_line < 0 {
        line := get_buffer_line(buffer, change_from.start_line);
        delete_lines_in_range(buffer, line, change_from.end_line - change_from.start_line, true);
    }
    else {
        if change_from.start_line == change_to.start_line {
            line := get_buffer_line(buffer, change_to.start_line);

            if change_from.end_line <= change_to.end_line {
                // Modify existing lines
                line_index := 0;
                overwrite_count := change_from.end_line - change_from.start_line + 1;
                line = overwrite_lines(line, overwrite_count, value_lines);

                // Insert additional lines if necessary
                if change_from.end_line < change_to.end_line {
                    line = line.previous;
                    each i in change_to.end_line - change_from.end_line {
                        line = add_new_line(buffer_window, buffer, line, false, false);
                        value_line := value_lines[i + overwrite_count];
                        add_text_to_line(line, value_line);
                    }
                }
            }
            else {
                line = overwrite_lines(line, change_to.end_line - change_to.start_line + 1, value_lines);

                line = line.previous;
                delete_lines_in_range(buffer, line, change_from.end_line - change_to.end_line);
           }
        }

        // TODO What other cases need to be handled here?
    }

    calculate_line_digits(buffer);
    adjust_start_line(buffer_window);
}

BufferLine* overwrite_lines(BufferLine* line, u32 count, Array<string> value_lines) {
    each i in count {
        value_line := value_lines[i];
        add_text_to_line(line, value_line, clear = true);

        line = line.next;
    }

    return line;
}

struct Change {
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
        end_line = 2;
        cursor = 6;
        cursor_line = 0;
        value = "Hello world 123456789\nThis is a test\nTest";
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


- Tracking line deletions
When deleting the line, first store the lines that were deleted and the start/end line

Set the new change start line to -1 to show that there should be no changes

When applying the changes:
- If the change from is -1, then just insert the new lines in the change to
- If the change to is -1, then just delete the lines that in the change from
*/
