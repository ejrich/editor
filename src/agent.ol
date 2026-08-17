#import openssl

init_ssl() {
    CRYPTO_set_mem_functions(CRYPTO_malloc_impl, CRYPTO_realloc_impl, CRYPTO_free_impl);

    cacert := temp_string(get_program_directory(), "/cacert.pem");
    ssl_context = initialize_openssl(OpenSSLMethod.Client, cacert);
    assert(ssl_context != null, "Unable to initialize OpenSSL context");

    // test_stream();
    load_models();
}

deinit_ssl() {
    SSL_CTX_free(ssl_context);
}

test_stream() {
    request: HTTPRequest = {
        version = HTTPVersion.HTTP1_1;
        method = HTTPMethod.POST;
        connection = HTTPConnection.KeepAlive;
        resource = "/v1/responses";
        host = "evan-desktop.local";
        authorization = "Bearer sk-lm-Mukalw9D:ubAtA8TNXFzf7D5I6clm";
        content_type = "application/json";
        body = "{ \"model\": \"google/gemma-4-26b-a4b-qat\", \"input\": \"hello world\", \"stream\": true }";
    }

    r := serialize_http_request(request);
    print("% %", r.length, r);

    success, address_info := lookup_ip_address_tcp("evan-desktop.local", "1234");
    if success {
        defer close_ip_address(address_info);

        connected, socket := connect_socket(address_info);
        if connected {
            print("Connected to socket\n", socket);
            sent := socket_send(socket, r.data, r.length);
            print("Data sent %\n", sent);

            response_parsed := false;
            receiving_chunks := true;
            carry := 0;
            while true {
                length := socket_receive(socket, response_buffer.data + carry, response_buffer.length - carry);
                str: string = { length = length + carry; data = response_buffer.data; }

                chunk_start := 0;
                if !response_parsed {
                    valid, index, response := parse_http_response(str);
                    if valid {
                        print("Response: %\n", response);

                        response_parsed = true;
                        carry = 0;
                        if response.transfer_encoding == "chunked" {
                            receiving_chunks = true;
                            chunk_start = index;
                        }
                        else {
                            break;
                        }
                    }
                    else {
                        carry = str.length;
                    }
                }

                if receiving_chunks {
                    str = { length = str.length - chunk_start; data = str.data + chunk_start; }

                    i := 0;
                    has_end_chunk := false;
                    while i < str.length {
                        valid, index, chunk_size := http_get_chunk_size(str, i);
                        if !valid {
                            memory_copy(response_buffer.data, str.data + i, carry);
                            print("Unable to determine the chunk size\n");
                            break;
                        }

                        if index + chunk_size >= str.length {
                            carry = str.length - i;
                            memory_copy(response_buffer.data, str.data + i, carry);
                            print("Carrying chunk into the next buffer read\n");
                            break;
                        }

                        carry = 0;
                        i = index;

                        if valid {
                            if chunk_size {
                                chunk: string = { length = chunk_size; data = str.data + i; }
                                print("Chunk Size: %, Data: '%'\n", chunk_size, chunk);
                                i += chunk_size + 2;
                            }
                            else {
                                print("End Chunk\n");
                                has_end_chunk = true;
                                break;
                            }
                        }
                    }

                    if has_end_chunk
                        break;
                }
            }

            close_socket(socket);
        }
    }

    exit_program(0);
}

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

response_buffer: Array<u8>[2000];


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
    input: string; // TODO Add support for input arrays
    instructions: string;
    max_output_tokens: u32;
    max_tool_calls: u32;
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
    none;
    minimal;
    low;
    medium;
    high;
    xhigh;
    max;
}

struct OpenAIResponseRequestTool {
    type: string;
    name: string;
    description: string;
    strict: bool;
    parameters: OpenAIResponseRequestToolParameters;
}

struct OpenAIResponseRequestToolParameters {
    type: string;
    parameters: Any;
    required: Array<string>;
    additionalProperties: bool;
}

enum OpenAIResponseRequestToolChoice {
    auto;
    none;
    required;
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
    arguments: Any; // TODO Figure this out
}

enum OpenAIResponseOutputType {
    None;
    message;
    reasoning;
    function_call;
    function_call_output;
}

enum OpenAIResponseOutputStatus {
    in_progress;
    completed;
    incomplete;
}

enum OpenAIResponseStatus {
    in_progress;
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

struct OpenAIResponseEventData {
    type: string;
    response: OpenAIResponse;
    item_id: string;
    output_index: u32;
    content_index: u32;
    delta: string;
    sequence_number: u32;
}

#private

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
