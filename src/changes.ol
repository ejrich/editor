// Recording prior states
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

begin_line_change(BufferLine* line, u32 line_number, u32 cursor, s32 cursor_line = -1) {
    value: ChangeValue = {
        start_line = line_number;
        end_line = line_number;
        cursor = cursor;
        cursor_line = line_number;
        value = record_change_line(line);
    }

    if cursor_line >= 0 {
        value.cursor_line = cursor_line;
    }

    pending_changes = new<Change>();
    pending_changes.old = value;
}

begin_insert_mode_change(FileBuffer* buffer, u32 start_line, u32 end_line, u32 cursor, u32 cursor_line) {
    if pending_changes return;

    value: ChangeValue = {
        start_line = start_line;
        end_line = end_line;
        cursor = cursor;
        cursor_line = cursor_line;
        value = record_change_lines(buffer, start_line, end_line);
    }

    pending_changes = new<Change>();
    pending_changes.old = value;

    insert_mode_changes = {
        start_line = start_line;
        end_line = start_line;
    }
}

begin_insert_mode_change(BufferLine* line, u32 line_number, u32 cursor) {
    if pending_changes return;

    value: ChangeValue = {
        start_line = line_number;
        end_line = line_number;
        cursor = cursor;
        cursor_line = line_number;
        value = record_change_line(line);
    }

    pending_changes = new<Change>();
    pending_changes.old = value;

    insert_mode_changes = {
        start_line = line_number;
        end_line = line_number;
    }
}

begin_block_insert_mode_change(FileBuffer* buffer, u32 start_line, u32 end_line, u32 cursor, u32 cursor_line) {
    if pending_changes return;

    value: ChangeValue = {
        start_line = start_line;
        end_line = end_line;
        cursor = cursor;
        cursor_line = cursor_line;
        value = record_change_lines(buffer, start_line, end_line);
    }

    pending_changes = new<Change>();
    pending_changes.old = value;

    insert_mode_changes = {
        start_line = start_line;
        end_line = end_line;
    }
}

begin_open_line_change(BufferLine* line, u32 line_number, u32 cursor, bool above) {
    value: ChangeValue = {
        start_line = -1;
        cursor = cursor;
        cursor_line = line_number;
    }

    pending_changes = new<Change>();
    pending_changes.old = value;

    if !above {
        line_number++;
    }

    insert_mode_changes = {
        start_line = line_number;
        end_line = line_number;
    }
}

update_insert_mode_change(FileBuffer* buffer, u32 line_number, bool merging = false) {
    if line_number < insert_mode_changes.start_line {
        // Change the start line to the line_number and record what was on the line before
        line := get_buffer_line(buffer, line_number);
        new_value: string;

        if pending_changes.old.start_line == -1 {
            new_value = record_change_line(line);
            pending_changes.old.end_line = line_number;
        }
        else {
            new_length := line.length + 1 + pending_changes.old.value.length;
            new_value = { length = new_length; data = allocate(new_length); }

            memory_copy(new_value.data, line.data.data, line.length);
            new_value[line.length] = '\n';
            memory_copy(new_value.data + line.length + 1, pending_changes.old.value.data, pending_changes.old.value.length);

            free_allocation(pending_changes.old.value.data);
        }

        pending_changes.old.value = new_value;
        pending_changes.old.start_line = line_number;

        if insert_mode_changes.start_line == insert_mode_changes.end_line {
            insert_mode_changes.end_line = line_number;
        }
        else {
            insert_mode_changes.end_line--;
        }
        insert_mode_changes.start_line = line_number;
    }
    else if insert_mode_changes.end_line <= line_number {
        if merging && insert_mode_changes.end_line == line_number {
            // Append the next line to the end of the pending changes
            line := get_buffer_line(buffer, line_number + 1);
            new_value: string;

            if pending_changes.old.start_line == -1 {
                new_value = record_change_line(line);
                pending_changes.old.start_line = insert_mode_changes.start_line;
                pending_changes.old.end_line = insert_mode_changes.start_line;
            }
            else {
                new_length := line.length + 1 + pending_changes.old.value.length;
                new_value = { length = new_length; data = allocate(new_length); }

                memory_copy(new_value.data, pending_changes.old.value.data, pending_changes.old.value.length);
                new_value[pending_changes.old.value.length] = '\n';
                memory_copy(new_value.data + pending_changes.old.value.length + 1, line.data.data, line.length);

                free_allocation(pending_changes.old.value.data);
                pending_changes.old.end_line++;
            }

            pending_changes.old.value = new_value;
        }

        // Change the end line to the line_number
        insert_mode_changes.end_line = line_number;
    }
    else if merging {
        insert_mode_changes.end_line--;
    }
}


// Recording new state
record_change(FileBuffer* buffer, s32 start_line, u32 end_line, u32 cursor, u32 cursor_line) {
    assert(pending_changes != null);

    value: ChangeValue = {
        start_line = start_line;
        end_line = end_line;
        cursor = cursor;
        cursor_line = cursor_line;
    }

    if start_line >= 0 {
        value.value = record_change_lines(buffer, start_line, end_line);
    }

    add_changes_to_buffer(buffer, value);
}

record_line_change(FileBuffer* buffer, BufferLine* line, u32 line_number, u32 cursor, s32 cursor_line = -1) {
    assert(pending_changes != null);

    value: ChangeValue = {
        start_line = line_number;
        end_line = line_number;
        cursor = cursor;
        cursor_line = line_number;
        value = record_change_line(line);
    }

    if cursor_line >= 0 {
        value.cursor_line = cursor_line;
    }

    add_changes_to_buffer(buffer, value);
}

record_insert_mode_change(FileBuffer* buffer, u32 line_number, u32 cursor) {
    assert(pending_changes != null);

    // Check if there were no changes made
    // TODO Check multiple lines
    if insert_mode_changes.start_line == insert_mode_changes.end_line {
        line := get_buffer_line(buffer, insert_mode_changes.start_line);
        line_string: string = { length = line.length; data = line.data.data; }

        if line_string == pending_changes.old.value {
            free_change(pending_changes);
            pending_changes = null;
            return;
        }
    }

    value: ChangeValue = {
        start_line = insert_mode_changes.start_line;
        end_line = insert_mode_changes.end_line;
        cursor = cursor;
        cursor_line = line_number;
        value = record_change_lines(buffer, insert_mode_changes.start_line, insert_mode_changes.end_line);
    }

    add_changes_to_buffer(buffer, value);
}

add_changes_to_buffer(FileBuffer* buffer, ChangeValue value) {
    pending_changes.new = value;
    pending_changes.previous = buffer.last_change;

    if buffer.last_change
        buffer.last_change.next = pending_changes;
    buffer.last_change = pending_changes;

    // Free the next changes in the tree, as they have been overwritten by the new change
    next := buffer.next_change;
    while next {
        new_next := next.next;
        free_change(next);
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

string record_change_line(BufferLine* line) {
    recorded_line: string = { length = line.length; data = line.data.data; }
    allocate_strings(&recorded_line);

    return recorded_line;
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

free_change(Change* change) {
    if change.old.value.length
        free_allocation(change.old.value.data);
    if change.new.value.length
        free_allocation(change.new.value.data);

    free_allocation(change);
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

struct InsertModeChanges {
    start_line: u32;
    end_line: u32;
}

insert_mode_changes: InsertModeChanges;

/*
- Change list
When opening the buffers, there are initially no changes.
When trying to undo/redo in this state, nothing happens.

The changes are a linked list, and branches can be trimmed when the tree diverts.

After a change has been made, the last change is recorded to the buffer.
If this change is undone, the changes are applied to the file, and the last change is cleared, the next change is then set to the last change.

When redoing, the next change is applied and this is set to the last change.

Undoing is disabled when the last change is null, and redoing is disabled when the next change is null


- Tracking line deletions
When deleting the line, first store the lines that were deleted and the start/end line

Set the new change start line to -1 to show that there should be no changes

When applying the changes:
* If the change from is -1, then just insert the new lines in the change to
* If the change to is -1, then just delete the lines that in the change from


- Insert mode change tracking
When insert mode is activated, record the initial state of the line
If enter/backspace reaches a new line, append that line to the pending changes and change the start/end line
When going back into normal mode, record the lines that have been modified

Example - starting at line 2
Key presses:
< < < < < < (back over line) a b c d Enter Enter Enter Enter a b c d < < < < < (back over line)
Current Line:
2 2 2 2 2 1                  1 1 1 1 2     3     4     5     5 5 5 5 5 5 5 5 4
Before start:
2 2 2 2 2 1                  1 1 1 1 1     1     1     1     1 1 1 1 1 1 1 1 1
Before end:
2 2 2 2 2 2                  2 2 2 2 2     2     2     2     2 2 2 2 2 2 2 2 2
New start:
2 2 2 2 2 1                  1 1 1 1 1     1     1     1     1 1 1 1 1 1 1 1 1
New end:
2 2 2 2 2 2                  2 2 2 2 2     3     4     5     5 5 5 5 5 5 5 5 5


- Opening new lines
When opening below the current line:
* Begin the recording with the start_line/end_line of the previous change to be the line that was opened from
* Set the start_line of the insert mode changes to be the line that was opened from
* Set the end_line of the insert mode changes to line opened to

When opening above the current line:
* Begin the recording with the start_line/end_line of the previous change to be the line that was opened from
* Set the start_line of the insert mode changes to be the line that was opened from
* Set the end_line of the insert mode changes to line opened to +1 (this will be the where the existing line is)

*/
