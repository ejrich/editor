open_files_list() {
    file_entries.length = 0;
    change_file_filter(empty_string);

    queue_work(&low_priority_queue, load_files);

    start_list_mode("Find Files", get_files, get_total_files, get_file, change_file_filter, draw_file_entry, open_file_to_buffer, cleanup = cleanup_files, loading = &loading_files);
}

open_search_list(string initial_search = empty_string) {
    change_search_filter(empty_string);
    start_list_mode("Search", get_search_results, get_total_search_results, get_file_at_line, change_search_filter, draw_search_result, open_file_at_line, cleanup = cancel_current_search, initial_value = initial_search, loading = &running_search);
}

struct Directory {
    parent: Directory*;
    name: string;
    sub_directories: Array<Directory*>;
}

free_directory(Directory* directory) {
    each sub_directory in directory.sub_directories {
        free_directory(sub_directory);
    }

    free_allocation(directory.sub_directories.data);
    free_allocation(directory.name.data);
    free_allocation(directory);
}

#private

Directory* get_or_create_directory(string name, Directory* parent_directory, Array<Directory*>* sub_directories) {
    each sub_directory in *sub_directories {
        if sub_directory.name == name {
            return sub_directory;
        }
    }

    allocate_strings(&name);
    directory := new<Directory>();
    directory.parent = parent_directory;
    directory.name = name;

    array_insert(sub_directories, directory, allocate, reallocate);

    return directory;
}

string get_full_path(string file, Directory* directory) #inline {
    if directory == null {
        return file;
    }

    path_length := file.length;
    dir := directory;
    while dir {
        path_length += dir.name.length + 1;
        dir = dir.parent;
    }

    path_data: Array<u8>[path_length];
    cursor := path_length - file.length;
    memory_copy(path_data.data + cursor, file.data, file.length);

    dir = directory;
    while dir {
        path_data[--cursor] = '/';
        cursor -= dir.name.length;
        memory_copy(path_data.data + cursor, dir.name.data, dir.name.length);
        dir = dir.parent;
    }

    path: string = { length = path_length; data = path_data.data; }
    return path;
}

// File finder functions
load_files(int thread, JobData data) {
    loading_files = true;
    defer {
        loading_files = false;
        cancel_loading_files = false;
        trigger_window_update();
    }

    file_entries.length = 0;

    workspace := get_workspace();
    load_directory(workspace.directory, empty_string, null, &workspace.sub_directories);

    if cancel_loading_files return;

    if filtered_file_entries_allocated < file_entries_allocated {
        filtered_file_entries_allocated = file_entries_allocated;
        reallocate_array(&filtered_file_entries, filtered_file_entries_allocated);
    }

    if cancel_loading_files return;

    change_file_filter(empty_string);
}

load_directory(string path, string display_path, Directory* parent_directory, Array<Directory*>* sub_directories) {
    load_sub_directories := load_directory_files(path, display_path, false, parent_directory, sub_directories);
    if load_sub_directories {
        load_directory_files(path, display_path, true, parent_directory, sub_directories);
    }
}

bool load_directory_files(string path, string display_path, bool load_sub_directories, Directory* parent_directory, Array<Directory*>* sub_directories) {
    found_sub_directory := false;

    #if os == OS.Linux {
        open_flags := OpenFlags.O_RDONLY | OpenFlags.O_NONBLOCK | OpenFlags.O_DIRECTORY | OpenFlags.O_LARGEFILE | OpenFlags.O_CLOEXEC;
        directory := open(path.data, open_flags, FileMode.S_RWALL);

        if directory < 0 {
            return false;
        }

        buffer: CArray<u8>[5600];
        while !cancel_loading_files {
            bytes := getdents64(directory, cast(Dirent*, &buffer), buffer.length);

            if bytes <= 0 break;

            position := 0;
            while position < bytes && !cancel_loading_files {
                dirent := cast(Dirent*, &buffer + position);
                name := convert_c_string(&dirent.d_name);

                if !array_contains(directories_to_ignore, name) {
                    if dirent.d_type == DirentType.DT_REG {
                        if !load_sub_directories {
                            file_path := name;
                            if !string_is_empty(display_path) {
                                file_path = temp_string(display_path, "/", name);
                            }

                            add_file_entry(name, parent_directory);
                        }
                    }
                    else if dirent.d_type == DirentType.DT_DIR {
                        if load_sub_directories {
                            sub_path := temp_string(path, "/", name);
                            sub_display_path := name;
                            if !string_is_empty(display_path) {
                                sub_display_path = temp_string(display_path, "/", name);
                            }
                            sub_directory := get_or_create_directory(name, parent_directory, sub_directories);
                            load_directory(sub_path, sub_display_path, sub_directory, &sub_directory.sub_directories);
                        }
                        else {
                            found_sub_directory = true;
                        }
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
            return false;
        }

        while !cancel_loading_files {
            name := convert_c_string(&find_data.cFileName);

            if !array_contains(directories_to_ignore, name) {
                if find_data.dwFileAttributes & FileAttribute.FILE_ATTRIBUTE_DIRECTORY {
                    if load_sub_directories {
                        sub_path := temp_string(path, "/", name);
                        sub_display_path := name;
                        if !string_is_empty(display_path) {
                            sub_display_path = temp_string(display_path, "/", name);
                        }
                        sub_directory := get_or_create_directory(name, parent_directory, sub_directories);
                        load_directory(sub_path, sub_display_path, sub_directory, &sub_directory.sub_directories);
                    }
                    else {
                        found_sub_directory = true;
                    }
                }
                else if !load_sub_directories {
                    file_path := name;
                    if !string_is_empty(display_path) {
                        file_path = temp_string(display_path, "/", name);
                    }

                    add_file_entry(name, parent_directory);
                }
            }

            if !FindNextFileA(find_handle, &find_data) break;
        }

        FindClose(find_handle);
    }

    return found_sub_directory;
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
    key := entry.key;
    file_entry := file_entries[key];

    defer trigger_window_update();

    file := get_full_path(file_entry.name, file_entry.directory);

    workspace := get_workspace();
    each buffer in workspace.buffers {
        if buffer.relative_path == file {
            entry.can_free_buffer = false;
            entry.buffer = &buffer;
            return;
        }
    }

    file_buffer := read_file_into_buffer(file);

    if file_buffer {
        if key == entry.key {
            entry.buffer = file_buffer;
        }
        else {
            free_buffer(file_buffer);
        }
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

    if is_file_binary(file) {
        add_text_to_end_of_buffer(buffer, "======== Binary File ========", false);
    }
    else if move_to_start_of_file(file) {
        length: int;
        buf: CArray<u8>[1000];
        while true {
            success, length = read_file_into_buffer(file, &buf, buf.length);
            if !success || length <= 0 break;

            text: string = { length = length; data = &buf; }
            add_text_to_end_of_buffer(buffer, text, false);
        }
    }

    close_file(file);

    return buffer;
}

change_file_filter(string filter) {
    if string_is_empty(filter) {
        filtered_file_entries.length = file_entries.length;
        each file, i in file_entries {
            filtered_file_entries[i] = file;
        }
    }
    else {
        filtered_file_entries.length = 0;
        each file in file_entries {
            if file_path_contains(file.name, file.directory, filter) {
                filtered_file_entries[filtered_file_entries.length++] = file;
            }
        }
    }
}

bool file_path_contains(string file, Directory* directory, string filter) {
    file_path := get_full_path(file, directory);
    return string_contains(file_path, filter, false);
}

draw_file_entry(ListEntry entry, float x, float y, u32 max_chars_per_line) {
    if entry.directory {
        draw_directory(entry.directory, &x, &y, &max_chars_per_line);
    }

    if entry.name.length > max_chars_per_line {
        entry.name.length = max_chars_per_line;
    }

    render_text(entry.name, settings.font_size, x, y, appearance.font_color, vec4());
}

draw_directory(Directory* directory, float* x, float* y, u32* max_chars_per_line) {
    if directory.parent {
        draw_directory(directory.parent, x, y, max_chars_per_line);
    }

    path := temp_string(directory.name, "/");
    if path.length > *max_chars_per_line {
        path.length = *max_chars_per_line;
    }

    *x = render_text(path, settings.font_size, *x, *y, appearance.font_color, vec4());
    *max_chars_per_line = *max_chars_per_line - path.length;
}

cleanup_files() {
    if loading_files {
        cancel_loading_files = true;
    }

    while loading_files {
        sleep(1);
    }

    file_entries.length = 0;
    each results_string in search_results_strings {
        results_string.cursor = 0;
    }
}

open_file_to_buffer(int key) {
    file_entry := file_entries[key];
    file := get_full_path(file_entry.name, file_entry.directory);
    open_file_buffer(file, true);
}

loading_files := false;
cancel_loading_files := false;

file_entries: Array<ListEntry>;
filtered_file_entries: Array<ListEntry>;

file_entries_allocated := 0;
filtered_file_entries_allocated := 0;
file_entries_block_size := 50; #const

// Search functions
Array<ListEntry> get_search_results() {
    return search_results;
}

int get_total_search_results() {
    return search_results.length;
}

get_file_at_line(int thread, JobData data) {
    entry := cast(SelectedEntry*, data.pointer);
    key := entry.key;
    search_result := search_results[key];

    defer trigger_window_update();

    file := get_full_path(search_result.name, search_result.directory);
    line := search_result.value1 - 1;
    start_line_adjust := global_font_config.max_lines_without_bottom_window / 2;

    workspace := get_workspace();
    each buffer in workspace.buffers {
        if buffer.relative_path == file {
            if key == entry.key {
                entry.buffer = &buffer;
                entry.can_free_buffer = false;
                entry.start_line = clamp(line - start_line_adjust, 0, buffer.line_count);
                entry.selected_line = line;
            }
            return;
        }
    }

    file_buffer := read_file_into_buffer(file);

    if file_buffer {
        if key == entry.key {
            entry.buffer = file_buffer;
            entry.start_line = clamp(line - start_line_adjust, 0, file_buffer.line_count);
            entry.selected_line = line;
        }
        else {
            free_buffer(file_buffer);
        }
    }
}

change_search_filter(string filter) {
    cancel_current_search();

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

draw_search_result(ListEntry entry, float x, float y, u32 max_chars_per_line) {
    if entry.directory {
        draw_directory(entry.directory, &x, &y, &max_chars_per_line);
    }

    if entry.name.length > max_chars_per_line {
        entry.name.length = max_chars_per_line;
    }

    x = render_text(entry.name, settings.font_size, x, y, appearance.font_color, vec4());
    max_chars_per_line -= entry.name.length;

    if max_chars_per_line {
        prev_x := x;
        x = render_text(settings.font_size, x, y, appearance.font_color, vec4(), ":%:%:", entry.value1, entry.value2);

        max_chars_per_line -= cast(u32, (x - prev_x) / global_font_config.quad_advance);

        if entry.value3.length > max_chars_per_line {
            entry.value3.length = max_chars_per_line;
        }

        render_text(entry.value3, settings.font_size, x, y, appearance.font_color, vec4());
    }
}

open_file_at_line(int key) {
    search_result := search_results[key];
    file := get_full_path(search_result.name, search_result.directory);
    buffer_window := open_file_buffer(file, true);
    buffer_window.line = search_result.value1;
    buffer_window.cursor = search_result.value2;
    adjust_start_line(buffer_window);
}

cancel_current_search() {
    if running_search {
        cancel_search = true;
        while running_search {
            sleep(1);
        }
    }
}

search_results: Array<ListEntry>;

search_results_allocated := 0;
search_results_block_size := 100; #const
max_search_results := 5000; #const

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
    search_directory(workspace.directory, empty_string, filter, null, &workspace.sub_directories);
}

search_directory(string path, string display_path, string filter, Directory* parent_directory, Array<Directory*>* sub_directories) {
    search_sub_directories := search_directory_files(path, display_path, filter, false, parent_directory, sub_directories);
    if search_sub_directories {
        search_directory_files(path, display_path, filter, true, parent_directory, sub_directories);
    }
}

bool search_directory_files(string path, string display_path, string filter, bool search_sub_directories, Directory* parent_directory, Array<Directory*>* sub_directories) {
    defer trigger_window_update();

    found_sub_directory := false;

    #if os == OS.Linux {
        open_flags := OpenFlags.O_RDONLY | OpenFlags.O_NONBLOCK | OpenFlags.O_DIRECTORY | OpenFlags.O_LARGEFILE | OpenFlags.O_CLOEXEC;
        directory := open(path.data, open_flags, FileMode.S_RWALL);

        if directory < 0 {
            return false;
        }

        buffer: CArray<u8>[5600];
        while !cancel_search && search_results.length < max_search_results {
            bytes := getdents64(directory, cast(Dirent*, &buffer), buffer.length);

            if bytes <= 0 break;

            position := 0;
            while position < bytes {
                dirent := cast(Dirent*, &buffer + position);
                name := convert_c_string(&dirent.d_name);

                if !array_contains(directories_to_ignore, name) {
                    if dirent.d_type == DirentType.DT_REG && !ignore_file(name) && !search_sub_directories {
                        file_path := name;
                        if !string_is_empty(display_path) {
                            file_path = temp_string(display_path, "/", name);
                        }

                        search_file(file_path, name, parent_directory, filter);
                    }
                    else if dirent.d_type == DirentType.DT_DIR {
                        if search_sub_directories {
                            sub_path := temp_string(path, "/", name);
                            sub_display_path := name;
                            if !string_is_empty(display_path) {
                                sub_display_path = temp_string(display_path, "/", name);
                            }
                            sub_directory := get_or_create_directory(name, parent_directory, sub_directories);
                            search_directory(sub_path, sub_display_path, filter, sub_directory, &sub_directory.sub_directories);
                        }
                        else {
                            found_sub_directory = true;
                        }
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
            return false;
        }

        while !cancel_search && search_results.length < max_search_results {
            name := convert_c_string(&find_data.cFileName);

            if !array_contains(directories_to_ignore, name) {
                if find_data.dwFileAttributes & FileAttribute.FILE_ATTRIBUTE_DIRECTORY {
                    if search_sub_directories {
                        sub_path := temp_string(path, "/", name);
                        sub_display_path := name;
                        if !string_is_empty(display_path) {
                            sub_display_path = temp_string(display_path, "/", name);
                        }
                        sub_directory := get_or_create_directory(name, parent_directory, sub_directories);
                        search_directory(sub_path, sub_display_path, filter, sub_directory, &sub_directory.sub_directories);
                    }
                    else {
                        found_sub_directory = true;
                    }
                }
                else if !ignore_file(name) && !search_sub_directories {
                    file_path := name;
                    if !string_is_empty(display_path) {
                        file_path = temp_string(display_path, "/", name);
                    }

                    search_file(file_path, name, parent_directory, filter);
                }
            }

            if !FindNextFileA(find_handle, &find_data) break;
        }

        FindClose(find_handle);
    }

    return found_sub_directory;
}

file_types_to_ignore: Array<string> = [".exe", ".pdb", ".dll", ".so", ".a"]

bool ignore_file(string file) {
    each file_type in file_types_to_ignore {
        if ends_with(file, file_type) {
            return true;
        }
    }

    return false;
}

bool is_file_binary(File file) {
    binary_file_buffer_size := 500; #const
    binary_file_buffer: CArray<u8>[binary_file_buffer_size];

    success, read := read_file_into_buffer(file, &binary_file_buffer, binary_file_buffer_size);
    if !success return true;

    each i in read {
        if binary_file_buffer[i] == 0 {
            return true;
        }
    }

    return false;
}

search_file(string path, string file_name, Directory* parent_directory, string filter) {
    if search_results.length == max_search_results return;

    success, file_handle := open_file(path);
    if !success || is_file_binary(file_handle) {
        close_file(file_handle);
        return;
    }

    found, file := read_file(file_handle, allocate);
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
                        if !add_search_result(file_name, parent_directory, line_number, column, line) return;
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

add_file_entry(string name, Directory* parent_directory) {
    if file_entries.length == file_entries_allocated {
        old_data := file_entries.data;
        old_size := file_entries_allocated * size_of(ListEntry);

        file_entries_allocated += file_entries_block_size;
        new_data := allocate(file_entries_allocated * size_of(ListEntry));
        memory_copy(new_data, file_entries.data, old_size);

        file_entries.data = new_data;
        free_allocation(old_data);
    }

    allocate_string_for_search_result(&name);

    file_entries[file_entries.length] = {
        key = file_entries.length;
        name = name;
        directory = parent_directory;
    }

    file_entries.length++;
}

bool add_search_result(string file, Directory* parent_directory, int line, int column, string line_text) {
    if search_results.length == max_search_results return false;

    if search_results.length == search_results_allocated {
        old_data := search_results.data;
        old_size := search_results_allocated * size_of(ListEntry);

        search_results_allocated += search_results_block_size;
        new_data := allocate(search_results_allocated * size_of(ListEntry));
        memory_copy(new_data, search_results.data, old_size);

        search_results.data = new_data;
        free_allocation(old_data);
    }

    allocate_string_for_search_result(&file);
    allocate_string_for_search_result(&line_text);

    search_results[search_results.length] = {
        key = search_results.length;
        name = file;
        directory = parent_directory;
        value1 = line;
        value2 = column;
        value3 = line_text;
    }

    search_results.length++;

    return true;
}

struct SearchResultsStrings {
    cursor: u64;
    pointer: u8*;
}
search_results_strings_size := 50000; #const
search_results_strings: Array<SearchResultsStrings>;

void allocate_string_for_search_result(string* value) {
    old_data := value.data;
    value.data = allocate_for_search_result(value.length);
    memory_copy(value.data, old_data, value.length);
}

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
