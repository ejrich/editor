init_run() {
    command_buffer_window.static_buffer = &command_buffer;

    create_semaphore(&run_mutex, initial_value = 1);
}

queue_command_to_run(string command) {
    data: JobData;
    data.string = command;
    queue_work(&low_priority_queue, run_command, data);
}

force_command_to_stop() {
    if current_command.running {
        #if os == OS.Windows {
            TerminateThread(current_process.thread, command_exited_code);
            TerminateProcess(current_process.process, command_exited_code);
        }
        else {
            // TODO Exit the process for linux
        }

        current_command.exited = true;
    }
}

#private

run_command(int index, JobData data) {
    semaphore_wait(&run_mutex);
    defer semaphore_release(&run_mutex);

    clear_command_buffer_window();

    log("Executing command: '%'\n", data.string);

    current_command = {
        command = data.string;
        running = false;
        exit_code = 0;
        failed = false;
        exited = false;
    }

    #if os == OS.Windows {
        sa: SECURITY_ATTRIBUTES = { nLength = size_of(SECURITY_ATTRIBUTES); bInheritHandle = true; }
        read_handle, write_handle: Handle*;

        if !CreatePipe(&read_handle, &write_handle, &sa, 0) {
            current_command.failed = true;
            return;
        }
        SetHandleInformation(read_handle, HandleFlags.HANDLE_FLAG_INHERIT, HandleFlags.None);

        si: STARTUPINFOA = {
            cb = size_of(STARTUPINFOA); dwFlags = 0x100;
            hStdInput = GetStdHandle(STD_INPUT_HANDLE);
            hStdError = write_handle; hStdOutput = write_handle;
        }
        pi: PROCESS_INFORMATION;

        if !CreateProcessA(null, current_command.command, null, null, true, 0x8, null, null, &si, &pi) {
            CloseHandle(read_handle);
            CloseHandle(write_handle);
            current_command.failed = true;
            return;
        }

        current_process = {
            thread = pi.hThread;
            process = pi.hProcess;
        }
        current_command.running = true;

        CloseHandle(si.hStdInput);
        CloseHandle(write_handle);

        buf: CArray<u8>[1000];
        while !current_command.exited {
            read: int;
            success := ReadFile(read_handle, &buf, buf.length, &read, null);

            if !success || read == 0 break;

            str: string = { length = read; data = &buf; }
            add_to_command_buffer(str);
        }

        GetExitCodeProcess(pi.hProcess, &current_command.exit_code);

        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        CloseHandle(read_handle);
    }
    else {
        // TODO Implement for linux
        current_command.exit_code = system(data.string);
    }

    log("Exit code: %\n", current_command.exit_code);
}

clear_command_buffer_window() {
    command_buffer_window = {
        cursor = 0;
        line = 0;
        start_line = 0;
    }

    line := command_buffer.lines;

    command_buffer = {
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

add_to_command_buffer(string value) {
    text: string = { data = value.data; }
    each i in value.length {
        char := value[i];
        if char == '\n' {
            if text.length {
                add_text_to_line(text, &command_buffer_window, &command_buffer);
            }

            line := get_buffer_line(&command_buffer, command_buffer_window.line);
            add_new_line(&command_buffer_window, &command_buffer, line, false, false);
            calculate_line_digits(&command_buffer);
            command_buffer_window.cursor = 0;

            text = { length = 0; data = value.data + i + 1; }
        }
        else {
            text.length++;
        }
    }

    if text.length {
        add_text_to_line(text, &command_buffer_window, &command_buffer);
    }
}

run_mutex: Semaphore;

command_exited_code := -100; #const

struct CommandRunData {
    command: string;
    running: bool;
    exit_code: int;
    failed: bool;
    exited: bool;
}

current_command: CommandRunData;

#if os == OS.Windows {
    struct RunProcessData {
        thread: Handle*;
        process: Handle*;
    }
}
else {
    struct RunProcessData {
        handle: s64;
    }
}

current_process: RunProcessData;

command_buffer: FileBuffer = { read_only = true; }
command_buffer_window: BufferWindow;
