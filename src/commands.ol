#import "parse.ol"

// Commands should be specified with the following attributes: [command, {command text}]
// The commands should return 'string, bool':
// - string: The result from the command
// - bool: Whether the string was allocated or not

[command, e]
string, bool open_file_command(string path) {
    edit_mode = EditMode.Normal;
    open_file_buffer(path, true);
    return empty_string, false;
}

[command, w]
string, bool save_current_buffer() {
    buffer_window := get_current_window();

    success, lines, bytes, file := save_buffer(buffer_window.buffer_index);
    if !success {
        error_result := format_string("Unable to open file \"%\" to write", allocate, file);
        return error_result, true;
    }

    if string_is_empty(file) {
        return empty_string, true;
    }

    command_result := format_string("\"%\" % lines and % bytes written", allocate, file, lines, bytes);
    return command_result, true;
}

[command, wa]
string, bool save_all_buffers() {
    workspace := get_workspace();
    each buffer_index in workspace.buffers.length {
        save_buffer(buffer_index);
    }

    return empty_string, false;
}

[command, ws]
string, bool change_workspace(string path) {
    result := open_workspace(path, true);
    switch result {
        case OpenWorkspaceResult.InvalidDirectory; {
            result_string := format_string("Unable to open workspace: '%' is not a directory", allocate, path);
            return result_string, true;
        }
        case OpenWorkspaceResult.OpenBuffersInCurrent;
            return "Unable to open workspace: Current workspace has unsaved buffers", false;
    }

    return empty_string, false;
}

[command, wn]
string, bool new_workspace(string path) {
    // Open a new workspace with the given path
    result := open_workspace(path, false);
    switch result {
        case OpenWorkspaceResult.InvalidDirectory; {
            result_string := format_string("Unable to open workspace: '%' is not a directory", allocate, path);
            return result_string, true;
        }
        case OpenWorkspaceResult.MaxWorkspacesActive;
            return "Unable to open new workspace: None available", false;
    }

    return empty_string, false;
}

[command, wc]
string, bool close_current_workspace() {
    // Close the current workspace and switch to the next
    if !close_workspace(true) {
        return "Unable to close workspace: current workspace has unsaved buffers", false;
    }

    return empty_string, false;
}

[command, reload]
string, bool reload_configurations() {
    load_settings_file();
    reload_keybinds();
    load_local_settings();

    return "Settings reloaded", false;
}

start_command_mode() {
    clear_buffer(CommandMode.Command);
}

start_search_mode() {
    clear_buffer(CommandMode.Search);
}

start_replace_mode() {
    clear_buffer(CommandMode.FindAndReplace);
}

start_list_command_mode() {
    clear_buffer(CommandMode.List);
}

start_commit_mode() {
    clear_buffer(CommandMode.Commit);
}

exit_command_mode() {
    current_command_mode = CommandMode.None;
}

show_current_search_result() {
    command_prompt_buffer.result = CommandResult.SearchResult;
}

draw_command(bool draw_cursor = true) {
    background_color: Vector4;
    x := -1.0;
    y := 1.0 - global_font_config.first_line_offset - global_font_config.line_height * (global_font_config.max_lines_without_run_window + 1);
    switch command_prompt_buffer.result {
        case CommandResult.None; {
            start, value: string;
            display_command := false;
            switch current_command_mode {
                case CommandMode.Command;
                    start = ":";
                case CommandMode.Search;
                    start = "Search:";
                case CommandMode.FindAndReplace;
                    start = "Replace:";
                case CommandMode.FindAndReplaceConfirm;
                    start = "Confirm Replacement:";
                case CommandMode.List;
                    display_command = true;
                case CommandMode.Commit;
                    start = "Commit Message:";
            }

            if start.length > 0 || display_command {
                render_text(start, settings.font_size, x, y, appearance.font_color, background_color);
                x += start.length * global_font_config.quad_advance;

                buffer_string, _ := get_buffer_string();
                render_line_with_cursor(buffer_string, x, y, command_prompt_buffer.cursor, 1.0, render_cursor = draw_cursor);
            }
        }
        case CommandResult.Success; {
            render_text(command_prompt_buffer.result_string, settings.font_size, x, y, appearance.font_color, background_color);
        }
        case CommandResult.IncorrectArgumentCount; {
            render_text(settings.font_size, x, y, appearance.font_color, background_color, "Incorrect argument count for command '%'", get_command());
        }
        case CommandResult.IncorrectArgumentTypes; {
            render_text(settings.font_size, x, y, appearance.font_color, background_color, "Incorrect arguments for command '%'", get_command());
        }
        case CommandResult.CommandNotFound; {
            render_text(settings.font_size, x, y, appearance.font_color, background_color, "Command '%' not found", get_command());
        }
        case CommandResult.SearchResult; {
            render_text(settings.font_size, x, y, appearance.font_color, background_color, "/%", get_current_search());
        }
    }
}

move_command_cursor(bool append, bool boundary) {
    buffer_string, _ := get_buffer_string();
    if boundary {
        if append {
            command_prompt_buffer.cursor = buffer_string.length;
        }
        else {
            command_prompt_buffer.cursor = 0;
        }
    }
    else if append {
        command_prompt_buffer.cursor++;
    }

    command_prompt_buffer.cursor = clamp(command_prompt_buffer.cursor, 0, buffer_string.length);
}

bool handle_command_press(PressState state, KeyCode code, ModCode mod, string char) {
    if current_command_mode == CommandMode.None return false;

    if current_command_mode == CommandMode.FindAndReplaceConfirm {
        switch code {
            case KeyCode.Escape;
            case KeyCode.Backspace;
            case KeyCode.Delete;
            case KeyCode.Q; {
                end_replace();
            }
            case KeyCode.A; {
                replace_value_in_buffer();
                while find_next_value_in_buffer() {
                    replace_value_in_buffer();
                }
                end_replace();
            }
            case KeyCode.N; {
                find_and_replace_data.cursor += find_and_replace_data.value.length;
                if !find_next_value_in_buffer() {
                    end_replace();
                }
            }
            case KeyCode.Y; {
                replace_value_in_buffer();
                if !find_next_value_in_buffer() {
                    end_replace();
                }
            }
        }
    }
    else {
        update_list := current_command_mode == CommandMode.List;

        switch code {
            case KeyCode.Escape; {
                switch current_command_mode {
                    case CommandMode.List; {
                        update_list = false;
                        enter_list_browse_mode();
                    }
                    default;
                        current_command_mode = CommandMode.None;
                }
            }
            case KeyCode.Backspace; {
                set_buffer_value();
                if command_prompt_buffer.length > 0 {
                    if command_prompt_buffer.cursor > 0 {
                        if command_prompt_buffer.cursor < command_prompt_buffer.length {
                            memory_copy(command_prompt_buffer.buffer.data + command_prompt_buffer.cursor - 1, command_prompt_buffer.buffer.data + command_prompt_buffer.cursor, command_prompt_buffer.length - command_prompt_buffer.cursor);
                        }

                        command_prompt_buffer.cursor--;
                        command_prompt_buffer.length--;
                    }
                    else {
                        update_list = false;
                    }
                }
                else {
                    update_list = false;
                    if current_command_mode != CommandMode.List {
                        current_command_mode = CommandMode.None;
                    }
                }
            }
            case KeyCode.Delete; {
                set_buffer_value();
                if command_prompt_buffer.length > 0 {
                    if command_prompt_buffer.cursor < command_prompt_buffer.length {
                        if command_prompt_buffer.cursor < command_prompt_buffer.length - 1 {
                            memory_copy(command_prompt_buffer.buffer.data + command_prompt_buffer.cursor, command_prompt_buffer.buffer.data + command_prompt_buffer.cursor + 1, command_prompt_buffer.length - command_prompt_buffer.cursor);
                        }
                        command_prompt_buffer.length--;
                    }
                    else {
                        update_list = false;
                    }
                }
                else {
                    update_list = false;
                    if current_command_mode != CommandMode.List {
                        current_command_mode = CommandMode.None;
                    }
                }
            }
            case KeyCode.Up; {
                buffer_string: string = { length = command_prompt_buffer.length; data = command_prompt_buffer.buffer.data; }
                switch current_command_mode {
                    case CommandMode.Command;
                        find_previous_string(buffer_string, false, command_strings, &command_index);
                    case CommandMode.Search;
                        find_previous_string(buffer_string, false, searches, &search_index);
                    case CommandMode.FindAndReplace;
                        find_previous_string(buffer_string, false, replacements, &replacement_index);
                }
                update_list = false;
            }
            case KeyCode.Down; {
                buffer_string: string = { length = command_prompt_buffer.length; data = command_prompt_buffer.buffer.data; }
                switch current_command_mode {
                    case CommandMode.Command;
                        find_previous_string(buffer_string, true, command_strings, &command_index);
                    case CommandMode.Search;
                        find_previous_string(buffer_string, true, searches, &search_index);
                    case CommandMode.FindAndReplace;
                        find_previous_string(buffer_string, true, replacements, &replacement_index);
                }
                update_list = false;
            }
            case KeyCode.Left; {
                buffer_string, _ := get_buffer_string();
                command_prompt_buffer.cursor = clamp(command_prompt_buffer.cursor - 1, 0, buffer_string.length);
                update_list = false;
            }
            case KeyCode.Right; {
                buffer_string, _ := get_buffer_string();
                command_prompt_buffer.cursor = clamp(command_prompt_buffer.cursor + 1, 0, buffer_string.length);
                update_list = false;
            }
            case KeyCode.Enter; {
                buffer_string, allocated := get_buffer_string();
                switch current_command_mode {
                    case CommandMode.Command;
                        call_command(buffer_string, allocated);
                    case CommandMode.Search;
                        set_search(buffer_string, allocated);
                    case CommandMode.FindAndReplace;
                        find_and_replace(buffer_string, allocated);
                    case CommandMode.List;
                        select_list_entry();
                    case CommandMode.Commit;
                        if !string_is_empty(buffer_string) {
                            source_control_commit(buffer_string);
                            current_command_mode = CommandMode.None;
                            command_prompt_buffer.result = CommandResult.Success;
                        }
                }
                update_list = false;
            }
            default; {
                set_buffer_value();
                if (mod & ModCode.Control) != ModCode.Control && command_prompt_buffer.length + char.length < command_prompt_buffer_length {
                    if command_prompt_buffer.length == command_prompt_buffer.cursor {
                        memory_copy(command_prompt_buffer.buffer.data + command_prompt_buffer.length, char.data, char.length);
                    }
                    else {
                        each i in command_prompt_buffer.length - command_prompt_buffer.cursor {
                            index := command_prompt_buffer.length - i - 1;
                            command_prompt_buffer.buffer[index + char.length] = command_prompt_buffer.buffer[index];
                        }
                        memory_copy(command_prompt_buffer.buffer.data + command_prompt_buffer.cursor, char.data, char.length);
                    }

                    command_prompt_buffer.length += char.length;
                    command_prompt_buffer.cursor += char.length;
                }
                else {
                    update_list = false;
                }
            }
        }

        if update_list {
            buffer_string, _ := get_buffer_string();
            filter_list(buffer_string);
        }
    }

    return true;
}

call_command(string command, bool allocated) {
    defer {
        if current_command_mode == CommandMode.Command {
            current_command_mode = CommandMode.None;
        }
        else {
            command_prompt_buffer.result = CommandResult.None;
        }
    }

    // Remove initial padding
    name_start := 0;
    while name_start < command.length {
        if command[name_start] != ' ' {
            break;
        }
        name_start++;
    }

    // Get the end of the command name
    name_end := name_start;
    while name_end < command.length {
        if command[name_end] == ' ' {
            break;
        }
        name_end++;
    }

    name: string = { length = name_end - name_start; data = command.data + name_start; }

    if name.length == 0 return;

    // Save the command in history
    if !allocated {
        allocate_strings(&command);
        array_insert(&command_strings, command, allocate, reallocate);
    }

    // Parse the command arguments
    i := name_end + 1;
    argument_count := 0;
    while i < command.length {
        if command[i++] != ' ' {
            argument_count++;
            while i < command.length && command[i++] != ' ' {}
        }
    }

    arguments: Array<string>[argument_count];
    if argument_count {
        i = name_end + 1;
        current_argument := 0;
        while i < command.length {
            if command[i++] != ' ' {
                arg_start := i - 1;
                arg_end := i;

                while i < command.length && command[i++] != ' ' {
                    arg_end++;
                }

                arguments[current_argument++] = { length = arg_end - arg_start; data = command.data + arg_start; }
            }
        }
    }

    // If the command is just a number, go to that line
    if argument_count == 0 {
        success, value := try_parse_u32(name);
        if success {
            go_to_line(value);
            command_prompt_buffer.result = CommandResult.None;
            return;
        }
    }

    // Attempt to find the function and then call it
    each command_def in commands {
        if command_def.name == name {
            command_prompt_buffer.result, command_prompt_buffer.result_string, command_prompt_buffer.free_result_string = command_def.handler(arguments);
            return;
        }
    }

    command_prompt_buffer.result = CommandResult.CommandNotFound;
}

set_search(string value, bool allocated) {
    defer current_command_mode = CommandMode.None;

    if allocated {
        current_search_index = search_index;
    }
    else {
        allocate_strings(&value);
        array_insert(&searches, value, allocate, reallocate);
        current_search_index = searches.length - 1;
    }

    find_value_in_buffer(value, true);
    command_prompt_buffer.result = CommandResult.SearchResult;
}

find_and_replace(string value, bool allocated) {
    if value.length == 0 {
        current_command_mode = CommandMode.None;
        return;
    }

    find_string_buffer: Array<u8>[value.length];
    find_string: string = { data = find_string_buffer.data; }
    escape := false;
    i := 0;
    while i < value.length {
        char := value[i++];
        if escape {
            escaped_char: u8;
            switch char {
                case 'n';  escaped_char = '\n';
                case 't';  escaped_char = '\t';
                case '\\'; escaped_char = '\\';
                case '/';  escaped_char = '/';
                default;   escaped_char = char;
            }
            find_string_buffer[find_string.length++] = escaped_char;
            escape = false;
        }
        else if char == '\\' {
            escape = true;
        }
        else if char == '/' {
            break;
        }
        else {
            find_string_buffer[find_string.length++] = char;
        }
    }

    if find_string.length == 0 {
        current_command_mode = CommandMode.None;
        return;
    }

    if !allocated {
        allocate_strings(&value);
        array_insert(&replacements, value, allocate, reallocate);
    }

    replace_string_buffer: Array<u8>[value.length - i];
    replace_string: string = { data = replace_string_buffer.data; }
    escape = false;
    while i < value.length {
        char := value[i++];
        if escape {
            escaped_char: u8;
            switch char {
                case 'n';  escaped_char = '\n';
                case 't';  escaped_char = '\t';
                case '\\'; escaped_char = '\\';
                case '/';  escaped_char = '/';
                default;   escaped_char = char;
            }
            replace_string_buffer[replace_string.length++] = escaped_char;
            escape = false;
        }
        else if char == '\\' {
            escape = true;
        }
        else if char == '/' {
            break;
        }
        else {
            replace_string_buffer[replace_string.length++] = char;
        }
    }

    options: FindAndReplaceOptions;
    while i < value.length {
        char := value[i++];
        switch char {
            case 'c';
            case 'C';
                options |= FindAndReplaceOptions.Confirm;
        }
    }

    if begin_replace_value_in_buffer(find_string, replace_string) {
        if options & FindAndReplaceOptions.Confirm {
            if find_next_value_in_buffer() {
                edit_mode = EditMode.Normal;
                allocate_strings(&find_and_replace_data.value, &find_and_replace_data.new_value);
                current_command_mode = CommandMode.FindAndReplaceConfirm;
                return;
            }
            else {
                end_replace(false);
            }
        }
        else {
            while find_next_value_in_buffer(false) {
                replace_value_in_buffer();
            }
            end_replace(false);
        }
    }

    current_command_mode = CommandMode.None;
}

end_replace(bool free = true) {
    if free free_allocation(find_and_replace_data.value.data);

    current_command_mode = CommandMode.None;
    edit_mode = EditMode.Normal;
    adjust_start_line(find_and_replace_data.buffer_window);
}

enum CommandResult {
    None;
    Success;
    IncorrectArgumentCount;
    IncorrectArgumentTypes;
    CommandNotFound;
    SearchResult;
}

enum CommandMode {
    None;
    Command;
    Search;
    FindAndReplace;
    FindAndReplaceConfirm;
    List;
    Commit;
}

current_command_mode: CommandMode;

string get_current_search() {
    if searches.length == 0 return empty_string;

    return searches[current_search_index];
}

#private

interface CommandResult, string, bool ConsoleCommand(Array<string> args)

struct CommandDefinition {
    name: string;
    handler: ConsoleCommand;
}

commands: Array<CommandDefinition>;

command_prompt_buffer_length := 200; #const
struct CommandPromptBuffer {
    length: int;
    cursor: int;
    buffer: Array<u8>[command_prompt_buffer_length];
    result: CommandResult;
    result_string: string;
    free_result_string: bool;
}

command_prompt_buffer: CommandPromptBuffer;

clear_buffer(CommandMode mode) {
    current_command_mode = mode;
    command_index = -1;
    search_index = -1;
    if command_prompt_buffer.free_result_string {
        free_allocation(command_prompt_buffer.result_string.data);
    }

    clear_memory(command_prompt_buffer.buffer.data, command_prompt_buffer_length);
    command_prompt_buffer = { length = 0; cursor = 0; result = CommandResult.None; result_string = empty_string; free_result_string = false; }

    if mode != CommandMode.Command {
        switch edit_mode {
            case EditMode.Visual;
            case EditMode.VisualLine;
            case EditMode.VisualBlock; {
                selection := get_selected_text();
                memory_copy(command_prompt_buffer.buffer.data, selection.data, selection.length);
                command_prompt_buffer = { length = selection.length; cursor = selection.length; }
            }
        }
    }
}

set_buffer_value() {
    switch current_command_mode {
        case CommandMode.Command;
            if command_index >= 0 {
                command := command_strings[command_index];
                memory_copy(command_prompt_buffer.buffer.data, command.data, command.length);
                command_prompt_buffer.length = command.length;
                command_index = -1;
            }
        case CommandMode.Search;
            if search_index >= 0 {
                search := searches[search_index];
                memory_copy(command_prompt_buffer.buffer.data, search.data, search.length);
                command_prompt_buffer.length = search.length;
                search_index = -1;
            }
        case CommandMode.FindAndReplace;
            if replacement_index >= 0 {
                replacement := replacements[replacement_index];
                memory_copy(command_prompt_buffer.buffer.data, replacement.data, replacement.length);
                command_prompt_buffer.length = replacement.length;
                replacement_index = -1;
            }
    }
}

string, bool get_buffer_string() {
    allocated := false;
    buffer_string: string = { length = command_prompt_buffer.length; data = command_prompt_buffer.buffer.data; }
    switch current_command_mode {
        case CommandMode.Command;
            if command_index >= 0 {
                buffer_string = command_strings[command_index];
                allocated = true;
            }
        case CommandMode.Search;
            if search_index >= 0 {
                buffer_string = searches[search_index];
                allocated = true;
            }
        case CommandMode.FindAndReplace;
            if replacement_index >= 0 {
                buffer_string = replacements[replacement_index];
                allocated = true;
            }
    }

    return buffer_string, allocated;
}

string get_command() {
    command: string = { length = command_prompt_buffer.length; data = command_prompt_buffer.buffer.data; }
    if command_index >= 0 {
        command = command_strings[command_index];
    }

    // Remove initial padding
    name_start := 0;
    while name_start < command.length {
        if command[name_start] != ' ' {
            break;
        }
        name_start++;
    }

    // Get the end of the command name
    name_end := name_start;
    while name_end < command.length {
        if command[name_end] == ' ' {
            break;
        }
        name_end++;
    }

    name: string = { length = name_end - name_start; data = command.data + name_start; }
    return name;
}

find_previous_string(string value, bool forward, Array<string> values, int* index) {
    if *index >= 0 {
        if forward {
            each i in *index + 1..values.length - 1 {
                if starts_with(values[i], value) {
                    *index = i;
                    command_prompt_buffer.cursor = values[i].length;
                    return;
                }
            }

            *index = -1;
            command_prompt_buffer.cursor = command_prompt_buffer.length;
        }
        else {
            each i in 0..*index - 1 {
                if starts_with(values[*index - 1 - i], value) {
                    *index = *index - 1 - i;
                    command_prompt_buffer.cursor = values[*index].length;
                    return;
                }
            }
        }
    }
    else if !forward {
        each i in values.length {
            if starts_with(values[values.length - 1 - i], value) {
                *index = values.length - 1 - i;
                command_prompt_buffer.cursor = values[*index].length;
                return;
            }
        }
    }
}

command_strings: Array<string>;
command_index := -1;

searches: Array<string>;
search_index := -1;
current_search_index: u32;

replacements: Array<string>;
replacement_index := -1;

[flags]
enum FindAndReplaceOptions {
    None    = 0x0;
    Confirm = 0x1;
}
