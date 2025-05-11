// TODO When to record jumps
// - Opening new buffer, record current jump to line 0, cursor 0
// - Swapping to buffer, record current position
// - Jump to top/bottom of buffer
// - Next/previous search result
// - Next/previous paragraph/sentence
// - Next/previous syntactical char (Need to implement this)


record_jump(BufferWindow* buffer_window) {
    current_jump_pointer: Jump**;
    switch current_window {
        case SelectedWindow.Left;
            current_jump_pointer = &current_left_jump;
        case SelectedWindow.Right;
            current_jump_pointer = &current_right_jump;
    }

    current_jump := *current_jump_pointer;
    if current_jump &&
        current_jump.buffer_index == buffer_window.buffer_index &&
        current_jump.line == buffer_window.line &&
        current_jump.cursor == buffer_window.cursor {
        return;
    }

    new_jump := new<Jump>();
    new_jump.buffer_index = buffer_window.buffer_index;
    new_jump.line = buffer_window.line;
    new_jump.cursor = buffer_window.cursor;

    if current_jump {
        if current_jump.next {
            next_jump := current_jump.next;
            while next_jump {
                next := next_jump.next;
                free_allocation(next_jump);
                next_jump = next;
            }
        }

        current_jump.next = new_jump;
        new_jump.previous = current_jump;
    }

    *current_jump_pointer = new_jump;
}

go_to_jump(bool forward, u32 jumps) {
    current_jump_pointer: Jump**;
    switch current_window {
        case SelectedWindow.Left;
            current_jump_pointer = &current_left_jump;
        case SelectedWindow.Right;
            current_jump_pointer = &current_right_jump;
    }

    current_jump := *current_jump_pointer;
    if current_jump == null return;

    each i in jumps {
        if forward {
            if current_jump.next {
                current_jump = current_jump.next;
            }
            else {
                break;
            }
        }
        else {
            if current_jump.previous {
                current_jump = current_jump.previous;
            }
            else {
                break;
            }
        }
    }

    if current_jump != *current_jump_pointer {
        set_current_location(current_jump.buffer_index, current_jump.line, current_jump.cursor);
        *current_jump_pointer = current_jump;
    }
}

clear_jumps() {
    window_jump_pointer: Jump**;
    switch current_window {
        case SelectedWindow.Left;
            window_jump_pointer = &current_left_jump;
        case SelectedWindow.Right;
            window_jump_pointer = &current_right_jump;
    }

    current_jump := *window_jump_pointer;
    if current_jump {
        next_jump := current_jump.next;
        while next_jump {
            next := next_jump.next;
            free_allocation(next_jump);
            next_jump = next;
        }

        previous_jump := current_jump.previous;
        while previous_jump {
            previous := previous_jump.previous;
            free_allocation(previous_jump);
            previous_jump = previous;
        }

        *window_jump_pointer = null;
    }
}

#private

struct Jump {
    buffer_index: s32;
    line: u32;
    cursor: u32;
    next: Jump*;
    previous: Jump*;
}

current_left_jump: Jump*;
current_right_jump: Jump*;
