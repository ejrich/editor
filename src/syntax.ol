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
            { value = "true";      color = KeywordColor.Red; },
            { value = "false";     color = KeywordColor.Red; },
            { value = "if";        color = KeywordColor.Red; },
            { value = "else";      color = KeywordColor.Red; },
            { value = "while";     color = KeywordColor.Red; },
            { value = "each";      color = KeywordColor.Red; },
            { value = "in";        color = KeywordColor.Red; },
            { value = "out";       color = KeywordColor.Red; },
            { value = "struct";    color = KeywordColor.Red; },
            { value = "enum";      color = KeywordColor.Red; },
            { value = "union";     color = KeywordColor.Red; },
            { value = "interface"; color = KeywordColor.Red; },
            { value = "null";      color = KeywordColor.Red; },
            { value = "cast";      color = KeywordColor.Red; },
            { value = "operator";  color = KeywordColor.Red; },
            { value = "break";     color = KeywordColor.Red; },
            { value = "continue";  color = KeywordColor.Red; },
            { value = "asm";       color = KeywordColor.Red; },
            { value = "switch";    color = KeywordColor.Red; },
            { value = "case";      color = KeywordColor.Red; },
            { value = "default";   color = KeywordColor.Red; },
            { value = "defer";     color = KeywordColor.Red; },
            { value = "void";      color = KeywordColor.Red; },
            { value = "bool";      color = KeywordColor.Red; },
            { value = "s8";        color = KeywordColor.Red; },
            { value = "u8";        color = KeywordColor.Red; },
            { value = "s16";       color = KeywordColor.Red; },
            { value = "u16";       color = KeywordColor.Red; },
            { value = "int";       color = KeywordColor.Red; },
            { value = "s32";       color = KeywordColor.Red; },
            { value = "u32";       color = KeywordColor.Red; },
            { value = "s64";       color = KeywordColor.Red; },
            { value = "u64";       color = KeywordColor.Red; },
            { value = "float";     color = KeywordColor.Red; },
            { value = "float64";   color = KeywordColor.Red; },
            { value = "Type";      color = KeywordColor.Red; },
            { value = "string";    color = KeywordColor.Red; },
            { value = "Array";     color = KeywordColor.Red; },
            { value = "CArray";    color = KeywordColor.Red; },
            { value = "Params";    color = KeywordColor.Red; },
            { value = "Any";       color = KeywordColor.Red; },
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
            { value = "auto";     color = KeywordColor.Red; },
            { value = "break";    color = KeywordColor.Red; },
            { value = "case";     color = KeywordColor.Red; },
            { value = "char";     color = KeywordColor.Red; },
            { value = "const";    color = KeywordColor.Red; },
            { value = "continue"; color = KeywordColor.Red; },
            { value = "default";  color = KeywordColor.Red; },
            { value = "do";       color = KeywordColor.Red; },
            { value = "double";   color = KeywordColor.Red; },
            { value = "else";     color = KeywordColor.Red; },
            { value = "enum";     color = KeywordColor.Red; },
            { value = "extern";   color = KeywordColor.Red; },
            { value = "float";    color = KeywordColor.Red; },
            { value = "for";      color = KeywordColor.Red; },
            { value = "goto";     color = KeywordColor.Red; },
            { value = "if";       color = KeywordColor.Red; },
            { value = "int";      color = KeywordColor.Red; },
            { value = "long";     color = KeywordColor.Red; },
            { value = "register"; color = KeywordColor.Red; },
            { value = "return";   color = KeywordColor.Red; },
            { value = "short";    color = KeywordColor.Red; },
            { value = "signed";   color = KeywordColor.Red; },
            { value = "sizeof";   color = KeywordColor.Red; },
            { value = "static";   color = KeywordColor.Red; },
            { value = "struct";   color = KeywordColor.Red; },
            { value = "switch";   color = KeywordColor.Red; },
            { value = "typedef";  color = KeywordColor.Red; },
            { value = "union";    color = KeywordColor.Red; },
            { value = "unsigned"; color = KeywordColor.Red; },
            { value = "void";     color = KeywordColor.Red; },
            { value = "volatile"; color = KeywordColor.Red; },
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
            { value = "abstract";   color = KeywordColor.Red; },
            { value = "as";         color = KeywordColor.Red; },
            { value = "base";       color = KeywordColor.Red; },
            { value = "bool";       color = KeywordColor.Red; },
            { value = "break";      color = KeywordColor.Red; },
            { value = "byte";       color = KeywordColor.Red; },
            { value = "case";       color = KeywordColor.Red; },
            { value = "catch";      color = KeywordColor.Red; },
            { value = "char";       color = KeywordColor.Red; },
            { value = "checked";    color = KeywordColor.Red; },
            { value = "class";      color = KeywordColor.Red; },
            { value = "const";      color = KeywordColor.Red; },
            { value = "continue";   color = KeywordColor.Red; },
            { value = "decimal";    color = KeywordColor.Red; },
            { value = "default";    color = KeywordColor.Red; },
            { value = "delegate";   color = KeywordColor.Red; },
            { value = "do";         color = KeywordColor.Red; },
            { value = "double";     color = KeywordColor.Red; },
            { value = "else";       color = KeywordColor.Red; },
            { value = "enum";       color = KeywordColor.Red; },
            { value = "event";      color = KeywordColor.Red; },
            { value = "explicit";   color = KeywordColor.Red; },
            { value = "extern";     color = KeywordColor.Red; },
            { value = "false";      color = KeywordColor.Red; },
            { value = "finally";    color = KeywordColor.Red; },
            { value = "fixed";      color = KeywordColor.Red; },
            { value = "float";      color = KeywordColor.Red; },
            { value = "for";        color = KeywordColor.Red; },
            { value = "foreach";    color = KeywordColor.Red; },
            { value = "goto";       color = KeywordColor.Red; },
            { value = "if";         color = KeywordColor.Red; },
            { value = "implicit";   color = KeywordColor.Red; },
            { value = "in";         color = KeywordColor.Red; },
            { value = "int";        color = KeywordColor.Red; },
            { value = "interface";  color = KeywordColor.Red; },
            { value = "internal";   color = KeywordColor.Red; },
            { value = "is";         color = KeywordColor.Red; },
            { value = "lock";       color = KeywordColor.Red; },
            { value = "long";       color = KeywordColor.Red; },
            { value = "namespace";  color = KeywordColor.Red; },
            { value = "new";        color = KeywordColor.Red; },
            { value = "null";       color = KeywordColor.Red; },
            { value = "object";     color = KeywordColor.Red; },
            { value = "operator";   color = KeywordColor.Red; },
            { value = "out";        color = KeywordColor.Red; },
            { value = "override";   color = KeywordColor.Red; },
            { value = "params";     color = KeywordColor.Red; },
            { value = "private";    color = KeywordColor.Red; },
            { value = "protected";  color = KeywordColor.Red; },
            { value = "public";     color = KeywordColor.Red; },
            { value = "readonly";   color = KeywordColor.Red; },
            { value = "ref";        color = KeywordColor.Red; },
            { value = "return";     color = KeywordColor.Red; },
            { value = "sbyte";      color = KeywordColor.Red; },
            { value = "sealed";     color = KeywordColor.Red; },
            { value = "short";      color = KeywordColor.Red; },
            { value = "sizeof";     color = KeywordColor.Red; },
            { value = "stackalloc"; color = KeywordColor.Red; },
            { value = "static";     color = KeywordColor.Red; },
            { value = "string";     color = KeywordColor.Red; },
            { value = "struct";     color = KeywordColor.Red; },
            { value = "switch";     color = KeywordColor.Red; },
            { value = "this";       color = KeywordColor.Red; },
            { value = "throw";      color = KeywordColor.Red; },
            { value = "true";       color = KeywordColor.Red; },
            { value = "try";        color = KeywordColor.Red; },
            { value = "typeof";     color = KeywordColor.Red; },
            { value = "uint";       color = KeywordColor.Red; },
            { value = "ulong";      color = KeywordColor.Red; },
            { value = "unchecked";  color = KeywordColor.Red; },
            { value = "unsafe";     color = KeywordColor.Red; },
            { value = "ushort";     color = KeywordColor.Red; },
            { value = "using";      color = KeywordColor.Red; },
            { value = "virtual";    color = KeywordColor.Red; },
            { value = "void";       color = KeywordColor.Red; },
            { value = "volatile";   color = KeywordColor.Red; },
            { value = "while";      color = KeywordColor.Red; },
        ]
        max_keyword_length = 10;
        single_line_comment = "//";
        multi_line_comment_start = "/*";
        multi_line_comment_end = "*/";
        string_boundary = '\"';
    }
]
