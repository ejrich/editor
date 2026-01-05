struct TerminalData {
    terminal_window_focused: bool;
    buffer: Buffer = { read_only = true; }
    buffer_window: BufferWindow;
    process: ProcessData;
    pipes: TerminalPipes;
}

start_or_select_terminal() {
    // TODO Fully implement
    data: JobData;
    data.pointer = get_workspace();
    queue_work(&low_priority_queue, terminal_job, data);
}

close_and_unselect_terminal() {
    // TODO Implement
}

send_input_to_terminal(string char) {
    // TODO Implement
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
}

terminal_job(int index, JobData data) {
    log("Starting terminal\n");
    workspace: Workspace* = data.pointer;
    exit_code: int;

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
        while true {
            read: int;
            success := ReadFile(stdout_read_handle, &buf, buf.length, &read, null);

            if !success || read == 0 break;

            text: string = { length = read; data = &buf; }
            add_text_to_end_of_buffer(&workspace.terminal_data.buffer, text);
        }

        GetExitCodeProcess(pi.hProcess, &exit_code);

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

            execve("/bin/sh".data, null, __environment_variables_pointer);
            exit(-1);
        }

        close(stdout_pipe_files[write_pipe]);
        close(stdin_pipe_files[read_pipe]);

        workspace.terminal_data = {
            process = {
                pid = pid;
            }
            pipes = {
                input = stdin_pipe_files[write_pipe];
                output = stdout_pipe_files[read_pipe];
            }
        }

        buf: CArray<u8>[1000];
        while true {
            length := read(stdout_pipe_files[read_pipe], &buf, buf.length);

            if length <= 0 break;

            text: string = { length = length; data = &buf; }
            add_text_to_end_of_buffer(&workspace.terminal_data.buffer, text);
        }

        wait4(pid, &exit_code, 0, null);
    }

    log("Terminal exited with code %\n", exit_code);
}
