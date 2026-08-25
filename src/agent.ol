#import openssl

init_agent() {
    // TODO Figure out why this is causing hang/additional allocations
    // queue_work(&low_priority_queue, init_ssl_job);
}

deinit_agent() {
    if ssl_initialized {
        SSL_CTX_free(ssl_context);
    }
}

struct AgentData {
    buffer: Buffer = { read_only = true; title = get_agent_title; }
    buffer_window: BufferWindow;
    socket: Socket;
    request_buffer: Array<u8>;
    response_buffer: Array<u8>;
    status: AgentStatus;
    display_thinking: bool;
    previous_response_id: string;
}

enum AgentStatus {
    Ready;
    UnableToConnect;
    Disconnected;
    Pending;
    Thinking;
    ThinkingComplete;
    Outputting;
    FunctionCall;
    Done;
}

send_agent_message(int thread, JobData data) {
    message := data.multiple.value1;
    workspace := cast(Workspace*, data.multiple.value2);

    if workspace.agent_data.buffer.line_count > 1
        add_to_agent_buffer(workspace, "\n");
    add_to_agent_buffer(workspace, message, BufferLineFlags.Message);
    add_to_agent_buffer(workspace, "\n\n", BufferLineFlags.Message);

    // TODO Use the selected model
    responses_request: OpenAIResponseRequest = {
        model = "google/gemma-4-26b-a4b-qat";
        input = data.multiple.value1;
        stream = true;
    }

    if string_is_empty(workspace.agent_data.previous_response_id) {
        responses_request.instructions = "Do not use latex in the output and make the output text easy to read without formatting.";
    }
    else {
        responses_request.previous_response_id = workspace.agent_data.previous_response_id;
    }

    // TODO Use workspace request buffer
    body := serialize_json(responses_request);
    defer free_allocation(body.data);

    request: HTTPRequest = {
        version = HTTPVersion.HTTP1_1;
        method = HTTPMethod.POST;
        connection = HTTPConnection.KeepAlive;
        resource = "/v1/responses";
        host = "evan-desktop.local";
        authorization = "Bearer sk-lm-Mukalw9D:ubAtA8TNXFzf7D5I6clm";
        content_type = "application/json";
        body = body;
    }

    // TODO Use workspace request buffer
    r := serialize_http_request(request, allocate);
    defer free_allocation(r.data);

    workspace.agent_data.status = AgentStatus.Ready;

    // TODO Don't hard code domain/port
    domain := "evan-desktop.local";
    port := "1234";

    if !socket_is_connected(workspace.agent_data.socket) {
        success, socket := connect_to_socket_with_retry(domain, port);
        if !success {
            workspace.agent_data.status = AgentStatus.UnableToConnect;
            return;
        }
        workspace.agent_data.socket = socket;
    }

    // TODO Replace with pointer to either socket_send or SSL_write_ex
    sent, sent_length := socket_send(workspace.agent_data.socket, r.data, r.length);
    if !sent {
        workspace.agent_data.status = AgentStatus.Disconnected;
        return;
    }
    workspace.agent_data.status = AgentStatus.Pending;

    response_parsed := false;
    receiving_chunks := false;
    carry := 0;
    event := OpenAIResponseEvent.None;

    response_id: string;

    // TODO Handle function calls and free after handling all results
    function_calls: Array<OpenAIResponseOutput>;
    name: string;
    call_id: string;

    while true {
        if carry == workspace.agent_data.response_buffer.length {
            previous_length := workspace.agent_data.response_buffer.length;
            new_length := previous_length + 1000; // TODO Check that this size is appropriate

            new_buffer := allocate(new_length);
            if workspace.agent_data.response_buffer.length {
                memory_copy(new_buffer, workspace.agent_data.response_buffer.data, previous_length);
                free_allocation(workspace.agent_data.response_buffer.data);
            }

            workspace.agent_data.response_buffer.data = new_buffer;
            workspace.agent_data.response_buffer.length = new_length;
        }

        // TODO Replace with pointer to either socket_receive or SSL_read_ex
        received, length := socket_receive(workspace.agent_data.socket, workspace.agent_data.response_buffer.data + carry, workspace.agent_data.response_buffer.length - carry);
        if !received {
            // Reconnect and resend if the socket was closed
            if !response_parsed {
                success, socket := connect_to_socket_with_retry(domain, port);
                if !success {
                    workspace.agent_data.status = AgentStatus.UnableToConnect;
                    return;
                }
                close_socket(workspace.agent_data.socket);
                workspace.agent_data.socket = socket;
                sent, sent_length = socket_send(workspace.agent_data.socket, r.data, r.length);
                if !sent {
                    workspace.agent_data.status = AgentStatus.Disconnected;
                    return;
                }
                carry = 0;
                continue;
            }

            if !string_is_empty(response_id) {
                free_allocation(response_id.data);
            }
            close_socket(workspace.agent_data.socket);
            workspace.agent_data.status = AgentStatus.Disconnected;
            return;
        }

        response: string = { length = length + carry; data = workspace.agent_data.response_buffer.data; }

        if !response_parsed {
            valid, index, http_response := parse_http_response(response);
            if valid {
                response_parsed = true;
                carry = 0;
                if http_response.transfer_encoding == "chunked" {
                    receiving_chunks = true;
                    response = { length = response.length - index; data = response.data + index; }
                }
                else {
                    break;
                }
            }
            else {
                carry = response.length;
            }
        }

        if receiving_chunks {
            i := 0;
            has_end_chunk := false;
            while i < response.length {
                valid, index, chunk_size := http_get_chunk_size(response, i);
                if !valid || index + chunk_size >= response.length {
                    carry = response.length - i;
                    memory_copy(workspace.agent_data.response_buffer.data, response.data + i, carry);
                    break;
                }

                carry = 0;
                i = index;

                if chunk_size {
                    chunk: string = { length = chunk_size; data = response.data + i; }
                    if starts_with(chunk, "event: ") {
                        event = parse_openai_event_name(chunk);
                    }
                    else if starts_with(chunk, "data: ") {
                        switch event {
                            case OpenAIResponseEvent.Created; {
                                if workspace.agent_data.buffer.line_count > 1 {

                                }
                                event_data := parse_json<OpenAIResponseEventData>(chunk, 6);
                                allocate_strings(&event_data.response.id);
                                response_id = event_data.response.id;
                            }
                            case OpenAIResponseEvent.OutputItemAdded; {
                                event_data := parse_json<OpenAIResponseEventData>(chunk, 6);
                                if event_data.item.type == OpenAIResponseOutputType.function_call {
                                    pointer := allocate_strings(&event_data.item.name, &event_data.item.call_id);
                                    name = event_data.item.name;
                                    call_id = event_data.item.call_id;
                                }
                            }
                            case OpenAIResponseEvent.ReasoningTextDelta; {
                                workspace.agent_data.status = AgentStatus.Thinking;
                                event_data := parse_json<OpenAIResponseEventData>(chunk, 6);
                                add_to_agent_buffer(workspace, event_data.delta, BufferLineFlags.Thinking);
                            }
                            case OpenAIResponseEvent.OutputTextDelta; {
                                workspace.agent_data.status = AgentStatus.Outputting;
                                event_data := parse_json<OpenAIResponseEventData>(chunk, 6);
                                add_to_agent_buffer(workspace, event_data.delta);
                            }
                            case OpenAIResponseEvent.ReasoningTextDone; {
                                workspace.agent_data.status = AgentStatus.ThinkingComplete;
                                add_to_agent_buffer(workspace, "\n", BufferLineFlags.Thinking);
                                add_to_agent_buffer(workspace, "\n");
                                trigger_window_update();
                            }
                            case OpenAIResponseEvent.FunctionCallArgumentsDone; {
                                event_data := parse_json<OpenAIResponseEventData>(chunk, 6);
                                arguments_pointer := allocate_strings(&event_data.arguments);
                                function_call: OpenAIResponseOutput = {
                                    name = name;
                                    call_id = call_id;
                                    arguments = event_data.arguments;
                                }
                                array_insert(&function_calls, function_call, allocate, reallocate);
                            }
                            case OpenAIResponseEvent.Completed; {
                                add_to_agent_buffer(workspace, "\n");
                            }
                        }
                    }
                    i += chunk_size + 2;
                }
                else {
                    has_end_chunk = true;
                    break;
                }
            }

            if has_end_chunk
                break;
        }
    }

    if !string_is_empty(workspace.agent_data.previous_response_id) {
        free_allocation(workspace.agent_data.previous_response_id.data);
    }

    workspace.agent_data = {
        status = AgentStatus.Done;
        previous_response_id = response_id;
    }
}

/*
load_models() {
    request: HTTPRequest = {
        version = HTTPVersion.HTTP1_1;
        method = HTTPMethod.GET;
        connection = HTTPConnection.Close;
        resource = "/v1/models";
        host = "evan-desktop.local";
        authorization = "Bearer sk-lm-Mukalw9D:ubAtA8TNXFzf7D5I6clm";
    }

    r := serialize_http_request(request);

    success, address_info := lookup_ip_address_tcp("evan-desktop.local", "1234");
    if success {
        defer close_ip_address(address_info);

        connected, socket := connect_socket(address_info);
        if connected {
            print("Connected to socket\n", socket);
            sent := socket_send(socket, r.data, r.length);
            print("Data sent %\n", sent);

            carry := 0;
            while true {
                length := socket_receive(socket, response_buffer.data + carry, response_buffer.length - carry);
                str: string = { length = length + carry; data = response_buffer.data; }

                valid, index, response := parse_http_response(str);
                if valid {
                    // print("Response: %\n", response);
                    models := parse_json<OpenAIModelResponse>(response.body);
                    print("Models: %\n", models);
                    break;
                }
                else {
                    carry = str.length;
                }
            }

            close_socket(socket);
        }
    }

    exit_program(0);
}
*/

bool, u64, u64 http_get_chunk_size(string text, u64 i) {
    size: u64;

    while i < text.length {
        char := text[i];
        if char == '\r' {
            if (i < text.length - 1) && text[i + 1] == '\n' {
                return true, i + 2, size;
            }
            break;
        }

        size *= 16;
        if char >= '0' && char <= '9' {
            size += char - '0';
        }
        else if char >= 'a' && char <= 'f' {
            size += char - 'a' + 10;

        }
        else if char >= 'A' && char <= 'F' {
            size += char - 'A' + 10;
        }
        else {
            break;
        }

        i++;
    }

    return false, i, 0;
}

string serialize_json<T>(T object) {
    #assert type_of(T).type == TypeKind.Struct;

    type := cast(StructTypeInfo*, type_of(T));

    buffer: Array<u8>[1000];
    string_buffer: StringBuffer = { buffer = buffer; }

    serialize_json(&object, type, &string_buffer);

    value: string;
    if string_buffer.length > string_buffer.buffer.length {
        value = { length = string_buffer.length; data = allocate(string_buffer.length); }
        string_buffer.length = 0;
        string_buffer.buffer.length = value.length;
        string_buffer.buffer.data = value.data;
        serialize_json(&object, type, &string_buffer);
    }
    else {
        value = { length = string_buffer.length; data = allocate(string_buffer.length); }
        memory_copy(value.data, buffer.data, string_buffer.length);
    }

    return value;
}

serialize_json(void* data, TypeInfo* type, StringBuffer* buffer) {
    if type == type_of(JsonSchema) {
        json_schema := *cast(JsonSchema*, data);
        add_char_to_string_buffer(buffer, '{');

        add_to_string_buffer(buffer, "\"type\":\"");
        add_to_string_buffer(buffer, json_schema.type);

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


T parse_json<T>(string text, u64 i = 0) {
    #assert type_of(T).type == TypeKind.Struct;

    result: T;

    type := cast(StructTypeInfo*, type_of(T));

    parse_json(text, i, &result, type);

    return result;
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
                        if char == '[' {
                            depth++;
                        }
                        else if char == ']' {
                            if depth == 0 break;
                            depth--;
                        }
                        else if char == '"' {
                            i, _ = get_json_string(text, i);
                        }

                        i++;
                    }
                }
                else if char == '{' {
                    i++;
                    depth := 0;
                    while i < text.length {
                        char = text[i];
                        if char == '{' {
                            depth++;
                        }
                        else if char == '}' {
                            if depth == 0 break;
                            depth--;
                        }
                        else if char == '"' {
                            i, _ = get_json_string(text, i);
                        }

                        i++;
                    }
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

struct OpenAIModelResponse {
    object: string;
    data: Array<OpenAIModel>;
}

struct OpenAIModel {
    id: string;
    object: string;
    created: u64;
    owned_by: string;
    shutdown_date: string;
}

struct OpenAIResponseRequest {
    model: string;
    input: string;
    [input]
    input_array: Array<OpenAIResponseOutput>;
    instructions: string;
    // max_output_tokens: u32;
    // max_tool_calls: u32;
    previous_response_id: string;
    reasoning: OpenAIResponseRequestReasoning;
    stream: bool;
    tool_choice: OpenAIResponseRequestToolChoice;
    tools: Array<OpenAIResponseRequestTool>;
}

struct OpenAIResponseRequestReasoning {
    effort: OpenAIResponseRequestReasoningEffort;
}

enum OpenAIResponseRequestReasoningEffort {
    none = 1;
    minimal;
    low;
    medium;
    high;
    xhigh;
    max;
}

enum OpenAIResponseRequestToolChoice {
    none = 1;
    auto;
    required;
}

struct OpenAIResponseRequestTool {
    type: string;
    name: string;
    description: string;
    strict: bool;
    parameters: JsonSchema;
}

struct JsonSchema {
    type: string;
    properties: Array<JsonSchemaProperty>;
    required: Array<string>;
    additionalProperties: bool;
}

struct JsonSchemaProperty {
    name: string;
    type: JsonSchemaPropertyType;
    description: string;
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

struct OpenAIResponse {
    id: string;
    created_at: u64;
    error: OpenAIResponseError;
    model: string;
    output: Array<OpenAIResponseOutput>;
    top_p: float;
    completed_at: u64;
    max_output_tokens: u32;
    max_tool_calls: u32;
    status: OpenAIResponseStatus;
    usage: OpenAIResponseUsage;
}

struct OpenAIResponseError {
    code: string;
    message: string;
}

struct OpenAIResponseOutput {
    id: string;
    type: OpenAIResponseOutputType;
    role: string;
    status: OpenAIResponseOutputStatus;

    // Message fields
    content: Array<OpenAIResponseOutputContent>;

    // Function call fields
    name: string;
    call_id: string;
    arguments: string;

    // Function call output fields
    output: string;
}

enum OpenAIResponseOutputType {
    message = 1;
    reasoning;
    function_call;
    function_call_output;
}

enum OpenAIResponseOutputStatus {
    in_progress = 1;
    completed;
    incomplete;
}

enum OpenAIResponseStatus {
    in_progress = 1;
    queued;
    failed;
    cancelled;
    incomplete;
    completed;
}

struct OpenAIResponseOutputContent {
    type: string;
    text: string;
}

struct OpenAIResponseUsage {
    input_tokens: u32;
    input_token_details: OpenAIResponseUsageInputDetails;
    output_tokens: u32;
    output_token_details: OpenAIResponseUsageOutputDetails;
    total_tokens: u32;
}

struct OpenAIResponseUsageInputDetails {
    cached_tokens: u32;
    cache_write_tokens: u32;
}

struct OpenAIResponseUsageOutputDetails {
    reasoning_tokens: u32;
}

enum OpenAIResponseEvent {
    None;
    Created;
    InProgress;
    OutputItemAdded;
    OutputItemDone;
    ContentPartAdded;
    ContentPartDone;
    ReasoningTextDelta;
    ReasoningTextDone;
    OutputTextDelta;
    OutputTextDone;
    FunctionCallArgumentsDone;
    Completed;
}

struct OpenAIResponseEventData {
    type: string;
    response: OpenAIResponse;
    item: OpenAIResponseOutput;
    item_id: string;
    output_index: u32;
    content_index: u32;
    delta: string;
    arguments: string;
    call_id: string;
    name: string;
    sequence_number: u32;
}

#private

bool socket_is_connected(Socket socket) {
    connected: bool;

    #if os == OS.Linux {
        connected = socket.socket > 0;
    }
    #if os == OS.Windows {
        connected = socket.socket != null;
    }

    if connected {
        byte: u8;
        success, bytes := socket_send(socket, &byte, 0);
        connected = success;
    }

    return connected;
}

bool, Socket connect_to_socket_with_retry(string domain, string port) {
    socket: Socket;
    success, address_info := lookup_address(domain, port);
    if !success return false, socket;

    each i in 5 {
        success, socket = connect_socket(address_info);
        if success break;
        sleep(500);
    }

    return success, socket;
}

struct AddressInfoRecord {
    domain: string;
    port: string;
    address_info: AddressInfo;
}

address_infos: Array<AddressInfoRecord>;

bool, AddressInfo lookup_address(string domain, string port) {
    each record in address_infos {
        if record.domain == domain && record.port == port {
            return true, record.address_info;
        }
    }

    success, address_info := lookup_ip_address_tcp(domain, port);
    if success {
        record: AddressInfoRecord = {
            domain = domain; port = port; address_info = address_info;
        }
        array_insert(&address_infos, record, allocate, reallocate);
    }

    return success, address_info;
}

string get_agent_title() {
    workspace := get_workspace();

    switch workspace.agent_data.status {
        case AgentStatus.Ready;            return "Ready";
        case AgentStatus.UnableToConnect;  return "Unable to connect";
        case AgentStatus.Disconnected;     return "Disconnected";
        case AgentStatus.Pending;          return "Pending...";
        case AgentStatus.Thinking;         return "Thinking...";
        case AgentStatus.ThinkingComplete; return "Pending...";
        case AgentStatus.Outputting;       return "Outputting...";
        case AgentStatus.FunctionCall;     return "Calling functions";
        case AgentStatus.Done;             return "Finished";
    }

    return empty_string;
}

add_to_agent_buffer(Workspace* workspace, string text, BufferLineFlags flags = BufferLineFlags.None) {
    original_line := workspace.agent_data.buffer_window.line;
    original_line_count := workspace.agent_data.buffer.line_count;

    line := add_text_to_end_of_buffer(&workspace.agent_data.buffer, text, false, flags);

    both_windows_open := workspace.left_window.displayed && workspace.right_window.displayed;
    max_chars: u32;
    if both_windows_open {
        max_chars = global_font_config.max_chars_per_line - workspace.agent_data.buffer.line_count_digits - 1;
    }
    else {
        max_chars = global_font_config.max_chars_per_line_full - workspace.agent_data.buffer.line_count_digits - 1;
    }

    if original_line == original_line_count - 1 {
        if original_line_count != workspace.agent_data.buffer.line_count {
            workspace.agent_data.buffer_window.line = workspace.agent_data.buffer.line_count - 1;
            adjust_start_line(&workspace.agent_data.buffer_window, workspace, !workspace.agent_data.display_thinking);
        }
        else if line.length > max_chars {
            adjust_start_line(&workspace.agent_data.buffer_window, workspace, !workspace.agent_data.display_thinking);
        }
    }

    trigger_window_update();
}

OpenAIResponseEvent parse_openai_event_name(string chunk) {
    start := 7;
    while start < chunk.length && is_whitespace(chunk[start]) {
        start++;
    }

    event_name: string = { data = chunk.data + start; }
    while start < chunk.length && !is_whitespace(chunk[start++]) {
        event_name.length++;
    }

    name_parts := split_string(event_name, '.');
    assert(name_parts.length >= 2);

    event := OpenAIResponseEvent.None;
    if name_parts[1] == "created" {
        event = OpenAIResponseEvent.Created;
    }
    else if name_parts[1] == "in_progress" {
        event = OpenAIResponseEvent.InProgress;
    }
    else if name_parts[1] == "output_item" {
        assert(name_parts.length >= 3);
        if name_parts[2] == "added" {
            event = OpenAIResponseEvent.OutputItemAdded;
        }
        else if name_parts[2] == "done" {
            event = OpenAIResponseEvent.OutputItemDone;
        }
    }
    else if name_parts[1] == "content_part" {
        assert(name_parts.length >= 3);
        if name_parts[2] == "added" {
            event = OpenAIResponseEvent.ContentPartAdded;
        }
        else if name_parts[2] == "done" {
            event = OpenAIResponseEvent.ContentPartDone;
        }
    }
    else if name_parts[1] == "reasoning_text" {
        assert(name_parts.length >= 3);
        if name_parts[2] == "delta" {
            event = OpenAIResponseEvent.ReasoningTextDelta;
        }
        else if name_parts[2] == "done" {
            event = OpenAIResponseEvent.ReasoningTextDone;
        }
    }
    else if name_parts[1] == "output_text" {
        assert(name_parts.length >= 3);
        if name_parts[2] == "delta" {
            event = OpenAIResponseEvent.OutputTextDelta;
        }
        else if name_parts[2] == "done" {
            event = OpenAIResponseEvent.OutputTextDone;
        }
    }
    else if name_parts[1] == "function_call_arguments" {
        assert(name_parts.length >= 3);
        if name_parts[2] == "done" {
            event = OpenAIResponseEvent.FunctionCallArgumentsDone;
        }
    }
    else if name_parts[1] == "completed" {
        event = OpenAIResponseEvent.Completed;
    }

    return event;
}

ssl_initialized := false;

init_ssl_job(int index, JobData data) {

    CRYPTO_set_mem_functions(CRYPTO_malloc_impl, CRYPTO_realloc_impl, CRYPTO_free_impl);

    cacert := temp_string(get_program_directory(), "/cacert.pem");
    ssl_context = initialize_openssl(OpenSSLMethod.Client, cacert);
    assert(ssl_context != null, "Unable to initialize OpenSSL context");

    ssl_initialized = true;
}

ssl_context: SSL_CTX*;

void* CRYPTO_malloc_impl(u64 num, u8* file, int line) {
    str := convert_c_string(file);
    return allocate(num);
}

void* CRYPTO_realloc_impl(void* addr, u64 num, u8* file, int line) {
    str := convert_c_string(file);
    if addr == null return allocate(num);

    block := cast(MemoryBlock*, addr) - 1;
    return reallocate(addr, block.size, num);
}

CRYPTO_free_impl(void* addr, u8* file, int line) {
    str := convert_c_string(file);
    free_allocation(addr);
}
