// TODO Reworking the terminal
// - Don't directly run the terminal process, I don't care about handling all of that
// - Show the directory, handle 'cd' and track the directory in TerminalData
// - Handle clear to reset the terminal buffer
// - Handle up/down to get to previous commands
// - Allow the use to type commands, then execute the commands using the appropriate shell
//   - Make sure to to handle things like escaped chars and paths with spaces
// - Allow for scrolling and refocus the bottom when typing a new command
// - Handle cancelling commands with Ctrl+C


init_terminal() {
    #if os == OS.Linux {
        shell = get_environment_variable("SHELL", allocate);
        if string_is_empty(shell) {
            shell = "/bin/sh";
        }
    }
}

struct TerminalData {
    running: bool;
    exit_code: int;
    buffer: Buffer = { read_only = true; title = get_terminal_title; }
    buffer_window: BufferWindow;
    process: ProcessData;
    pipes: TerminalPipes;
}

start_or_select_terminal() {
    workspace := get_workspace();
    if workspace.terminal_data.running return;

    data: JobData;
    data.pointer = workspace;
    queue_work(&low_priority_queue, terminal_job, data);
}

close_and_unselect_terminal() {
    workspace := get_workspace();
    if !workspace.terminal_data.running return;

    #if os == OS.Windows {
        CloseHandle(workspace.terminal_data.pipes.input);
        CloseHandle(workspace.terminal_data.pipes.output);
        TerminateThread(workspace.terminal_data.process.thread, 0);
        TerminateProcess(workspace.terminal_data.process.process, 0);
    }
    else {
        close(workspace.terminal_data.pipes.input);
        close(workspace.terminal_data.pipes.output);
        kill(workspace.terminal_data.process.pid, 0);
    }

    workspace.bottom_window_selected = false;
    workspace.terminal_data.running = false;
}

bool send_input_to_terminal(string char) {
    workspace := get_workspace();
    if !workspace.terminal_data.running || !workspace.bottom_window_selected || get_run_window(workspace) != null return false;

    #if os == OS.Windows {
        WriteFile(workspace.terminal_data.pipes.input, char.data, char.length, null, null);
    }
    #if os == OS.Linux {
        write(workspace.terminal_data.pipes.input, char.data, char.length);
    }

    return true;
}

BufferWindow* get_terminal_window(Workspace* workspace) {
    if workspace.terminal_data.running {
        return &workspace.terminal_data.buffer_window;
    }

    return null;
}

#private


#if os == OS.Windows {
    struct TerminalPipes {
        input: Handle*;
        output: Handle*;
    }
}
else {
    struct TerminalPipes {
        input: int;
        output: int;
    }

    shell: string;
}

terminal_job(int index, JobData data) {
    log("Starting terminal\n");
    workspace: Workspace* = data.pointer;
    defer workspace.terminal_data.running = false;

    clear_terminal_buffer_window(workspace);

    #if os == OS.Windows {
        sa: SECURITY_ATTRIBUTES = { nLength = size_of(SECURITY_ATTRIBUTES); bInheritHandle = true; }
        stdout_read_handle, stdout_write_handle: Handle*;
        if !CreatePipe(&stdout_read_handle, &stdout_write_handle, &sa, 0) {
            return;
        }
        SetHandleInformation(stdout_read_handle, HandleFlags.HANDLE_FLAG_INHERIT, HandleFlags.None);

        stdin_read_handle, stdin_write_handle: Handle*;
        if !CreatePipe(&stdin_read_handle, &stdin_write_handle, &sa, 0) {
            return;
        }
        SetHandleInformation(stdin_write_handle, HandleFlags.HANDLE_FLAG_INHERIT, HandleFlags.None);

        si: STARTUPINFOA = {
            cb = size_of(STARTUPINFOA); dwFlags = 0x100;
            hStdInput = stdin_read_handle;
            hStdError = stdout_write_handle; hStdOutput = stdout_write_handle;
        }
        pi: PROCESS_INFORMATION;

        if !CreateProcessA(null, "powershell -NoLogo", null, null, true, 0x8000000, null, null, &si, &pi) {
            log("Failed to start terminal\n");
            CloseHandle(stdout_read_handle);
            CloseHandle(stdout_write_handle);
            CloseHandle(stdin_read_handle);
            CloseHandle(stdin_write_handle);
            return;
        }

        CloseHandle(stdin_read_handle);
        CloseHandle(stdout_write_handle);

        workspace.terminal_data = {
            running = true;
            process = {
                thread = pi.hThread;
                process = pi.hProcess;
            }
            pipes = {
                input = stdin_write_handle;
                output = stdout_read_handle;
            }
        }

        buf: CArray<u8>[1000];
        while workspace.terminal_data.running {
            read: int;
            success := ReadFile(stdout_read_handle, &buf, buf.length, &read, null);

            if !success || read == 0 break;

            text: string = { length = read; data = &buf; }
            add_to_terminal_buffer(workspace, text);
        }

        GetExitCodeProcess(pi.hProcess, &workspace.terminal_data.exit_code);

        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        CloseHandle(stdout_read_handle);
        CloseHandle(stdin_write_handle);
    }
    else {
        stdout_pipe_files: Array<int>[2];
        if pipe2(stdout_pipe_files.data, 0x80000) < 0 {
            return;
        }

        stdin_pipe_files: Array<int>[2];
        if pipe2(stdin_pipe_files.data, 0x80000) < 0 {
            return;
        }

        pid := fork();

        if pid < 0 {
            return;
        }

        read_pipe := 0; #const
        write_pipe := 1; #const

        if pid == 0 {
            close(stdout_pipe_files[read_pipe]);
            dup2(stdout_pipe_files[write_pipe], stdout);

            close(stdin_pipe_files[write_pipe]);
            dup2(stdin_pipe_files[read_pipe], stdin);

            exec_args: Array<u8*>[2];
            exec_args[0] = shell.data;
            exec_args[1] = null;
            execve(shell.data, exec_args.data, __environment_variables_pointer);
            exit(-1);
        }

        close(stdout_pipe_files[write_pipe]);
        close(stdin_pipe_files[read_pipe]);

        workspace.terminal_data = {
            running = true;
            process = {
                pid = pid;
            }
            pipes = {
                input = stdin_pipe_files[write_pipe];
                output = stdout_pipe_files[read_pipe];
            }
        }

        buf: CArray<u8>[1000];
        while workspace.terminal_data.running {
            length := read(stdout_pipe_files[read_pipe], &buf, buf.length);

            if length <= 0 break;

            text: string = { length = length; data = &buf; }
            add_to_terminal_buffer(workspace, text);
        }

        if workspace.terminal_data.running {
            close(stdout_pipe_files[read_pipe]);
            close(stdin_pipe_files[write_pipe]);
        }

        wait4(pid, &workspace.terminal_data.exit_code, 0, null);
    }

    log("Terminal exited with code %\n", workspace.terminal_data.exit_code);
}

add_to_terminal_buffer(Workspace* workspace, string text) {
    add_text_to_end_of_buffer(&workspace.terminal_data.buffer, text);
    workspace.terminal_data.buffer_window.line = workspace.terminal_data.buffer.line_count - 1;
    adjust_start_line(&workspace.terminal_data.buffer_window);
}

clear_terminal_buffer_window(Workspace* workspace) {
    workspace.terminal_data.buffer_window = {
        cursor = 0;
        line = 0;
        start_line = 0;
    }

    line := workspace.terminal_data.buffer.lines;

    workspace.terminal_data.buffer = {
        line_count = 1;
        line_count_digits = 1;
        lines = allocate_line();
    }

    while line {
        next := line.next;
        free_line_and_children(line);
        line = next;
    }
}

string get_terminal_title() {
    return "Terminal";
}
