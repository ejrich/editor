#if os == OS.Linux {
    #system_library shaderc "shaderc_shared"
}
#if os == OS.Windows {
    #library shaderc "shaderc_shared"
}

enum shaderc_target_env {
    shaderc_target_env_vulkan = 0;
    shaderc_target_env_opengl;
    shaderc_target_env_opengl_compat;
    shaderc_target_env_webgpu;
    shaderc_target_env_default = shaderc_target_env_vulkan;
}

enum shaderc_env_version {
    shaderc_env_version_vulkan_1_0 = 0x400000;
    shaderc_env_version_vulkan_1_1 = 0x401000;
    shaderc_env_version_vulkan_1_2 = 0x402000;
    shaderc_env_version_vulkan_1_3 = 0x403000;
    shaderc_env_version_opengl_4_5 = 450;
    shaderc_env_version_webgpu = 451;
}

enum shaderc_spirv_version {
    shaderc_spirv_version_1_0 = 0x010000;
    shaderc_spirv_version_1_1 = 0x010100;
    shaderc_spirv_version_1_2 = 0x010200;
    shaderc_spirv_version_1_3 = 0x010300;
    shaderc_spirv_version_1_4 = 0x010400;
    shaderc_spirv_version_1_5 = 0x010500;
    shaderc_spirv_version_1_6 = 0x010600;
}

enum shaderc_compilation_status {
    shaderc_compilation_status_success = 0;
    shaderc_compilation_status_invalid_stage = 1;
    shaderc_compilation_status_compilation_error = 2;
    shaderc_compilation_status_internal_error = 3;
    shaderc_compilation_status_null_result_object = 4;
    shaderc_compilation_status_invalid_assembly = 5;
    shaderc_compilation_status_validation_error = 6;
    shaderc_compilation_status_transformation_error = 7;
    shaderc_compilation_status_configuration_error = 8;
}

enum shaderc_source_language {
    shaderc_source_language_glsl;
    shaderc_source_language_hlsl;
}

enum shaderc_shader_kind {
    shaderc_vertex_shader = 0;
    shaderc_fragment_shader = 1;
    shaderc_compute_shader = 2;
    shaderc_geometry_shader = 3;
    shaderc_tess_control_shader = 4;
    shaderc_tess_evaluation_shader = 5;
    shaderc_glsl_vertex_shader = shaderc_vertex_shader;
    shaderc_glsl_fragment_shader = shaderc_fragment_shader;
    shaderc_glsl_compute_shader = shaderc_compute_shader;
    shaderc_glsl_geometry_shader = shaderc_geometry_shader;
    shaderc_glsl_tess_control_shader = shaderc_tess_control_shader;
    shaderc_glsl_tess_evaluation_shader = shaderc_tess_evaluation_shader;
    shaderc_glsl_infer_from_source = 6;
    shaderc_glsl_default_vertex_shader = 7;
    shaderc_glsl_default_fragment_shader = 8;
    shaderc_glsl_default_compute_shader = 9;
    shaderc_glsl_default_geometry_shader = 10;
    shaderc_glsl_default_tess_control_shader = 11;
    shaderc_glsl_default_tess_evaluation_shader = 12;
    shaderc_spirv_assembly = 13;
    shaderc_raygen_shader = 14;
    shaderc_anyhit_shader = 15;
    shaderc_closesthit_shader = 16;
    shaderc_miss_shader = 17;
    shaderc_intersection_shader = 18;
    shaderc_callable_shader = 19;
    shaderc_glsl_raygen_shader = shaderc_raygen_shader;
    shaderc_glsl_anyhit_shader = shaderc_anyhit_shader;
    shaderc_glsl_closesthit_shader = shaderc_closesthit_shader;
    shaderc_glsl_miss_shader = shaderc_miss_shader;
    shaderc_glsl_intersection_shader = shaderc_intersection_shader;
    shaderc_glsl_callable_shader = shaderc_callable_shader;
    shaderc_glsl_default_raygen_shader = 20;
    shaderc_glsl_default_anyhit_shader = 21;
    shaderc_glsl_default_closesthit_shader = 22;
    shaderc_glsl_default_miss_shader = 23;
    shaderc_glsl_default_intersection_shader = 24;
    shaderc_glsl_default_callable_shader = 25;
    shaderc_task_shader = 26;
    shaderc_mesh_shader = 27;
    shaderc_glsl_task_shader = shaderc_task_shader;
    shaderc_glsl_mesh_shader = shaderc_mesh_shader;
    shaderc_glsl_default_task_shader = 28;
    shaderc_glsl_default_mesh_shader = 29;
}

enum shaderc_profile {
    shaderc_profile_none;
    shaderc_profile_core;
    shaderc_profile_compatibility;
    shaderc_profile_es;
}

enum shaderc_optimization_level {
    shaderc_optimization_level_zero;
    shaderc_optimization_level_size;
    shaderc_optimization_level_performance;
}

enum shaderc_limit {
    shaderc_limit_max_lights;
    shaderc_limit_max_clip_planes;
    shaderc_limit_max_texture_units;
    shaderc_limit_max_texture_coords;
    shaderc_limit_max_vertex_attribs;
    shaderc_limit_max_vertex_uniform_components;
    shaderc_limit_max_varying_floats;
    shaderc_limit_max_vertex_texture_image_units;
    shaderc_limit_max_combined_texture_image_units;
    shaderc_limit_max_texture_image_units;
    shaderc_limit_max_fragment_uniform_components;
    shaderc_limit_max_draw_buffers;
    shaderc_limit_max_vertex_uniform_vectors;
    shaderc_limit_max_varying_vectors;
    shaderc_limit_max_fragment_uniform_vectors;
    shaderc_limit_max_vertex_output_vectors;
    shaderc_limit_max_fragment_input_vectors;
    shaderc_limit_min_program_texel_offset;
    shaderc_limit_max_program_texel_offset;
    shaderc_limit_max_clip_distances;
    shaderc_limit_max_compute_work_group_count_x;
    shaderc_limit_max_compute_work_group_count_y;
    shaderc_limit_max_compute_work_group_count_z;
    shaderc_limit_max_compute_work_group_size_x;
    shaderc_limit_max_compute_work_group_size_y;
    shaderc_limit_max_compute_work_group_size_z;
    shaderc_limit_max_compute_uniform_components;
    shaderc_limit_max_compute_texture_image_units;
    shaderc_limit_max_compute_image_uniforms;
    shaderc_limit_max_compute_atomic_counters;
    shaderc_limit_max_compute_atomic_counter_buffers;
    shaderc_limit_max_varying_components;
    shaderc_limit_max_vertex_output_components;
    shaderc_limit_max_geometry_input_components;
    shaderc_limit_max_geometry_output_components;
    shaderc_limit_max_fragment_input_components;
    shaderc_limit_max_image_units;
    shaderc_limit_max_combined_image_units_and_fragment_outputs;
    shaderc_limit_max_combined_shader_output_resources;
    shaderc_limit_max_image_samples;
    shaderc_limit_max_vertex_image_uniforms;
    shaderc_limit_max_tess_control_image_uniforms;
    shaderc_limit_max_tess_evaluation_image_uniforms;
    shaderc_limit_max_geometry_image_uniforms;
    shaderc_limit_max_fragment_image_uniforms;
    shaderc_limit_max_combined_image_uniforms;
    shaderc_limit_max_geometry_texture_image_units;
    shaderc_limit_max_geometry_output_vertices;
    shaderc_limit_max_geometry_total_output_components;
    shaderc_limit_max_geometry_uniform_components;
    shaderc_limit_max_geometry_varying_components;
    shaderc_limit_max_tess_control_input_components;
    shaderc_limit_max_tess_control_output_components;
    shaderc_limit_max_tess_control_texture_image_units;
    shaderc_limit_max_tess_control_uniform_components;
    shaderc_limit_max_tess_control_total_output_components;
    shaderc_limit_max_tess_evaluation_input_components;
    shaderc_limit_max_tess_evaluation_output_components;
    shaderc_limit_max_tess_evaluation_texture_image_units;
    shaderc_limit_max_tess_evaluation_uniform_components;
    shaderc_limit_max_tess_patch_components;
    shaderc_limit_max_patch_vertices;
    shaderc_limit_max_tess_gen_level;
    shaderc_limit_max_viewports;
    shaderc_limit_max_vertex_atomic_counters;
    shaderc_limit_max_tess_control_atomic_counters;
    shaderc_limit_max_tess_evaluation_atomic_counters;
    shaderc_limit_max_geometry_atomic_counters;
    shaderc_limit_max_fragment_atomic_counters;
    shaderc_limit_max_combined_atomic_counters;
    shaderc_limit_max_atomic_counter_bindings;
    shaderc_limit_max_vertex_atomic_counter_buffers;
    shaderc_limit_max_tess_control_atomic_counter_buffers;
    shaderc_limit_max_tess_evaluation_atomic_counter_buffers;
    shaderc_limit_max_geometry_atomic_counter_buffers;
    shaderc_limit_max_fragment_atomic_counter_buffers;
    shaderc_limit_max_combined_atomic_counter_buffers;
    shaderc_limit_max_atomic_counter_buffer_size;
    shaderc_limit_max_transform_feedback_buffers;
    shaderc_limit_max_transform_feedback_interleaved_components;
    shaderc_limit_max_cull_distances;
    shaderc_limit_max_combined_clip_and_cull_distances;
    shaderc_limit_max_samples;
    shaderc_limit_max_mesh_output_vertices_nv;
    shaderc_limit_max_mesh_output_primitives_nv;
    shaderc_limit_max_mesh_work_group_size_x_nv;
    shaderc_limit_max_mesh_work_group_size_y_nv;
    shaderc_limit_max_mesh_work_group_size_z_nv;
    shaderc_limit_max_task_work_group_size_x_nv;
    shaderc_limit_max_task_work_group_size_y_nv;
    shaderc_limit_max_task_work_group_size_z_nv;
    shaderc_limit_max_mesh_view_count_nv;
    shaderc_limit_max_mesh_output_vertices_ext;
    shaderc_limit_max_mesh_output_primitives_ext;
    shaderc_limit_max_mesh_work_group_size_x_ext;
    shaderc_limit_max_mesh_work_group_size_y_ext;
    shaderc_limit_max_mesh_work_group_size_z_ext;
    shaderc_limit_max_task_work_group_size_x_ext;
    shaderc_limit_max_task_work_group_size_y_ext;
    shaderc_limit_max_task_work_group_size_z_ext;
    shaderc_limit_max_mesh_view_count_ext;
    shaderc_limit_max_dual_source_draw_buffers_ext;
}

enum shaderc_uniform_kind {
    shaderc_uniform_kind_image;
    shaderc_uniform_kind_sampler;
    shaderc_uniform_kind_texture;
    shaderc_uniform_kind_buffer;
    shaderc_uniform_kind_storage_buffer;
    shaderc_uniform_kind_unordered_access_view;
}

struct shaderc_compiler {}
struct shaderc_compile_options {}
struct shaderc_compilation_result {}

shaderc_compiler* shaderc_compiler_initialize() #extern shaderc

shaderc_compiler_release(shaderc_compiler* compiler) #extern shaderc

shaderc_compile_options* shaderc_compile_options_initialize() #extern shaderc

shaderc_compile_options* shaderc_compile_options_clone(shaderc_compile_options* options) #extern shaderc

shaderc_compile_options_release(shaderc_compile_options* options) #extern shaderc

shaderc_compile_options_add_macro_definition(shaderc_compile_options* options, u8* name, s64 name_length, u8* value, s64 value_length) #extern shaderc

shaderc_compile_options_set_source_language(shaderc_compile_options* options, shaderc_source_language lang) #extern shaderc

shaderc_compile_options_set_generate_debug_info(shaderc_compile_options* options) #extern shaderc

shaderc_compile_options_set_optimization_level(shaderc_compile_options* options, shaderc_optimization_level level) #extern shaderc

shaderc_compile_options_set_forced_version_profile(shaderc_compile_options* options, s32 version, shaderc_profile profile) #extern shaderc

struct shaderc_include_result {
    source_name: u8*;
    source_name_length: s64;
    content: u8*;
    content_length: s64;
    user_data: void*;
}

enum shaderc_include_type {
    shaderc_include_type_relative;
    shaderc_include_type_standard;
}

interface shaderc_include_result* shaderc_include_resolve_fn(void* user_data, u8* requested_source, s32 type, u8* requesting_source, s64 include_depth)

interface shaderc_include_result_release_fn(void* user_data, shaderc_include_result* include_result)

shaderc_compile_options_set_include_callbacks(shaderc_compile_options* options, shaderc_include_resolve_fn resolver, shaderc_include_result_release_fn result_releaser, void* user_data) #extern shaderc

shaderc_compile_options_set_suppress_warnings(shaderc_compile_options* options) #extern shaderc

shaderc_compile_options_set_target_env(shaderc_compile_options* options, shaderc_target_env target, u32 version) #extern shaderc

shaderc_compile_options_set_target_spirv(shaderc_compile_options* options, shaderc_spirv_version version) #extern shaderc

shaderc_compile_options_set_warnings_as_errors(shaderc_compile_options* options) #extern shaderc

shaderc_compile_options_set_limit(shaderc_compile_options* options, shaderc_limit limit, s32 value) #extern shaderc

shaderc_compile_options_set_auto_bind_uniforms(shaderc_compile_options* options, bool auto_bind) #extern shaderc

shaderc_compile_options_set_auto_combined_image_sampler(shaderc_compile_options* options, bool upgrade) #extern shaderc

shaderc_compile_options_set_hlsl_io_mapping(shaderc_compile_options* options, bool hlsl_iomap) #extern shaderc

shaderc_compile_options_set_hlsl_offsets(shaderc_compile_options* options, bool hlsl_offsets) #extern shaderc

shaderc_compile_options_set_binding_base(shaderc_compile_options* options, shaderc_uniform_kind kind, u32 base) #extern shaderc

shaderc_compile_options_set_binding_base_for_stage(shaderc_compile_options* options, shaderc_shader_kind shader_kind, shaderc_uniform_kind kind, u32 base) #extern shaderc

shaderc_compile_options_set_preserve_bindings(shaderc_compile_options* options, bool preserve_bindings) #extern shaderc

shaderc_compile_options_set_auto_map_locations(shaderc_compile_options* options, bool auto_map) #extern shaderc

shaderc_compile_options_set_hlsl_register_set_and_binding_for_stage(shaderc_compile_options* options, shaderc_shader_kind shader_kind, u8* reg, u8* set, u8* binding) #extern shaderc

shaderc_compile_options_set_hlsl_register_set_and_binding(shaderc_compile_options* options, u8* reg, u8* set, u8* binding) #extern shaderc

shaderc_compile_options_set_hlsl_functionality1(shaderc_compile_options* options, bool enable) #extern shaderc

shaderc_compile_options_set_hlsl_16bit_types(shaderc_compile_options* options, bool enable) #extern shaderc

shaderc_compile_options_set_invert_y(shaderc_compile_options* options, bool enable) #extern shaderc

shaderc_compile_options_set_nan_clamp(shaderc_compile_options* options, bool enable) #extern shaderc

shaderc_compilation_result* shaderc_compile_into_spv(shaderc_compiler* compiler, u8* source_text, s64 source_text_size, shaderc_shader_kind shader_kind, u8* input_file_name, u8* entry_point_name, shaderc_compile_options* additional_options) #extern shaderc

shaderc_compilation_result* shaderc_compile_into_spv_assembly(shaderc_compiler* compiler, u8* source_text, s64 source_text_size, shaderc_shader_kind shader_kind, u8* input_file_name, u8* entry_point_name, shaderc_compile_options* additional_options) #extern shaderc

shaderc_compilation_result* shaderc_compile_into_preprocessed_text(shaderc_compiler* compiler, u8* source_text, s64 source_text_size, shaderc_shader_kind shader_kind, u8* input_file_name, u8* entry_point_name, shaderc_compile_options* additional_options) #extern shaderc

shaderc_compilation_result* shaderc_assemble_into_spv(shaderc_compiler* compiler, u8* source_assembly, s64 source_assembly_size, shaderc_compile_options* additional_options) #extern shaderc

shaderc_result_release(shaderc_compilation_result* result) #extern shaderc

s64 shaderc_result_get_length(shaderc_compilation_result* result) #extern shaderc

s64 shaderc_result_get_num_warnings(shaderc_compilation_result* result) #extern shaderc

s64 shaderc_result_get_num_errors(shaderc_compilation_result* result) #extern shaderc

shaderc_compilation_status shaderc_result_get_compilation_status(shaderc_compilation_result* result) #extern shaderc

u8* shaderc_result_get_bytes(shaderc_compilation_result* result) #extern shaderc

u8* shaderc_result_get_error_message(shaderc_compilation_result* result) #extern shaderc

shaderc_get_spv_version(u32* version, u32* revision) #extern shaderc

bool shaderc_parse_version_profile(u8* str, s32* version, shaderc_profile* profile) #extern shaderc
