open_files_list() {
    load_files();
    start_list_mode("Find Files", get_files, get_total_files, get_file, change_file_filter, open_file_to_buffer, cleanup = cleanup_files);
}

open_search_list(string initial_search = empty_string) {
    change_search_filter(empty_string);
    start_list_mode("Search", get_search_results, get_total_search_results, get_file_at_line, change_search_filter, open_file_at_line, initial_value = initial_search);
}

#private

// File finder functions
load_files() {
    free_allocation(file_entries_string_pointer);
    file_entries.length = 0;

    file_entry_index = 0;
    length_to_allocate = 0;

    workspace := get_workspace();
    load_directory(workspace.directory, empty_string, true);

    if file_entry_index > file_entries_reserved {
        while file_entries_reserved < file_entry_index {
            file_entries_reserved += file_entries_block_size;
        }

        reallocate_array(&file_entries, file_entries_reserved);
        reallocate_array(&filtered_file_entries, file_entries_reserved);
    }

    file_entries.length = file_entry_index;
    file_entry_index = 0;
    file_entries_string_pointer = allocate(length_to_allocate);
    file_entries_string_index = 0;
    load_directory(workspace.directory, empty_string, false);

    change_file_filter(empty_string);
}

load_directory(string path, string display_path, bool counting) {
    #if os == OS.Linux {
        open_flags := OpenFlags.O_RDONLY | OpenFlags.O_NONBLOCK | OpenFlags.O_DIRECTORY | OpenFlags.O_LARGEFILE | OpenFlags.O_CLOEXEC;
        directory := open(path.data, open_flags, OpenMode.S_RWALL);

        if directory < 0 {
            return;
        }

        buffer: CArray<u8>[5600];
        while true {
            bytes := getdents64(directory, cast(Dirent*, &buffer), buffer.length);

            if bytes == 0 break;

            position := 0;
            while position < bytes {
                dirent := cast(Dirent*, &buffer + position);
                name := convert_c_string(&dirent.d_name);

                if !array_contains(directories_to_ignore, name) {
                    if dirent.d_type == DirentType.DT_REG {
                        file_path := name;
                        if !string_is_empty(display_path) {
                            file_path = temp_string(display_path, "/", name);
                        }

                        if counting {
                            file_entry_index++;
                            length_to_allocate += file_path.length;
                        }
                        else {
                            file_entries[file_entry_index++] = copy_path(file_path);
                        }
                    }
                    else if dirent.d_type == DirentType.DT_DIR {
                        sub_path := temp_string(path, "/", name);
                        sub_display_path := name;
                        if !string_is_empty(display_path) {
                            sub_display_path = temp_string(display_path, "/", name);
                        }
                        load_directory(sub_path, sub_display_path, counting);
                    }
                }

                position += dirent.d_reclen;
            }
        }

        close(directory);
    }
    #if os == OS.Windows {
        wildcard := "/*"; #const
        path_with_wildcard: Array<u8>[path.length + wildcard.length + 1];
        memory_copy(path_with_wildcard.data, path.data, path.length);
        memory_copy(path_with_wildcard.data + path.length, wildcard.data, wildcard.length);
        path_with_wildcard[path.length + wildcard.length] = 0;

        find_data: WIN32_FIND_DATAA;
        find_handle := FindFirstFileA(path_with_wildcard.data, &find_data);

        if cast(s64, find_handle) == -1 {
            return;
        }

        while true {
            name := convert_c_string(&find_data.cFileName);

            if !array_contains(directories_to_ignore, name) {
                if find_data.dwFileAttributes & FileAttribute.FILE_ATTRIBUTE_DIRECTORY {
                    sub_path := temp_string(path, "/", name);
                    sub_display_path := name;
                    if !string_is_empty(display_path) {
                        sub_display_path = temp_string(display_path, "/", name);
                    }
                    load_directory(sub_path, sub_display_path, counting);
                }
                else {
                    file_path := name;
                    if !string_is_empty(display_path) {
                        file_path = temp_string(display_path, "/", name);
                    }

                    if counting {
                        file_entry_index++;
                        length_to_allocate += file_path.length;
                    }
                    else {
                        file_entries[file_entry_index++] = copy_path(file_path);
                    }
                }
            }

            if !FindNextFileA(find_handle, &find_data) break;
        }

        FindClose(find_handle);
    }
}

directories_to_ignore: Array<string> = [".", "..", "bin", "obj", ".git"]

Array<ListEntry> get_files() {
    return filtered_file_entries;
}

int get_total_files() {
    return file_entries.length;
}

get_file(int thread, JobData data) {
    entry := cast(SelectedEntry*, data.pointer);
    file := entry.key;

    defer trigger_window_update();

    workspace := get_workspace();
    each buffer in workspace.buffers {
        if buffer.relative_path == file {
            entry.can_free_buffer = false;
            entry.buffer = &buffer;
            return;
        }
    }

    file_buffer := read_file_into_buffer(file);

    if file == entry.key {
        entry.buffer = file_buffer;
    }
    else {
        free_buffer(file_buffer);
    }
}

Buffer* read_file_into_buffer(string file_path) {
    success, file := open_file(file_path);
    if !success return null;

    buffer := new<Buffer>();
    buffer.read_only = true;
    buffer.line_count = 1;
    buffer.line_count_digits = 1;
    buffer.lines = allocate_line();
    buffer.syntax = get_syntax_for_file(file_path);

    buf: CArray<u8>[1000];
    while true {
        #if os == OS.Linux {
            length := read(file.handle, &buf, buf.length);
        }
        #if os == OS.Windows {
            length: int;
            ReadFile(file.handle, &buf, buf.length, &length, null);
        }

        if length <= 0 break;

        text: string = { length = length; data = &buf; }
        add_text_to_end_of_buffer(buffer, text, false);
    }

    close_file(file);
    return buffer;
}

change_file_filter(string filter) {
    if string_is_empty(filter) {
        filtered_file_entries.length = file_entries.length;
        each file, i in file_entries {
            filtered_file_entries[i] = {
                key = file;
                display = file;
            }
        }
    }
    else {
        filtered_file_entries.length = 0;
        each file in file_entries {
            if string_contains(file, filter) {
                filtered_file_entries[filtered_file_entries.length++] = {
                    key = file;
                    display = file;
                }
            }
        }
    }
}

cleanup_files() {
    free_allocation(file_entries_string_pointer);
    file_entries_string_pointer = null;
}

open_file_to_buffer(string file) {
    open_file_buffer(file, true);
}

file_entries: Array<string>;
filtered_file_entries: Array<ListEntry>;

file_entries_reserved := 0;
file_entries_block_size := 50; #const
file_entry_index := 0;
length_to_allocate := 0;
file_entries_string_pointer: u8*;
file_entries_string_index := 0;

string copy_path(string file_path) {
    path: string = {
        length = file_path.length;
        data = file_entries_string_pointer + file_entries_string_index;
    }

    file_entries_string_index += file_path.length;
    memory_copy(path.data, file_path.data, file_path.length);

    return path;
}

// Search functions
Array<ListEntry> get_search_results() {
    return search_results;
}

int get_total_search_results() {
    return search_results.length;
}

get_file_at_line(int thread, JobData data) {
    entry := cast(SelectedEntry*, data.pointer);
    search_result := entry.key;

    workspace := get_workspace();
    line, column, file := parse_search_key(search_result);
    start_line_adjust := global_font_config.max_lines_without_bottom_window / 2;

    defer trigger_window_update();

    each buffer in workspace.buffers {
        if buffer.relative_path == file {
            if search_result == entry.key {
                entry.buffer = &buffer;
                entry.can_free_buffer = false;
                entry.start_line = clamp(line - start_line_adjust, 0, buffer.line_count);
                entry.selected_line = line;
            }
            return;
        }
    }

    file_buffer := read_file_into_buffer(file);

    if search_result == entry.key {
        entry.buffer = file_buffer;
        entry.start_line = clamp(line - start_line_adjust, 0, file_buffer.line_count);
        entry.selected_line = line;
    }
    else {
        free_buffer(file_buffer);
    }
}

change_search_filter(string filter) {
    if running_search {
        cancel_search = true;
        while running_search {}
    }

    search_results.length = 0;
    each results_string in search_results_strings {
        results_string.cursor = 0;
    }

    if !string_is_empty(filter) {
        data: JobData;
        data.string = filter;
        queue_work(&low_priority_queue, search_text_in_files, data);
    }
}

open_file_at_line(string search_result) {
    line, column, file := parse_search_key(search_result);
    buffer_window := open_file_buffer(file, true);
    buffer_window.line = line;
    buffer_window.cursor = column;
    adjust_start_line(buffer_window);
}

// Search results entries are stored in the following format
// - key = {line}:{column}-{file}
// - display = {file}:{line}:{column}:{line text}
search_results: Array<ListEntry>;

search_results_allocated := 0;
search_results_block_size := 100; #const

running_search := false;
cancel_search := false;

search_text_in_files(int thread, JobData data) {
    running_search = true;
    defer {
        running_search = false;
        cancel_search = false;
    }

    filter_buffer: Array<u8>[data.string.length];
    filter: string = { data = filter_buffer.data; }

    escape := false;
    each i in data.string.length {
        char := data.string[i];
        if escape {
            escaped_char: u8;
            switch char {
                case 'n';  escaped_char = '\n';
                case 't';  escaped_char = '\t';
                case '\\'; escaped_char = '\\';
                case '/';  escaped_char = '/';
                default; {
                    filter[filter.length++] = '\\';
                    escaped_char = char;
                }
            }
            filter[filter.length++] = escaped_char;
            escape = false;
        }
        else if char == '\\' {
            escape = true;
        }
        else {
            filter[filter.length++] = char;
        }
    }
    if escape {
        filter[filter.length++] = '\\';
    }

    workspace := get_workspace();
    search_directory(workspace.directory, empty_string, filter);
}

search_directory(string path, string display_path, string filter) {
    defer trigger_window_update();

    #if os == OS.Linux {
        open_flags := OpenFlags.O_RDONLY | OpenFlags.O_NONBLOCK | OpenFlags.O_DIRECTORY | OpenFlags.O_LARGEFILE | OpenFlags.O_CLOEXEC;
        directory := open(path.data, open_flags, OpenMode.S_RWALL);

        if directory < 0 {
            return;
        }

        buffer: CArray<u8>[5600];
        while !cancel_search {
            bytes := getdents64(directory, cast(Dirent*, &buffer), buffer.length);

            if bytes == 0 break;

            position := 0;
            while position < bytes {
                dirent := cast(Dirent*, &buffer + position);
                name := convert_c_string(&dirent.d_name);

                if !array_contains(directories_to_ignore, name) {
                    if dirent.d_type == DirentType.DT_REG && !ignore_file(name) {
                        file_path := name;
                        if !string_is_empty(display_path) {
                            file_path = temp_string(display_path, "/", name);
                        }

                        search_file(file_path, filter);
                    }
                    else if dirent.d_type == DirentType.DT_DIR {
                        sub_path := temp_string(path, "/", name);
                        sub_display_path := name;
                        if !string_is_empty(display_path) {
                            sub_display_path = temp_string(display_path, "/", name);
                        }
                        search_directory(sub_path, sub_display_path, filter);
                    }
                }

                position += dirent.d_reclen;
            }
        }

        close(directory);
    }
    #if os == OS.Windows {
        wildcard := "/*"; #const
        path_with_wildcard: Array<u8>[path.length + wildcard.length + 1];
        memory_copy(path_with_wildcard.data, path.data, path.length);
        memory_copy(path_with_wildcard.data + path.length, wildcard.data, wildcard.length);
        path_with_wildcard[path.length + wildcard.length] = 0;

        find_data: WIN32_FIND_DATAA;
        find_handle := FindFirstFileA(path_with_wildcard.data, &find_data);

        if cast(s64, find_handle) == -1 {
            return;
        }

        while !cancel_search {
            name := convert_c_string(&find_data.cFileName);

            if !array_contains(directories_to_ignore, name) {
                if find_data.dwFileAttributes & FileAttribute.FILE_ATTRIBUTE_DIRECTORY {
                    sub_path := temp_string(path, "/", name);
                    sub_display_path := name;
                    if !string_is_empty(display_path) {
                        sub_display_path = temp_string(display_path, "/", name);
                    }
                    search_directory(sub_path, sub_display_path, filter);
                }
                else if !ignore_file(name) {
                    file_path := name;
                    if !string_is_empty(display_path) {
                        file_path = temp_string(display_path, "/", name);
                    }

                    search_file(file_path, filter);
                }
            }

            if !FindNextFileA(find_handle, &find_data) break;
        }

        FindClose(find_handle);
    }
}

file_types_to_ignore: Array<string> = [".exe", ".pdb", ".dll", ".so"]

bool ignore_file(string file) {
    each file_type in file_types_to_ignore {
        if ends_with(file, file_type) {
            return true;
        }
    }

    return false;
}

search_file(string path, string filter) {
    found, file := read_file(path, allocate);
    if !found return;

    defer free_allocation(file.data);

    line_number, column := 1;
    skip_until_next_line := false;
    each i in file.length {
        char := file[i];
        if skip_until_next_line {
            if char == '\n' {
                line_number++;
                column = 1;
                skip_until_next_line = false;
            }
        }
        else {
            if char == filter[0] {
                if file.length - i >= filter.length {
                    match := true;
                    filter_index := 1;
                    file_index := i + 1;
                    while filter_index < filter.length && file_index < file.length {
                        test_char := file[file_index];
                        filter_char := filter[filter_index];
                        if test_char == '\r' {
                            file_index++;
                        }
                        else if test_char != filter_char {
                            match = false;
                            break;
                        }
                        else {
                            filter_index++;
                            file_index++;
                        }
                    }

                    if match && filter_index == filter.length {
                        line: string = { data = file.data + i - column + 1; }
                        while line.length < global_font_config.max_chars_per_line {
                            if line[line.length] == '\n' {
                                break;
                            }
                            line.length++;
                        }
                        add_search_result(path, line_number, column, line);
                        skip_until_next_line = true;
                    }
                }
            }

            if char == '\n' {
                line_number++;
                column = 1;
            }
            else {
                column++;
            }
        }
    }
}

add_search_result(string file, int line, int column, string line_text) {
    if search_results.length == search_results_allocated {
        old_data := search_results.data;
        old_size := search_results_allocated * size_of(ListEntry);

        search_results_allocated += search_results_block_size;
        new_data := allocate(search_results_allocated * size_of(ListEntry));
        memory_copy(new_data, search_results.data, old_size);

        search_results.data = new_data;
        free_allocation(old_data);
    }

    search_results[search_results.length++] = {
        key = format_string("%:%-%", allocate_for_search_result, line, column, file);
        display = format_string("%:%:%:%", allocate_for_search_result, file, line, column, line_text);
    }
}

struct SearchResultsStrings {
    cursor: u64;
    pointer: u8*;
}
search_results_strings_size := 50000; #const
search_results_strings: Array<SearchResultsStrings>;

void* allocate_for_search_result(u64 length) {
    each results_string in search_results_strings {
        if results_string.cursor + length < search_results_strings_size {
            pointer := results_string.pointer + results_string.cursor;
            results_string.cursor += length;
            return pointer;
        }
    }

    assert(length < search_results_strings_size);
    pointer := allocate(search_results_strings_size);
    results_strings: SearchResultsStrings = {
        cursor = length;
        pointer = pointer;
    }

    array_insert(&search_results_strings, results_strings, allocate, reallocate);
    return pointer;
}


int, int, string parse_search_key(string key) {
    line, column: int;
    i := 0;
    while key[i] != ':' {
        line *= 10;
        line += key[i] - '0';
        i++;
    }

    line--;
    i++;

    while key[i] != '-' {
        column *= 10;
        column += key[i] - '0';
        i++;
    }

    column--;
    i++;

    file: string = {
        length = key.length - i;
        data = key.data + i;
    }

    return line, column, file;
}
