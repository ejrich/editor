struct ToolSchema {
    type: ToolSchemaType;
    name: string;
    description: string;
    strict: bool;
    parameters: JsonSchema;
    output_schema: JsonSchema;
}

enum ToolSchemaType {
    function = 1;
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

struct ReadFileOutput {
    file: string;
    text: string;
}

[tool, "Reads the entire text of a requested file"]
string, bool read_file_text(Workspace* workspace, ReadFileArguments args, ReadFileOutput output) {
    print("Read file\n");
    return "Test", false;
}

struct ReadFileLineArguments {
    file: string;
    start: u32;
    end: u32;
}

struct ReadFileLinesOutput {
    file: string;
    start_line: u32;
    end_line: u32;
    text: string;
}

[tool, "Reads a block of lines from a requested file"]
string, bool read_file_lines(Workspace* workspace, ReadFileLineArguments args, ReadFileLinesOutput output) {
    print("Read file lines\n");
    return "Test", false;
}
