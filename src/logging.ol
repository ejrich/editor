init_logging() {
    home_directory := get_environment_variable(home_environment_variable, temp_allocate);
    log_file_path := temp_string(home_directory, "/Documents/", application_name, "/log/run.log");

    create_directories_recursively(log_file_path);

    opened: bool;
    opened, log_file = open_file(log_file_path, FileFlags.Create);
    if !opened {
        print("Unable to write to log file: '%'\n", log_file_path);
    }
}

deinit_logging() {
    if log_file.handle
        close_file(log_file);
}

log(string format, Params args) {
    timestamped_format: string;
    #if os == OS.Linux {
        now: Timespec;
        clock_gettime(ClockId.CLOCK_REALTIME, &now);
        t := now.tv_sec;
        time := localtime(&t);
        write_to_console_and_file("[ %/%/% %:%:% ] ", int_format(time.tm_mon, min_chars = 2), int_format(time.tm_mday, min_chars = 2), int_format(time.tm_year - 100, min_chars = 2), int_format(time.tm_hour, min_chars = 2), int_format(time.tm_min, min_chars = 2), int_format(time.tm_sec, min_chars = 2));
    }
    else #if os == OS.Windows {
        time: SYSTEMTIME;
        GetLocalTime(&time);
        write_to_console_and_file("[ %/%/% %:%:% ] ", int_format(time.wMonth, min_chars = 2), int_format(time.wDay, min_chars = 2), int_format(time.wYear % 100, min_chars = 2), int_format(time.wHour, min_chars = 2), int_format(time.wMinute, min_chars = 2), int_format(time.wSecond, min_chars = 2));
    }

    write_to_console_and_file(format, args);
}

#private

write_to_console_and_file(string format, Params args) {
    if args.length == 0 {
        string_buffer_write_to_console_and_file(null, format.data, format.length);
        return;
    }

    buffer: Array<u8>[1000];
    string_buffer: StringBuffer = { buffer = buffer; flush = string_buffer_write_to_console_and_file; }
    format_string_arguments(&string_buffer, format, args);
    string_buffer_write_to_console_and_file(null, buffer.data, string_buffer.length);
}

string_buffer_write_to_console_and_file(void* data, u8* buffer, s64 length) {
    write_buffer_to_standard_out(buffer, length);
    if log_file.handle
        write_buffer_to_file(log_file, buffer, length);
}

log_file: File;
