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

        i := 0;
        line := 1;
        settings_pointer: void* = &local_settings;
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

            // Parse settings
            if section == LocalSettingsSection.Settings {
                name: string = { data = local_settings_file.data + i; }

                while i < local_settings_file.length && local_settings_file[i] != '=' && local_settings_file[i] != '\n' {
                    name.length++;
                    i++;
                }

                if local_settings_file[i] == '\n' || i >= local_settings_file.length {
                    if name.length
                        log("Unable to parse setting value at line %, setting name = %\n", line, name);
                    line++;
                    i++;
                    continue;
                }

                i++;
                value: string = { data = local_settings_file.data + i; }

                while i < local_settings_file.length && local_settings_file[i] != '\n' {
                    value.length++;
                    i++;
                }

                // Trim any trailing whitespace
                while value[value.length - 1] == ' ' {
                    value.length--;
                }

                if value.length == 0 {
                    log("Blank setting value at line %, setting name = %\n", line, name);
                }
                else {
                    setting_found := false;
                    each setting, i in local_settings_type.fields {
                        if setting.name == name {
                            setting_found = true;
                            if settings_found[i] {
                                log("Duplicate local setting value % at line %\n", name, line);
                                break;
                            }

                            settings_found[i] = true;

                            switch setting.type_info.type {
                                case TypeKind.Boolean; {
                                    if value == "true" || value == "false" {
                                        bool_setting: bool* = settings_pointer + setting.offset;
                                        *bool_setting = value == "true";
                                    }
                                    else {
                                        log("Invalid value for boolean setting % at line %, value should be 'true' or 'false', but got '%'\n", name, line, value);
                                    }
                                }
                                case TypeKind.Integer; {
                                    if array_contains(setting.attributes, "color") {
                                        integer_value: u32;

                                        j := 0;
                                        is_valid := true;
                                        while j < value.length {
                                            digit := value[j++];
                                            if digit >= '0' && digit <= '9' {
                                                integer_value <<= 4;
                                                integer_value += digit - '0';
                                            }
                                            else if digit >= 'a' && digit <= 'f' {
                                                integer_value <<= 4;
                                                integer_value += digit - 87;
                                            }
                                            else if digit >= 'A' && digit <= 'F' {
                                                integer_value <<= 4;
                                                integer_value += digit - 55;
                                            }
                                            else {
                                                log("Invalid value for integer setting % at line %, value is '%'\n", name, line, value);
                                                is_valid = false;
                                                break;
                                            }
                                        }

                                        if is_valid {
                                            u32_setting: u32* = settings_pointer + setting.offset;
                                            *u32_setting = integer_value & 0xFFFFFF;
                                        }
                                    }
                                    else {
                                        integer_value: u64;
                                        j := 0;
                                        is_negative := false;
                                        if value[j] == '-' {
                                            is_negative = true;
                                            j++;
                                        }

                                        is_valid := true;
                                        while j < value.length {
                                            digit := value[j++];
                                            if digit < '0' || digit > '9' {
                                                log("Invalid value for integer setting % at line %, value is '%'\n", name, line, value);
                                                is_valid = false;
                                                break;
                                            }

                                            integer_value *= 10;
                                            integer_value += digit - '0';
                                        }

                                        if is_valid {
                                            integer_type_info := cast(IntegerTypeInfo*, setting.type_info);
                                            if integer_type_info.signed {
                                                signed_value: s64 = integer_value;
                                                if is_negative signed_value *= -1;

                                                max_value := cast(s64, 1) << (integer_type_info.size * 8 - 1);
                                                min_value := max_value * -1;

                                                if signed_value >= max_value || signed_value < min_value {
                                                    log("Invalid value for integer setting % at line %, value cannot be greater than % or less than %, was %\n", name, line, max_value - 1, min_value, integer_value);
                                                }
                                                else {
                                                    switch integer_type_info.size {
                                                        case 1; {
                                                            s8_setting: s8* = settings_pointer + setting.offset;
                                                            *s8_setting = signed_value;
                                                        }
                                                        case 2; {
                                                            s16_setting: s16* = settings_pointer + setting.offset;
                                                            *s16_setting = signed_value;
                                                        }
                                                        case 4; {
                                                            s32_setting: s32* = settings_pointer + setting.offset;
                                                            *s32_setting = signed_value;
                                                        }
                                                        case 8; {
                                                            s64_setting: s64* = settings_pointer + setting.offset;
                                                            *s64_setting = signed_value;
                                                        }
                                                    }
                                                }
                                            }
                                            else if is_negative {
                                                log("Invalid value for integer setting % at line %, value should be unsigned but is '%'\n", name, line, value);
                                            }
                                            else {
                                                max_value: u64 = cast(u64, 1) << (integer_type_info.size * 8);
                                                if integer_value >= max_value {
                                                    log("Invalid value for integer setting % at line %, value cannot be greater than %, was %\n", name, line, max_value - 1, integer_value);
                                                }
                                                else {
                                                    switch integer_type_info.size {
                                                        case 1; {
                                                            u8_setting: u8* = settings_pointer + setting.offset;
                                                            *u8_setting = integer_value;
                                                        }
                                                        case 2; {
                                                            u16_setting: u16* = settings_pointer + setting.offset;
                                                            *u16_setting = integer_value;
                                                        }
                                                        case 4; {
                                                            u32_setting: u32* = settings_pointer + setting.offset;
                                                            *u32_setting = integer_value;
                                                        }
                                                        case 8; {
                                                            u64_setting: u64* = settings_pointer + setting.offset;
                                                            *u64_setting = integer_value;
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                case TypeKind.Enum; {
                                    enum_value_found := false;
                                    enum_type := cast(EnumTypeInfo*, setting.type_info);
                                    each enum_value in enum_type.values {
                                        if enum_value.name == value {
                                            enum_value_found = true;
                                            switch enum_type.size {
                                                case 1; {
                                                    s8_setting: s8* = settings_pointer + setting.offset;
                                                    *s8_setting = enum_value.value;
                                                }
                                                case 2; {
                                                    s16_setting: s16* = settings_pointer + setting.offset;
                                                    *s16_setting = enum_value.value;
                                                }
                                                case 4; {
                                                    s32_setting: s32* = settings_pointer + setting.offset;
                                                    *s32_setting = enum_value.value;
                                                }
                                                case 8; {
                                                    s64_setting: s64* = settings_pointer + setting.offset;
                                                    *s64_setting = enum_value.value;
                                                }
                                            }
                                            break;
                                        }
                                    }

                                    if !enum_value_found {
                                        log("Invalid value for enum setting % at line %, value is '%'\n", name, line, value);
                                    }
                                }
                                case TypeKind.Float; {
                                    whole: u64;
                                    decimal: float64;

                                    j := 0;
                                    is_negative := false;
                                    if value[j] == '-' {
                                        is_negative = true;
                                        j++;
                                    }

                                    is_valid := true;
                                    parsing_decimal := false;
                                    decimal_factor := 0.1;
                                    while j < value.length {
                                        digit := value[j++];
                                        if digit == '.' {
                                            if parsing_decimal {
                                                log("Invalid value for float setting % at line %, value is '%'\n", name, line, value);
                                                is_valid = false;
                                                break;
                                            }
                                            else parsing_decimal = true;
                                        }
                                        else if digit < '0' || digit > '9' {
                                            log("Invalid value for float setting % at line %, value is '%'\n", name, line, value);
                                            is_valid = false;
                                            break;
                                        }
                                        else {
                                            if parsing_decimal {
                                                decimal += decimal_factor * (digit - '0');
                                                decimal_factor /= 10.0;
                                            }
                                            else {
                                                whole *= 10;
                                                whole += digit - '0';
                                            }
                                        }
                                    }

                                    if is_valid {
                                        float_value := whole + decimal;
                                        if is_negative float_value *= -1.0;

                                        if setting.type_info.size == 4 {
                                            float_setting: float* = settings_pointer + setting.offset;
                                            *float_setting = float_value;
                                        }
                                        else {
                                            float64_setting: float64* = settings_pointer + setting.offset;
                                            *float64_setting = float_value;
                                        }
                                    }
                                }
                                case TypeKind.String; {
                                    allocate_strings(&value);
                                    string_setting: string* = settings_pointer + setting.offset;
                                    *string_setting = value;
                                }
                            }
                            break;
                        }
                    }

                    if !setting_found {
                        log("Setting not found at line %, setting name = %\n", line, name);
                    }
                }
            }
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
