struct ToolSchema {
    type: ToolSchemaType;
    name: string;
    description: string;
    strict: bool;
    parameters: JsonSchema;
}

enum ToolSchemaType {
    function;
}

interface string, bool ToolCall(Workspace* workspace, string arguments)

struct Tool {
    name: string;
    call: ToolCall;
}

tools: Array<Tool>;
tool_schemas: Array<ToolSchema>;

struct ReadFileArguments {
    file: string;
}

[tool, "Reads the entire text of a requested file"]
string, bool read_file_text(Workspace* workspace, ReadFileArguments args) {
    print("Read file\n");
    return "Test", false;
}

struct ReadFileLineArguments {
    file: string;
    start: u32;
    end: u32;
}

[tool, "Reads a block of lines from a requested file"]
string, bool read_file_lines(Workspace* workspace, ReadFileLineArguments args) {
    print("Read file lines\n");
    return "Test", false;
}

// TODO Implement the rest of the tools
