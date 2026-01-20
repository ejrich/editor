Syntax* get_syntax_for_file(string file_path) {
    extension_start := file_path.length;
    each i in file_path.length {
        if file_path[i] == '.' {
            extension_start = i + 1;
        }
    }

    if extension_start + 1 < file_path.length {
        extension: string = {
            length = file_path.length - extension_start;
            data = file_path.data + extension_start;
        }

        each syntax in syntax_configurations {
            if syntax.extension == extension {
                return &syntax;
            }
        }
    }

    return null;
}

struct Syntax {
    extension: string;
    keywords: Array<SyntaxKeyword>;
    max_keyword_length: u32;
    single_line_comment: string;
    multi_line_comment_start: string;
    multi_line_comment_end: string;
    string_boundary: u8;
    multi_line_string_boundary: string;
}

struct SyntaxKeyword {
    value: string;
    color: KeywordColor;
}

enum KeywordColor : u8 {
    Red;
    Green;
    Yellow;
    Blue;
    Purple;
    Aqua;
    Orange;
}

keyword_colors := 7; #const

#private

syntax_configurations: Array<Syntax> = [
    {
        extension = "ol";
        keywords = [
            { value = "return";    color = KeywordColor.Red; },
            { value = "true";      color = KeywordColor.Purple; },
            { value = "false";     color = KeywordColor.Purple; },
            { value = "if";        color = KeywordColor.Red; },
            { value = "else";      color = KeywordColor.Red; },
            { value = "while";     color = KeywordColor.Red; },
            { value = "each";      color = KeywordColor.Red; },
            { value = "in";        color = KeywordColor.Orange; },
            { value = "out";       color = KeywordColor.Orange; },
            { value = "struct";    color = KeywordColor.Aqua; },
            { value = "enum";      color = KeywordColor.Aqua; },
            { value = "union";     color = KeywordColor.Aqua; },
            { value = "interface"; color = KeywordColor.Aqua; },
            { value = "null";      color = KeywordColor.Purple; },
            { value = "cast";      color = KeywordColor.Orange; },
            { value = "operator";  color = KeywordColor.Orange; },
            { value = "break";     color = KeywordColor.Red; },
            { value = "continue";  color = KeywordColor.Red; },
            { value = "asm";       color = KeywordColor.Orange; },
            { value = "switch";    color = KeywordColor.Red; },
            { value = "case";      color = KeywordColor.Red; },
            { value = "default";   color = KeywordColor.Red; },
            { value = "defer";     color = KeywordColor.Orange; },
            { value = "void";      color = KeywordColor.Yellow; },
            { value = "bool";      color = KeywordColor.Yellow; },
            { value = "s8";        color = KeywordColor.Yellow; },
            { value = "u8";        color = KeywordColor.Yellow; },
            { value = "s16";       color = KeywordColor.Yellow; },
            { value = "u16";       color = KeywordColor.Yellow; },
            { value = "int";       color = KeywordColor.Yellow; },
            { value = "s32";       color = KeywordColor.Yellow; },
            { value = "u32";       color = KeywordColor.Yellow; },
            { value = "s64";       color = KeywordColor.Yellow; },
            { value = "u64";       color = KeywordColor.Yellow; },
            { value = "float";     color = KeywordColor.Yellow; },
            { value = "float64";   color = KeywordColor.Yellow; },
            { value = "Type";      color = KeywordColor.Yellow; },
            { value = "string";    color = KeywordColor.Yellow; },
            { value = "Array";     color = KeywordColor.Yellow; },
            { value = "CArray";    color = KeywordColor.Yellow; },
            { value = "Params";    color = KeywordColor.Orange; },
            { value = "Any";       color = KeywordColor.Yellow; },
        ]
        max_keyword_length = 9;
        single_line_comment = "//";
        multi_line_comment_start = "/*";
        multi_line_comment_end = "*/";
        string_boundary = '\"';
        multi_line_string_boundary = "\"\"\"";
    },
    {
        extension = "c";
        keywords = [
            { value = "auto";     color = KeywordColor.Orange; },
            { value = "break";    color = KeywordColor.Red; },
            { value = "case";     color = KeywordColor.Red; },
            { value = "char";     color = KeywordColor.Yellow; },
            { value = "const";    color = KeywordColor.Orange; },
            { value = "continue"; color = KeywordColor.Red; },
            { value = "default";  color = KeywordColor.Red; },
            { value = "do";       color = KeywordColor.Red; },
            { value = "double";   color = KeywordColor.Yellow; },
            { value = "else";     color = KeywordColor.Red; },
            { value = "enum";     color = KeywordColor.Aqua; },
            { value = "extern";   color = KeywordColor.Orange; },
            { value = "false";    color = KeywordColor.Purple; },
            { value = "float";    color = KeywordColor.Yellow; },
            { value = "for";      color = KeywordColor.Red; },
            { value = "goto";     color = KeywordColor.Red; },
            { value = "if";       color = KeywordColor.Red; },
            { value = "int";      color = KeywordColor.Yellow; },
            { value = "long";     color = KeywordColor.Yellow; },
            { value = "register"; color = KeywordColor.Orange; },
            { value = "return";   color = KeywordColor.Red; },
            { value = "short";    color = KeywordColor.Yellow; },
            { value = "signed";   color = KeywordColor.Yellow; },
            { value = "sizeof";   color = KeywordColor.Purple; },
            { value = "static";   color = KeywordColor.Red; },
            { value = "struct";   color = KeywordColor.Aqua; },
            { value = "switch";   color = KeywordColor.Red; },
            { value = "true";     color = KeywordColor.Purple; },
            { value = "typedef";  color = KeywordColor.Aqua; },
            { value = "union";    color = KeywordColor.Aqua; },
            { value = "unsigned"; color = KeywordColor.Yellow; },
            { value = "void";     color = KeywordColor.Yellow; },
            { value = "volatile"; color = KeywordColor.Orange; },
            { value = "while";    color = KeywordColor.Red; },
        ]
        max_keyword_length = 8;
        single_line_comment = "//";
        multi_line_comment_start = "/*";
        multi_line_comment_end = "*/";
        string_boundary = '\"';
    },
    {
        extension = "cs";
        keywords = [
            { value = "abstract";   color = KeywordColor.Orange; },
            { value = "as";         color = KeywordColor.Red; },
            { value = "base";       color = KeywordColor.Red; },
            { value = "bool";       color = KeywordColor.Yellow; },
            { value = "break";      color = KeywordColor.Red; },
            { value = "byte";       color = KeywordColor.Yellow; },
            { value = "case";       color = KeywordColor.Red; },
            { value = "catch";      color = KeywordColor.Red; },
            { value = "char";       color = KeywordColor.Yellow; },
            { value = "checked";    color = KeywordColor.Orange; },
            { value = "class";      color = KeywordColor.Aqua; },
            { value = "const";      color = KeywordColor.Orange; },
            { value = "continue";   color = KeywordColor.Red; },
            { value = "decimal";    color = KeywordColor.Yellow; },
            { value = "default";    color = KeywordColor.Red; },
            { value = "delegate";   color = KeywordColor.Orange; },
            { value = "do";         color = KeywordColor.Red; },
            { value = "double";     color = KeywordColor.Yellow; },
            { value = "else";       color = KeywordColor.Red; },
            { value = "enum";       color = KeywordColor.Aqua; },
            { value = "event";      color = KeywordColor.Orange; },
            { value = "explicit";   color = KeywordColor.Red; },
            { value = "extern";     color = KeywordColor.Orange; },
            { value = "false";      color = KeywordColor.Purple; },
            { value = "finally";    color = KeywordColor.Red; },
            { value = "fixed";      color = KeywordColor.Red; },
            { value = "float";      color = KeywordColor.Yellow; },
            { value = "for";        color = KeywordColor.Red; },
            { value = "foreach";    color = KeywordColor.Red; },
            { value = "goto";       color = KeywordColor.Red; },
            { value = "if";         color = KeywordColor.Red; },
            { value = "implicit";   color = KeywordColor.Red; },
            { value = "in";         color = KeywordColor.Red; },
            { value = "int";        color = KeywordColor.Yellow; },
            { value = "interface";  color = KeywordColor.Aqua; },
            { value = "internal";   color = KeywordColor.Orange; },
            { value = "is";         color = KeywordColor.Red; },
            { value = "lock";       color = KeywordColor.Red; },
            { value = "long";       color = KeywordColor.Yellow; },
            { value = "namespace";  color = KeywordColor.Aqua; },
            { value = "new";        color = KeywordColor.Red; },
            { value = "null";       color = KeywordColor.Purple; },
            { value = "object";     color = KeywordColor.Yellow; },
            { value = "operator";   color = KeywordColor.Orange; },
            { value = "out";        color = KeywordColor.Red; },
            { value = "override";   color = KeywordColor.Orange; },
            { value = "params";     color = KeywordColor.Red; },
            { value = "private";    color = KeywordColor.Orange; },
            { value = "protected";  color = KeywordColor.Orange; },
            { value = "public";     color = KeywordColor.Orange; },
            { value = "readonly";   color = KeywordColor.Orange; },
            { value = "ref";        color = KeywordColor.Red; },
            { value = "return";     color = KeywordColor.Red; },
            { value = "sbyte";      color = KeywordColor.Yellow; },
            { value = "sealed";     color = KeywordColor.Orange; },
            { value = "short";      color = KeywordColor.Yellow; },
            { value = "sizeof";     color = KeywordColor.Red; },
            { value = "stackalloc"; color = KeywordColor.Red; },
            { value = "static";     color = KeywordColor.Orange; },
            { value = "string";     color = KeywordColor.Yellow; },
            { value = "struct";     color = KeywordColor.Aqua; },
            { value = "switch";     color = KeywordColor.Red; },
            { value = "this";       color = KeywordColor.Red; },
            { value = "throw";      color = KeywordColor.Red; },
            { value = "true";       color = KeywordColor.Purple; },
            { value = "try";        color = KeywordColor.Red; },
            { value = "typeof";     color = KeywordColor.Red; },
            { value = "uint";       color = KeywordColor.Yellow; },
            { value = "ulong";      color = KeywordColor.Yellow; },
            { value = "unchecked";  color = KeywordColor.Red; },
            { value = "unsafe";     color = KeywordColor.Orange; },
            { value = "ushort";     color = KeywordColor.Yellow; },
            { value = "using";      color = KeywordColor.Red; },
            { value = "virtual";    color = KeywordColor.Orange; },
            { value = "void";       color = KeywordColor.Yellow; },
            { value = "volatile";   color = KeywordColor.Orange; },
            { value = "while";      color = KeywordColor.Red; },
        ]
        max_keyword_length = 10;
        single_line_comment = "//";
        multi_line_comment_start = "/*";
        multi_line_comment_end = "*/";
        string_boundary = '\"';
    }
]
