load_keybinds() {
    home_directory := get_environment_variable(home_environment_variable, temp_allocate);
    keybinds_file_path = format_string("%/Documents/%/keybinds", allocate, home_directory, application_name);
    found, keybinds_file := read_file(keybinds_file_path, allocate);

    if !found {
        default_keybinds_file := temp_string(get_program_directory(), "/default_keybinds");
        found, keybinds_file = read_file(default_keybinds_file, allocate);
    }

    if found {
        parse_keybinds_file(keybinds_file);
    }
    else {
        log("Unable to load keybinds file, couldn't load file '%' or default keybinds\n", keybinds_file_path);
    }

    write_keybinds();
}

write_keybinds() {
    opened, keybinds_file := open_file(keybinds_file_path, FileFlags.Create);
    if !opened {
        log("Unable to write to keybinds file: '%'\n", keybinds_file_path);
        return;
    }

    each keybind, i in keybind_definitions {
        index := i + 1;
        mod: ModCode;
        code: KeyCode;
        each handler_index, j in keybind_lookup {
            if handler_index == index {
                mod = cast(ModCode, (j & 0xE00) >> 9);
                code = cast(KeyCode, j & 0x1FF);
                break;
            }
        }

        write_to_file(keybinds_file, "%=", keybind.name);

        if mod & ModCode.Shift
            write_to_file(keybinds_file, "Shift+");
        if mod & ModCode.Control
            write_to_file(keybinds_file, "Control+");
        if mod & ModCode.Alt
            write_to_file(keybinds_file, "Alt+");

        write_to_file(keybinds_file, "%\n", code);
    }

    close_file(keybinds_file);
}

bool handle_keybind_event(KeyCode code, PressState state, ModCode mod) {
    code_value := cast(int, code);
    mod_value := (cast(int, mod) << 9) | code_value;

    handler_index := keybind_lookup[mod_value];
    if handler_index == 0 {
        handler_index = keybind_lookup[code_value];
    }
    if handler_index == 0 return false;

    keybind := keybind_definitions[handler_index - 1];

    result: bool;
    if keybind.no_repeat || key_command.repeats == 0 {
        result = keybind.handler(state, mod);
    }
    else {
        each i in key_command.repeats {
            result = keybind.handler(state, mod);

            if !result
                break;
        }
    }

    reset_key_command();

    return result;
}

reassign_keybind(KeyCode code, string keybind) {
    each definition, i in keybind_definitions {
        if definition.name == keybind {
            index := i + 1;
            // Determine if the keybind is already assigned
            each lookup in keybind_lookup {
                if lookup == index {
                    lookup = 0;
                    break;
                }
            }

            keybind_lookup[cast(int, code)] = index;
            write_keybinds();
            return;
        }
    }

    log("Unable to reassign keybind '%', not found\n", keybind);
}

#private

parse_keybinds_file(string keybinds_file) {
    i := 0;
    line := 1;
    while i < keybinds_file.length {
        name: string = { data = keybinds_file.data + i; }

        while i < keybinds_file.length && keybinds_file[i] != '=' && keybinds_file[i] != '\n' {
            name.length++;
            i++;
        }

        if keybinds_file[i] == '\n' || i >= keybinds_file.length {
            if name.length
                log("Unable to parse keybind at line %, keybind name = %\n", line, name);
            line++;
            i++;
            continue;
        }

        i++;
        value: string = { data = keybinds_file.data + i; }

        while i < keybinds_file.length && keybinds_file[i] != '\n' {
            value.length++;
            i++;
        }

        // Trim any trailing whitespace
        while name[name.length - 1] == ' ' {
            name.length--;
        }
        while value[value.length - 1] == ' ' {
            value.length--;
        }

        if name.length > 0 && value.length > 0 {
            handler_index := 0;
            each definition, i in keybind_definitions {
                if definition.name == name {
                    handler_index = i + 1;
                }
            }

            if handler_index == 0 {
                log("Invalid keybind name % at line %\n", name, line);
                continue;
            }

            valid, lookup_index := parse_keybind_value(value);

            if valid {
                keybind_lookup[lookup_index] = handler_index;
            }
            else {
                log("Invalid key code for setting % at line %, value is '%'\n", name, line, value);
            }
        }

        line++;
        i++;
    }

    free_allocation(keybinds_file.data);
}

bool, u32 parse_keybind_value(string value) {
    mod: ModCode;
    start := 0;
    each i in value.length {
        if value[i] == '+' {
            mod_string: string = {
                length = i - start;
                data = value.data + start;
            }

            valid, code := get_enum_value<ModCode>(mod_string);
            if valid
                mod |= code;
            else
                return false, 0;

            start = i + 1;
        }
    }

    value.length -= start;
    value.data = value.data + start;
    valid, code := get_enum_value<KeyCode>(value);
    return valid, (cast(u32, mod) << 9) | cast(u32, code);
}

interface bool KeybindHandler(PressState state, ModCode mod)

struct KeybindDefinition {
    name: string;
    handler: KeybindHandler;
    no_repeat: bool;
}

keybind_definitions: Array<KeybindDefinition>;
keybind_lookup: Array<int>[0xF24];

keybinds_file_path: string;

assign_keybind(KeyCode code, KeybindHandler handler) {
    each definition, i in keybind_definitions {
        if definition.handler == handler {
            keybind_lookup[cast(int, code)] = i + 1;
            return;
        }
    }

    log("Unable to assign keybind to code '%'\n", code);
}
