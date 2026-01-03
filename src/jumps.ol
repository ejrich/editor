// When jumps are recorded:
// - Opening new buffer, record current jump to line 0, cursor 0
// - Swapping to buffer, record current position
// - Jump to top/bottom of buffer
// - Next/previous search result
// - Next/previous paragraph/sentence
// - Next/previous syntactical char (Need to implement this)

record_jump(BufferWindow* buffer_window) {
    if buffer_window == null return;

    current_jump_pointer := get_jump_pointer();

    current_jump := *current_jump_pointer;
    if jump_is_current_location(current_jump, buffer_window) {
        return;
    }

    new_jump := new<Jump>();
    new_jump.buffer_index = buffer_window.buffer_index;
    new_jump.line = buffer_window.line;
    new_jump.cursor = buffer_window.cursor;

    if current_jump {
        if current_jump.next {
            clear_jumps_after(current_jump);
        }

        current_jump.next = new_jump;
        new_jump.previous = current_jump;
    }

    *current_jump_pointer = new_jump;
}

go_to_jump(bool forward, u32 jumps) {
    current_jump_pointer := get_jump_pointer();
    buffer_window := get_current_window();

    current_jump := *current_jump_pointer;
    if jump_is_current_location(current_jump, buffer_window) {
        if forward {
            if current_jump.next {
                current_jump = current_jump.next;
            }
        }
        else if current_jump.previous {
            current_jump = current_jump.previous;
        }
    }

    if current_jump == null return;

    each i in jumps - 1 {
        if forward {
            if current_jump.next == null
                break;

            current_jump = current_jump.next;
        }
        else {
            if current_jump.previous == null
                break;

            current_jump = current_jump.previous;
        }
    }

    set_current_location(current_jump.buffer_index, current_jump.line, current_jump.cursor);
    *current_jump_pointer = current_jump;
}

clear_jumps(Jump** window_jump_pointer) {
    current_jump := *window_jump_pointer;
    if current_jump {
        clear_jumps_after(current_jump);

        previous_jump := current_jump.previous;
        while previous_jump {
            previous := previous_jump.previous;
            free_allocation(previous_jump);
            previous_jump = previous;
        }

        *window_jump_pointer = null;
    }
}

struct Jump {
    buffer_index: s32;
    line: u32;
    cursor: u32;
    next: Jump*;
    previous: Jump*;
}

#private

Jump** get_jump_pointer() {
    current_jump_pointer: Jump**;
    workspace := get_workspace();
    switch workspace.current_window {
        case SelectedWindow.Left;
            current_jump_pointer = &workspace.left_window.current_jump;
        case SelectedWindow.Right;
            current_jump_pointer = &workspace.right_window.current_jump;
    }

    return current_jump_pointer;
}

clear_jumps_after(Jump* jump) {
    next_jump := jump.next;
    while next_jump {
        next := next_jump.next;
        free_allocation(next_jump);
        next_jump = next;
    }
}

bool jump_is_current_location(Jump* jump, BufferWindow* buffer_window) {
    if jump != null && jump.buffer_index == buffer_window.buffer_index &&
        jump.line == buffer_window.line && jump.cursor == buffer_window.cursor
        return true;

    return false;
}
