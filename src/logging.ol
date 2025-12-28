init_logging() {
    home_directory := get_environment_variable(home_environment_variable, temp_allocate);
    log_file_path := temp_string(home_directory, "/Documents/", application_name, "/log/run.log");

    create_directories_recursively(log_file_path);

    opened: bool;
    opened, log_file = open_file(log_file_path, FileFlags.Create);
    if !opened {
        print("Unable to write to log file: '%'\n", log_file_path);
    }

    #if os == OS.Linux {
        found, tzfile := read_file("/etc/localtime", allocate);
        if found {
            defer free_allocation(tzfile.data);

            head := cast(tzhead*, tzfile.data);
            timecnt := decode(&head.tzh_timecnt);
            typecnt := decode(&head.tzh_typecnt);
            index := size_of(tzhead);

            now: Timespec;
            clock_gettime(ClockId.CLOCK_REALTIME, &now);
            time := now.tv_sec + time_adjust;

            highest: u64;
            transition_index: u8;
            each i in timecnt {
                transition := decode(tzfile.data + index);
                if time > transition && transition > highest {
                    highest = transition;
                    transition_index = i;
                }
                index += 4;
            }

            type_index := *(tzfile.data + index + transition_index);
            index += timecnt;

            each i in typecnt {
                if i == type_index {
                    time_adjust = decode(tzfile.data + index);
                    break;
                }
                index += 6;
            }
        }
    }
}

deinit_logging() {
    if log_file.handle
        close_file(log_file);
}

log(string format, Params args) {
    #if os == OS.Linux {
        month, day, year, hour, min, sec: u32;
        calculate_timestamp(&month, &day, &year, &hour, &min, &sec);
        write_to_console_and_file("[ %/%/% %:%:% ] ", int_format(month, min_chars = 2), int_format(day, min_chars = 2), int_format(year, min_chars = 2), int_format(hour, min_chars = 2), int_format(min, min_chars = 2), int_format(sec, min_chars = 2));
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

#if os == OS.Linux {
    calculate_timestamp(u32* month, u32* day, u32* year, u32* hour, u32* min, u32* sec) {
        now: Timespec;
        clock_gettime(ClockId.CLOCK_REALTIME, &now);
        time := now.tv_sec + time_adjust;

        seconds_in_day := 60 * 60 * 24; #const
        secs := time % seconds_in_day;

        seconds := secs % 60;
        mins := secs / 60;
        minutes := mins % 60;
        hours := mins / 60;

        days := time / seconds_in_day;

        actual_year := 1970;
        leap_index := 2;
        while true {
            if leap_index == 4 {
                if days < 366 break;

                days -= 366;
                leap_index = 1;
            }
            else {
                if days < 365 break;

                days -= 365;
                leap_index++;
            }

            actual_year++;
        }

        month_index := 0;
        while true {
            month_days := month_day_count[month_index];
            if leap_index == 4 && month_index == 1
                month_days++;

            if days < month_days break;

            days -= month_days;
            month_index++;
        }

        *month = month_index + 1;
        *day = days + 1;
        *year = actual_year % 100;
        *hour = hours;
        *min = minutes;
        *sec = seconds;
    }

    time_adjust := 0;
    month_day_count: Array<u8> = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

    struct tzhead {
        tzh_magic: CArray<u8>[4];
        tzh_version: u8;
        tzh_reserved: CArray<u8>[15];
        tzh_ttisutcnt: CArray<u8>[4];
        tzh_ttisstdcnt: CArray<u8>[4];
        tzh_leapcnt: CArray<u8>[4];
        tzh_timecnt: CArray<u8>[4];
        tzh_typecnt: CArray<u8>[4];
        tzh_charcnt: CArray<u8>[4];
    }

    u32 decode(u8* bytes) {
        value: u32 = bytes[0];
        value = (value << 8) | bytes[1];
        value = (value << 8) | bytes[2];
        value = (value << 8) | bytes[3];

        return value;
    }
}
