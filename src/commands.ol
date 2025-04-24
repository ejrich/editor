#import "parse.ol"

[command, e]
string, bool open_file_command(string path) {
    edit_mode = EditMode.Normal;
    allocate_strings(&path);
    open_file_buffer(path);
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
    each buffer_index in buffers.length {
        save_buffer(buffer_index);
    }

    return empty_string, false;
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

show_current_search_result() {
    command_prompt_buffer.result = CommandResult.SearchResult;
}

draw_command() {
    background_color: Vector4;
    x := -1.0;
    y := 1.0 - global_font_config.first_line_offset - global_font_config.line_height * (global_font_config.max_lines + 1);
    switch command_prompt_buffer.result {
        case CommandResult.None; {
            start, value: string;
            switch current_command_mode {
                case CommandMode.Command;
                    start = ":";
                case CommandMode.Search;
                    start = "/";
                case CommandMode.FindAndReplace;
                    start = "Replace:";
            }

            if start.length {
                render_text(start, settings.font_size, x, y, appearance.font_color, background_color);
                x += start.length * global_font_config.quad_advance;

                buffer_string, _ := get_buffer_string();
                render_line_with_cursor(buffer_string, x, y, command_prompt_buffer.cursor, 1.0);
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

bool handle_command_press(PressState state, KeyCode code, ModCode mod, string char) {
    if current_command_mode == CommandMode.None return false;

    switch code {
        case KeyCode.Escape;
            current_command_mode = CommandMode.None;
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
            }
            else {
                current_command_mode = CommandMode.None;
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
            }
            else {
                current_command_mode = CommandMode.None;
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
        }
        case KeyCode.Left; {
            buffer_string, _ := get_buffer_string();
            command_prompt_buffer.cursor = clamp(command_prompt_buffer.cursor - 1, 0, buffer_string.length);
        }
        case KeyCode.Right; {
            buffer_string, _ := get_buffer_string();
            command_prompt_buffer.cursor = clamp(command_prompt_buffer.cursor + 1, 0, buffer_string.length);
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
            }
        }
        default; {
            set_buffer_value();
            if command_prompt_buffer.length + char.length < command_prompt_buffer_length {
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
        }
    }

    return true;
}

call_command(string command, bool allocated) {
    defer current_command_mode = CommandMode.None;

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
    defer current_command_mode = CommandMode.None;

    if value.length == 0 return;

    find_string: string = { data = value.data; }
    escape := false;
    i := 0;
    while i < value.length {
        char := value[i++];
        if char == '\\' {
            escape = !escape;
        }
        else if char == '/' && !escape {
            break;
        }
        else if escape {
            escape = false;
        }
        find_string.length++;
    }

    if find_string.length == 0 return;

    if !allocated {
        allocate_strings(&value);
        array_insert(&replacements, value, allocate, reallocate);
    }

    replace_string: string = { data = value.data + find_string.length + 1; }
    escape = false;
    while i < value.length {
        char := value[i++];
        if char == '\\' {
            escape = !escape;
        }
        else if char == '/' && !escape {
            break;
        }
        else if escape {
            escape = false;
        }
        replace_string.length++;
    }

    options: FindAndReplaceOptions;
    switch edit_mode {
        case EditMode.Visual;
        case EditMode.VisualLine;
        case EditMode.VisualBlock;
            options |= FindAndReplaceOptions.Visual;
    }

    while i < value.length {
        char := value[i++];
        switch char {
            case 'c';
            case 'C';
                options |= FindAndReplaceOptions.Confirm;
        }
    }

    log("Find: '%', Replace: '%', Options: %\n", find_string, replace_string, options);
    // TODO Implement this
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
    Visual  = 0x1;
    Confirm = 0x2;
}
