#import openssl

init_ssl() {
    CRYPTO_set_mem_functions(CRYPTO_malloc_impl, CRYPTO_realloc_impl, CRYPTO_free_impl);

    cacert := temp_string(get_program_directory(), "/cacert.pem");
    ssl_context = initialize_openssl(OpenSSLMethod.Client, cacert);
    assert(ssl_context != null, "Unable to initialize OpenSSL context");

    // test_stream();
    // load_models();
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
                    print("Response: %\n", response);
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

    type := type_of(T);

    in_object := false;
    while i < text.length {
        char := text[i];
        if char == '{' {
            if !in_object {
                in_object = true;
            }
            else {
                break;
            }
        }
        else if char == '\"' {
            // TODO Implement
            // - Parse the name of the property
            // - Get the type
            //   - If the field is not there, skip to the next property
            //   - If the field is in the type, parse based on the type
            //     - bool: true or false/null
            //     - string: Take starting from the next " to the next unescaped "
            //     - integer or float: Add the next chars until the next ,/}/]
            //     - enum: Get the string then look up the value
            //     - struct: Call parse_json using the field type
            //     - Array: Start at the next [, use this function to get the next value and array_insert, ignore if null
            //     - otherwise assert(false)
        }

        i++;
    }

    return result;
}

struct OpenAIModelResponse {
    object: string;
    list: Array<OpenAIModel>;
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
