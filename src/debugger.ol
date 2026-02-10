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
    StackTrace;
    Registers;
    Threads;
    Expression;
}

struct DebuggerParseState {
    command_line_read: bool;
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

    buf: CArray<u8>[10000];
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

    send_command_to_debugger(workspace, "target stop-hook add\n");
    send_command_to_debugger(workspace, "source info\n");
    send_command_to_debugger(workspace, "v\n");
    send_command_to_debugger(workspace, "bt\n");
    send_command_to_debugger(workspace, "register read\n");
    send_command_to_debugger(workspace, "thread list\n");
    send_command_to_debugger(workspace, "DONE\n");

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
    if workspace.debugger_data.parse_status == DebuggerParseStatus.None {
        source_info_start := "Lines found in module "; #const
        if starts_with(text, source_info_start) {
            // Execution is paused, start parsing the program state
            workspace.debugger_data.command_executing = false;
            workspace.debugger_data.parse_status = DebuggerParseStatus.Source;
        }
        else {
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
                                queue_work(&low_priority_queue, load_watches, data);
                            }

                            workspace.debugger_data.skip_next_stop = false;
                            return true;
                        }

                        break;
                    }

                    i++;
                }
            }

            return false;
        }
    }

    log("%, %\n", workspace.debugger_data.parse_status, text);

    switch workspace.debugger_data.parse_status {
        case DebuggerParseStatus.Source; {
            // TODO Parse
            // Lines found in module `editor
            // [0x000000000041ad44-0x000000000041ad59): /home/evan/editor/src/buffers.ol:3:5
            workspace.debugger_data.parse_status = DebuggerParseStatus.Variables;
        }
        case DebuggerParseStatus.Variables; {
            // TODO Parse
            // (Workspace *) workspace = 0xff0000000000000a
            // (BufferWindow *) bottom_window = 0x00000000004795e0
            // (bool) bottom_focused = true
            workspace.debugger_data.parse_status = DebuggerParseStatus.StackTrace;
        }
        case DebuggerParseStatus.StackTrace; {
            // TODO Parse
            // * thread #1, name = 'editor', stop reason = breakpoint 1.1
            //   * frame #0: 0x000000000041ad44 editor`draw_buffers at buffers.ol:3:5
            //     frame #1: 0x000000000040dcaf editor`main at main.ol:78:17
            //     frame #2: 0x00000000004055a1 editor`__start(argc=2, argv=0x00007fffffffd128) at runtime.ol:296:5
            //     frame #3: 0x00000000004596dd editor`_start + 13
            workspace.debugger_data.parse_status = DebuggerParseStatus.Registers;
        }
        case DebuggerParseStatus.Registers; {
            // TODO Parse
            // General Purpose Registers:
            //        rax = 0x0000000000000000
            //        rbx = 0x0000000000000000
            //        rcx = 0xff0000000000000a
            //        rdx = 0x000000000047b8e0  editor`__bss_start + 37888
            //        rdi = 0x00000000000001ff
            //        rsi = 0x0000000000002300
            //        rbp = 0x00007fffffffd120
            //        rsp = 0x00007fffffffcfd0
            //         r8 = 0x00007fffd830d000
            //         r9 = 0x0000000000000000
            //        r10 = 0x0000000000000000
            //        r11 = 0x0000000000000000
            //        r12 = 0x00000000004596d0  editor`_start
            //        r13 = 0x00007fffffffd120
            //        r14 = 0x0000000000000000
            //        r15 = 0x0000000000000000
            //        rip = 0x000000000041ad44  editor`draw_buffers + 4 at buffers.ol:3:5
            //     rflags = 0x0000000000000202
            //         cs = 0x0000000000000033
            //         fs = 0x0000000000000000
            //         gs = 0x0000000000000000
            //         ss = 0x000000000000002b
            //    fs_base = 0x00007ffff76f2340
            //    gs_base = 0x0000000000000000
            //         ds = 0x0000000000000000
            //         es = 0x0000000000000000
            workspace.debugger_data.parse_status = DebuggerParseStatus.Threads;
        }
        case DebuggerParseStatus.Threads; {
            // TODO Parse
            // Process 14109 stopped
            // * thread #1: tid = 14109, 0x000000000041ad44 editor`draw_buffers at buffers.ol:3:5, name = 'editor', stop reason = breakpoint 1.1
            //   thread #2: tid = 14216, 0x00000000004455d5 editor`semaphore_wait(semaphore=0x000000000046fc30) at thread.ol:55:13, name = 'editor'
            //   thread #3: tid = 14217, 0x00000000004455d5 editor`semaphore_wait(semaphore=0x000000000046fc30) at thread.ol:55:13, name = 'editor'
            //   thread #4: tid = 14218, 0x00000000004455d5 editor`semaphore_wait(semaphore=0x000000000046fc30) at thread.ol:55:13, name = 'editor'
            //   thread #5: tid = 14219, 0x00000000004455d5 editor`semaphore_wait(semaphore=0x000000000046fc30) at thread.ol:55:13, name = 'editor'
            //   thread #6: tid = 14220, 0x00000000004455d5 editor`semaphore_wait(semaphore=0x000000000046fc30) at thread.ol:55:13, name = 'editor'
            //   thread #7: tid = 14221, 0x00000000004455d5 editor`semaphore_wait(semaphore=0x000000000046fc30) at thread.ol:55:13, name = 'editor'
            //   thread #8: tid = 14222, 0x0000Threads, Threads, r`semaphore_wait(semaphore=0x000000000046fc30) at thread.ol:55:13, name = 'editor'
            //   thread #9: tid = 14223, 0x00000000004455d5 editor`semaphore_wait(semaphore=0x000000000046fc30) at thread.ol:55:13, name = 'editor'
            //   thread #10: tid = 14224, 0x00000000004455d5 editor`semaphore_wait(semaphore=0x000000000046e020) at thread.ol:55:13, name = 'editor'
            //   thread #11: tid = 14225, 0x00000000004455d5 editor`semaphore_wait(semaphore=0x000000000046e020) at thread.ol:55:13, name = 'editor'
            //   thread #12: tid = 14226, 0x00000000004455d5 editor`semaphore_wait(semaphore=0x000000000046e020) at thread.ol:55:13, name = 'editor'
            //   thread #13: tid = 14227, 0x00000000004455d5 editor`semaphore_wait(semaphore=0x000000000046e020) at thread.ol:55:13, name = 'editor'
            //   thread #14: tid = 14228, 0x00000000004455d5 editor`semaphore_wait(semaphore=0x000000000046e020) at thread.ol:55:13, name = 'editor'
            //   thread #15: tid = 14229, 0x00000000004455d5 editor`semaphore_wait(semaphore=0x000000000046e020Threads, Threads, 13, name = 'editor'
            //   thread #16: tid = 14230, 0x00000000004455d5 editor`semaphore_wait(semaphore=0x000000000046e020) at thread.ol:55:13, name = 'editor'
            //   thread #17: tid = 14289, 0x00007ffff7cdf9f2 libc.so.6`__syscall_cancel_arch at syscall_cancel.S:56, name = 'editor:disk$0'
            //   thread #18: tid = 14290, 0x00007ffff7cdf9f2 libc.so.6`__syscall_cancel_arch at syscall_cancel.S:56, name = 'editor:disk$0'
            //   thread #19: tid = 14291, 0x00007ffff7cdf9f2 libc.so.6`__syscall_cancel_arch at syscall_cancel.S:56, name = 'editor:disk$0'
            //   thread #20: tid = 14292, 0x00007ffff7cdf9f2 libc.so.6`__syscall_cancel_arch at syscall_cancel.S:56, name = 'editor:disk$0'
            //   thread #23: tid = 14295, 0x00007ffff7cdf9f2 libc.so.6`__syscall_cancel_arch at syscall_cancel.S:56, name = 'editor'
            //   thread #24: tid = 14298, 0x00007ffff7cdf9f2 libc.so.6`__syscall_cancel_arch at syscall_cancel.S:56, name = 'editor'
            //   thread #25: tid = 14319, 0x00007ffff7cdf9f2 libc.so.6`__syscall_cancel_arch at syscall_canThreads, WSI swapchain q'
            //   thread #26: tid = 14320, 0x00007ffff7cdf9f2 libc.so.6`__syscall_cancel_arch at syscall_cancel.S:56, name = 'WSI swapchain e'
            workspace.debugger_data.parse_status = DebuggerParseStatus.None;
        }
        case DebuggerParseStatus.Expression; {
            if workspace.debugger_data.parse_state.command_line_read {
                // TODO Allocate and add result to watches
                // Ex 1:
                // (BufferWindow) {
                //   cursor = 257
                //   line = 0
                //   start_line = 17
                //   buffer_index = 0
                //   hex_view = true
                //   start_byte = 32767
                //   previous = 0x0000000000000006
                // Ex 2:
                // (unsigned int) 1
                // Ex 3:
                // (BufferWindow *) 0x00000000004795e0
                workspace.debugger_data.parse_status = DebuggerParseStatus.None;
            }
            else if starts_with(text, "(lldb)") {
                workspace.debugger_data.parse_state.command_line_read = true;
            }
        }
    }

    return true;
}

load_watches(int thread, JobData data) {
    workspace: Workspace* = data.pointer;

    // TODO Evaluate watches
    // wait_for_debugger_parsing(workspace, "p frame_index\n", DebuggerParseStatus.Expression);
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
