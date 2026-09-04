string serialize_json<T>(T object, Array<u8>* buffer) {
    #assert type_of(T).type == TypeKind.Struct;

    type := cast(StructTypeInfo*, type_of(T));

    string_buffer: StringBuffer = { buffer = *buffer; }

    serialize_json(&object, type, &string_buffer);

    if string_buffer.length > buffer.length {
        increment_size := 1000; #const
        new_size := buffer.length + increment_size;
        while new_size < string_buffer.length {
            new_size += increment_size;
        }

        resize_buffer(buffer, new_size);

        string_buffer.length = 0;
        string_buffer.buffer = *buffer;
        serialize_json(&object, type, &string_buffer);
    }

    value: string = { length = string_buffer.length; data = buffer.data; }
    return value;
}

T parse_json<T>(string text, u64 i = 0) {
    #assert type_of(T).type == TypeKind.Struct;

    result: T;

    type := cast(StructTypeInfo*, type_of(T));

    parse_json(text, i, &result, type);

    return result;
}

struct JsonSchema {
    type: JsonSchemaType;
    properties: Array<JsonSchemaProperty>;
    required: Array<string>;
    additionalProperties: bool;
}

enum JsonSchemaType {
    object;
}

struct JsonSchemaProperty {
    name: string;
    description: string;
    type: JsonSchemaPropertyType;
    enum_names: Array<string>;
}

enum JsonSchemaPropertyType {
    array = 1;
    boolean;
    integer;
    number;
    object;
    string;
}

#private

serialize_json(void* data, TypeInfo* type, StringBuffer* buffer) {
    if type == type_of(JsonSchema) {
        json_schema := *cast(JsonSchema*, data);
        add_char_to_string_buffer(buffer, '{');

        add_to_string_buffer(buffer, "\"type\":\"");
        add_to_string_buffer(buffer, get_enum_name(json_schema.type));

        add_to_string_buffer(buffer, "\",\"required\":");
        serialize_json_array(&json_schema.required, type_of(string), buffer);

        add_to_string_buffer(buffer, ",\"additionalProperties\":");
        if json_schema.additionalProperties
             add_to_string_buffer(buffer, "true");
        else
             add_to_string_buffer(buffer, "false");

        add_to_string_buffer(buffer, ",\"properties\":{");
        length := json_schema.properties.length;
        each property, i in json_schema.properties {
            add_char_to_string_buffer(buffer, '"');
            add_to_string_buffer(buffer, property.name);
            add_to_string_buffer(buffer, "\":{\"type\":");

            serialize_json_enum(&property.type, cast(EnumTypeInfo*, type_of(JsonSchemaPropertyType)), buffer);

            if !string_is_empty(property.description) {
                add_to_string_buffer(buffer, ",\"description\":");
                serialize_json_string(property.description, buffer);
            }

            if property.enum_names.length {
                add_to_string_buffer(buffer, ",\"enum\":");
                serialize_json_array(&property.enum_names, type_of(JsonSchemaPropertyType), buffer);
            }

            add_char_to_string_buffer(buffer, '}');
            if i < length - 1
                add_char_to_string_buffer(buffer, ',');
        }

        add_char_to_string_buffer(buffer, '}');
        add_char_to_string_buffer(buffer, '}');
        return;
    }

    switch type.type {
        case TypeKind.Boolean; {
            value := *cast(bool*, data);
            if value add_to_string_buffer(buffer, "true");
            else add_to_string_buffer(buffer, "false");
        }
        case TypeKind.Integer; {
            type_info := cast(IntegerTypeInfo*, type);
            format: IntFormat = { signed = type_info.signed; }

            if type_info.signed {
                switch type_info.size {
                    case 1;  format.value.signed = *cast(s8*, data);
                    case 2;  format.value.signed = *cast(s16*, data);
                    case 4;  format.value.signed = *cast(s32*, data);
                    default; format.value.signed = *cast(s64*, data);
                }
            }
            else {
                switch type_info.size {
                    case 1;  format.value.unsigned = *cast(u8*, data);
                    case 2;  format.value.unsigned = *cast(u16*, data);
                    case 4;  format.value.unsigned = *cast(u32*, data);
                    default; format.value.unsigned = *cast(u64*, data);
                }
            }

            write_integer(buffer, format);
        }
        case TypeKind.Float; {
            format: FloatFormat;
            if type.size == 4 format.value = *cast(float*, data);
            else format.value = *cast(float64*, data);

            write_float(buffer, format);
        }
        case TypeKind.String; {
            value := *cast(string*, data);
            serialize_json_string(value, buffer);
        }
        case TypeKind.Array; {
            type_info := cast(StructTypeInfo*, type);
            pointer_field := type_info.fields[1];
            pointer_type_info := cast(PointerTypeInfo*, pointer_field.type_info);
            element_type := pointer_type_info.pointer_type;

            serialize_json_array(data, element_type, buffer);
        }
        case TypeKind.Enum; {
            type_info := cast(EnumTypeInfo*, type);
            serialize_json_enum(data, type_info, buffer);
        }
        case TypeKind.Struct; {
            type_info := cast(StructTypeInfo*, type);
            add_char_to_string_buffer(buffer, '{');

            length := type_info.fields.length;
            serialized_field_count := 0;
            each field, i in type_info.fields {
                field_data := data + field.offset;
                if !should_serialize_json_struct_field(field_data, field.type_info) continue;

                if serialized_field_count++
                    add_char_to_string_buffer(buffer, ',');

                add_char_to_string_buffer(buffer, '"');
                if field.attributes.length {
                    add_to_string_buffer(buffer, field.attributes[0]);
                }
                else {
                    add_to_string_buffer(buffer, field.name);
                }
                add_to_string_buffer(buffer, "\":");

                serialize_json(field_data, field.type_info, buffer);
            }

            add_char_to_string_buffer(buffer, '}');
        }
        default; {
            assert(false, format_string("Unable to serialize type '%'\n", temp_allocate, type.name));
        }
    }
}

bool should_serialize_json_struct_field(void* data, TypeInfo* type) {
    switch type.type {
        case TypeKind.Boolean;
        case TypeKind.Integer;
        case TypeKind.Float;
        case TypeKind.Struct;
            return true;
        case TypeKind.String; {
            value := *cast(string*, data);
            return value.data != null;
        }
        case TypeKind.Array; {
            value := *cast(Array<void*>*, data);
            return value.length > 0;
        }
        case TypeKind.Enum; {
            value: s64;
            switch type.size {
                case 1;  value = *cast(s8*, data);
                case 2;  value = *cast(s16*, data);
                case 4;  value = *cast(s32*, data);
                default; value = *cast(s64*, data);
            }
            return value != 0;
        }
        default; {
            assert(false, format_string("Unable to serialize type '%'\n", temp_allocate, type.name));
        }
    }

    return false;
}

serialize_json_string(string value, StringBuffer* buffer) {
    if string_is_empty(value) {
        add_to_string_buffer(buffer, "null");
    }
    else {
        add_char_to_string_buffer(buffer, '"');
        each i in value.length {
            char := value[i];
            switch char {
                case '\b'; add_to_string_buffer(buffer, "\\b");
                case '\f'; add_to_string_buffer(buffer, "\\f");
                case '\n'; add_to_string_buffer(buffer, "\\n");
                case '\r'; add_to_string_buffer(buffer, "\\r");
                case '\t'; add_to_string_buffer(buffer, "\\t");
                case '"';  add_to_string_buffer(buffer, "\\\"");
                case '\\'; add_to_string_buffer(buffer, "\\\\");
                default;   add_char_to_string_buffer(buffer, char);
            }
        }
        add_char_to_string_buffer(buffer, '"');
    }
}

serialize_json_enum(void* data, EnumTypeInfo* type_info, StringBuffer* buffer) {
    value: s64;
    switch type_info.size {
        case 1;  value = *cast(s8*, data);
        case 2;  value = *cast(s16*, data);
        case 4;  value = *cast(s32*, data);
        default; value = *cast(s64*, data);
    }

    found := false;
    each enum_value in type_info.values {
        if enum_value.value == value {
            add_char_to_string_buffer(buffer, '"');
            add_to_string_buffer(buffer, enum_value.name);
            add_char_to_string_buffer(buffer, '"');
            found = true;
            break;
        }
    }

    if !found {
        add_to_string_buffer(buffer, "null");
    }
}

serialize_json_array(void* data, TypeInfo* element_type, StringBuffer* buffer) {
    array := cast(Array<void*>*, data);
    if array.length == 0 {
        add_to_string_buffer(buffer, "null");
    }
    else {
        add_char_to_string_buffer(buffer, '[');

        each i in array.length {
            element_data := array.data + element_type.size * i;
            serialize_json(element_data, element_type, buffer);

            if i < array.length - 1
                add_char_to_string_buffer(buffer, ',');
        }

        add_char_to_string_buffer(buffer, ']');
    }
}


u64 parse_json(string text, u64 i, void* pointer, StructTypeInfo* type) {
    in_object := false;
    while i < text.length {
        char := text[i];
        if char == '{' {
            if !in_object {
                in_object = true;
            }
        }
        else if char == '}' {
            if in_object {
                break;
            }
        }
        else if char == '"' {
            name: string;
            i, name = get_json_string(text, i);

            // Try to find a field with the name
            matched_field: TypeField*;
            each field in type.fields {
                if field.name == name {
                    matched_field = &field;
                    break;
                }
            }

            // Move past the colon and whitespace after the property name
            while i < text.length && text[i] != ':' {
                i++;
            }
            i++;

            while i < text.length && is_whitespace(text[i]) {
                i++;
            }

            // Set the data on the matched field or skip to the next property
            if matched_field {
                field_pointer := pointer + matched_field.offset;
                i = parse_json_value(text, i, field_pointer, matched_field.type_info);
            }
            else {
                char = text[i];
                _: string;
                if char == '"' {
                    i, _ = get_json_string(text, i);
                }
                else if char == '[' {
                    i++;
                    depth := 0;
                    while i < text.length {
                        char = text[i];
                        if char == '"' {
                            i, _ = get_json_string(text, i);
                        }
                        else {
                            if char == '[' {
                                depth++;
                            }
                            else if char == ']' {
                                if depth == 0 break;
                                depth--;
                            }

                            i++;
                        }
                    }
                }
                else if char == '{' {
                    i++;
                    depth := 0;
                    while i < text.length {
                        char = text[i];
                        if char == '"' {
                            i, _ = get_json_string(text, i);
                        }
                        else {
                            if char == '{' {
                                depth++;
                            }
                            else if char == '}' {
                                if depth == 0 break;
                                depth--;
                            }

                            i++;
                        }
                    }

                    i++;
                    continue;
                }
                else {
                    i, _ = get_next_json_value(text, i);
                }
            }
        }

        // Check for end of object after parsing
        if in_object && text[i] == '}' {
            break;
        }

        i++;
    }

    return i;
}

u64 parse_json_value(string text, u64 i, void* pointer, TypeInfo* type_info) {
    value: string;
    switch type_info.type {
        case TypeKind.Boolean; {
            i, value = get_next_json_value(text, i);
            bool_pointer := cast(bool*, pointer);
            *bool_pointer = value == "true";
        }
        case TypeKind.Integer; {
            i, value = get_next_json_value(text, i);
            if value != "null" {
                negative := false;
                number: u64;
                if value.length {
                    j := 0;
                    if value[0] == '-' {
                        negative = true;
                        j++;
                    }

                    while j < value.length {
                        number *= 10;
                        number += value[j++] - '0';
                    }
                }

                if negative {
                    negative_number := cast(s64, number) * -1;
                    switch type_info.size {
                        case 1; {
                            s8_pointer := cast(s8*, pointer);
                            *s8_pointer = negative_number;
                        }
                        case 2; {
                            s16_pointer := cast(s16*, pointer);
                            *s16_pointer = negative_number;
                        }
                        case 1; {
                            s32_pointer := cast(s32*, pointer);
                            *s32_pointer = negative_number;
                        }
                        default; {
                            s64_pointer := cast(s64*, pointer);
                            *s64_pointer = negative_number;
                        }
                    }
                }
                else {
                    switch type_info.size {
                        case 1; {
                            u8_pointer := cast(u8*, pointer);
                            *u8_pointer = number;
                        }
                        case 2; {
                            u16_pointer := cast(u16*, pointer);
                            *u16_pointer = number;
                        }
                        case 1; {
                            u32_pointer := cast(u32*, pointer);
                            *u32_pointer = number;
                        }
                        default; {
                            u64_pointer := cast(u64*, pointer);
                            *u64_pointer = number;
                        }
                    }
                }
            }
        }
        case TypeKind.Float; {
            i, value = get_next_json_value(text, i);
            if value != "null" {
                negative := false;
                number: float64;
                if value.length {
                    j := 0;
                    if value[0] == '-' {
                        negative = true;
                        j++;
                    }

                    while j < value.length {
                        digit := value[j++];
                        if digit == '.' break;
                        number *= 10.0;
                        number += digit - '0';
                    }

                    factor: float64 = 0.1;
                    while j < value.length {
                        digit := value[j++];
                        number += (digit - '0') * factor;
                        factor *= 0.1;
                    }

                    if negative {
                        number *= -1.0;
                    }
                }

                if type_info.size == 4 {
                    float_pointer := cast(float*, pointer);
                    *float_pointer = number;
                }
                else {
                    float64_pointer := cast(float64*, pointer);
                    *float64_pointer = number;
                }
            }
        }
        case TypeKind.String; {
            // Handle null
            if text[i] == 'n' {
                i, value = get_next_json_value(text, i);
            }
            else {
                assert(text[i] == '"', "JSON string value does not begin with '\"'\n");
                i, value = get_json_string(text, i, true);
                string_pointer := cast(string*, pointer);
                *string_pointer = value;
            }
        }
        case TypeKind.Array; {
            // Handle null
            if text[i] == 'n' {
                i, value = get_next_json_value(text, i);
            }
            else {
                assert(text[i] == '[', "JSON array value does not begin with '['\n");
                array_struct_type := cast(StructTypeInfo*, type_info);
                element_pointer_type := cast(PointerTypeInfo*, array_struct_type.fields[1].type_info);
                element_type := element_pointer_type.pointer_type;

                element_buffer: Array<u8>[element_type.size];
                i++;
                length: s64;
                data: void*;

                while i < text.length {
                    char := text[i];
                    if char == ']' {
                        i++;
                        break;
                    }
                    else if !is_whitespace(char) && char != ',' {
                        clear_memory(element_buffer.data, element_buffer.length);
                        i = parse_json_value(text, i, element_buffer.data, element_type);

                        if length % ARRAY_BLOCK_SIZE == 0 {
                            new_blocks := length / ARRAY_BLOCK_SIZE + 1;

                            if length {
                                data = reallocate(data, length * element_type.size, element_type.size * new_blocks * ARRAY_BLOCK_SIZE);
                            }
                            else {
                                data = allocate(element_type.size * new_blocks * ARRAY_BLOCK_SIZE);
                            }
                        }

                        memory_copy(data + element_type.size * length, element_buffer.data, element_buffer.length);
                        length++;
                    }

                    i++;
                }

                length_pointer := cast(s64*, pointer);
                *length_pointer = length;

                data_pointer := cast(void**, pointer + size_of(s64));
                *data_pointer = data;
            }
        }
        case TypeKind.Enum; {
            // Handle null
            if text[i] == 'n' {
                i, value = get_next_json_value(text, i);
            }
            else {
                assert(text[i] == '"', "JSON enum value does not begin with '\"'\n");
                i, value = get_json_string(text, i, true);

                enum_type := cast(EnumTypeInfo*, type_info);
                raw_enum_value: s64;

                each enum_value in enum_type.values {
                    if enum_value.name == value {
                        raw_enum_value = enum_value.value;
                        break;
                    }
                }

                switch enum_type.size {
                    case 1; {
                        s8_pointer := cast(s8*, pointer);
                        *s8_pointer = raw_enum_value;
                    }
                    case 2; {
                        s16_pointer := cast(s16*, pointer);
                        *s16_pointer = raw_enum_value;
                    }
                    case 1; {
                        s32_pointer := cast(s32*, pointer);
                        *s32_pointer = raw_enum_value;
                    }
                    default; {
                        s64_pointer := cast(s64*, pointer);
                        *s64_pointer = raw_enum_value;
                    }
                }
            }
        }
        case TypeKind.Struct; {
            // Handle null
            if text[i] == 'n' {
                i, value = get_next_json_value(text, i);
            }
            else {
                assert(text[i] == '{', "JSON struct value does not begin with '{'\n");
                i = parse_json(text, i, pointer, cast(StructTypeInfo*, type_info));
            }
        }
        default; {
            assert(false, format_string("Unable to parse type '%'\n", temp_allocate, type_info.name));
        }
    }

    return i;
}

// i should be the first index following the initial "
u64, string get_json_string(string text, u64 i, bool replace = false) {
    i++;
    string_index := i;
    escaping := false;
    result: string = { data = text.data + i; }
    while i < text.length {
        char := text[i];
        if escaping {
            escaping = false;
            if replace {
                switch char {
                    case 'b'; char = '\b';
                    case 'f'; char = '\f';
                    case 'n'; char = '\n';
                    case 'r'; char = '\r';
                    case 't'; char = '\t';
                }

                text[string_index++] = char;
                result.length++;
            }
        }
        else if char == '\\' {
            escaping = true;
        }
        else if char == '"' {
            i++;
            break;
        }
        else {
            if replace && string_index < i {
                text[string_index] = char;
            }

            string_index++;
            result.length++;
        }

        i++;
    }

    return i, result;
}

u64, string get_next_json_value(string text, u64 i) {
    result: string = { data = text.data + i; }

    while i < text.length {
        char := text[i];

        if char == ',' || char == '}' || char == ']' break;

        result.length++;
        i++;
    }

    return i, result;
}
