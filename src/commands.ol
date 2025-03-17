toggle_command_prompt() {
    display_command_prompt = !display_command_prompt;
    clear_buffer();
}

draw_command_prompt() {
    if !display_command_prompt return;

    color := vec4(1.0, 1.0, 1.0, 1.0);
    position := vec3(-0.9675, 0.95);
    render_text("~", 20, position, color);

    position.x = -0.95;
    command_prompt_buffer_str: string = { length = command_prompt_buffer.length; data = command_prompt_buffer.buffer.data; }
    render_text(command_prompt_buffer_str, 20, position, color);

    if command_prompt_buffer.result != CommandResult.None {
        result_string := format_string("Result = %", temp_allocate, command_prompt_buffer.result);
        position.y = 0.9;
        render_text(result_string, 20, position, color);
    }
}

bool handle_command_prompt_press(PressState state, KeyCode code, ModCode mod, string char) {
    if !display_command_prompt return false;

    if command_prompt_buffer.reset clear_buffer();

    switch code {
        case KeyCode.Tick;
        case KeyCode.Escape;
            toggle_command_prompt();
        case KeyCode.Backspace;
            if command_prompt_buffer.length
                command_prompt_buffer.buffer[--command_prompt_buffer.length];
        case KeyCode.Enter;
            if command_prompt_buffer.length > 0 {
                command: string = { length = command_prompt_buffer.length; data = command_prompt_buffer.buffer.data; }
                call_command(command);
                command_prompt_buffer.reset = true;
            }
        default;
            if command_prompt_buffer.length + char.length < command_prompt_buffer_length {
                memory_copy(command_prompt_buffer.buffer.data + command_prompt_buffer.length, char.data, char.length);
                command_prompt_buffer.length += char.length;
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

#private

interface CommandResult ConsoleCommand(Array<string> args)

struct CommandDefinition {
    name: string;
    handler: ConsoleCommand;
}

commands: Array<CommandDefinition>;

display_command_prompt: bool;

command_prompt_buffer_length := 200; #const
struct CommandPromptBuffer {
    reset: bool;
    length: int;
    buffer: Array<u8>[command_prompt_buffer_length];
    result: CommandResult;
}

command_prompt_buffer: CommandPromptBuffer;

clear_buffer() {
    clear_memory(command_prompt_buffer.buffer.data, command_prompt_buffer_length);
    command_prompt_buffer = { reset = false; length = 0; result = CommandResult.None; }
}
