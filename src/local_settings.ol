struct LocalSettings {
    source_control: SourceControl;

    // Perforce specific settings
    perforce_client_name: string;
    perforce_client_suffix: string;
}

enum SourceControl {
    None;
    Git;
    Perforce;
    Svn;
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

local_settings: LocalSettings;

enum LocalSettingsSection {
    Unknown;
    Settings;
    Commands;
}

load_local_settings() {
    get_default_local_settings();

    local_settings_type := cast(StructTypeInfo*, type_of(LocalSettings));

    found, local_settings_file := read_file("localsettings", allocate);

    if found {
        settings_found: Array<bool>[local_settings_type.fields.length];
        each setting_found in settings_found setting_found = false;

        i: u32;
        line := 1;
        local_settings_pointer: void* = &local_settings;
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
                // TODO Implement
            }

            line++;
            i++;
        }

        free_allocation(local_settings_file.data);
    }

    // TODO Initialize local settings
}

#private

get_default_local_settings() {
    local_settings = {
        source_control = SourceControl.Git;
    }
}
