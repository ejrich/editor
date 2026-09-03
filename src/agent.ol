#import openssl
#import "json.ol"
#import "tools.ol"

init_agent() {
    queue_work(&low_priority_queue, load_models_job);
}

deinit_agent() {
    if ssl_initialized {
        SSL_CTX_free(ssl_context);
    }
}

agent_settings: Array<AgentSettings>;

struct AgentSettings {
    url: string;
    token: string;
    type: AgentType;
}

enum AgentType {
    OpenAI = 1;
    // @Future Implement these APIs
    Anthropic;
    Google;
}

models: Array<AgentModel>;
models_loaded := false;

struct AgentModel {
    api: u32;
    name: string;
}

open_models_list() {
    change_model_filter(empty_string);
    start_list_mode("Models", get_models, get_model_count, null, change_model_filter, null, select_model);
}

struct AgentData {
    buffer: Buffer = { read_only = true; title = get_agent_title; }
    buffer_window: BufferWindow;
    model: int = -1;
    socket: Socket;
    ssl: SSL*;
    // TODO Use single buffer for this
    request_body_buffer: Array<u8>;
    request_buffer: Array<u8>;
    response_buffer: Array<u8>;
    status: AgentStatus;
    display_thinking: bool;
    previous_response_id: string;
    context: u32;
    cancel: bool;
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
    Cancelled;
    Done;
}

// TODO Prevent multiple requests at the same time
send_agent_message(int thread, JobData data) {
    defer trigger_window_update();

    message := data.multiple.value1;
    workspace := cast(Workspace*, data.multiple.value2);
    defer free_allocation(message.data);

    model_index := workspace.agent_data.model;
    if model_index < 0 || model_index >= models.length || !models_loaded return;

    workspace.agent_data.status = AgentStatus.Ready;

    if workspace.agent_data.buffer.line_count > 1
        add_agent_buffer_new_lines(workspace, 1);
    add_to_agent_buffer(workspace, message, BufferLineFlags.Message);
    add_agent_buffer_new_lines(workspace, 2);

    model := models[model_index];
    model_settings := agent_settings[model.api];
    use_ssl, domain, port := parse_url(model_settings.url);

    request_text := build_agent_request(workspace, model, domain, workspace.agent_data.previous_response_id, message);

    if !send_agent_request(workspace, use_ssl, domain, port, request_text) {
        return;
    }

    workspace.agent_data.status = AgentStatus.Pending;
    trigger_window_update();

    response_parsed := false;
    receiving_chunks := false;
    carry := 0;
    event := OpenAIResponseEvent.None;

    response_id: string;

    function_calls: Array<FunctionCall>;
    name: string;
    call_id: string;

    while workspace.agent_data.status != AgentStatus.Cancelled {
        if carry == workspace.agent_data.response_buffer.length {
            resize_buffer(&workspace.agent_data.response_buffer, carry + 1000);
        }

        received: bool;
        length: u64;
        if use_ssl {
            received, length = socket_receive_ssl(workspace.agent_data.ssl, workspace.agent_data.response_buffer.data + carry, workspace.agent_data.response_buffer.length - carry);
        }
        else {
            length_s32: s32;
            received, length_s32 = socket_receive(workspace.agent_data.socket, workspace.agent_data.response_buffer.data + carry, workspace.agent_data.response_buffer.length - carry);
            length = length_s32;
        }

        if !received {
            // Reconnect and resend if the socket was closed
            if !response_parsed {
                if !send_agent_request(workspace, use_ssl, domain, port, request_text, true) {
                    return;
                }
                carry = 0;
                continue;
            }

            if !string_is_empty(response_id) {
                free_allocation(response_id.data);
            }
            close_and_clear_socket(workspace, use_ssl);
            workspace.agent_data.status = AgentStatus.Disconnected;
            return;
        }

        if workspace.agent_data.status == AgentStatus.Cancelled break;

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
                    response_object := parse_json<OpenAIResponse>(http_response.body);
                    allocate_strings(&response_object.id);
                    response_id = response_object.id;

                    each output in response_object.output {
                        switch output.type {
                            case OpenAIResponseOutputType.message;
                            case OpenAIResponseOutputType.reasoning; {
                                each content in output.content {
                                    switch content.type {
                                        case OpenAIResponseOutputContentType.output_text; {
                                            add_to_agent_buffer(workspace, content.text);
                                            add_agent_buffer_new_lines(workspace, 1);
                                        }
                                        case OpenAIResponseOutputContentType.reasoning_text; {
                                            add_to_agent_buffer(workspace, content.text, BufferLineFlags.Thinking);
                                            add_agent_buffer_new_lines(workspace, 2);
                                        }
                                    }
                                }
                            }
                            case OpenAIResponseOutputType.function_call; {
                                allocate_strings(&output.name, &output.call_id);
                                allocate_strings(&output.arguments);
                                function_call: FunctionCall = {
                                    name = output.name;
                                    call_id = output.call_id;
                                    arguments = output.arguments;
                                }
                                array_insert(&function_calls, function_call, allocate, reallocate);
                            }
                        }

                        if output.content.length
                            free_allocation(output.content.data);
                    }

                    if response_object.output.length
                        free_allocation(response_object.output.data);

                    workspace.agent_data.context = response_object.usage.total_tokens;
                }
            }
            else {
                carry = response.length;
            }
        }

        has_end_chunk := false;
        if receiving_chunks {
            i := 0;
            while i < response.length {
                if workspace.agent_data.status == AgentStatus.Cancelled break;

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
                        event_data := parse_json<OpenAIResponseEventData>(chunk, 6);
                        switch event {
                            case OpenAIResponseEvent.OutputItemAdded; {
                                if event_data.item.type == OpenAIResponseOutputType.function_call {
                                    pointer := allocate_strings(&event_data.item.name, &event_data.item.call_id);
                                    name = event_data.item.name;
                                    call_id = event_data.item.call_id;
                                }
                            }
                            case OpenAIResponseEvent.ReasoningTextDelta; {
                                workspace.agent_data.status = AgentStatus.Thinking;
                                add_to_agent_buffer(workspace, event_data.delta, BufferLineFlags.Thinking);
                            }
                            case OpenAIResponseEvent.OutputTextDelta; {
                                workspace.agent_data.status = AgentStatus.Outputting;
                                add_to_agent_buffer(workspace, event_data.delta);
                            }
                            case OpenAIResponseEvent.ReasoningTextDone; {
                                workspace.agent_data.status = AgentStatus.ThinkingComplete;
                                add_agent_buffer_new_lines(workspace, 2);
                                trigger_window_update();
                            }
                            case OpenAIResponseEvent.FunctionCallArgumentsDone; {
                                allocate_strings(&event_data.arguments);
                                function_call: FunctionCall = {
                                    name = name;
                                    call_id = call_id;
                                    arguments = event_data.arguments;
                                }
                                array_insert(&function_calls, function_call, allocate, reallocate);
                            }
                            case OpenAIResponseEvent.Completed; {
                                allocate_strings(&event_data.response.id);
                                response_id = event_data.response.id;
                                workspace.agent_data.context = event_data.response.usage.total_tokens;
                                add_agent_buffer_new_lines(workspace, 1);
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
        }

        if (receiving_chunks && has_end_chunk) || (!receiving_chunks && response_parsed) {
            if function_calls.length {
                request_text = handle_function_calls(workspace, model, domain, response_id, function_calls);

                function_calls.length = 0;
                free_allocation(function_calls.data);
                response_id.length = 0;
                free_allocation(response_id.data);

                if !send_agent_request(workspace, use_ssl, domain, port, request_text) {
                    return;
                }

                receiving_chunks = false;
                response_parsed = false;
                carry = 0;
                event = OpenAIResponseEvent.None;
            }
            else {
                break;
            }
        }
    }

    if workspace.agent_data.status == AgentStatus.Cancelled {
        close_and_clear_socket(workspace, use_ssl);
        return;
    }

    if !string_is_empty(workspace.agent_data.previous_response_id) {
        free_allocation(workspace.agent_data.previous_response_id.data);
    }

    workspace.agent_data = {
        previous_response_id = response_id;
        status = AgentStatus.Done;
    }
}

resize_buffer(Array<u8>* buffer, u64 new_length) {
    previous_length := buffer.length;

    new_buffer := allocate(new_length);
    if buffer.length {
        memory_copy(new_buffer, buffer.data, previous_length);
        free_allocation(buffer.data);
    }

    buffer.data = new_buffer;
    buffer.length = new_length;
}


// OpenAI Contracts
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
    tools: Array<ToolSchema>;
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

struct OpenAIResponseWithoutOutput {
    id: string;
    error: OpenAIResponseError;
    model: string;
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
    type: OpenAIResponseOutputContentType;
    text: string;
}

enum OpenAIResponseOutputContentType {
    output_text = 1;
    reasoning_text;
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
    response: OpenAIResponseWithoutOutput;
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

// Agent functions
struct FunctionCall {
    name: string;
    call_id: string;
    arguments: string;
}

string handle_function_calls(Workspace* workspace, AgentModel model, string domain, string response_id, Array<FunctionCall> function_calls) {
    function_call_allocations: Array<bool>[function_calls.length];
    function_call_outputs: Array<OpenAIResponseOutput>[function_calls.length];

    each function_call, i in function_calls {
        result, allocated := call_function(workspace, function_call);
        function_call_outputs[i] = {
            type = OpenAIResponseOutputType.function_call_output;
            call_id = function_calls[i].call_id;
            output = result;
        }
        function_call_allocations[i] = allocated;
    }

    request_text := build_agent_request(workspace, model, domain, response_id, function_call_outputs);

    each i in function_calls.length {
        if function_call_allocations[i] {
            free_allocation(function_call_outputs[i].output.data);
        }

        free_allocation(function_calls[i].name.data);
        free_allocation(function_calls[i].arguments.data);
    }

    return request_text;
}

string, bool call_function(Workspace* workspace, FunctionCall function_call) {
    result: string;
    allocated: bool;

    each tool in tools {
        if tool.name == function_call.name {
            result, allocated = tool.call(workspace, function_call.arguments);
            break;
        }
    }

    return result, allocated;
}

string build_agent_request(Workspace* workspace, AgentModel model, string domain, string response_id, string message = empty_string, Params<OpenAIResponseOutput> function_call_output) {
    responses_request: OpenAIResponseRequest = {
        model = model.name;
        instructions = "Do not use latex in the output and make the output text easy to read without formatting.";
        input = message;
        input_array = function_call_output;
        stream = true;
    }

    if !string_is_empty(response_id) {
        responses_request.previous_response_id = response_id;
    }
    else {
        responses_request.tools = tool_schemas;
    }

    body := serialize_json(responses_request, &workspace.agent_data.request_body_buffer);

    model_settings := agent_settings[model.api];

    request: HTTPRequest = {
        version = HTTPVersion.HTTP1_1;
        method = HTTPMethod.POST;
        connection = HTTPConnection.KeepAlive;
        resource = "/v1/responses";
        host = domain;
        content_type = "application/json";
        body = body;
    }

    if !string_is_empty(model_settings.token) {
        request.authorization = temp_string("Bearer ", model_settings.token);
    }

    return serialize_http_request(request, allocate_from_request_buffer, workspace);
}

bool send_agent_request(Workspace* workspace, bool use_ssl, string domain, string port, string request_text, bool close = false) {
    workspace.agent_data.status = AgentStatus.Ready;

    if close || !socket_is_connected(workspace.agent_data.socket) {
        success, socket := connect_to_socket_with_retry(domain, port);
        if !success {
            close_and_clear_socket(workspace, use_ssl);
            workspace.agent_data.status = AgentStatus.UnableToConnect;
            return false;
        }

        close_socket(workspace.agent_data.socket);
        workspace.agent_data.socket = socket;

        if use_ssl {
            init_ssl();
            SSL_free(workspace.agent_data.ssl);

            ssl_success, ssl := connect_socket_openssl(socket, domain, ssl_context);
            if !ssl_success {
                close_and_clear_socket(workspace, use_ssl);
                workspace.agent_data.status = AgentStatus.UnableToConnect;
                return false;
            }

            workspace.agent_data.ssl = ssl;
        }
    }

    sent: bool;
    sent_length: u64;
    if use_ssl {
        sent, sent_length = socket_send_ssl(workspace.agent_data.ssl, request_text.data, request_text.length);
    }
    else {
        sent_length_s32: s32;
        sent, sent_length_s32 = socket_send(workspace.agent_data.socket, request_text.data, request_text.length);
        sent_length = sent_length_s32;
    }

    if !sent {
        close_and_clear_socket(workspace, use_ssl);
        workspace.agent_data.status = AgentStatus.Disconnected;
    }

    return sent;
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

// Models
load_models_job(int thread, JobData data) {
    models_loaded = false;

    if models.length {
        each model in models {
            free_allocation(model.name.data);
        }

        free_allocation(models.data);
        models.length = 0;
    }

    each setting, i in agent_settings {
        use_ssl, domain, port := parse_url(setting.url);

        request: HTTPRequest = {
            version = HTTPVersion.HTTP1_1;
            method = HTTPMethod.GET;
            connection = HTTPConnection.Close;
            resource = "/v1/models";
            host = domain;
        }

        if !string_is_empty(setting.token) {
            request.authorization = temp_string("Bearer ", setting.token);
        }

        workspace := get_workspace();
        request_text := serialize_http_request(request, allocate_from_request_buffer, workspace);

        success, socket := connect_to_socket_with_retry(domain, port);
        ssl: SSL*;

        if !success continue;

        if use_ssl {
            init_ssl();
            success, ssl = connect_socket_openssl(socket, domain, ssl_context);
            if !success {
                close_socket(socket);
                continue;
            }
        }

        sent: u64;
        if use_ssl {
            success, sent = socket_send_ssl(ssl, request_text.data, request_text.length);
        }
        else {
            sent_s32: s32;
            success, sent_s32 = socket_send(socket, request_text.data, request_text.length);
            sent = sent_s32;
        }

        if !success {
            close_socket(socket);
            if use_ssl SSL_free(ssl);
            continue;
        }

        carry := 0;
        while true {
            if carry == workspace.agent_data.response_buffer.length {
                resize_buffer(&workspace.agent_data.response_buffer, carry + 1000);
            }

            received: bool;
            length: u64;
            if use_ssl {
                received, length = socket_receive_ssl(ssl, workspace.agent_data.response_buffer.data + carry, workspace.agent_data.response_buffer.length - carry);
            }
            else {
                length_s32: s32;
                received, length_s32 = socket_receive(socket, workspace.agent_data.response_buffer.data + carry, workspace.agent_data.response_buffer.length - carry);
                length = length_s32;
            }

            response_text: string = { length = length + carry; data = workspace.agent_data.response_buffer.data; }

            valid, index, response := parse_http_response(response_text);
            if valid {
                model_list := parse_json<OpenAIModelResponse>(response.body);
                agent_model: AgentModel = { api = i; }

                each model in model_list.data {
                    if string_is_empty(model.shutdown_date) {
                        allocate_strings(&model.id);
                        agent_model.name = model.id;
                        array_insert(&models, agent_model, allocate, reallocate);
                    }
                }

                if model_list.data.length {
                    free_allocation(model_list.data.data);
                }
                break;
            }
            else {
                carry = response_text.length;
            }
        }

        close_socket(socket);
        if use_ssl {
            SSL_free(ssl);
        }
    }

    models_loaded = true;
}


Array<ListEntry> get_models() {
    return model_entries;
}

int get_model_count() {
    return models.length;
}

change_model_filter(string filter) {
    if models.length > model_entries_reserved {
        while model_entries_reserved < models.length {
            model_entries_reserved += model_entries_block_size;
        }

        reallocate_array(&model_entries, model_entries_reserved);
    }

    if string_is_empty(filter) {
        model_entries.length = models.length;
        each model, i in models {
            model_entries[i] = {
                key = i;
                name = model.name;
            }
        }
    }
    else {
        model_entries.length = 0;
        each model, i in models {
            if string_contains(model.name, filter, false) {
                model_entries[model_entries.length++] = {
                    key = i;
                    name = model.name;
                }
            }
        }
    }
}

select_model(int key) {
    workspace := get_workspace();
    workspace.agent_data.model = key;
    // @Future handle changing provider
}

model_entries: Array<ListEntry>;
model_entries_reserved := 0;
model_entries_block_size := 10; #const


// HTTP helpers
bool, string, string parse_url(string url) {
    ssl: bool;
    domain, port: string;
    if starts_with(url, "https://") {
        url.length -= 8;
        url.data += 8;
        ssl = true;
    }
    else if starts_with(url, "http://") {
        url.length -= 7;
        url.data += 7;
    }

    parts := split_string(url, ':');
    if parts.length == 1 {
        domain = parts[0];
        if ssl port = "443";
        else   port = "80";
    }
    else if parts.length >= 2 {
        domain = parts[0];
        port = parts[1];
    }

    return ssl, domain, port;
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

void* allocate_from_request_buffer(u64 length, void* data) {
    workspace := cast(Workspace*, data);

    if workspace.agent_data.request_buffer.length < length {
        increment_size := 1000; #const
        new_size := workspace.agent_data.request_buffer.length + increment_size;
        while new_size < length {
            new_size += increment_size;
        }

        resize_buffer(&workspace.agent_data.request_buffer, new_size);
    }

    return workspace.agent_data.request_buffer.data;
}


// Sockets
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

close_and_clear_socket(Workspace* workspace, bool use_ssl) {
    close_socket(workspace.agent_data.socket);

    if use_ssl && workspace.agent_data.ssl != null {
        SSL_free(workspace.agent_data.ssl);
        workspace.agent_data.ssl = null;
    }

    #if os == OS.Linux {
        workspace.agent_data.socket.socket = 0;
    }
    #if os == OS.Windows {
        workspace.agent_data.socket.socket = null;
    }
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


// Agent buffer functions
string get_agent_title() {
    workspace := get_workspace();

    title: string;
    switch workspace.agent_data.status {
        case AgentStatus.Ready;            title = "Ready";
        case AgentStatus.UnableToConnect;  title = "Unable to connect";
        case AgentStatus.Disconnected;     title = "Disconnected";
        case AgentStatus.Pending;          title = "Pending...";
        case AgentStatus.Thinking;         title = "Thinking...";
        case AgentStatus.ThinkingComplete; title = "Pending...";
        case AgentStatus.Outputting;       title = "Outputting...";
        case AgentStatus.FunctionCall;     title = "Calling functions";
        case AgentStatus.Cancelled;        title = "Cancelled";
        case AgentStatus.Done;             title = "Finished";
    }

    model: string;
    if workspace.agent_data.model < 0 || workspace.agent_data.model >= models.length {
        model = "No model selected";
    }
    else {
        model = models[workspace.agent_data.model].name;
    }

    return format_string("% | Context: % | %", temp_allocate, model, workspace.agent_data.context, title);
}

add_agent_buffer_new_lines(Workspace* workspace, u32 count) {
    original_line := workspace.agent_data.buffer_window.line;
    original_line_count := workspace.agent_data.buffer.line_count;

    buffer := &workspace.agent_data.buffer;
    end_line := get_buffer_line(buffer, buffer.line_count - 1);
    each i in count {
        end_line = add_new_line(null, buffer, end_line, false, false);
    }

    adjust_agent_window(workspace, end_line, original_line, original_line_count);
}

add_to_agent_buffer(Workspace* workspace, string text, BufferLineFlags flags = BufferLineFlags.None) {
    original_line := workspace.agent_data.buffer_window.line;
    original_line_count := workspace.agent_data.buffer.line_count;

    line := add_text_to_end_of_buffer(&workspace.agent_data.buffer, text, false, flags);

    adjust_agent_window(workspace, line, original_line, original_line_count);
}

adjust_agent_window(Workspace* workspace, BufferLine* line, u32 original_line, u32 original_line_count) {
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


// SSL
ssl_initializing := false;
ssl_initialized := false;
ssl_context: SSL_CTX*;

init_ssl() {
    if !ssl_initialized {
        if !ssl_initializing && compare_exchange(&ssl_initializing, true, false) == false {
            CRYPTO_set_mem_functions(CRYPTO_malloc_impl, CRYPTO_realloc_impl, CRYPTO_free_impl);

            cacert := temp_string(get_program_directory(), "/cacert.pem");
            ssl_context = initialize_openssl(OpenSSLMethod.Client, cacert);
            assert(ssl_context != null, "Unable to initialize OpenSSL context");

            ssl_initialized = true;
        }
        else {
            while !ssl_initialized {
                sleep(1);
            }
        }
    }
}

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
