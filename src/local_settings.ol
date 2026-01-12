struct LocalSettings {
    source_control: SourceControl;

    // Perforce specific settings
    perforce_client_name: string;
    perforce_client_suffix: string;
}

#run {
    local_settings_type := cast(StructTypeInfo*, type_of(Settings));

    each local_setting in local_settings_type.fields {
        switch local_setting.type_info.type {
            case TypeKind.Boolean;
            case TypeKind.Integer;
            case TypeKind.Enum;
            case TypeKind.Float;
            case TypeKind.String; {}
            default; {
                error_message := temp_string("Invalid local setting type ", local_setting.type_info.name, " in field ", local_setting.name);
                report_error(error_message);
            }
        }
    }
}

enum LocalSettingsSection {
    Unknown;
    Settings;
    Commands;
}

load_local_settings(Workspace* workspace) {
    get_default_local_settings(&workspace.local_settings);

    local_settings_type := cast(StructTypeInfo*, type_of(LocalSettings));

    found, local_settings_file := read_file("localsettings", allocate);

    if found {
        settings_found: Array<bool>[local_settings_type.fields.length];
        each setting_found in settings_found setting_found = false;

        i: u32;
        line := 1;
        local_settings_pointer: void* = &workspace.local_settings;
        section: LocalSettingsSection;
        while i < local_settings_file.length {
            // Determine the section being parsed
            while i < local_settings_file.length && (local_settings_file[i] == ' ' || local_settings_file[i] == '\n') {
                if local_settings_file[i] == '\n' {
                    line++;
                }
                i++;
            }

            if i >= local_settings_file.length {
                continue;
            }

            if local_settings_file[i] == '-' {
                i++;
                while i < local_settings_file.length && local_settings_file[i] == ' ' {
                    i++;
                }

                section_name: string = { data = local_settings_file.data + i; }
                while i < local_settings_file.length && local_settings_file[i] != ' ' && local_settings_file[i] != '\n' {
                    section_name.length++;
                    i++;
                }

                section_found, section_value := get_enum_value<LocalSettingsSection>(section_name);
                if section_found {
                    section = section_value;
                }
                else {
                    log("Unable to determine local setting section at line %, setting name = %\n", line, section_name);
                }

                // Move to the next line
                while i < local_settings_file.length && local_settings_file[i] != '\n' {
                    i++;
                }

                if local_settings_file[i] == '\n' || i >= local_settings_file.length {
                    line++;
                    i++;
                }
            }

            success, name, value := parse_settings_line(local_settings_file, &i);

            // Parse settings
            if section == LocalSettingsSection.Settings {
                if !success {
                    if name.length
                        log("Unable to parse local setting value at line %, setting name = %\n", line, name);
                }
                else if value.length == 0 {
                    log("Blank setting value at line %, setting name = %\n", line, name);
                }
                else {
                    set_setting(name, value, local_settings_pointer, local_settings_type, settings_found, line);
                }
            }
            // Parse commands
            else if section == LocalSettingsSection.Commands {
                allocate_strings(true, &value);
                if !add_command_keybind(name, value, workspace) {
                    log("Invalid key code for command keybind at line %, value is '%'\n", line, name);
                    free_allocation(value.data);
                }
            }

            line++;
            i++;
        }

        free_allocation(local_settings_file.data);
    }

    switch workspace.local_settings.source_control {
        case SourceControl.Perforce; {
            if string_is_empty(workspace.local_settings.perforce_client_name) {
                computer_name := get_computer_name();
                each i in computer_name.length {
                    char := computer_name[i];
                    if char >= 'A' && char <= 'Z' {
                        computer_name[i] = char + 0x20;
                    }
                }

                workspace.local_settings.perforce_client_name = format_string("%%", allocate, computer_name, workspace.local_settings.perforce_client_suffix);
            }
        }
    }
}

close_local_settings(LocalSettings* local_settings) {
    if !string_is_empty(local_settings.perforce_client_name) {
        free_allocation(local_settings.perforce_client_name.data);
    }
    if !string_is_empty(local_settings.perforce_client_suffix) {
        free_allocation(local_settings.perforce_client_suffix.data);
    }

    local_settings.source_control = SourceControl.None;
    local_settings.perforce_client_name = empty_string;
    local_settings.perforce_client_suffix = empty_string;
}

#private

get_default_local_settings(LocalSettings* local_settings) {
    default_local_settings: LocalSettings = {
        source_control = SourceControl.Git;
    }

    *local_settings = default_local_settings;
}

string get_computer_name() {
    result: string;
    #if os == OS.Windows {
        computer_name_variable := "computername"; #const
        result = get_environment_variable(computer_name_variable, temp_allocate);
    }
    else {
        found, hostname := read_file("/etc/hostname", temp_allocate);
        if found {
            result = hostname;
            each i in result.length {
                if result[i] == '\n' || result[i] == ' ' {
                    result.length = i;
                    break;
                }
            }
        }
    }

    return result;
}

#if os == OS.Windows {
    computer_name_variable := "computername"; #const
}
else {
    computer_name_variable := "HOSTNAME"; #const
}
