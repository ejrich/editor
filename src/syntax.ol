Syntax* get_syntax_for_file(string file_path) {
    extension_start := file_path.length;
    each i in file_path.length {
        if file_path[i] == '.' {
            extension_start = i + 1;
        }
    }

    result: Syntax*;
    if extension_start + 1 < file_path.length {
        extension: string = {
            length = file_path.length - extension_start;
            data = file_path.data + extension_start;
        }

        result = get_syntax_for_extension(extension);
    }

    return result;
}

Syntax* get_syntax_for_extension(string extension) {
    each syntax in syntax_configurations {
        if syntax.extension == extension {
            return &syntax;
        }
    }

    return null;
}


struct Syntax {
    extension: string;
    line_color_modifiers: Array<LineColorModifier>;
    keywords: Array<SyntaxKeyword>;
    max_keyword_length: u32;
    single_line_comment: string;
    multi_line_comment_start: string;
    multi_line_comment_end: string;
    char_boundary: u8;
    string_boundary: u8;
    multi_line_string_boundary: string;
}

struct LineColorModifier {
    start: string;
    color: SyntaxColor;
}

struct SyntaxKeyword {
    value: string;
    color: SyntaxColor;
}

enum SyntaxColor : u8 {
    Red;
    Green;
    Yellow;
    Blue;
    Purple;
    Aqua;
    Orange;
}

syntax_colors := 7; #const

#private

syntax_configurations: Array<Syntax> = [
    {
        extension = "ol";
        keywords = [
            { value = "return";    color = SyntaxColor.Red; },
            { value = "true";      color = SyntaxColor.Purple; },
            { value = "false";     color = SyntaxColor.Purple; },
            { value = "if";        color = SyntaxColor.Red; },
            { value = "else";      color = SyntaxColor.Red; },
            { value = "while";     color = SyntaxColor.Red; },
            { value = "each";      color = SyntaxColor.Red; },
            { value = "in";        color = SyntaxColor.Orange; },
            { value = "out";       color = SyntaxColor.Orange; },
            { value = "struct";    color = SyntaxColor.Aqua; },
            { value = "enum";      color = SyntaxColor.Aqua; },
            { value = "union";     color = SyntaxColor.Aqua; },
            { value = "interface"; color = SyntaxColor.Aqua; },
            { value = "null";      color = SyntaxColor.Purple; },
            { value = "cast";      color = SyntaxColor.Orange; },
            { value = "operator";  color = SyntaxColor.Orange; },
            { value = "break";     color = SyntaxColor.Red; },
            { value = "continue";  color = SyntaxColor.Red; },
            { value = "asm";       color = SyntaxColor.Orange; },
            { value = "switch";    color = SyntaxColor.Red; },
            { value = "case";      color = SyntaxColor.Red; },
            { value = "default";   color = SyntaxColor.Red; },
            { value = "defer";     color = SyntaxColor.Orange; },
            { value = "void";      color = SyntaxColor.Yellow; },
            { value = "bool";      color = SyntaxColor.Yellow; },
            { value = "s8";        color = SyntaxColor.Yellow; },
            { value = "u8";        color = SyntaxColor.Yellow; },
            { value = "s16";       color = SyntaxColor.Yellow; },
            { value = "u16";       color = SyntaxColor.Yellow; },
            { value = "int";       color = SyntaxColor.Yellow; },
            { value = "s32";       color = SyntaxColor.Yellow; },
            { value = "u32";       color = SyntaxColor.Yellow; },
            { value = "s64";       color = SyntaxColor.Yellow; },
            { value = "u64";       color = SyntaxColor.Yellow; },
            { value = "float";     color = SyntaxColor.Yellow; },
            { value = "float64";   color = SyntaxColor.Yellow; },
            { value = "Type";      color = SyntaxColor.Yellow; },
            { value = "string";    color = SyntaxColor.Yellow; },
            { value = "Array";     color = SyntaxColor.Yellow; },
            { value = "CArray";    color = SyntaxColor.Yellow; },
            { value = "Params";    color = SyntaxColor.Orange; },
            { value = "Any";       color = SyntaxColor.Yellow; },
        ]
        max_keyword_length = 9;
        single_line_comment = "//";
        multi_line_comment_start = "/*";
        multi_line_comment_end = "*/";
        char_boundary = '\'';
        string_boundary = '\"';
        multi_line_string_boundary = "\"\"\"";
    },
    {
        extension = "c";
        keywords = [
            { value = "auto";     color = SyntaxColor.Orange; },
            { value = "break";    color = SyntaxColor.Red; },
            { value = "case";     color = SyntaxColor.Red; },
            { value = "char";     color = SyntaxColor.Yellow; },
            { value = "const";    color = SyntaxColor.Orange; },
            { value = "continue"; color = SyntaxColor.Red; },
            { value = "default";  color = SyntaxColor.Red; },
            { value = "do";       color = SyntaxColor.Red; },
            { value = "double";   color = SyntaxColor.Yellow; },
            { value = "else";     color = SyntaxColor.Red; },
            { value = "enum";     color = SyntaxColor.Aqua; },
            { value = "extern";   color = SyntaxColor.Orange; },
            { value = "false";    color = SyntaxColor.Purple; },
            { value = "float";    color = SyntaxColor.Yellow; },
            { value = "for";      color = SyntaxColor.Red; },
            { value = "goto";     color = SyntaxColor.Red; },
            { value = "if";       color = SyntaxColor.Red; },
            { value = "int";      color = SyntaxColor.Yellow; },
            { value = "long";     color = SyntaxColor.Yellow; },
            { value = "register"; color = SyntaxColor.Orange; },
            { value = "return";   color = SyntaxColor.Red; },
            { value = "short";    color = SyntaxColor.Yellow; },
            { value = "signed";   color = SyntaxColor.Yellow; },
            { value = "sizeof";   color = SyntaxColor.Purple; },
            { value = "static";   color = SyntaxColor.Red; },
            { value = "struct";   color = SyntaxColor.Aqua; },
            { value = "switch";   color = SyntaxColor.Red; },
            { value = "true";     color = SyntaxColor.Purple; },
            { value = "typedef";  color = SyntaxColor.Aqua; },
            { value = "union";    color = SyntaxColor.Aqua; },
            { value = "unsigned"; color = SyntaxColor.Yellow; },
            { value = "void";     color = SyntaxColor.Yellow; },
            { value = "volatile"; color = SyntaxColor.Orange; },
            { value = "while";    color = SyntaxColor.Red; },
        ]
        max_keyword_length = 8;
        single_line_comment = "//";
        multi_line_comment_start = "/*";
        multi_line_comment_end = "*/";
        char_boundary = '\'';
        string_boundary = '\"';
    },
    {
        extension = "cs";
        keywords = [
            { value = "abstract";   color = SyntaxColor.Orange; },
            { value = "as";         color = SyntaxColor.Red; },
            { value = "base";       color = SyntaxColor.Red; },
            { value = "bool";       color = SyntaxColor.Yellow; },
            { value = "break";      color = SyntaxColor.Red; },
            { value = "byte";       color = SyntaxColor.Yellow; },
            { value = "case";       color = SyntaxColor.Red; },
            { value = "catch";      color = SyntaxColor.Red; },
            { value = "char";       color = SyntaxColor.Yellow; },
            { value = "checked";    color = SyntaxColor.Orange; },
            { value = "class";      color = SyntaxColor.Aqua; },
            { value = "const";      color = SyntaxColor.Orange; },
            { value = "continue";   color = SyntaxColor.Red; },
            { value = "decimal";    color = SyntaxColor.Yellow; },
            { value = "default";    color = SyntaxColor.Red; },
            { value = "delegate";   color = SyntaxColor.Orange; },
            { value = "do";         color = SyntaxColor.Red; },
            { value = "double";     color = SyntaxColor.Yellow; },
            { value = "else";       color = SyntaxColor.Red; },
            { value = "enum";       color = SyntaxColor.Aqua; },
            { value = "event";      color = SyntaxColor.Orange; },
            { value = "explicit";   color = SyntaxColor.Red; },
            { value = "extern";     color = SyntaxColor.Orange; },
            { value = "false";      color = SyntaxColor.Purple; },
            { value = "finally";    color = SyntaxColor.Red; },
            { value = "fixed";      color = SyntaxColor.Red; },
            { value = "float";      color = SyntaxColor.Yellow; },
            { value = "for";        color = SyntaxColor.Red; },
            { value = "foreach";    color = SyntaxColor.Red; },
            { value = "goto";       color = SyntaxColor.Red; },
            { value = "if";         color = SyntaxColor.Red; },
            { value = "implicit";   color = SyntaxColor.Red; },
            { value = "in";         color = SyntaxColor.Red; },
            { value = "int";        color = SyntaxColor.Yellow; },
            { value = "interface";  color = SyntaxColor.Aqua; },
            { value = "internal";   color = SyntaxColor.Orange; },
            { value = "is";         color = SyntaxColor.Red; },
            { value = "lock";       color = SyntaxColor.Red; },
            { value = "long";       color = SyntaxColor.Yellow; },
            { value = "namespace";  color = SyntaxColor.Aqua; },
            { value = "new";        color = SyntaxColor.Red; },
            { value = "null";       color = SyntaxColor.Purple; },
            { value = "object";     color = SyntaxColor.Yellow; },
            { value = "operator";   color = SyntaxColor.Orange; },
            { value = "out";        color = SyntaxColor.Red; },
            { value = "override";   color = SyntaxColor.Orange; },
            { value = "params";     color = SyntaxColor.Red; },
            { value = "private";    color = SyntaxColor.Orange; },
            { value = "protected";  color = SyntaxColor.Orange; },
            { value = "public";     color = SyntaxColor.Orange; },
            { value = "readonly";   color = SyntaxColor.Orange; },
            { value = "ref";        color = SyntaxColor.Red; },
            { value = "return";     color = SyntaxColor.Red; },
            { value = "sbyte";      color = SyntaxColor.Yellow; },
            { value = "sealed";     color = SyntaxColor.Orange; },
            { value = "short";      color = SyntaxColor.Yellow; },
            { value = "sizeof";     color = SyntaxColor.Red; },
            { value = "stackalloc"; color = SyntaxColor.Red; },
            { value = "static";     color = SyntaxColor.Orange; },
            { value = "string";     color = SyntaxColor.Yellow; },
            { value = "struct";     color = SyntaxColor.Aqua; },
            { value = "switch";     color = SyntaxColor.Red; },
            { value = "this";       color = SyntaxColor.Red; },
            { value = "throw";      color = SyntaxColor.Red; },
            { value = "true";       color = SyntaxColor.Purple; },
            { value = "try";        color = SyntaxColor.Red; },
            { value = "typeof";     color = SyntaxColor.Red; },
            { value = "uint";       color = SyntaxColor.Yellow; },
            { value = "ulong";      color = SyntaxColor.Yellow; },
            { value = "unchecked";  color = SyntaxColor.Red; },
            { value = "unsafe";     color = SyntaxColor.Orange; },
            { value = "ushort";     color = SyntaxColor.Yellow; },
            { value = "using";      color = SyntaxColor.Red; },
            { value = "virtual";    color = SyntaxColor.Orange; },
            { value = "void";       color = SyntaxColor.Yellow; },
            { value = "volatile";   color = SyntaxColor.Orange; },
            { value = "while";      color = SyntaxColor.Red; },
        ]
        max_keyword_length = 10;
        single_line_comment = "//";
        multi_line_comment_start = "/*";
        multi_line_comment_end = "*/";
        char_boundary = '\'';
        string_boundary = '\"';
    },
    {
        extension = "diff";
        line_color_modifiers = [
            { start = "<";     color = SyntaxColor.Red; },
            { start = "-";     color = SyntaxColor.Red; },
            { start = ">";     color = SyntaxColor.Green; },
            { start = "+";     color = SyntaxColor.Green; },
            { start = "+++";   color = SyntaxColor.Yellow; },
            { start = "==== "; color = SyntaxColor.Orange; },
            { start = "diff "; color = SyntaxColor.Orange; },
            { start = "index"; color = SyntaxColor.Aqua; },
            { start = "---";   color = SyntaxColor.Blue; },
            { start = "--- ";  color = SyntaxColor.Orange; },
            { start = "@@";    color = SyntaxColor.Blue; },
        ]
    }
]
