record_jump(BufferWindow* buffer_window, u32 line, u32 cursor) {
    // TODO Implement
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
