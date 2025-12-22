init_run() {
    run_buffer_window.static_buffer = &run_buffer;

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

close_run_buffer_and_stop_command() {
    current_command.displayed = false;
    force_command_to_stop();
}

BufferWindow* get_run_window() {
    if current_command.displayed {
        return &run_buffer_window;
    }

    return null;
}

Buffer* run_command_and_save_to_buffer(string command) {
    buffer := new<Buffer>();
    buffer.read_only = true;
    buffer.line_count = 1;
    buffer.line_count_digits = 1;
    buffer.lines = allocate_line();

    success, exit_code := execute_command(command, buffer, add_text_to_end_of_buffer);

    return buffer;
}

#if os == OS.Linux {
    void* popen(string command, string type) #extern "c"
    int pclose(void* stream) #extern "c"
    u8* fgets(u8* s, int n, void* stream) #extern "c"
}

#private

run_command(int index, JobData data) {
    semaphore_wait(&run_mutex);
    defer semaphore_release(&run_mutex);

    clear_run_buffer_window(data.string);

    log("Executing command: '%'\n", data.string);

    current_command = {
        command = data.string;
        running = true;
        exit_code = 0;
        failed = false;
        exited = false;
        displayed = true;
    }

    success, exit_code := execute_command(data.string, &run_buffer, add_to_run_buffer, &current_process, &current_command.exited);

    if success {
        current_command.exit_code = exit_code;
    }
    else {
        current_command.failed = true;
    }

    current_command.running = false;
    log("Exit code: %\n", current_command.exit_code);
}

bool, int execute_command(string command, Buffer* buffer, SaveToBuffer save_to_buffer, ProcessData* process_data = null, bool* exited = null) {
    exit_code: int;

    #if os == OS.Windows {
        sa: SECURITY_ATTRIBUTES = { nLength = size_of(SECURITY_ATTRIBUTES); bInheritHandle = true; }
        read_handle, write_handle: Handle*;

        if !CreatePipe(&read_handle, &write_handle, &sa, 0) {
            return false, 0;
        }
        SetHandleInformation(read_handle, HandleFlags.HANDLE_FLAG_INHERIT, HandleFlags.None);

        si: STARTUPINFOA = {
            cb = size_of(STARTUPINFOA); dwFlags = 0x100;
            hStdInput = GetStdHandle(STD_INPUT_HANDLE);
            hStdError = write_handle; hStdOutput = write_handle;
        }
        pi: PROCESS_INFORMATION;

        if !CreateProcessA(null, command, null, null, true, 0x8, null, null, &si, &pi) {
            CloseHandle(read_handle);
            CloseHandle(write_handle);
            return false, 0;
        }

        if process_data {
            process_data.thread = pi.hThread;
            process_data.process = pi.hProcess;
        }

        CloseHandle(si.hStdInput);
        CloseHandle(write_handle);

        buf: CArray<u8>[1000];
        while exited == null || !(*exited) {
            read: int;
            success := ReadFile(read_handle, &buf, buf.length, &read, null);

            if !success || read == 0 break;

            text: string = { length = read; data = &buf; }
            save_to_buffer(buffer, text);
        }

        GetExitCodeProcess(pi.hProcess, &exit_code);

        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        CloseHandle(read_handle);
    }
    else {
        pid := popen(command, "r");

        buf: CArray<u8>[1000];
        while exited == null || !(*exited) {
            read: int;
            result := fgets(&buf, buf.length, pid);

            if result == null break;

            text := convert_c_string(result);
            save_to_buffer(buffer, text);
        }

        exit_code = pclose(pid);
    }

    return true, exit_code;
}

clear_run_buffer_window(string command) {
    run_buffer_window = {
        cursor = 0;
        line = 0;
        start_line = 0;
    }

    line := run_buffer.lines;

    run_buffer = {
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

interface SaveToBuffer(Buffer* buffer, string text)

add_to_run_buffer(Buffer* _, string text) {
    change_line := run_buffer_window.line == run_buffer.line_count - 1;

    add_text_to_end_of_buffer(&run_buffer, text);

    if change_line {
        run_buffer_window.line = run_buffer.line_count - 1;
        adjust_start_line(&run_buffer_window);
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
    displayed: bool;
}

current_command: CommandRunData;

#if os == OS.Windows {
    struct ProcessData {
        thread: Handle*;
        process: Handle*;
    }
}
else {
    struct ProcessData {
        handle: s64;
    }
}

current_process: ProcessData;

string get_run_buffer_title() {
    if current_command.running {
        return format_string("Running: %", temp_allocate, current_command.command);
    }

    if current_command.failed {
        return format_string("Failed to execute: %", temp_allocate, current_command.command);
    }

    if current_command.exit_code == 0 {
        return format_string("Success: %", temp_allocate, current_command.command);
    }

    return format_string("Failed with code %: %", temp_allocate, current_command.exit_code, current_command.command);
}

run_buffer: Buffer = { read_only = true; title = get_run_buffer_title; }
run_buffer_window: BufferWindow;
