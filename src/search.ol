open_files_list() {
    load_files();
    start_list_mode("Find Files", get_files, get_file, change_file_filter, open_file_to_buffer);
}

open_search_list() {
    // TODO Implement
}

#private

// File finder functions
load_files() {
    each entry in file_entries {
        free_allocation(entry.data);
    }
    file_entries.length = 0;
    file_entry_index = 0;

    load_directory(current_directory, empty_string, true);

    if file_entry_index > file_entries_reserved {
        free_allocation(file_entries.data);
        free_allocation(filtered_file_entries.data);

        while file_entries_reserved < file_entry_index {
            file_entries_reserved += file_entries_block_size;
        }

        array_resize(&file_entries, file_entries_reserved, allocate);
        array_resize(&filtered_file_entries, file_entries_reserved, allocate);
    }

    file_entries.length = file_entry_index;
    file_entry_index = 0;
    load_directory(current_directory, empty_string, false);

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
                        if counting {
                            file_entry_index++;
                        }
                        else {
                            file_path := name;
                            if !string_is_empty(display_path) {
                                file_path = temp_string(display_path, "/", name);
                            }
                            allocate_strings(&file_path);
                            file_entries[file_entry_index++] = file_path;
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
                    if counting {
                        file_entry_index++;
                    }
                    else {
                        file_path := name;
                        if !string_is_empty(display_path) {
                            file_path = temp_string(display_path, "/", name);
                        }
                        allocate_strings(&file_path);
                        file_entries[file_entry_index++] = file_path;
                    }
                }
            }

            if !FindNextFileA(find_handle, &find_data) break;
        }

        FindClose(find_handle);
    }
}

directories_to_ignore: Array<string> = [".", "..", "bin", "obj"]

Array<ListEntry> get_files() {
    return filtered_file_entries;
}

get_file(int thread, JobData data) {
    entry := cast(SelectedEntry*, data.pointer);
    file := entry.key;

    each buffer in buffers {
        if buffer.relative_path == file {
            entry.can_free_buffer = false;
            entry.buffer = &buffer;
            return;
        }
    }

    command := temp_string("cat ", file);
    file_buffer := run_command_and_save_to_buffer(command);

    if file == entry.key {
        entry.buffer = file_buffer;
    }
    else {
        free_buffer(file_buffer);
    }
}

change_file_filter(string filter) {
    if buffers.length > file_entries_reserved {
        free_allocation(file_entries.data);

        while file_entries_reserved < buffers.length {
            file_entries_reserved += file_entries_block_size;
        }

        array_resize(&file_entries, file_entries_reserved, allocate);
    }

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

open_file_to_buffer(string file) {
    open_file_buffer(file, true);
}

file_entries: Array<string>;
filtered_file_entries: Array<ListEntry>;

file_entries_reserved := 0;
file_entries_block_size := 10; #const
file_entry_index := 0;

// Search functions
// TODO Implement functions
