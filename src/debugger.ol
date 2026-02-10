struct DebuggerData {
    running: bool;
    started: bool;
    failed_to_start: bool;
    exited: bool;
    exit_code: int;
    process: ProcessData;
    buffer: Buffer = { read_only = true; title = get_debugger_buffer_title; }
    buffer_window: BufferWindow;
    command_executing: bool;
    skip_next_stop: bool;
    parse_status: DebuggerParseStatus;
    parse_state: DebuggerParseState;
    paused_file_index: u32;
    paused_line: u32;
}

enum DebuggerParseStatus : u8 {
    None;
    Source;
    Variables;
    Expression;
    StackTrace;
    Registers;
    Threads;
}

struct DebuggerParseState {
    command_line_read: bool;
    header_read: bool;
    lines_read: u16;
}

// TODO Move breakpoint lines when deleting/adding lines
struct Breakpoint {
    line: u32;
    active: bool;
    next: Breakpoint*;
}

BufferWindow* get_debugger_window(Workspace* workspace) {
    if workspace.debugger_data.running {
        return &workspace.debugger_data.buffer_window;
    }

    return null;
}

start_or_continue_debugger() {
    workspace := get_workspace();
    if workspace.debugger_data.running {
        continue_debugger(workspace);
    }
    else if !string_is_empty(workspace.local_settings.debug_command) {
        force_command_to_stop();
        workspace.debugger_data = {
            running = true;
            started = true;
            failed_to_start = false;
            exited = false;
            skip_next_stop = false;
        }

        data: JobData;
        data.pointer = workspace;
        queue_work(&low_priority_queue, debugger_thread, data);
    }
}

bool stop_debugger() {
    workspace := get_workspace();
    if !workspace.debugger_data.running {
        return false;
    }

    data: JobData;
    data.pointer = workspace;
    queue_work(&low_priority_queue, exit_debugger, data);
    return true;
}

toggle_breakpoint() {
    workspace := get_workspace();
    if workspace.bottom_window_selected return;

    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null return;

    line := clamp(buffer_window.line, 0, buffer.line_count - 1) + 1;

    breakpoint := buffer.breakpoints;
    clear := false;
    while breakpoint {
        if breakpoint.line == line {
            clear = true;
            break;
        }

        breakpoint = breakpoint.next;
    }

    if workspace.debugger_data.running {
        was_executing := workspace.debugger_data.command_executing;
        if was_executing {
            escape_debugger(workspace);
        }

        command: string;
        if clear {
            path_end := 0;
            each i in buffer.relative_path.length {
                if buffer.relative_path[i] == '/' {
                    path_end = i + 1;
                }
            }

            file: string = { length = buffer.relative_path.length - path_end; data = buffer.relative_path.data + path_end; }
            command = format_string("br clear -f % -l %\n", temp_allocate, file, line);
        }
        else {
            command = format_string("b %:%\n", temp_allocate, buffer.relative_path, line);
        }

        send_command_to_debugger(workspace, command);

        if was_executing {
            continue_debugger(workspace);
        }
    }

    if clear {
        current_breakpoint := buffer.breakpoints;
        if current_breakpoint == breakpoint {
            buffer.breakpoints = breakpoint.next;
        }
        else {
            while current_breakpoint {
                if current_breakpoint.next == breakpoint {
                    current_breakpoint.next = breakpoint.next;
                    break;
                }

                current_breakpoint = current_breakpoint.next;
            }
        }

        free_allocation(breakpoint);
    }
    else {
        breakpoint = new<Breakpoint>();
        breakpoint.line = line;
        breakpoint.active = true;

        current_breakpoint := buffer.breakpoints;
        if current_breakpoint == null || line < current_breakpoint.line {
            breakpoint.next = current_breakpoint;
            buffer.breakpoints = breakpoint;
        }
        else {
            while current_breakpoint {
                if current_breakpoint.next == null || line < current_breakpoint.next.line {
                    breakpoint.next = current_breakpoint.next;
                    current_breakpoint.next = breakpoint;
                    break;
                }

                current_breakpoint = current_breakpoint.next;
            }
        }
    }
}

step_over() {
    workspace := get_workspace();
    if !workspace.debugger_data.running || workspace.debugger_data.command_executing return;

    send_command_to_debugger(workspace, "n\n");
    workspace.debugger_data.command_executing = true;
}

step_in() {
    workspace := get_workspace();
    if !workspace.debugger_data.running || workspace.debugger_data.command_executing return;

    send_command_to_debugger(workspace, "s\n");
    workspace.debugger_data.command_executing = true;
}

step_out() {
    workspace := get_workspace();
    if !workspace.debugger_data.running || workspace.debugger_data.command_executing return;

    send_command_to_debugger(workspace, "finish\n");
    workspace.debugger_data.command_executing = true;
}

run_to() {
    workspace := get_workspace();
    if workspace.bottom_window_selected || !workspace.debugger_data.running || workspace.debugger_data.command_executing return;

    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null return;

    line := clamp(buffer_window.line, 0, buffer.line_count - 1) + 1;

    command := format_string("br set -o 1 -f % -l %\n", temp_allocate, buffer.relative_path, line);
    send_command_to_debugger(workspace, command);
    continue_debugger(workspace);
}

skip_to() {
    workspace := get_workspace();
    if workspace.bottom_window_selected || !workspace.debugger_data.running || workspace.debugger_data.command_executing return;

    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null || buffer_window.buffer_index != workspace.debugger_data.paused_file_index return;

    line := clamp(buffer_window.line, 0, buffer.line_count - 1) + 1;

    command := format_string("jump %\n", temp_allocate, line);
    send_command_to_debugger(workspace, command);
}

#private

debugger_thread(int thread, JobData data) {
    workspace: Workspace* = data.pointer;

    clear_debugger_buffer_window(workspace);

    found_executable := false;
    executable, args: string;
    each i in workspace.local_settings.debug_command.length {
        char := workspace.local_settings.debug_command[i];
        if found_executable {
            if char == ' ' {
                args = {
                    length = workspace.local_settings.debug_command.length - i;
                    data = workspace.local_settings.debug_command.data + i;
                }
                break;
            }
            else {
                executable.length++;
            }
        }
        else if char != ' ' {
            found_executable = true;
            executable = {
                length = 1;
                data = workspace.local_settings.debug_command.data + i;
            }
        }
    }

    #if os == OS.Windows {
        if !ends_with(executable, ".exe") {
            executable = temp_string(executable, ".exe");
        }
    }

    command := temp_string("lldb -- ", executable, args);
    workspace.debugger_data.started = start_command(command, workspace.directory, &workspace.debugger_data.process, true, false);

    if !workspace.debugger_data.started {
        workspace.debugger_data.failed_to_start = true;
        return;
    }

    buf: CArray<u8>[5000];
    success, text := read_from_output_pipe(&workspace.debugger_data.process, &buf, buf.length);
    add_to_debugger_buffer(workspace, text);

    each buffer in workspace.buffers {
        breakpoint := buffer.breakpoints;
        while breakpoint {
            if breakpoint.active {
                command = format_string("b %:%\n", temp_allocate, buffer.relative_path, breakpoint.line);
                send_command_to_debugger(workspace, command);
            }

            breakpoint = breakpoint.next;
        }
    }

    send_command_to_debugger(workspace, "r\n");
    workspace.debugger_data.command_executing = true;

    while workspace.debugger_data.running {
        success, text = read_from_output_pipe(&workspace.debugger_data.process, &buf, buf.length);

        if !success break;

        if !parse_debugger_output(workspace, text) {
            add_to_debugger_buffer(workspace, text);
        }
    }

    close_process_and_get_exit_code(&workspace.debugger_data.process, &workspace.debugger_data.exit_code);
    workspace.debugger_data.exited = true;

    log("lldb exited with code %\n", workspace.debugger_data.exit_code);
}

exit_debugger(int thread, JobData data) {
    workspace: Workspace* = data.pointer;

    escape_debugger(workspace);
    send_command_to_debugger(workspace, "kill\n");
    send_command_to_debugger(workspace, "quit\n");
    workspace.debugger_data.running = false;

    trigger_window_update();
}

escape_debugger(Workspace* workspace) {
    workspace.debugger_data.skip_next_stop = true;

    #if os == OS.Windows {
        send_command_to_debugger(workspace, "process interrupt\n");
    }
    #if os == OS.Linux {
        kill(workspace.debugger_data.process.pid, KillSignal.SIGINT);
    }

    sleep(200);
    workspace.debugger_data.command_executing = false;
}

continue_debugger(Workspace* workspace) {
    if !workspace.debugger_data.command_executing {
        send_command_to_debugger(workspace, "c\n");
        workspace.debugger_data.command_executing = true;
    }
}

send_command_to_debugger(Workspace* workspace, string command) {
    #if os == OS.Windows {
        WriteFile(workspace.debugger_data.process.input_pipe, command.data, command.length, null, null);
    }
    #if os == OS.Linux {
        write(workspace.debugger_data.process.input_pipe, command.data, command.length);
    }
}

bool parse_debugger_output(Workspace* workspace, string text) {
    process := "Process "; #const
    if starts_with(text, process) {
        i := process.length;
        parsing_pid := true;
        parsing_status := false;
        while i < text.length {
            char := text[i];
            if char == ' ' {
                if parsing_pid {
                    parsing_pid = false;
                    parsing_status = true;
                }
            }
            else if parsing_pid && (char < '0' || char > '9') {
                break;
            }
            else if parsing_status {
                status: string = { length = text.length - i; data = text.data + i; }
                if starts_with(status, "stopped") {
                    workspace.debugger_data.command_executing = false;
                    if !workspace.debugger_data.skip_next_stop {
                        data: JobData;
                        data.pointer = workspace;
                        queue_work(&low_priority_queue, load_debugger_info, data);
                    }

                    workspace.debugger_data.skip_next_stop = false;
                    return true;
                }

                break;
            }

            i++;
        }
    }

    if workspace.debugger_data.parse_status == DebuggerParseStatus.None {
        return false;
    }

    if !workspace.debugger_data.parse_state.command_line_read {
        i := 0;
        while i < text.length {
            char := text[i++];
            if char == '\n' {
                workspace.debugger_data.parse_state.command_line_read = true;
                break;
            }
        }

        text.length -= i;
        text.data += i;
    }

    if !workspace.debugger_data.parse_state.header_read {
        switch workspace.debugger_data.parse_status {
            case DebuggerParseStatus.Variables;
            case DebuggerParseStatus.Expression; {}
            default; {
                i := 0;
                while i < text.length {
                    char := text[i++];
                    if char == '\n' {
                        workspace.debugger_data.parse_state.header_read = true;
                        break;
                    }
                }

                text.length -= i;
                text.data += i;
            }
        }
    }

    if text.length == 0 return true;

    log("%, '%'\n", workspace.debugger_data.parse_status, text);

    // TODO Implement these
    switch workspace.debugger_data.parse_status {
        case DebuggerParseStatus.Source; {
        }
        case DebuggerParseStatus.Variables; {
        }
        case DebuggerParseStatus.Expression; {
        }
        case DebuggerParseStatus.StackTrace; {
        }
        case DebuggerParseStatus.Registers; {
        }
        case DebuggerParseStatus.Threads; {
        }
    }

    workspace.debugger_data.parse_status = DebuggerParseStatus.None;
    return true;
}

load_debugger_info(int thread, JobData data) {
    workspace: Workspace* = data.pointer;

    wait_for_debugger_parsing(workspace, "source info\n", DebuggerParseStatus.Source);
    wait_for_debugger_parsing(workspace, "v\n", DebuggerParseStatus.Variables);
    // TODO Evaluate watches
    // wait_for_debugger_parsing(workspace, "p\n", DebuggerParseStatus.Expression);
    // wait_for_debugger_parsing(workspace, "bt\n", DebuggerParseStatus.StackTrace);
    // wait_for_debugger_parsing(workspace, "register read\n", DebuggerParseStatus.Registers);
    // wait_for_debugger_parsing(workspace, "thread list\n", DebuggerParseStatus.Threads);
}

wait_for_debugger_parsing(Workspace* workspace, string command, DebuggerParseStatus status) {
    state: DebuggerParseState;
    workspace.debugger_data = {
        parse_status = status;
        parse_state = state;
    }

    send_command_to_debugger(workspace, command);

    while workspace.debugger_data.parse_status != DebuggerParseStatus.None {}
}

add_to_debugger_buffer(Workspace* workspace, string text) {
    line := add_text_to_end_of_buffer(&workspace.debugger_data.buffer, text, true);
    workspace.debugger_data.buffer_window.line = workspace.debugger_data.buffer.line_count - 1;
    workspace.debugger_data.buffer_window.cursor = line.length;
    adjust_start_line(&workspace.debugger_data.buffer_window);
    trigger_window_update();
}

clear_debugger_buffer_window(Workspace* workspace) {
    clear_buffer_and_window(&workspace.debugger_data.buffer, &workspace.debugger_data.buffer_window);
}

string get_debugger_buffer_title() {
    workspace := get_workspace();

    if workspace.debugger_data.failed_to_start {
        return format_string("Failed to start lldb with command '%'", temp_allocate, workspace.local_settings.debug_command);
    }

    if !workspace.debugger_data.command_executing {
        return format_string("Execution paused for command '%'", temp_allocate, workspace.local_settings.debug_command);
    }

    if workspace.debugger_data.exited {
        return format_string("lldb exited with code '%'", temp_allocate, workspace.debugger_data.exit_code);
    }

    return format_string("Running debugger with command '%'", temp_allocate, workspace.local_settings.debug_command);
}
