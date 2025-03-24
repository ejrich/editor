start_command_mode() {
    command_mode = true;
    clear_buffer();
}

draw_command() {
    if !command_mode return;

    background_color: Vector4;
    x := -1.0;
    y := 1.0 - first_line_offset - line_height * (max_lines + 1);
    render_text(":", settings.font_size, x, y, appearance.font_color, background_color);

    x += quad_advance;
    command_prompt_buffer_str: string = { length = command_prompt_buffer.length; data = command_prompt_buffer.buffer.data; }
    render_text(command_prompt_buffer_str, settings.font_size, x, y, appearance.font_color, background_color);

    // if command_prompt_buffer.result != CommandResult.None {
    //     result_string := format_string("Result = %", temp_allocate, command_prompt_buffer.result);
    //     render_text(result_string, settings.font_size, x, y, appearance.font_color, background_color);
    // }
}

bool handle_command_press(PressState state, KeyCode code, ModCode mod, string char) {
    if !command_mode return false;

    if command_prompt_buffer.reset clear_buffer();

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
        case KeyCode.Enter;
            if command_prompt_buffer.length > 0 {
                command: string = { length = command_prompt_buffer.length; data = command_prompt_buffer.buffer.data; }
                call_command(command);
                command_prompt_buffer.reset = true;
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

    // Attempt to find the function and then call it
    each command_def in commands {
        if command_def.name == name {
            command_prompt_buffer.result = command_def.handler(arguments);
            return;
        }
    }

    command_prompt_buffer.result = CommandResult.CommandNotFound;
}

enum CommandResult {
    None;
    Success;
    CommandFailed;
    IncorrectArgumentCount;
    IncorrectArgumentTypes;
    CommandNotFound;
}

command_mode: bool;

#private

interface CommandResult ConsoleCommand(Array<string> args)

struct CommandDefinition {
    name: string;
    handler: ConsoleCommand;
}

commands: Array<CommandDefinition>;

command_prompt_buffer_length := 200; #const
struct CommandPromptBuffer {
    reset: bool;
    length: int;
    cursor: int;
    buffer: Array<u8>[command_prompt_buffer_length];
    result: CommandResult;
}

command_prompt_buffer: CommandPromptBuffer;

clear_buffer() {
    clear_memory(command_prompt_buffer.buffer.data, command_prompt_buffer_length);
    command_prompt_buffer = { reset = false; length = 0; result = CommandResult.None; }
}
