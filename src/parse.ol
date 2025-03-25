// Try parse functions
bool, bool try_parse_bool(string arg) {
    if arg == "0" return true, false;
    if arg == "1" return true, true;

    // True path
    if arg.length == 4 &&
       (arg[0] == 't' || arg[0] == 'T') &&
       (arg[1] == 'r' || arg[1] == 'R') &&
       (arg[2] == 'u' || arg[2] == 'U') &&
       (arg[3] == 'e' || arg[3] == 'E')
       return true, false;

    // False path
    if arg.length == 5 &&
       (arg[0] == 'f' || arg[0] == 'F') &&
       (arg[1] == 'a' || arg[1] == 'A') &&
       (arg[2] == 'l' || arg[2] == 'L') &&
       (arg[3] == 's' || arg[3] == 'S') &&
       (arg[4] == 'e' || arg[4] == 'E')
       return true, false;

    return false, false;
}

bool, u32 try_parse_u32(string value) {
    return try_parse_integer<u32>(value);
}

bool, s32 try_parse_s32(string value) {
    return try_parse_integer<s32>(value);
}

bool, s64 try_parse_s64(string value) {
    return try_parse_integer<s64>(value);
}

bool, float try_parse_float(string value) {
    if value.length == 0 return false, 0.0;

    whole: u64;
    decimal: float64;

    i := 0;
    is_negative := false;
    if value[i] == '-' {
        is_negative = true;
        i++;
    }

    is_valid := true;
    parsing_decimal := false;
    decimal_factor := 0.1;
    while i < value.length {
        digit := value[i++];
        if digit == '.' {
            if parsing_decimal {
                return false, 0.0;
            }
            else parsing_decimal = true;
        }
        else if digit < '0' || digit > '9' {
            return false, 0.0;
        }
        else {
            if parsing_decimal {
                decimal += decimal_factor * (digit - '0');
                decimal_factor /= 10.0;
            }
            else {
                whole *= 10;
                whole += digit - '0';
            }
        }
    }

    float_value := whole + decimal;
    if is_negative float_value *= -1.0;

    return true, float_value;
}

#private

bool, T try_parse_integer<T>(string value) {
    #assert type_of(T).type == TypeKind.Integer;
    if value.length == 0 return false, 0;

    integer_value: T;
    i := 0;

    #if cast(IntegerTypeInfo*, type_of(T)).signed {
        is_negative := false;
        if value[i] == '-' {
            is_negative = true;
            i++;
        }
    }

    while i < value.length {
        digit := value[i++];
        if digit < '0' || digit > '9' {
            return false, 0;
        }

        integer_value *= 10;
        integer_value += digit - '0';
    }

    #if cast(IntegerTypeInfo*, type_of(T)).signed {
        if is_negative integer_value *= -1;
    }

    return true, integer_value;
}
