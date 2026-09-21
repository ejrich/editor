init_search() {
    create_semaphore(&search_result_mutex, initial_value = 1);
    create_semaphore(&allocate_search_result_mutex, initial_value = 1);
}

open_files_list() {
    file_entries.length = 0;
    change_file_filter(empty_string);

    queue_work(&low_priority_queue, load_files);

    start_list_mode("Find Files", get_files, get_total_files, get_file, change_file_filter, draw_file_entry, open_file_to_buffer, cleanup = cleanup_files, loading = &loading_files);
}

open_search_list(string initial_search = empty_string) {
    change_search_filter(empty_string);
    start_list_mode("Search", get_search_results, get_total_search_results, get_file_at_line, change_search_filter, draw_search_result, open_file_at_line, cleanup = cleanup_search, initial_value = initial_search, loading = &running_search);
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

    if directory.sub_directories.length {
        free_allocation(directory.sub_directories.data);
        directory.sub_directories.length = 0;
    }

    directory.parent = null;

    free_allocation(directory.name.data);
    free_allocation(directory);
}

Array<string> find_files(Workspace* workspace, string filter, u32 max) {
    files: Array<string>;

    find_files(workspace, &files, filter, workspace.directory, empty_string, max);

    return files;
}

Array<SearchResult> search_for_text(Workspace* workspace, string filter, string query, u32 max) {
    results: Array<SearchResult>;

    search_for_text(workspace, &results, filter, query, workspace.directory, empty_string, max);

    return results;
}

#if os == OS.Linux {
    struct DirectoryIterator {
        fd: int;
        buffer: CArray<u8>[5600];
        bytes: int;
        position: int;
    }
}
#if os == OS.Windows {
    struct DirectoryIterator {
        find_data: WIN32_FIND_DATAA;
        find_handle: Handle*;
        first := true;
    }
}

bool start_directory_search(DirectoryIterator* iterator, string path, bool use_path_wildcard = true) {
    success: bool;

    #if os == OS.Linux {
        open_flags := OpenFlags.O_RDONLY | OpenFlags.O_NONBLOCK | OpenFlags.O_DIRECTORY | OpenFlags.O_LARGEFILE | OpenFlags.O_CLOEXEC;
        iterator.fd = open(path.data, open_flags, FileMode.S_RWALL);

        success = iterator.fd >= 0;
    }
    #if os == OS.Windows {
        if use_path_wildcard {
            wildcard := "/*"; #const
            path_with_wildcard: Array<u8>[path.length + wildcard.length + 1];
            memory_copy(path_with_wildcard.data, path.data, path.length);
            memory_copy(path_with_wildcard.data + path.length, wildcard.data, wildcard.length);
            path_with_wildcard[path.length + wildcard.length] = 0;

            iterator.find_handle = FindFirstFileA(path_with_wildcard.data, &iterator.find_data);
        }
        else {
            iterator.find_handle = FindFirstFileA(path.data, &iterator.find_data);
        }

        success = cast(s64, iterator.find_handle) != -1;
    }

    return success;
}

bool get_next_directory_entry(DirectoryIterator* iterator, string* name, bool* is_directory) {
    success: bool;

    #if os == OS.Linux {
        while !success {
            if iterator.position >= iterator.bytes {
                iterator.bytes = getdents64(iterator.fd, cast(Dirent*, &iterator.buffer), iterator.buffer.length);
                iterator.position = 0;
            }

            if iterator.bytes <= 0 break;

            while !success && iterator.position < iterator.bytes {
                dirent := cast(Dirent*, &iterator.buffer + iterator.position);
                *name = convert_c_string(&dirent.d_name);

                if dirent.d_type == DirentType.DT_REG {
                    *is_directory = false;
                    success = true;
                }
                if dirent.d_type == DirentType.DT_DIR {
                    *is_directory = true;
                    success = true;
                }

                iterator.position += dirent.d_reclen;
            }
        }
    }
    #if os == OS.Windows {
        if iterator.first || FindNextFileA(iterator.find_handle, &iterator.find_data) {
            success = true;
            iterator.first = false;
            *name = convert_c_string(&iterator.find_data.cFileName);
            *is_directory = (iterator.find_data.dwFileAttributes & FileAttribute.FILE_ATTRIBUTE_DIRECTORY) == FileAttribute.FILE_ATTRIBUTE_DIRECTORY;
        }
    }

    return success;
}

finish_directory_search(DirectoryIterator* iterator) {
    #if os == OS.Linux {
        close(iterator.fd);
    }
    #if os == OS.Windows {
        FindClose(iterator.find_handle);
    }
}


#private


find_files(Workspace* workspace, Array<string>* files, string filter, string path, string display_path, u32 max) {
    iterator: DirectoryIterator;

    if !start_directory_search(&iterator, path) {
        return;
    }

    name: string;
    is_directory: bool;

    while files.length < max && get_next_directory_entry(&iterator, &name, &is_directory) {
        if is_directory {
            if ignore_directory(name, workspace) continue;

            sub_path := temp_string(path, "/", name);
            sub_display_path := name;
            if !string_is_empty(display_path) {
                sub_display_path = temp_string(display_path, "/", name);
            }

            find_files(workspace, files, filter, sub_path, sub_display_path, max);
        }
        else if !ignore_file(name, workspace) {
            file_path := name;
            if !string_is_empty(display_path) {
                file_path = temp_string(display_path, "/", name);
            }

            if string_contains(file_path, filter, false) {
                allocate_strings(&file_path);
                array_insert(files, file_path, allocate, reallocate);
            }
        }
    }

    finish_directory_search(&iterator);
}

search_for_text(Workspace* workspace, Array<SearchResult>* results, string filter, string query, string path, string display_path, u32 max) {
    iterator: DirectoryIterator;

    if !start_directory_search(&iterator, path) {
        return;
    }

    name: string;
    is_directory: bool;

    while results.length < max && get_next_directory_entry(&iterator, &name, &is_directory) {
        if is_directory {
            if ignore_directory(name, workspace) continue;

            sub_path := temp_string(path, "/", name);
            sub_display_path := name;
            if !string_is_empty(display_path) {
                sub_display_path = temp_string(display_path, "/", name);
            }

            search_for_text(workspace, results, filter, query, sub_path, sub_display_path, max);
        }
        else if !ignore_file(name, workspace) {
            file_path := name;
            if !string_is_empty(display_path) {
                file_path = temp_string(display_path, "/", name);
            }

            if string_is_empty(filter) || string_contains(file_path, filter, false) {
                absolute_file_path := temp_string(path, "/", name);
                search_file_for_text(workspace, results, absolute_file_path, file_path, query, max);
            }
        }
    }

    finish_directory_search(&iterator);
}

search_file_for_text(Workspace* workspace, Array<SearchResult>* results, string path, string relative_path, string query, u32 max) {
    if results.length >= max return;

    // Try to search in an open buffer
    existing_buffer: Buffer*;
    each buffer in workspace.buffers {
        if buffer.relative_path == relative_path {
            existing_buffer = &buffer;
            break;
        }
    }

    if existing_buffer {
        // TODO Search the existing buffer
    }


    // Otherwise read the file and search
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
    found_match := false;
    each i in file.length {
        if results.length >= max break;

        char := file[i];
        if skip_until_next_line {
            if char == '\n' {
                line_number++;
                column = 1;
                skip_until_next_line = false;
            }
        }
        else {
            if char == query[0] {
                if file.length - i >= query.length {
                    match := true;
                    query_index := 1;
                    file_index := i + 1;
                    while query_index < query.length && file_index < file.length {
                        test_char := file[file_index];
                        filter_char := query[query_index];
                        if test_char == '\r' {
                            file_index++;
                        }
                        else if test_char != filter_char {
                            match = false;
                            break;
                        }
                        else {
                            query_index++;
                            file_index++;
                        }
                    }

                    if match && query_index == query.length {
                        if !found_match {
                            found_match = true;
                            allocate_strings(&relative_path);
                        }

                        result: SearchResult = {
                            file = relative_path;
                            line = line_number;
                            column = column;
                        }

                        array_insert(results, result, allocate, reallocate);
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
    directory.sub_directories.length = 0;
    directory.sub_directories.data = null;

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
    load_directory(workspace, workspace.directory, empty_string, null, &workspace.sub_directories);

    if cancel_loading_files return;

    if filtered_file_entries_allocated < file_entries_allocated {
        filtered_file_entries_allocated = file_entries_allocated;

        free_allocation(filtered_file_entries.data);
        filtered_file_entries.data = allocate(size_of(ListEntry) * filtered_file_entries_allocated);
    }

    if cancel_loading_files return;

    loading_files = false;

    change_file_filter(empty_string);
}

load_directory(Workspace* workspace, string path, string display_path, Directory* parent_directory, Array<Directory*>* sub_directories) {
    load_sub_directories := load_directory_files(workspace, path, display_path, false, parent_directory, sub_directories);
    if load_sub_directories {
        load_directory_files(workspace, path, display_path, true, parent_directory, sub_directories);
    }

    trigger_window_update();
}

bool load_directory_files(Workspace* workspace, string path, string display_path, bool load_sub_directories, Directory* parent_directory, Array<Directory*>* sub_directories) {
    found_sub_directory := false;
    iterator: DirectoryIterator;

    if !start_directory_search(&iterator, path) {
        return false;
    }

    name: string;
    is_directory: bool;

    while !cancel_loading_files && get_next_directory_entry(&iterator, &name, &is_directory) {
        if is_directory {
            if ignore_directory(name, workspace) continue;

            if load_sub_directories {
                sub_path := temp_string(path, "/", name);
                sub_display_path := name;
                if !string_is_empty(display_path) {
                    sub_display_path = temp_string(display_path, "/", name);
                }
                sub_directory := get_or_create_directory(name, parent_directory, sub_directories);
                load_directory(workspace, sub_path, sub_display_path, sub_directory, &sub_directory.sub_directories);
            }
            else {
                found_sub_directory = true;
            }
        }
        else if !ignore_file(name, workspace) && !load_sub_directories {
            file_path := name;
            if !string_is_empty(display_path) {
                file_path = temp_string(display_path, "/", name);
            }

            add_file_entry(name, parent_directory);
        }
    }

    finish_directory_search(&iterator);
    return found_sub_directory;
}

directories_to_ignore: Array<string> = [".", "..", "bin", "obj", ".git"]

bool ignore_directory(string target, Workspace* workspace) {
    each directory in directories_to_ignore {
        if target == directory {
            return true;
        }
    }

    each directory in workspace.excluded_directories {
        if target == directory {
            return true;
        }
    }

    return false;
}

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
    filtered_file_entries.length = 0;

    if loading_files return;

    if string_is_empty(filter) {
        filtered_file_entries.length = file_entries.length;
        each file, i in file_entries {
            filtered_file_entries[i] = file;
        }
    }
    else {
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
    buffer_window.line = search_result.value1 - 1;
    buffer_window.cursor = search_result.value2 - 1;
    buffer := get_buffer_from_window(buffer_window);
    scroll_to_position(ScrollTo.Middle, buffer_window, buffer);
}

cleanup_search() {
    cancel_current_search();

    if search_results_cache.length {
        search_results_cache.length = 0;
        free_allocation(search_results_cache.data);
    }

    if search_results_cache_filter.length {
        search_results_cache_filter.length = 0;
    }

    free_allocation(search_results_cache_string_pointer);
    search_results_cache_string_pointer = null;
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
search_filter: string;
searches_in_progress: u32;
search_result_mutex: Semaphore;

struct SearchResultCacheFile {
    file: string;
    directory: Directory*;
}

pending_search_results_cache: Array<SearchResultCacheFile>;
search_results_cache: Array<SearchResultCacheFile>;
search_results_cache_filter: string;
search_results_cache_string_pointer: void*;

search_results_allocated := 0;
search_results_block_size := 100; #const
max_search_results := 5000; #const

running_search := false;
cancel_search := false;

search_text_in_files(int thread, JobData data) {
    running_search = true;
    searches_in_progress = 0;

    defer {
        running_search = false;
        cancel_search = false;
    }

    search_filter = { length = 0; data = allocate(data.string.length); }
    defer {
        search_filter.length = 0;
        free_allocation(search_filter.data);
    }

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
                    search_filter[search_filter.length++] = '\\';
                    escaped_char = char;
                }
            }
            search_filter[search_filter.length++] = escaped_char;
            escape = false;
        }
        else if char == '\\' {
            escape = true;
        }
        else {
            search_filter[search_filter.length++] = char;
        }
    }
    if escape {
        search_filter[search_filter.length++] = '\\';
    }

    workspace := get_workspace();
    if search_results_cache_filter.length > 0 && starts_with(search_filter, search_results_cache_filter) {
        each cache_file in search_results_cache {
            if cancel_search break;

            file_path := get_full_path(cache_file.file, cache_file.directory);
            atomic_increment(&searches_in_progress);
            search_file(cache_file.file, cache_file.directory);
        }
    }
    else {
        search_directory(workspace, workspace.directory, null, &workspace.sub_directories);
    }

    while searches_in_progress {
        sleep(1);
    }

    if !cancel_search && search_results.length < max_search_results {
        old_cache := search_results_cache;
        old_string_pointer := search_results_cache_string_pointer;

        strings: Array<string*>[pending_search_results_cache.length + 1];
        filter := search_filter;
        strings[0] = &filter;

        each i in pending_search_results_cache.length {
            strings[i + 1] = &pending_search_results_cache[i].file;
        }

        search_results_cache_string_pointer = allocate_strings(strings);
        search_results_cache_filter = filter;
        search_results_cache = pending_search_results_cache;

        pending_search_results_cache.length = 0;
        pending_search_results_cache.data = null;

        free_allocation(old_string_pointer);
        if old_cache.length {
            free_allocation(old_cache.data);
        }
    }
    else if pending_search_results_cache.length {
        pending_search_results_cache.length = 0;
        free_allocation(pending_search_results_cache.data);
    }
}

search_directory(Workspace* workspace, string path, Directory* parent_directory, Array<Directory*>* sub_directories) {
    search_sub_directories := search_directory_files(workspace, path, false, parent_directory, sub_directories);
    if search_sub_directories {
        search_directory_files(workspace, path, true, parent_directory, sub_directories);
    }
}

bool search_directory_files(Workspace* workspace, string path, bool search_sub_directories, Directory* parent_directory, Array<Directory*>* sub_directories) {
    defer trigger_window_update();

    found_sub_directory := false;
    iterator: DirectoryIterator;

    if !start_directory_search(&iterator, path) {
        return false;
    }

    name: string;
    is_directory: bool;

    while get_next_directory_entry(&iterator, &name, &is_directory) {
        if is_directory {
            if ignore_directory(name, workspace) continue;

            if search_sub_directories {
                sub_path := temp_string(path, "/", name);
                sub_directory := get_or_create_directory(name, parent_directory, sub_directories);
                search_directory(workspace, sub_path, sub_directory, &sub_directory.sub_directories);
            }
            else {
                found_sub_directory = true;
            }
        }
        else if !ignore_file(name, workspace) && !search_sub_directories {
            atomic_increment(&searches_in_progress);
            search_file(name, parent_directory);
        }
    }

    finish_directory_search(&iterator);
    return found_sub_directory;
}

file_types_to_ignore: Array<string> = [".exe", ".pdb", ".dll", ".so", ".a"]

bool ignore_file(string file, Workspace* workspace) {
    each file_type in file_types_to_ignore {
        if ends_with(file, file_type) {
            return true;
        }
    }

    each file_type in workspace.excluded_extensions {
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

search_file(string file_name, Directory* parent_directory) {
    allocate_string_for_search_result(&file_name);

    data: JobData;
    data.multiple.value1 = file_name;
    data.multiple.value2 = parent_directory;

    queue_work(&low_priority_queue, search_file_job, data);
}

search_file_job(int thread, JobData data) {
    defer atomic_decrement(&searches_in_progress);

    if search_results.length == max_search_results return;

    file_name := data.multiple.value1;
    parent_directory: Directory* = data.multiple.value2;

    path := get_full_path(file_name, parent_directory);
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
    found_match := false;
    each i in file.length {
        if cancel_search break;

        char := file[i];
        if skip_until_next_line {
            if char == '\n' {
                line_number++;
                column = 1;
                skip_until_next_line = false;
            }
        }
        else {
            if char == search_filter[0] {
                if file.length - i >= search_filter.length {
                    match := true;
                    filter_index := 1;
                    file_index := i + 1;
                    while filter_index < search_filter.length && file_index < file.length {
                        test_char := file[file_index];
                        filter_char := search_filter[filter_index];
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

                    if match && filter_index == search_filter.length {
                        line: string = { data = file.data + i - column + 1; }
                        while line.length < global_font_config.max_chars_per_line {
                            if line[line.length] == '\n' {
                                break;
                            }
                            line.length++;
                        }

                        if !found_match {
                            found_match = true;
                            semaphore_wait(&search_result_mutex);

                            cache_file: SearchResultCacheFile = {
                                file = file_name;
                                directory = parent_directory;
                            }
                            array_insert(&pending_search_results_cache, cache_file, allocate, reallocate);
                        }

                        if !add_search_result(file_name, parent_directory, line_number, column, line) break;
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

    if found_match {
        semaphore_release(&search_result_mutex);
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
allocate_search_result_mutex: Semaphore;

void allocate_string_for_search_result(string* value) {
    old_data := value.data;
    value.data = allocate_for_search_result(value.length);
    memory_copy(value.data, old_data, value.length);
}

void* allocate_for_search_result(u64 length) {
    semaphore_wait(&allocate_search_result_mutex);
    defer semaphore_release(&allocate_search_result_mutex);

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
