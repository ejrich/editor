struct Settings {
    tab_size: u8;
    window_width: u32;
    window_height: u32;
    font: string;
    font_size: u8;
    [color]
    font_color: u32;
    [color]
    line_number_color: u32;
    [color]
    current_line_color: u32;
    [color]
    cursor_color: u32;
    [color]
    cursor_font_color: u32;
    [color]
    visual_font_color: u32;
    [color]
    background_color: u32;
    background_transparency: float;
    scroll_offset: u8;
    [color]
    normal_mode_color: u32;
    [color]
    insert_mode_color: u32;
    [color]
    visual_mode_color: u32;
}

#run {
    settings_type := cast(StructTypeInfo*, type_of(Settings));

    each setting in settings_type.fields {
        switch setting.type_info.type {
            case TypeKind.Boolean;
            case TypeKind.Integer;
            case TypeKind.Enum;
            case TypeKind.Float;
            case TypeKind.String; {}
            default; {
                error_message := temp_string("Invalid setting type ", setting.type_info.name, " in field ", setting.name);
                report_error(error_message);
            }
        }
    }
}

settings: Settings;

struct AppearanceSettings {
    font_color: Vector4;
    line_number_color: Vector4;
    current_line_color: Vector4;
    cursor_color: Vector4;
    cursor_font_color: Vector4;
    visual_font_color: Vector4;
    background_color: Vector4;
    normal_mode_color: Vector4;
    insert_mode_color: Vector4;
    visual_mode_color: Vector4;
}

appearance: AppearanceSettings;

load_settings() {
    get_default_settings();

    settings_type := cast(StructTypeInfo*, type_of(Settings));

    home_directory := get_environment_variable(home_environment_variable, temp_allocate);
    settings_file_path = format_string("%/Documents/%/settings", allocate, home_directory, application_name);
    found, settings_file := read_file(settings_file_path, allocate);
    all_settings_set := true;

    if found {
        settings_found: Array<bool>[settings_type.fields.length];
        each setting_found in settings_found setting_found = false;

        i: u32;
        line: u32 = 1;
        settings_pointer: void* = &settings;
        while i < settings_file.length {
            success, name, value := parse_settings_line(settings_file, &i);

            if !success {
                if name.length
                    log("Unable to parse setting value at line %, setting name = %\n", line, name);
            }
            else if value.length == 0 {
                log("Blank setting value at line %, setting name = %\n", line, name);
            }
            else {
                set_setting(name, value, settings_pointer, settings_type, settings_found, line);
            }

            line++;
            i++;
        }

        free_allocation(settings_file.data);

        each setting_found in settings_found {
            if !setting_found {
                all_settings_set = false;
                break;
            }
        }
    }

    // Override any invalid settings
    {
        if settings.tab_size == 0 {
            settings.tab_size = default_tab_size;
        }
    }

    if !found || !all_settings_set {
        write_settings();
    }

    appearance = {
        font_color = convert_to_color(settings.font_color);
        line_number_color = convert_to_color(settings.line_number_color);
        current_line_color = convert_to_color(settings.current_line_color);
        cursor_color = convert_to_color(settings.cursor_color);
        cursor_font_color = convert_to_color(settings.cursor_font_color);
        visual_font_color = convert_to_color(settings.visual_font_color);
        background_color = convert_to_color(settings.background_color, settings.background_transparency);
        normal_mode_color = convert_to_color(settings.normal_mode_color);
        insert_mode_color = convert_to_color(settings.insert_mode_color);
        visual_mode_color = convert_to_color(settings.visual_mode_color);
    }
}

bool, string, string parse_settings_line(string file, u32* index) {
    i := *index;
    name: string = { data = file.data + i; }

    while i < file.length && file[i] != '=' && file[i] != '\n' {
        name.length++;
        i++;
    }

    if file[i] == '\n' || i >= file.length {
        *index = i;
        return false, name, empty_string;
    }

    i++;
    value: string = { data = file.data + i; }

    while i < file.length && file[i] != '\n' {
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

    *index = i;
    return true, name, value;
}

set_setting(string name, string value, void* settings_pointer, StructTypeInfo* settings_type, Array<bool> settings_found, u32 line) {
    setting_found := false;
    each setting, i in settings_type.fields {
        if setting.name == name {
            setting_found = true;
            if settings_found[i] {
                log("Duplicate setting value % at line %\n", name, line);
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

write_settings() {
    if !file_exists(settings_file_path) {
        create_directories_recursively(settings_file_path);
    }

    opened, settings_file := open_file(settings_file_path, FileFlags.Create);
    if !opened {
        log("Unable to write to settings file: '%'\n", settings_file_path);
        return;
    }

    settings_pointer: void* = &settings;
    settings_type := cast(StructTypeInfo*, type_of(Settings));
    each setting in settings_type.fields {
        if array_contains(setting.attributes, "color") {
            value := *cast(u32*, settings_pointer + setting.offset);
            write_to_file(settings_file, "%=%\n", setting.name, int_format(value, 16, 6));
        }
        else {
            value: Any = { type = setting.type_info; data = settings_pointer + setting.offset; }
            write_to_file(settings_file, "%=%\n", setting.name, value);
        }
    }

    close_file(settings_file);
}


#private

settings_file_path: string;

default_tab_size: u32 = 4; #const

get_default_settings() {
    settings = {
        tab_size = default_tab_size;
        window_width = display_width;
        window_height = display_height;
        font = default_font;
        font_size = 18;
        font_color = 0xFFFFFF;
        line_number_color = 0xFFFFFF;
        current_line_color = 0x000000;
        cursor_color = 0x000000;
        cursor_font_color = 0xFFFFFF;
        visual_font_color = 0x000000;
        background_color = 0x000000;
        background_transparency = 1.0;
        scroll_offset = 10;
        normal_mode_color = 0xA89984;
        insert_mode_color = 0x83A598;
        visual_mode_color = 0xFE8019;
    }
}

Vector4 convert_to_color(u32 rgb, float alpha = 1.0) {
    color: Vector4 = {
        x = ((rgb >> 16) & 0xFF) / 255.0;
        y = ((rgb >> 8) & 0xFF) / 255.0;
        z = (rgb & 0xFF) / 255.0;
        w = alpha;
    }
    return color;
}
