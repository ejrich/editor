init_exception_handler() {
    #if os == OS.Windows {
        process_handle = GetCurrentProcess();
        SymSetOptions(0x10);
        SymInitialize(process_handle, null, true);
        AddVectoredExceptionHandler(1, exception_handler);
    }
    #if os == OS.Linux {
        handler: SigHandler_T;
        handler.sigaction_handler = signal_handler;
        sigaction: Sigaction = {
            sa_handler = handler;
            sa_flags = 0x4000000;
            sa_restorer = signal_restorer;
        }
        rt_sigaction(LinuxSignal.SIGSEGV, &sigaction, null, 8);
    }

    a: int* = null;
    b := *a;
}

#private

#if os == OS.Windows {
    process_handle: Handle*;

    int exception_handler(EXCEPTION_POINTERS* exception_info) {
        stack_frames := 100; #const
        stack: Array<void*>[stack_frames];

        frames := RtlCaptureStackBackTrace(4, stack_frames, stack.data, null);

        max_name_length := 255;
        symbol_buffer: Array<u8>[size_of(SYMBOL_INFO) + max_name_length];

        symbol := cast(SYMBOL_INFO*, symbol_buffer.data);
        symbol.SizeOfStruct = size_of(SYMBOL_INFO);
        symbol.MaxNameLen = max_name_length;
        line: IMAGEHLP_LINE = {
            SizeOfStruct = size_of(IMAGEHLP_LINE);
        }
        column: int;

        if exception_info != null && exception_info.ExceptionRecord != null {
            log("Exception occured with code 0x%\n", uint_format(exception_info.ExceptionRecord.ExceptionCode, 16, 8));
        }
        else {
            log("Exception occured\n");
        }

        log("Stack trace:\n");

        each i in frames {
            address := cast(s64, stack[i]);
            success := SymFromAddr(process_handle, address, null, symbol);
            if success {
                name := convert_c_string(&symbol.Name);
                success = SymGetLineFromAddr64(process_handle, address, &column, &line);
                if success {
                    file := convert_c_string(line.FileName);
                    log("% %:%:% % - %\n", i, file, line.LineNumber, column, name, stack[i]);
                }
                else {
                    log("% % - %\n", i, name, stack[i]);
                }
            }
            else {
                log("% - %\n", i, stack[i]);
            }
        }

        exit_program(-1);
        return 0;
    }
}
#if os == OS.Linux {
    struct StackFrameAddress {
        previous: StackFrameAddress*;
        return_address: void*;
    }

    signal_handler(LinuxSignal signal, SigInfo* info, UContext* context) {
        path_length := 4096; #const
        executable_path: CArray<u8>[path_length];
        self_path := "/proc/self/exe"; #const
        bytes := readlink(self_path.data, &executable_path, path_length - 1);

        debug_info, debug_abbrev, debug_str, debug_line: Elf64_Shdr*;
        path_string: string = { length = bytes; data = &executable_path; }
        found, executable_file := read_file(path_string);
        if found {
            header := cast(Elf64_Ehdr*, executable_file.data);

            sections: Array<Elf64_Shdr>;
            sections.length = header.e_shnum;
            sections.data = cast(Elf64_Shdr*, executable_file.data + header.e_shoff);
            shstrtab := sections[header.e_shstrndx];

            each section in sections {
                name := convert_c_string(executable_file.data + shstrtab.sh_offset + section.sh_name);
                if name == ".debug_info" {
                    debug_info = &section;
                }
                if name == ".debug_abbrev" {
                    debug_abbrev = &section;
                }
                if name == ".debug_str" {
                    debug_str = &section;
                }
                if name == ".debug_line" {
                    debug_line = &section;
                }
            }
        }

        declarations: Array<AbbrevDeclaration>;
        if debug_abbrev {
            i := 0;
            abbrev_data := executable_file.data + debug_abbrev.sh_offset;
            while i < debug_abbrev.sh_size {
                code := translate_leb128(abbrev_data, &i);
                if code == 0 break;

                declaration: AbbrevDeclaration;
                declaration.tag = cast(DwarfTag, translate_leb128(abbrev_data, &i));
                declaration.has_children = abbrev_data[i++] > 0;

                while i < debug_abbrev.sh_size {
                    attribute: AbbrevAttribute;
                    attribute.name = cast(DwarfAttribute, translate_leb128(abbrev_data, &i));
                    attribute.form = cast(DwarfForm, translate_leb128(abbrev_data, &i));
                    if attribute.name == DwarfAttribute.None && attribute.form == DwarfForm.None break;

                    if attribute.form == DwarfForm.DW_FORM_implicit_const {
                        attribute.value = translate_leb128(abbrev_data, &i);
                    }

                    array_insert(&declaration.attributes, attribute);
                }

                array_insert(&declarations, declaration);
            }
        }

        frame: StackFrameAddress*;
        asm {
            out frame, rbp;
        }

        log("Stack trace:\n");

        index := 0;
        while frame {
            if debug_info {
                address := cast(u64, frame.return_address);
                function_found, start, function := find_function_in_die(executable_file.data + debug_info.sh_offset, debug_info.sh_size, declarations,address , executable_file.data + debug_str.sh_offset);

                if function_found {
                    location_found, line, column, folder, file := find_debug_line_location(executable_file.data + debug_line.sh_offset, debug_line.sh_size, address, start);

                    if location_found {
                        log("% %/%:%:% % - %\n", index++, folder, file, line, column, function, frame.return_address);
                    }
                    else {
                        log("% % - %\n", index++, function, frame.return_address);
                    }
                }
                else {
                    log("% - %\n", index++, frame.return_address);
                }
            }
            else {
                log("% - %\n", index++, frame.return_address);
            }

            frame = frame.previous;
        }

        exit_program(-1);
    }

    signal_restorer() {
        rt_sigreturn();
    }

    struct Elf64_Ehdr {
        __reserved1: u64;
        __reserved2: u64;
        e_type: u16;
        e_machine: u16;
        e_version: u32;
        e_entry: u64;
        e_phoff: u64;
        e_shoff: u64;
        e_flags: u32;
        e_ehsize: u16;
        e_phentsize: u16;
        e_phnum: u16;
        e_shentsize: u16;
        e_shnum: u16;
        e_shstrndx: u16;
    }

    struct Elf64_Shdr {
        sh_name: u32;
        sh_type: u32;
        sh_flags: u64;
        sh_addr: u64;
        sh_offset: u64;
        sh_size: u64;
        sh_link: u32;
        sh_info: u32;
        sh_addralign: u64;
        sh_entsize: u64;
    }

    enum DwarfTag : u64 {
        None = 0x0;
        DW_TAG_array_type = 0x01;
        DW_TAG_class_type = 0x02;
        DW_TAG_entry_point = 0x03;
        DW_TAG_enumeration_type = 0x04;
        DW_TAG_formal_parameter = 0x05;
        DW_TAG_imported_declaration = 0x08;
        DW_TAG_label = 0x0a;
        DW_TAG_lexical_block = 0x0b;
        DW_TAG_member = 0x0d;
        DW_TAG_pointer_type = 0x0f;
        DW_TAG_reference_type = 0x10;
        DW_TAG_compile_unit = 0x11;
        DW_TAG_string_type = 0x12;
        DW_TAG_structure_type = 0x13;
        DW_TAG_subroutine_type = 0x15;
        DW_TAG_typedef = 0x16;
        DW_TAG_union_type = 0x17;
        DW_TAG_unspecified_parameters = 0x18;
        DW_TAG_variant = 0x19;
        DW_TAG_common_block = 0x1a;
        DW_TAG_common_inclusion = 0x1b;
        DW_TAG_inheritance = 0x1c;
        DW_TAG_inlined_subroutine = 0x1d;
        DW_TAG_module = 0x1e;
        DW_TAG_ptr_to_member_type = 0x1f;
        DW_TAG_set_type = 0x20;
        DW_TAG_subrange_type = 0x21;
        DW_TAG_with_stmt = 0x22;
        DW_TAG_access_declaration = 0x23;
        DW_TAG_base_type = 0x24;
        DW_TAG_catch_block = 0x25;
        DW_TAG_const_type = 0x26;
        DW_TAG_constant = 0x27;
        DW_TAG_enumerator = 0x28;
        DW_TAG_file_type = 0x29;
        DW_TAG_friend = 0x2a;
        DW_TAG_namelist = 0x2b;
        DW_TAG_namelist_item = 0x2c;
        DW_TAG_packed_type = 0x2d;
        DW_TAG_subprogram = 0x2e;
        DW_TAG_template_type_parameter = 0x2f;
        DW_TAG_template_value_parameter = 0x30;
        DW_TAG_thrown_type = 0x31;
        DW_TAG_try_block = 0x32;
        DW_TAG_variant_part = 0x33;
        DW_TAG_variable = 0x34;
        DW_TAG_volatile_type = 0x35;
        DW_TAG_dwarf_procedure = 0x36;
        DW_TAG_restrict_type = 0x37;
        DW_TAG_interface_type = 0x38;
        DW_TAG_namespace = 0x39;
        DW_TAG_imported_module = 0x3a;
        DW_TAG_unspecified_type = 0x3b;
        DW_TAG_partial_unit = 0x3c;
        DW_TAG_imported_unit = 0x3d;
        DW_TAG_condition = 0x3f;
        DW_TAG_shared_type = 0x40;
        DW_TAG_type_unit = 0x41;
        DW_TAG_rvalue_reference_type = 0x42;
        DW_TAG_template_alias = 0x43;
        DW_TAG_coarray_type = 0x44;
        DW_TAG_generic_subrange = 0x45;
        DW_TAG_dynamic_type = 0x46;
        DW_TAG_atomic_type = 0x47;
        DW_TAG_call_site = 0x48;
        DW_TAG_call_site_parameter = 0x49;
        DW_TAG_skeleton_unit = 0x4a;
        DW_TAG_immutable_type = 0x4b;
        DW_TAG_lo_user = 0x4080;
        DW_TAG_MIPS_loop = 0x4081;
        DW_TAG_format_label = 0x4101;
        DW_TAG_function_template = 0x4102;
        DW_TAG_class_template = 0x4103;
        DW_TAG_GNU_BINCL = 0x4104;
        DW_TAG_GNU_EINCL = 0x4105;
        DW_TAG_GNU_template_template_param = 0x4106;
        DW_TAG_GNU_template_parameter_pack = 0x4107;
        DW_TAG_GNU_formal_parameter_pack = 0x4108;
        DW_TAG_GNU_call_site = 0x4109;
        DW_TAG_GNU_call_site_parameter = 0x410a;
        DW_TAG_hi_user = 0xffff;
    }

    enum DwarfAttribute : u64 {
        None = 0x0;
        DW_AT_sibling = 0x01;
        DW_AT_location = 0x02;
        DW_AT_name = 0x03;
        DW_AT_ordering = 0x09;
        DW_AT_byte_size = 0x0b;
        DW_AT_bit_offset = 0x0c;
        DW_AT_bit_size = 0x0d;
        DW_AT_stmt_list = 0x10;
        DW_AT_low_pc = 0x11;
        DW_AT_high_pc = 0x12;
        DW_AT_language = 0x13;
        DW_AT_discr = 0x15;
        DW_AT_discr_value = 0x16;
        DW_AT_visibility = 0x17;
        DW_AT_import = 0x18;
        DW_AT_string_length = 0x19;
        DW_AT_common_reference = 0x1a;
        DW_AT_comp_dir = 0x1b;
        DW_AT_const_value = 0x1c;
        DW_AT_containing_type = 0x1d;
        DW_AT_default_value = 0x1e;
        DW_AT_inline = 0x20;
        DW_AT_is_optional = 0x21;
        DW_AT_lower_bound = 0x22;
        DW_AT_producer = 0x25;
        DW_AT_prototyped = 0x27;
        DW_AT_return_addr = 0x2a;
        DW_AT_start_scope = 0x2c;
        DW_AT_bit_stride = 0x2e;
        DW_AT_upper_bound = 0x2f;
        DW_AT_abstract_origin = 0x31;
        DW_AT_accessibility = 0x32;
        DW_AT_address_class = 0x33;
        DW_AT_artificial = 0x34;
        DW_AT_base_types = 0x35;
        DW_AT_calling_convention = 0x36;
        DW_AT_count = 0x37;
        DW_AT_data_member_location = 0x38;
        DW_AT_decl_column = 0x39;
        DW_AT_decl_file = 0x3a;
        DW_AT_decl_line = 0x3b;
        DW_AT_declaration = 0x3c;
        DW_AT_discr_list = 0x3d;
        DW_AT_encoding = 0x3e;
        DW_AT_external = 0x3f;
        DW_AT_frame_base = 0x40;
        DW_AT_friend = 0x41;
        DW_AT_identifier_case = 0x42;
        DW_AT_macro_info = 0x43;
        DW_AT_namelist_item = 0x44;
        DW_AT_priority = 0x45;
        DW_AT_segment = 0x46;
        DW_AT_specification = 0x47;
        DW_AT_static_link = 0x48;
        DW_AT_type = 0x49;
        DW_AT_use_location = 0x4a;
        DW_AT_variable_parameter = 0x4b;
        DW_AT_virtuality = 0x4c;
        DW_AT_vtable_elem_location = 0x4d;
        DW_AT_allocated = 0x4e;
        DW_AT_associated = 0x4f;
        DW_AT_data_location = 0x50;
        DW_AT_byte_stride = 0x51;
        DW_AT_entry_pc = 0x52;
        DW_AT_use_UTF8 = 0x53;
        DW_AT_extension = 0x54;
        DW_AT_ranges = 0x55;
        DW_AT_trampoline = 0x56;
        DW_AT_call_column = 0x57;
        DW_AT_call_file = 0x58;
        DW_AT_call_line = 0x59;
        DW_AT_description = 0x5a;
        DW_AT_binary_scale = 0x5b;
        DW_AT_decimal_scale = 0x5c;
        DW_AT_small = 0x5d;
        DW_AT_decimal_sign = 0x5e;
        DW_AT_digit_count = 0x5f;
        DW_AT_picture_string = 0x60;
        DW_AT_mutable = 0x61;
        DW_AT_threads_scaled = 0x62;
        DW_AT_explicit = 0x63;
        DW_AT_object_pointer = 0x64;
        DW_AT_endianity = 0x65;
        DW_AT_elemental = 0x66;
        DW_AT_pure = 0x67;
        DW_AT_recursive = 0x68;
        DW_AT_signature = 0x69;
        DW_AT_main_subprogram = 0x6a;
        DW_AT_data_bit_offset = 0x6b;
        DW_AT_const_expr = 0x6c;
        DW_AT_enum_class = 0x6d;
        DW_AT_linkage_name = 0x6e;
        DW_AT_string_length_bit_size = 0x6f;
        DW_AT_string_length_byte_size = 0x70;
        DW_AT_rank = 0x71;
        DW_AT_str_offsets_base = 0x72;
        DW_AT_addr_base = 0x73;
        DW_AT_rnglists_base = 0x74;
        DW_AT_dwo_name = 0x76;
        DW_AT_reference = 0x77;
        DW_AT_rvalue_reference = 0x78;
        DW_AT_macros = 0x79;
        DW_AT_call_all_calls = 0x7a;
        DW_AT_call_all_source_calls = 0x7b;
        DW_AT_call_all_tail_calls = 0x7c;
        DW_AT_call_return_pc = 0x7d;
        DW_AT_call_value = 0x7e;
        DW_AT_call_origin = 0x7f;
        DW_AT_call_parameter = 0x80;
        DW_AT_call_pc = 0x81;
        DW_AT_call_tail_call = 0x82;
        DW_AT_call_target = 0x83;
        DW_AT_call_target_clobbered = 0x84;
        DW_AT_call_data_location = 0x85;
        DW_AT_call_data_value = 0x86;
        DW_AT_noreturn = 0x87;
        DW_AT_alignment = 0x88;
        DW_AT_export_symbols = 0x89;
        DW_AT_deleted = 0x8a;
        DW_AT_defaulted = 0x8b;
        DW_AT_loclists_base = 0x8c;
        DW_AT_language_name = 0x90;
        DW_AT_language_version = 0x91;
        DW_AT_lo_user = 0x2000;
        DW_AT_MIPS_fde = 0x2001;
        DW_AT_MIPS_loop_begin = 0x2002;
        DW_AT_MIPS_tail_loop_begin = 0x2003;
        DW_AT_MIPS_epilog_begin = 0x2004;
        DW_AT_MIPS_loop_unroll_factor = 0x2005;
        DW_AT_MIPS_software_pipeline_depth = 0x2006;
        DW_AT_MIPS_linkage_name = 0x2007;
        DW_AT_MIPS_stride = 0x2008;
        DW_AT_MIPS_abstract_name = 0x2009;
        DW_AT_MIPS_clone_origin = 0x200a;
        DW_AT_MIPS_has_inlines = 0x200b;
        DW_AT_MIPS_stride_byte = 0x200c;
        DW_AT_MIPS_stride_elem = 0x200d;
        DW_AT_MIPS_ptr_dopetype = 0x200e;
        DW_AT_MIPS_allocatable_dopetype = 0x200f;
        DW_AT_MIPS_assumed_shape_dopetype = 0x2010;
        DW_AT_MIPS_assumed_size = 0x2011;
        DW_AT_sf_names = 0x2101;
        DW_AT_src_info = 0x2102;
        DW_AT_mac_info = 0x2103;
        DW_AT_src_coords = 0x2104;
        DW_AT_body_begin = 0x2105;
        DW_AT_body_end = 0x2106;
        DW_AT_GNU_vector = 0x2107;
        DW_AT_GNU_guarded_by = 0x2108;
        DW_AT_GNU_pt_guarded_by = 0x2109;
        DW_AT_GNU_guarded = 0x210a;
        DW_AT_GNU_pt_guarded = 0x210b;
        DW_AT_GNU_locks_excluded = 0x210c;
        DW_AT_GNU_exclusive_locks_required = 0x210d;
        DW_AT_GNU_shared_locks_required = 0x210e;
        DW_AT_GNU_odr_signature = 0x210f;
        DW_AT_GNU_template_name = 0x2110;
        DW_AT_GNU_call_site_value = 0x2111;
        DW_AT_GNU_call_site_data_value = 0x2112;
        DW_AT_GNU_call_site_target = 0x2113;
        DW_AT_GNU_call_site_target_clobbered = 0x2114;
        DW_AT_GNU_tail_call = 0x2115;
        DW_AT_GNU_all_tail_call_sites = 0x2116;
        DW_AT_GNU_all_call_sites = 0x2117;
        DW_AT_GNU_all_source_call_sites = 0x2118;
        DW_AT_GNU_locviews = 0x2137;
        DW_AT_GNU_entry_view = 0x2138;
        DW_AT_GNU_macros = 0x2119;
        DW_AT_GNU_deleted = 0x211a;
        DW_AT_GNU_dwo_name = 0x2130;
        DW_AT_GNU_dwo_id = 0x2131;
        DW_AT_GNU_ranges_base = 0x2132;
        DW_AT_GNU_addr_base = 0x2133;
        DW_AT_GNU_pubnames = 0x2134;
        DW_AT_GNU_pubtypes = 0x2135;
        DW_AT_GNU_numerator = 0x2303;
        DW_AT_GNU_denominator = 0x2304;
        DW_AT_GNU_bias = 0x2305;
        DW_AT_hi_user = 0x3fff;
    }

    enum DwarfForm : u64 {
        None = 0x0;
        DW_FORM_addr = 0x01;
        DW_FORM_block2 = 0x03;
        DW_FORM_block4 = 0x04;
        DW_FORM_data2 = 0x05;
        DW_FORM_data4 = 0x06;
        DW_FORM_data8 = 0x07;
        DW_FORM_string = 0x08;
        DW_FORM_block = 0x09;
        DW_FORM_block1 = 0x0a;
        DW_FORM_data1 = 0x0b;
        DW_FORM_flag = 0x0c;
        DW_FORM_sdata = 0x0d;
        DW_FORM_strp = 0x0e;
        DW_FORM_udata = 0x0f;
        DW_FORM_ref_addr = 0x10;
        DW_FORM_ref1 = 0x11;
        DW_FORM_ref2 = 0x12;
        DW_FORM_ref4 = 0x13;
        DW_FORM_ref8 = 0x14;
        DW_FORM_ref_udata = 0x15;
        DW_FORM_indirect = 0x16;
        DW_FORM_sec_offset = 0x17;
        DW_FORM_exprloc = 0x18;
        DW_FORM_flag_present = 0x19;
        DW_FORM_strx = 0x1a;
        DW_FORM_addrx = 0x1b;
        DW_FORM_ref_sup4 = 0x1c;
        DW_FORM_strp_sup = 0x1d;
        DW_FORM_data16 = 0x1e;
        DW_FORM_line_strp = 0x1f;
        DW_FORM_ref_sig8 = 0x20;
        DW_FORM_implicit_const = 0x21;
        DW_FORM_loclistx = 0x22;
        DW_FORM_rnglistx = 0x23;
        DW_FORM_ref_sup8 = 0x24;
        DW_FORM_strx1 = 0x25;
        DW_FORM_strx2 = 0x26;
        DW_FORM_strx3 = 0x27;
        DW_FORM_strx4 = 0x28;
        DW_FORM_addrx1 = 0x29;
        DW_FORM_addrx2 = 0x2a;
        DW_FORM_addrx3 = 0x2b;
        DW_FORM_addrx4 = 0x2c;
        DW_FORM_GNU_addr_index = 0x1f01;
        DW_FORM_GNU_str_index = 0x1f02;
        DW_FORM_GNU_ref_alt = 0x1f20;
        DW_FORM_GNU_strp_alt = 0x1f21;
    }

    enum DwarfLineOpcode : u8 {
        DW_LNE = 0;
        DW_LNS_copy = 1;
        DW_LNS_advance_pc = 2;
        DW_LNS_advance_line = 3;
        DW_LNS_set_file = 4;
        DW_LNS_set_column = 5;
        DW_LNS_negate_stmt = 6;
        DW_LNS_set_basic_block = 7;
        DW_LNS_const_add_pc = 8;
        DW_LNS_fixed_advance_pc = 9;
        DW_LNS_set_prologue_end = 10;
        DW_LNS_set_epilogue_begin = 11;
        DW_LNS_set_isa = 12;
    }

    struct AbbrevDeclaration {
        tag: DwarfTag;
        has_children: bool;
        attributes: Array<AbbrevAttribute>;
    }

    struct AbbrevAttribute {
        name: DwarfAttribute;
        form: DwarfForm;
        value: u64;
    }

    u64 translate_leb128(u8* data, int* i) {
        value, shift: u64;
        index := *i;
        while true {
            byte := data[index++];
            value |= (byte & 0x7F) << shift;
            shift += 7;
            if (byte & 0x80) == 0 break;
        }

        *i = index;
        return value;
    }

    bool, u64, string find_function_in_die(u8* data, u64 length, Array<AbbrevDeclaration> declarations, u64 address, u8* debug_strings) {
        is_32bit := false;
        i := 0;

        section_length: u64 = *cast(u32*, data);
        if section_length != 0xFFFFFFFF {
            i = 4;
            is_32bit = true;
        }
        else {
            section_length = *cast(u64*, data + 4);
            i = 12;
        }

        version := *cast(u16*, data + i);
        i += 2;

        address_size: u8;
        abbrev_offset: u64;
        if version >= 5 {
            unit_type := *cast(u8*, data + i++);
            address_size = *cast(u8*, data + i++);
            if is_32bit {
                abbrev_offset = *cast(u32*, data + i);
                i += 4;
            }
            else {
                abbrev_offset = *cast(u64*, data + i);
                i += 8;
            }
        }
        else {
            if is_32bit {
                abbrev_offset = *cast(u32*, data + i);
                i += 4;
            }
            else {
                abbrev_offset = *cast(u64*, data + i);
                i += 8;
            }
            address_size = *cast(u8*, data + i++);
        }

        while i < length {
            abbrev_index := translate_leb128(data, &i);
            if abbrev_index == 0 continue;

            declaration := declarations[abbrev_index - 1];

            low, high, file, name: u64;
            each attribute in declaration.attributes {
                value := parse_dwarf_attribute_value(data, &i, attribute, address_size, is_32bit);
                switch attribute.name {
                    case DwarfAttribute.DW_AT_low_pc; low = value;
                    case DwarfAttribute.DW_AT_high_pc; high = value;
                    case DwarfAttribute.DW_AT_decl_file; file = value;
                    case DwarfAttribute.DW_AT_name; name = value;
                }
            }

            if declaration.tag == DwarfTag.DW_TAG_subprogram {
                if low <= address && address - low <= high {
                    function := convert_c_string(debug_strings + name);
                    return true, low, function;
                }
            }
        }

        return false, 0, empty_string;
    }

    u64 parse_dwarf_attribute_value(u8* data, int* i, AbbrevAttribute attribute, u8 address_size, bool is_32bit) {
        value: u64;
        index := *i;

        switch attribute.form {
            case DwarfForm.DW_FORM_data1;
            case DwarfForm.DW_FORM_ref1;
            case DwarfForm.DW_FORM_flag; {
                value = *(data + index);
                index++;
            }
            case DwarfForm.DW_FORM_data2;
            case DwarfForm.DW_FORM_ref2; {
                value = *cast(u16*, data + index);
                index += 2;
            }
            case DwarfForm.DW_FORM_data4;
            case DwarfForm.DW_FORM_ref4; {
                value = *cast(u32*, data + index);
                index += 4;
            }
            case DwarfForm.DW_FORM_data8;
            case DwarfForm.DW_FORM_ref8; {
                value = *cast(u64*, data + index);
                index += 8;
            }
            case DwarfForm.DW_FORM_sdata;
            case DwarfForm.DW_FORM_udata; {
                value = translate_leb128(data, &index);
            }
            case DwarfForm.DW_FORM_addr; {
                if address_size == 8 {
                    value = *cast(u64*, data + index);
                    index += 8;
                }
                else {
                    value = *cast(u32*, data + index);
                    index += 4;
                }
            }
            case DwarfForm.DW_FORM_ref_addr;
                value = read_dwarf_offset(data, &index, is_32bit);
            case DwarfForm.DW_FORM_flag_present;
                value = 1;
            case DwarfForm.DW_FORM_string; {
                read_inline_dwarf_string(data, &index);
            }
            case DwarfForm.DW_FORM_strp;
            case DwarfForm.DW_FORM_line_strp;
                value = read_dwarf_offset(data, &index, is_32bit);
            case DwarfForm.DW_FORM_exprloc; {
                length := translate_leb128(data, &index);
                index += length;
            }
            case DwarfForm.DW_FORM_sec_offset;
                value = read_dwarf_offset(data, &index, is_32bit);
            case DwarfForm.DW_FORM_implicit_const;
                value = attribute.value;
        }

        *i = index;
        return value;
    }

    u64 read_dwarf_offset(u8* data, int* i, bool is_32bit) {
        value: u64;
        if is_32bit {
            value = *cast(u32*, data + *i);
            *i = *i + 4;
        }
        else {
            value = *cast(u64*, data + *i);
            *i = *i + 8;
        }

        return value;
    }

    bool, u64, u64, string, string find_debug_line_location(u8* data, u64 length, u64 address, u64 function_start) {
        is_32bit := false;
        i := 0;

        section_length: u64 = *cast(u32*, data);
        if section_length != 0xFFFFFFFF {
            i = 4;
            is_32bit = true;
        }
        else {
            section_length = *cast(u64*, data + 4);
            i = 12;
        }

        version := *cast(u16*, data + i);
        i += 2;

        prologue_length: u64;
        if is_32bit {
            prologue_length = *cast(u32*, data + i);
            i += 4;
        }
        else {
            prologue_length = *cast(u64*, data + i);
            i += 8;
        }
        min_instruction_length := translate_leb128(data, &i);
        max_ops_per_instruction := translate_leb128(data, &i);
        default_is_statement := translate_leb128(data, &i);
        line_base := *cast(s8*, data + i++);
        line_range := translate_leb128(data, &i);
        opcode_base := translate_leb128(data, &i);

        i += 12;

        directories: Array<string>;
        while i < length {
            directory := read_inline_dwarf_string(data, &i);
            if directory.length == 0 break;

            array_insert(&directories, directory);
        }

        files: Array<DwarfFileEntry>;
        while i < length {
            file := read_inline_dwarf_string(data, &i);
            if file.length == 0 break;

            entry: DwarfFileEntry = { file = file; }
            entry.directory = translate_leb128(data, &i);
            entry.mod_time = translate_leb128(data, &i);
            entry.length = translate_leb128(data, &i);

            array_insert(&files, entry);
        }

        current_address, file, line, column: u64;
        while i < length {
            opcode := *cast(DwarfLineOpcode*, data + i++);
            switch opcode {
                case DwarfLineOpcode.DW_LNE; {
                    // TODO Handle extended opcodes
                }
                case DwarfLineOpcode.DW_LNS_copy;
                case DwarfLineOpcode.DW_LNS_negate_stmt;
                case DwarfLineOpcode.DW_LNS_set_basic_block;
                case DwarfLineOpcode.DW_LNS_fixed_advance_pc;
                case DwarfLineOpcode.DW_LNS_set_prologue_end;
                case DwarfLineOpcode.DW_LNS_set_epilogue_begin; {
                    // These opcodes have no arguments or actions
                }
                case DwarfLineOpcode.DW_LNS_advance_pc; {
                    // TODO Update address
                }
                case DwarfLineOpcode.DW_LNS_advance_line; {
                    // TODO Update line
                }
                case DwarfLineOpcode.DW_LNS_set_file; {
                    // TODO Calculate file
                }
                case DwarfLineOpcode.DW_LNS_set_column; {
                    // TODO Calculate column
                }
                case DwarfLineOpcode.DW_LNS_const_add_pc; {
                    // TODO Calculate advance
                }
                case DwarfLineOpcode.DW_LNS_set_isa; {
                    i++;
                }
                default; {
                    // TODO Update address/line/op-index
                }
            }
        }

        return false, 0, 0, empty_string, empty_string;
    }

    struct DwarfFileEntry {
        file: string;
        directory: u64;
        mod_time: u64;
        length: u64;
    }

    string read_inline_dwarf_string(u8* data, int* i) {
        value := convert_c_string(data + *i);
        *i = *i + value.length + 1;
        return value;
    }
}
