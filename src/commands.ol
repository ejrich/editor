#import "parse.ol"

[command, e]
string, bool open_file_command(string path) {
    open_file_buffer(path);
    return empty_string, false;
}

[command, w]
string, bool save_current_buffer() {
    buffer_index := -1;
    switch current_window {
        case SelectedWindow.Left;
            buffer_index = left_window.buffer_index;
        case SelectedWindow.Right;
            buffer_index = right_window.buffer_index;
    }

    success, lines, bytes, file := save_buffer(buffer_index);
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
    command_mode = true;
    clear_buffer();
}

draw_command() {
    background_color: Vector4;
    x := -1.0;
    y := 1.0 - global_font_config.first_line_offset - global_font_config.line_height * (global_font_config.max_lines + 1);
    switch command_prompt_buffer.result {
        case CommandResult.None; {
            if command_mode {
                render_text(":", settings.font_size, x, y, appearance.font_color, background_color);

                x += global_font_config.quad_advance;
                command_prompt_buffer_str: string = { length = command_prompt_buffer.length; data = command_prompt_buffer.buffer.data; }
                render_line_with_cursor(command_prompt_buffer_str, x, y, command_prompt_buffer.cursor, 1.0);
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
    }
}

bool handle_command_press(PressState state, KeyCode code, ModCode mod, string char) {
    if !command_mode return false;

    switch code {
        case KeyCode.Escape;
            command_mode = false;
        case KeyCode.Backspace; {
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
                command_mode = false;
            }
        }
        case KeyCode.Delete; {
            if command_prompt_buffer.length > 0 {
                if command_prompt_buffer.cursor < command_prompt_buffer.length {
                    if command_prompt_buffer.cursor < command_prompt_buffer.length - 1 {
                        memory_copy(command_prompt_buffer.buffer.data + command_prompt_buffer.cursor, command_prompt_buffer.buffer.data + command_prompt_buffer.cursor + 1, command_prompt_buffer.length - command_prompt_buffer.cursor);
                    }
                    command_prompt_buffer.length--;
                }
            }
            else {
                command_mode = false;
            }
        }
        case KeyCode.Left; {
            command_prompt_buffer.cursor = clamp(command_prompt_buffer.cursor - 1, 0, command_prompt_buffer.length);
        }
        case KeyCode.Right; {
            command_prompt_buffer.cursor = clamp(command_prompt_buffer.cursor + 1, 0, command_prompt_buffer.length);
        }
        case KeyCode.Enter; {
            command: string = { length = command_prompt_buffer.length; data = command_prompt_buffer.buffer.data; }
            call_command(command);
        }
        default;
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

    return true;
}

call_command(string command) {
    defer command_mode = false;

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

enum CommandResult {
    None;
    Success;
    IncorrectArgumentCount;
    IncorrectArgumentTypes;
    CommandNotFound;
}

command_mode: bool;


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

clear_buffer() {
    if command_prompt_buffer.free_result_string {
        free_allocation(command_prompt_buffer.result_string.data);
    }

    clear_memory(command_prompt_buffer.buffer.data, command_prompt_buffer_length);
    command_prompt_buffer = { length = 0; cursor = 0; result = CommandResult.None; result_string = empty_string; free_result_string = false; }
}

string get_command() {
    command: string = { length = command_prompt_buffer.length; data = command_prompt_buffer.buffer.data; }

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
