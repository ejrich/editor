#import math
#import vulkan

MAX_FRAMES_IN_FLIGHT: u32 = 2; #const
VERTICES_PER_QUAD := 6; #const
frame_index: u32;

graphics_initialized := false;

// Data structures for storing general graphics data and handles
struct Vertex {
    position: Vector3;
    normal: Vector3;
    texture_coordinate: Vector2;
}

struct Buffer {
    length: u64;
    buffer: VkBuffer*;
    memory: VkDeviceMemory*;
}

struct Texture {
    image: VkImage*;
    image_memory: VkDeviceMemory*;
    image_view: VkImageView*;
}

struct GraphicsPipeline {
    descriptor_set_layouts: Array<VkDescriptorSetLayout*>;
    layout: VkPipelineLayout*;
    handle: VkPipeline*;
}

struct GraphicsPipelineLayout {
    shader: ShaderName;
    render_pass: RenderPass;
    topology := PrimitiveTopology.Triangles;
    descriptor_set_layouts := 1;
    push_constant_stage := ShaderStage.Vertex;
    push_constant_type: TypeInfo*;
    bindings: Array<PipelineBinding>;
    vertex_bindings: Array<VertexBinding>;
}

enum PrimitiveTopology {
    Points;
    Line;
    LineStrip;
    Triangles;
    TriangleStrip;
    TriangleFan;
}

enum RenderPass {
    UI;
}

struct VertexBinding {
    type: TypeInfo*;
    instanced: bool;
}

struct PipelineBinding {
    binding_type: PipelineBindingType;
    descriptor_set_index: int;
    stage: ShaderStage;
    type: TypeInfo*;
}

enum PipelineBindingType {
    None = 0;
    Texture;
    UniformBuffer;
    StorageBuffer;
    UniformBufferDynamic;
    StorageBufferDynamic;
}

struct DescriptorSet {
    pool: VkDescriptorPool*;
    set: VkDescriptorSet*;
}

struct InstanceBuffer {
    buffer: Buffer;
    descriptor_set: DescriptorSet;
    data: void*;
}

enum QuadFlags : u32 {
    None;
    SingleChannel;
    Solid;
}

struct QuadInstanceData {
    color: Vector4 = { x = 1.0; y = 1.0; z = 1.0; w = 1.0; }
    position: Vector3;
    flags: QuadFlags;
    width: float;
    height: float;
    bottom_left_texture_coord: Vector2;
    top_right_texture_coord: Vector2;
    __padding: Vector2;
}

// General functions for initialization and deinitialization
init_graphics() {
    #if DEVELOPER {
        shader_directory := temp_string(get_program_directory(), "/shaders");
        if !file_exists(shader_directory) {
            create_directory(shader_directory);
        }
    }

    // Initialize the vulkan instance with the required extensions
    version := vk_make_api_version(0, 1, 0, 0);
    engine_name := "cen"; #const

    app_info: VkApplicationInfo = {
        pApplicationName = application_name.data;
        applicationVersion = version;
        pEngineName = engine_name.data;
        engineVersion = version;
        apiVersion = vk_api_version_1_1();
    }

    extension_count: u32;
    result := vkEnumerateInstanceExtensionProperties(null, &extension_count, null);

    if result != VkResult.VK_SUCCESS {
        log("Unable to get vulkan extensions\n");
        exit_program(1);
    }

    extensions: Array<VkExtensionProperties>[extension_count];
    vkEnumerateInstanceExtensionProperties(null, &extension_count, extensions.data);

    // Initialize with capacity for all extensions
    enabled_extensions: Array<u8*>[extension_count];
    enabled_extensions.length = 0;

    each extension in extensions {
        name := convert_c_string(&extension.extensionName);

        if name == VK_KHR_SURFACE_EXTENSION_NAME {
            enabled_extensions[enabled_extensions.length++] = VK_KHR_SURFACE_EXTENSION_NAME.data;
        }
        #if os == OS.Linux {
            if name == VK_KHR_XLIB_SURFACE_EXTENSION_NAME {
                enabled_extensions[enabled_extensions.length++] = VK_KHR_XLIB_SURFACE_EXTENSION_NAME.data;
            }
        }
        #if os == OS.Windows {
            if name == VK_KHR_WIN32_SURFACE_EXTENSION_NAME {
                enabled_extensions[enabled_extensions.length++] = VK_KHR_WIN32_SURFACE_EXTENSION_NAME.data;
            }
        }
    }

    instance_create_info: VkInstanceCreateInfo;
    #if DEVELOPER {
        layer_count: u32;
        vkEnumerateInstanceLayerProperties(&layer_count, null);

        available_layers: Array<VkLayerProperties>[layer_count];
        vkEnumerateInstanceLayerProperties(&layer_count, available_layers.data);

        each layer_name in validation_layers {
            layer_found := false;

            each layer_properties in available_layers {
                name := convert_c_string(&layer_properties.layerName);
                if layer_name == name {
                    layer_found = true;
                    break;
                }
            }

            if !layer_found {
                log("Validation layer '%' not found\n", layer_name);
                exit_program(1);
            }
        }

        enabled_extensions[enabled_extensions.length++] = VK_EXT_DEBUG_UTILS_EXTENSION_NAME.data;

        instance_create_info = {
            pApplicationInfo = &app_info;
            enabledExtensionCount = enabled_extensions.length;
            ppEnabledExtensionNames = enabled_extensions.data;
            enabledLayerCount = validation_layers.length;
            ppEnabledLayerNames = &validation_layers[0].data; // Not pretty, but works
        }
    }
    else {
        instance_create_info = {
            pApplicationInfo = &app_info;
            enabledExtensionCount = enabled_extensions.length;
            ppEnabledExtensionNames = enabled_extensions.data;
        }
    }

    result = vkCreateInstance(&instance_create_info, &allocator, &instance);
    if result != VkResult.VK_SUCCESS {
        log("Unable to create vulkan instance %\n", result);
        exit_program(1);
    }

    // Create the debug messenger if building in developer
    #if DEVELOPER {
        messenger_create_info: VkDebugUtilsMessengerCreateInfoEXT = {
            messageSeverity = VkDebugUtilsMessageSeverityFlagBitsEXT.VK_DEBUG_UTILS_MESSAGE_SEVERITY_NOT_INFO_BIT_EXT;
            messageType = VkDebugUtilsMessageTypeFlagBitsEXT.VK_DEBUG_UTILS_MESSAGE_TYPE_ALL_EXT;
            pfnUserCallback = debug_callback;
        }

        func: PFN_vkCreateDebugUtilsMessengerEXT = vkGetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT");
        if func != null {
            result = func(instance, &messenger_create_info, &allocator, &debug_messenger);
            if result != VkResult.VK_SUCCESS {
                log("Failed to set up debug messenger %\n", result);
                exit_program(1);
            }
        }
        else {
            log("Failed to set up debug messenger\n");
            exit_program(1);
        }
    }

    // Create the window surface
    #if os == OS.Linux {
        surface_create_info: VkXlibSurfaceCreateInfoKHR = {
            dpy = window.handle;
            window = window.window;
        }

        result = vkCreateXlibSurfaceKHR(instance, &surface_create_info, &allocator, &surface);
    }
    #if os == OS.Windows {
        surface_create_info: VkWin32SurfaceCreateInfoKHR = {
            hinstance = GetModuleHandleA(null);
            hwnd = window.handle;
        }

        result = vkCreateWin32SurfaceKHR(instance, &surface_create_info, &allocator, &surface);
    }

    if result != VkResult.VK_SUCCESS {
        log("Unable to create window surface %\n", result);
        exit_program(1);
    }

    // Pick the physical device
    device_count: u32;
    vkEnumeratePhysicalDevices(instance, &device_count, null);

    if device_count == 0 {
        log("Failed to find GPUs with Vulkan support\n");
        exit_program(1);
    }

    devices: Array<VkPhysicalDevice*>[device_count];
    vkEnumeratePhysicalDevices(instance, &device_count, devices.data);

    highest_score: u32;
    each device_candidate in devices {
        properties: VkPhysicalDeviceProperties;
        vkGetPhysicalDeviceProperties(device_candidate, &properties);

        features: VkPhysicalDeviceFeatures;
        vkGetPhysicalDeviceFeatures(device_candidate, &features);

        device_score := properties.limits.maxImageDimension2D;
        if properties.deviceType == VkPhysicalDeviceType.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU device_score += 1000;

        if features.geometryShader == VK_FALSE || features.samplerAnisotropy == VK_FALSE continue;

        graphics_family, present_family, compute_family, transfer_family: u32;
        queue_flags: PhysicalDeviceQueueFlags;
        if !find_queue_families(device_candidate, &graphics_family, &present_family, &compute_family, &transfer_family, &queue_flags) continue;

        if !check_device_extension_support(device_candidate) continue;

        format_count: u32;
        vkGetPhysicalDeviceSurfaceFormatsKHR(device_candidate, surface, &format_count, null);
        if format_count <= 0 continue;

        present_mode_count: u32;
        vkGetPhysicalDeviceSurfacePresentModesKHR(device_candidate, surface, &present_mode_count, null);
        if present_mode_count <= 0 continue;

        if device_score > highest_score {
            physical_device = device_candidate;
            graphics_queue_family = graphics_family;
            present_queue_family = present_family;
            compute_queue_family = compute_family;
            transfer_queue_family = transfer_family;
            queue_family_flags = queue_flags;
            highest_score = device_score;
        }
    }

    if physical_device == null {
        log("Failed to find a suitable GPU\n");
        exit_program(1);
    }

    format_properties: VkFormatProperties;
    each format in depth_formats {
        vkGetPhysicalDeviceFormatProperties(physical_device, format, &format_properties);
        if (format_properties.optimalTilingFeatures & VkFormatFeatureFlagBits.VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT) == VkFormatFeatureFlagBits.VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT
            depth_format = format;
    }

    if depth_format == VkFormat.VK_FORMAT_UNDEFINED {
        log("Failed to find supported depth format\n");
        exit_program(1);
    }

    properties: VkPhysicalDeviceProperties;
    vkGetPhysicalDeviceProperties(physical_device, &properties);
    max_ubo_size           = properties.limits.maxUniformBufferRange;
    ubo_offset_alignment   = properties.limits.minUniformBufferOffsetAlignment;
    max_ssbo_size          = properties.limits.maxStorageBufferRange;
    ssbo_offset_alignment  = properties.limits.minStorageBufferOffsetAlignment;
    max_push_constant_size = properties.limits.maxPushConstantsSize;

    counts := properties.limits.framebufferColorSampleCounts & properties.limits.framebufferDepthSampleCounts;
    if counts & VkSampleCountFlagBits.VK_SAMPLE_COUNT_64_BIT      msaa_samples = VkSampleCountFlagBits.VK_SAMPLE_COUNT_64_BIT;
    else if counts & VkSampleCountFlagBits.VK_SAMPLE_COUNT_32_BIT msaa_samples = VkSampleCountFlagBits.VK_SAMPLE_COUNT_32_BIT;
    else if counts & VkSampleCountFlagBits.VK_SAMPLE_COUNT_16_BIT msaa_samples = VkSampleCountFlagBits.VK_SAMPLE_COUNT_16_BIT;
    else if counts & VkSampleCountFlagBits.VK_SAMPLE_COUNT_8_BIT  msaa_samples = VkSampleCountFlagBits.VK_SAMPLE_COUNT_8_BIT;
    else if counts & VkSampleCountFlagBits.VK_SAMPLE_COUNT_4_BIT  msaa_samples = VkSampleCountFlagBits.VK_SAMPLE_COUNT_4_BIT;
    else if counts & VkSampleCountFlagBits.VK_SAMPLE_COUNT_2_BIT  msaa_samples = VkSampleCountFlagBits.VK_SAMPLE_COUNT_2_BIT;

    // Determine the queues to create
    max_queue_count, queue_family_count, graphics_queue_count, compute_queue_count, transfer_queue_count, used_families: u32;
    vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, null);

    families: Array<VkQueueFamilyProperties>[queue_family_count];
    vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, families.data);

    queue_create_infos: Array<VkDeviceQueueCreateInfo>[queue_family_count];
    each family, i in families {
        queue_count := 0;
        if i == present_queue_family {
            queue_count = 1;
        }

        if i == graphics_queue_family {
            queue_count = family.queueCount;
            graphics_queue_count = family.queueCount;
        }
        else if i == compute_queue_family {
            queue_count = family.queueCount;
            compute_queue_count = family.queueCount;
        }
        else if i == transfer_queue_family {
            queue_count = family.queueCount;
            transfer_queue_count = family.queueCount;
        }

        if queue_count {
            if queue_count > max_queue_count {
                max_queue_count = queue_count;
            }

            queue_create_info: VkDeviceQueueCreateInfo = {
                queueFamilyIndex = i;
                queueCount = queue_count;
            }

            queue_create_infos[used_families++] = queue_create_info;
        }
    }

    queue_priorities: Array<float>[max_queue_count];
    each priority in queue_priorities {
        priority = 1.0;
    }

    each i in used_families {
        queue_create_infos[i].pQueuePriorities = queue_priorities.data;
    }

    // Create the logical device
    features: VkPhysicalDeviceFeatures2;
    #if DEVELOPER {
        barycentric_features: VkPhysicalDeviceFragmentShaderBarycentricFeaturesNV = { fragmentShaderBarycentric = 0; }
        features.pNext = &barycentric_features;
    }
    vkGetPhysicalDeviceFeatures2(physical_device, &features);

    device_extension_pointers: Array<u8*>[device_extensions.length];
    each extension, i in device_extensions {
        device_extension_pointers[i] = extension.data;
    }

    device_create_info: VkDeviceCreateInfo = {
        pNext = features.pNext;
        queueCreateInfoCount = used_families;
        pQueueCreateInfos = queue_create_infos.data;
        enabledExtensionCount = device_extensions.length;
        ppEnabledExtensionNames = device_extension_pointers.data;
        pEnabledFeatures = &features.features;
    }

    #if DEVELOPER {
        device_create_info = {
            enabledLayerCount = validation_layers.length;
            ppEnabledLayerNames = &validation_layers[0].data;
        }
    }

    result = vkCreateDevice(physical_device, &device_create_info, &allocator, &device);
    if result != VkResult.VK_SUCCESS {
        log("Unable to create vulkan device %\n", result);
        exit_program(1);
    }

    // Create the command pools and queues
    create_command_pools(&graphics_command_pools, graphics_queue_family);


    if queue_family_flags == PhysicalDeviceQueueFlags.SingleQueue {
        vkGetDeviceQueue(device, graphics_queue_family, 0, &graphics_queue);
        create_semaphore(&graphics_queue_semaphore, 1, 1);
        submit_to_graphics_queue = submit_command_buffer_to_single_graphics_queue;

        submit_to_compute_queue = submit_command_buffer_to_single_graphics_queue;
        compute_command_pools = graphics_command_pools;

        submit_to_transfer_queue = submit_command_buffer_to_single_graphics_queue;
        transfer_command_pools = graphics_command_pools;

        if graphics_queue_family == present_queue_family {
            submit_present = submit_present_single_queue;
        }
        else {
            submit_present = submit_present_dedicated_present_queue;
            vkGetDeviceQueue(device, present_queue_family, 0, &present_queue);
        }
    }
    else if queue_family_flags & PhysicalDeviceQueueFlags.SingleGraphicsQueue {
        vkGetDeviceQueue(device, graphics_queue_family, 0, &graphics_queue);
        create_semaphore(&graphics_queue_semaphore, 1, 1);
        submit_to_graphics_queue = submit_command_buffer_to_single_graphics_queue;

        if queue_family_flags & PhysicalDeviceQueueFlags.CombinedComputeTransferQueueFamily {
            assert(compute_queue_family == transfer_queue_family);

            create_queues_and_locks(compute_queue_family, &compute_queue_semaphore, compute_queue_count, &compute_queue_locks, &compute_queues);

            submit_to_compute_queue = submit_command_buffer_to_compute_queue;
            create_command_pools(&compute_command_pools, compute_queue_family);

            submit_to_transfer_queue = submit_command_buffer_to_compute_queue;
            transfer_command_pools = compute_command_pools;
        }
        else {
            if queue_family_flags & PhysicalDeviceQueueFlags.DedicatedComputeQueueFamily {
                create_queues_and_locks(compute_queue_family, &compute_queue_semaphore, compute_queue_count, &compute_queue_locks, &compute_queues);

                create_command_pools(&compute_command_pools, compute_queue_family);
                submit_to_compute_queue = submit_command_buffer_to_compute_queue;
            }
            else {
                submit_to_compute_queue = submit_command_buffer_to_single_graphics_queue;
                compute_command_pools = graphics_command_pools;
            }

            if queue_family_flags & PhysicalDeviceQueueFlags.DedicatedTransferQueueFamily {
                create_queues_and_locks(transfer_queue_family, &transfer_queue_semaphore, transfer_queue_count, &transfer_queue_locks, &transfer_queues);

                create_command_pools(&transfer_command_pools, transfer_queue_family);
                submit_to_transfer_queue = submit_command_buffer_to_transfer_queue;
            }
            else {
                submit_to_transfer_queue = submit_command_buffer_to_single_graphics_queue;
                transfer_command_pools = graphics_command_pools;
            }
        }

        if graphics_queue_family == present_queue_family {
            submit_present = submit_present_single_queue;
        }
        else if compute_queue_family == present_queue_family {
            submit_present = submit_present_compute_queue;
        }
        else if transfer_queue_family == present_queue_family {
            submit_present = submit_present_transfer_queue;
        }
        else {
            submit_present = submit_present_dedicated_present_queue;
            vkGetDeviceQueue(device, present_queue_family, 0, &present_queue);
        }
    }
    else {
        if graphics_queue_family != present_queue_family {
            submit_present = submit_present_dedicated_present_queue;
            vkGetDeviceQueue(device, present_queue_family, 0, &present_queue);
        }

        // If there are enough graphics queues for each thread, only allocate 1 graphics queue for each thread
        if graphics_queue_count >= thread_count {
            submit_to_graphics_queue = submit_command_buffer_to_graphics_queue_by_thread;
            graphics_queue_count = thread_count;

            if graphics_queue_family == present_queue_family {
                submit_present = submit_present_first_graphics_queue;
            }
        }
        else {
            submit_to_graphics_queue = submit_command_buffer_to_graphics_queue_by_lock;

            if graphics_queue_family == present_queue_family {
                submit_present = submit_present_graphics_queue_by_lock;
            }
        }

        create_queues_and_locks(graphics_queue_family, &graphics_queue_semaphore, graphics_queue_count, &graphics_queue_locks, &graphics_queues);

        submit_to_transfer_queue = submit_to_graphics_queue;
        compute_command_pools = graphics_command_pools;

        submit_to_transfer_queue = submit_to_graphics_queue;
        transfer_command_pools = graphics_command_pools;

        // @Future Consider using other dedicated queue families to balance other background work
    }
    array_resize(&thread_fences, thread_count, allocate);

    fence_info: VkFenceCreateInfo = {
        flags = cast(u32, VkFenceCreateFlagBits.VK_FENCE_CREATE_SIGNALED_BIT);
    }

    each fence, i in thread_fences {
        result = vkCreateFence(device, &fence_info, &allocator, &fence);
        if result != VkResult.VK_SUCCESS {
            log("Unable to create fence %\n", result);
            exit_program(1);
        }
    }

    // Create command buffers
    alloc_info: VkCommandBufferAllocateInfo = {
        commandPool = graphics_command_pools[0];
        level = VkCommandBufferLevel.VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        commandBufferCount = command_buffers.length;
    }

    result = vkAllocateCommandBuffers(device, &alloc_info, command_buffers.data);
    if result != VkResult.VK_SUCCESS {
        log("Unable to allocate command buffers %\n", result);
        exit_program(1);
    }

    // Create the base texture image sampler
    sampler_info: VkSamplerCreateInfo = {
        magFilter = VkFilter.VK_FILTER_LINEAR; minFilter = VkFilter.VK_FILTER_LINEAR;
        addressModeU = VkSamplerAddressMode.VK_SAMPLER_ADDRESS_MODE_REPEAT;
        addressModeV = VkSamplerAddressMode.VK_SAMPLER_ADDRESS_MODE_REPEAT;
        addressModeW = VkSamplerAddressMode.VK_SAMPLER_ADDRESS_MODE_REPEAT;
        anisotropyEnable = VK_TRUE;
        maxAnisotropy = properties.limits.maxSamplerAnisotropy;
        borderColor = VkBorderColor.VK_BORDER_COLOR_INT_OPAQUE_BLACK;
        unnormalizedCoordinates = VK_FALSE; compareEnable = VK_FALSE;
        compareOp = VkCompareOp.VK_COMPARE_OP_ALWAYS;
        mipmapMode = VkSamplerMipmapMode.VK_SAMPLER_MIPMAP_MODE_LINEAR;
        mipLodBias = 0.0; minLod = 0.0; maxLod = 10.0;
    }

    result = vkCreateSampler(device, &sampler_info, &allocator, &texture_sampler);
    if result != VkResult.VK_SUCCESS {
        log("Unable to create image sampler %\n", result);
        exit_program(1);
    }

    // Create the initial swapchain
    create_swap_chain();

    // Create sync objects
    array_resize(&images_in_flight, swap_chain_images.length, allocate);

    semaphore_info: VkSemaphoreCreateInfo;

    each i in 0..MAX_FRAMES_IN_FLIGHT-1 {
        result = vkCreateSemaphore(device, &semaphore_info, &allocator, &image_available_semaphores[i]);
        if result != VkResult.VK_SUCCESS {
            log("Unable to create semaphore %\n", result);
            exit_program(1);
        }

        result = vkCreateSemaphore(device, &semaphore_info, &allocator, &render_finished_semaphores[i]);
        if result != VkResult.VK_SUCCESS {
            log("Unable to create semaphore %\n", result);
            exit_program(1);
        }

        result = vkCreateFence(device, &fence_info, &allocator, &in_flight_fences[i]);
        if result != VkResult.VK_SUCCESS {
            log("Unable to create fence %\n", result);
            exit_program(1);
        }
    }

    // Initialize quad graphics pipeline and default texture
    quad_layout: GraphicsPipelineLayout = { shader = ShaderName.quad; render_pass = RenderPass.UI; descriptor_set_layouts = 2; }

    array_resize(&quad_layout.bindings, 2, allocate, reallocate);
    quad_layout.bindings[0] = { binding_type = PipelineBindingType.StorageBufferDynamic; stage = ShaderStage.Vertex; type = type_of(QuadDataBuffer); }
    quad_layout.bindings[1] = { binding_type = PipelineBindingType.Texture; descriptor_set_index = 1; stage = ShaderStage.Fragment; }

    create_graphics_pipeline(quad_layout);
    quad_instance_data_buffer_length, quad_instance_data_frame_offset = calculate_ssbo_length_with_offsets<QuadDataBuffer>(MAX_FRAMES_IN_FLIGHT);

    white_pixel: u32 = 0xFFFFFFFF;
    default_texture = create_texture(&white_pixel, 1, 1, 4, 0, 1);
    quad_default_texture_descriptor_set = create_quad_descriptor_set(default_texture);

    graphics_initialized = true;
    log("Graphics properly initialized\n");
}

wait_for_graphics_idle() {
    vkDeviceWaitIdle(device);
}

deinit_graphics() {
    graphics_initialized = false;
    wait_for_graphics_idle();

    destroy_texture(default_texture);
    destroy_descriptor_set(quad_default_texture_descriptor_set);

    each instance_buffer in quad_instance_buffers {
        destroy_descriptor_set(instance_buffer.descriptor_set);
        unmap_buffer_memory(instance_buffer.buffer);
        destroy_buffer(instance_buffer.buffer);
    }

    destroy_swap_chain();

    each i in 0..MAX_FRAMES_IN_FLIGHT-1 {
        vkDestroySemaphore(device, image_available_semaphores[i], &allocator);
        vkDestroySemaphore(device, render_finished_semaphores[i], &allocator);
        vkDestroyFence(device, in_flight_fences[i], &allocator);
    }

    each fence in thread_fences {
        vkDestroyFence(device, fence, &allocator);
    }

    vkDestroySampler(device, texture_sampler, &allocator);

    each i in __graphics_pipelines.pipelines.length {
        deinit_graphics_pipeline(i);
    }

    vkFreeCommandBuffers(device, graphics_command_pools[0], command_buffers.length, command_buffers.data);

    each i in thread_count {
        graphics_command_pool := graphics_command_pools[i];
        compute_command_pool := compute_command_pools[i];
        transfer_command_pool := transfer_command_pools[i];

        vkDestroyCommandPool(device, graphics_command_pool, &allocator);
        if graphics_command_pool != compute_command_pool {
            vkDestroyCommandPool(device, compute_command_pool, &allocator);

            if graphics_command_pool != transfer_command_pool && compute_command_pool != transfer_command_pool {
                vkDestroyCommandPool(device, transfer_command_pool, &allocator);
            }
        }
        else if graphics_command_pool != transfer_command_pool {
            vkDestroyCommandPool(device, transfer_command_pool, &allocator);
        }
    }

    vkDestroyDevice(device, &allocator);
    vkDestroySurfaceKHR(instance, surface, &allocator);

    #if DEVELOPER {
        func: PFN_vkDestroyDebugUtilsMessengerEXT = vkGetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT");
        if func != null {
            func(instance, debug_messenger, &allocator);
        }
    }

    vkDestroyInstance(instance, &allocator);

    log("Graphics properly deinitialized\n");
}

create_graphics_pipeline(GraphicsPipelineLayout layout) {
    shader_index := cast(u32, layout.shader);
    __graphics_pipelines.layouts[shader_index] = layout;

    #if DEVELOPER {
        compile_shader(layout.shader);

        #if SHADER_HOT_RELOADING {
            shader_name := get_enum_name(layout.shader);
            source_file := format_string("%/../src/shaders/%.glsl", allocate, get_program_directory(), shader_name);
            shader: ShaderDefinition = {
                source = source_file;
                last_updated = file_get_last_modified(source_file);
            }
            __shader_library[shader_index] = shader;
        }
    }

    create_graphics_pipeline(layout.shader);
}

recreate_swap_chain() {
    if !graphics_initialized return;
    wait_for_graphics_idle();

    destroy_swap_chain(true);
    create_swap_chain();
}

Buffer create_staging_buffer<T>(int length) {
    size := size_of(T) * length;

    return create_buffer(size, VkBufferUsageFlagBits.VK_BUFFER_USAGE_TRANSFER_SRC_BIT, VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
}

Buffer create_vertex_buffer<T>(int length) {
    size := size_of(T) * length;

    return create_buffer(size, VkBufferUsageFlagBits.VK_BUFFER_USAGE_TRANSFER_DST_BIT | VkBufferUsageFlagBits.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
}

u64 calculate_ubo_length_with_offsets<T>(int elements) {
    element_size := size_of(T);
    aligned_size := calculate_ubo_alignment(element_size);

    return elements * aligned_size;
}

u64 calculate_ubo_alignment(u32 size) {
    alignment_mask: u64 = 0xFFFFFFFFFFFFFFFF - (ubo_offset_alignment - 1);
    return (size + ubo_offset_alignment - 1) & alignment_mask;
}

Buffer create_uniform_buffer(u64 length) {
    assert(length <= max_ubo_size);
    return create_buffer(length, VkBufferUsageFlagBits.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
}

u64, u64 calculate_ssbo_length_with_offsets<T>(int elements) {
    element_size := size_of(T);
    alignment_mask: u64 = 0xFFFFFFFFFFFFFFFF - (ssbo_offset_alignment - 1);
    aligned_size := (element_size + ssbo_offset_alignment - 1) & alignment_mask;

    return elements * aligned_size, aligned_size;
}

u64 calculate_ssbo_alignment(u32 size) {
    alignment_mask: u64 = 0xFFFFFFFFFFFFFFFF - (ssbo_offset_alignment - 1);
    return (size + ssbo_offset_alignment - 1) & alignment_mask;
}

Buffer create_storage_buffer(u64 length) {
    assert(length <= max_ssbo_size);
    return create_buffer(length, VkBufferUsageFlagBits.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
}

Array<T> map_buffer_to_array<T>(Buffer buffer, int length, int offset = 0) {
    array: Array<T>;
    array.length = length;
    array.data = map_buffer_to_memory<T>(buffer, length, offset);

    return array;
}

void* map_buffer_to_memory<T>(Buffer buffer, int length, int offset = 0) {
    buffer_length := size_of(T) * length;

    buffer_pointer: void*;
    vkMapMemory(device, buffer.memory, offset, buffer_length, 0, &buffer_pointer);

    return buffer_pointer;
}

unmap_buffer_memory(Buffer buffer) {
    vkUnmapMemory(device, buffer.memory);
}

copy_memory_to_buffer<T>(Buffer buffer, T* data, int length = 1, u64 offset = 0) {
    copy_length := size_of(T) * length;

    buffer_pointer: void*;
    vkMapMemory(device, buffer.memory, offset, copy_length, 0, &buffer_pointer);
    memory_copy(buffer_pointer, data, copy_length);
    vkUnmapMemory(device, buffer.memory);
}

destroy_buffer(Buffer buffer) {
    vkDestroyBuffer(device, buffer.buffer, &allocator);
    vkFreeMemory(device, buffer.memory, &allocator);
}

Texture create_texture(void* buffer, int width, int height, int channels, int index, u32 mip_levels = 0) {
    texture: Texture;

    // Create the image buffer
    image_size := width * height * channels;
    staging_buffer := create_buffer(image_size, VkBufferUsageFlagBits.VK_BUFFER_USAGE_TRANSFER_SRC_BIT, VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);

    data: void*;
    vkMapMemory(device, staging_buffer.memory, 0, image_size, 0, &data);
    memory_copy(data, buffer, image_size);
    vkUnmapMemory(device, staging_buffer.memory);

    format: VkFormat;
    switch channels {
        case 1; format = VkFormat.VK_FORMAT_R8_SRGB;
        case 2; format = VkFormat.VK_FORMAT_R8G8_SRGB;
        case 4; format = VkFormat.VK_FORMAT_R8G8B8A8_SRGB;
        default; {
            log("Unable to determine texture format from given number of channels %\n", channels);
            exit_program(1);
        }
    }

    if mip_levels == 0 {
        min := width;
        if width > height min = height;

        mip_levels = cast(u32, floor(log_2(cast(float64, min)))) + 1;
    }

    create_image(width, height, format, VkImageTiling.VK_IMAGE_TILING_OPTIMAL, VkImageUsageFlagBits.VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VkImageUsageFlagBits.VK_IMAGE_USAGE_TRANSFER_DST_BIT | VkImageUsageFlagBits.VK_IMAGE_USAGE_SAMPLED_BIT, VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, &texture.image, &texture.image_memory, mip_levels);

    command_pool := transfer_command_pools[index];
    command_buffer := begin_single_time_commands(command_pool);

    transition_image_layout(texture.image, format, VkImageLayout.VK_IMAGE_LAYOUT_UNDEFINED, VkImageLayout.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, mip_levels, command_buffer = command_buffer);

    // Copy buffer to image
    region: VkBufferImageCopy = {
        imageSubresource = { aspectMask = VkImageAspectFlagBits.VK_IMAGE_ASPECT_COLOR_BIT; layerCount = 1; }
        imageExtent = { width = width; height = height; depth = 1; }
    }

    vkCmdCopyBufferToImage(command_buffer, staging_buffer.buffer, texture.image, VkImageLayout.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);

    end_single_time_commands(command_buffer, command_pool, submit_to_transfer_queue, index);

    // Free staging buffer and generate mipmaps
    destroy_buffer(staging_buffer);

    // Check if image format supports linear blitting
    format_properties: VkFormatProperties;
    vkGetPhysicalDeviceFormatProperties(physical_device, format, &format_properties);

    if (format_properties.optimalTilingFeatures & VkFormatFeatureFlagBits.VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT) != VkFormatFeatureFlagBits.VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT {
        log("Texture image format does not support linear blitting\n");
        exit_program(1);
    }

    command_pool = graphics_command_pools[index];
    command_buffer = begin_single_time_commands(command_pool);

    barrier: VkImageMemoryBarrier = {
        srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED; dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        image = texture.image;
        subresourceRange = {
            aspectMask = VkImageAspectFlagBits.VK_IMAGE_ASPECT_COLOR_BIT;
            levelCount = 1; baseArrayLayer = 0; layerCount = 1;
        }
    }

    blit: VkImageBlit = {
        srcSubresource = {
            aspectMask = VkImageAspectFlagBits.VK_IMAGE_ASPECT_COLOR_BIT; layerCount = 1;
        }
        dstSubresource = {
            aspectMask = VkImageAspectFlagBits.VK_IMAGE_ASPECT_COLOR_BIT; layerCount = 1;
        }
    }
    blit.srcOffsets[0] = { x = 0; y = 0; z = 0; }
    blit.srcOffsets[1] = { x = 0; y = 0; z = 1; }
    blit.dstOffsets[0] = { x = 0; y = 0; z = 0; }
    blit.dstOffsets[1] = { x = 0; y = 0; z = 1; }

    each i in 1..mip_levels - 1 {
        barrier = {
            srcAccessMask = VkAccessFlagBits.VK_ACCESS_TRANSFER_WRITE_BIT;
            dstAccessMask = VkAccessFlagBits.VK_ACCESS_TRANSFER_READ_BIT;
            oldLayout = VkImageLayout.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
            newLayout = VkImageLayout.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
            subresourceRange = { baseMipLevel = i - 1; }
        }
        blit = {
            srcSubresource = { mipLevel = i - 1; }
            dstSubresource = { mipLevel = i; }
        }
        blit.srcOffsets[1] = { x = width; y = height; }

        if width > 1 {
            blit.dstOffsets[1] = { x = width / 2; y = height / 2; }
            width /= 2;
            height /= 2;
        }
        else {
            blit.dstOffsets[1] = { x = 1; y = 1; }
        }

        vkCmdPipelineBarrier(command_buffer, VkPipelineStageFlagBits.VK_PIPELINE_STAGE_TRANSFER_BIT, VkPipelineStageFlagBits.VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, null, 0, null, 1, &barrier);

        vkCmdBlitImage(command_buffer, texture.image, VkImageLayout.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, texture.image, VkImageLayout.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &blit, VkFilter.VK_FILTER_LINEAR);

        barrier = {
            srcAccessMask = VkAccessFlagBits.VK_ACCESS_TRANSFER_READ_BIT;
            dstAccessMask = VkAccessFlagBits.VK_ACCESS_SHADER_READ_BIT;
            oldLayout = VkImageLayout.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
            newLayout = VkImageLayout.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        }

        vkCmdPipelineBarrier(command_buffer, VkPipelineStageFlagBits.VK_PIPELINE_STAGE_TRANSFER_BIT, VkPipelineStageFlagBits.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, null, 0, null, 1, &barrier);
    }

    barrier = {
        srcAccessMask = VkAccessFlagBits.VK_ACCESS_TRANSFER_WRITE_BIT;
        dstAccessMask = VkAccessFlagBits.VK_ACCESS_SHADER_READ_BIT;
        oldLayout = VkImageLayout.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        newLayout = VkImageLayout.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        subresourceRange = { baseMipLevel = mip_levels - 1; }
    }

    vkCmdPipelineBarrier(command_buffer, VkPipelineStageFlagBits.VK_PIPELINE_STAGE_TRANSFER_BIT, VkPipelineStageFlagBits.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, null, 0, null, 1, &barrier);

    end_single_time_commands(command_buffer, command_pool, submit_to_graphics_queue, index);

    // Create the texture image view
    view_info: VkImageViewCreateInfo = {
        image = texture.image; viewType = VkImageViewType.VK_IMAGE_VIEW_TYPE_2D; format = format;
        subresourceRange = { aspectMask = VkImageAspectFlagBits.VK_IMAGE_ASPECT_COLOR_BIT; levelCount = mip_levels; layerCount = 1; }
    }

    result := vkCreateImageView(device, &view_info, &allocator, &texture.image_view);
    if result != VkResult.VK_SUCCESS {
        log("Unable to create image view %\n", result);
        exit_program(1);
    }

    return texture;
}

destroy_texture(Texture texture) {
    vkDestroyImage(device, texture.image, &allocator);
    vkFreeMemory(device, texture.image_memory, &allocator);
    vkDestroyImageView(device, texture.image_view, &allocator);
}

struct DescriptorSetInput {
    buffer: Buffer*;
    texture: Texture*;
}

DescriptorSet create_descriptor_set(ShaderName shader, int descriptor_set_layout = 0, Params<DescriptorSetInput> inputs) {
    pipeline_index := cast(u32, shader);
    pipeline := __graphics_pipelines.pipelines[pipeline_index];
    layout := __graphics_pipelines.layouts[pipeline_index];
    assert(layout.descriptor_set_layouts > descriptor_set_layout);

    // Create a descriptor pool for allocating the sets
    pool_sizes: Array<VkDescriptorPoolSize>[inputs.length];
    descriptor_writes: Array<VkWriteDescriptorSet>[inputs.length];
    image_infos: Array<VkDescriptorImageInfo>[inputs.length];
    buffer_infos: Array<VkDescriptorBufferInfo>[inputs.length];

    index := 0;
    each binding, i in layout.bindings {
        if binding.descriptor_set_index < descriptor_set_layout continue;
        if binding.descriptor_set_index > descriptor_set_layout break;

        assert(index < inputs.length);
        input := inputs[index];

        switch binding.binding_type {
            case PipelineBindingType.Texture; {
                pool_sizes[index] = {
                    type = VkDescriptorType.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER; descriptorCount = 1;
                }

                assert(input.texture != null);
                image_infos[index] = {
                    imageLayout = VkImageLayout.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
                    imageView = input.texture.image_view; sampler = texture_sampler;
                }
                descriptor_write: VkWriteDescriptorSet = {
                    descriptorCount = 1; dstBinding = i; pImageInfo = &image_infos[index];
                    descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
                }
                descriptor_writes[index] = descriptor_write;
            }
            case PipelineBindingType.UniformBuffer; {
                assert(input.buffer != null);
                set_descriptor_set_buffer_data(index, VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, input.buffer, i, binding.type.size, pool_sizes, descriptor_writes, buffer_infos);
            }
            case PipelineBindingType.StorageBuffer; {
                assert(input.buffer != null);
                set_descriptor_set_buffer_data(index, VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, input.buffer, i, binding.type.size, pool_sizes, descriptor_writes, buffer_infos);
            }
            case PipelineBindingType.UniformBufferDynamic; {
                assert(input.buffer != null);
                set_descriptor_set_buffer_data(index, VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC, input.buffer, i, calculate_ubo_alignment(binding.type.size), pool_sizes, descriptor_writes, buffer_infos);
            }
            case PipelineBindingType.StorageBufferDynamic; {
                assert(input.buffer != null);
                set_descriptor_set_buffer_data(index, VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC, input.buffer, i, calculate_ssbo_alignment(binding.type.size), pool_sizes, descriptor_writes, buffer_infos);
            }
            default;
                assert(false, format_string("Unsupported pipeline binding type %", allocate, binding.binding_type));
        }

        index++;
    }

    pool_info: VkDescriptorPoolCreateInfo = {
        maxSets = 1; poolSizeCount = pool_sizes.length; pPoolSizes = pool_sizes.data;
    }

    descriptor_set: DescriptorSet;
    result := vkCreateDescriptorPool(device, &pool_info, &allocator, &descriptor_set.pool);
    if result != VkResult.VK_SUCCESS {
        log("Unable to create descriptor pool %\n", result);
        exit_program(1);
    }

    // Create the descriptor set
    alloc_info: VkDescriptorSetAllocateInfo = {
        descriptorPool = descriptor_set.pool; descriptorSetCount = 1; pSetLayouts = &pipeline.descriptor_set_layouts[descriptor_set_layout];
    }

    result = vkAllocateDescriptorSets(device, &alloc_info, &descriptor_set.set);
    if result != VkResult.VK_SUCCESS {
        log("Unable to allocate descriptor sets %\n", result);
        exit_program(1);
    }

    each descriptor_write in descriptor_writes {
        descriptor_write.dstSet = descriptor_set.set;
    }
    vkUpdateDescriptorSets(device, descriptor_writes.length, descriptor_writes.data, 0, null);

    return descriptor_set;
}

DescriptorSet create_quad_descriptor_set(Texture texture) {
    texture_descriptor: DescriptorSetInput = { texture = &texture; }
    return create_descriptor_set(ShaderName.quad, 1, texture_descriptor);
}

destroy_descriptor_set(DescriptorSet descriptor_set) {
    if descriptor_set.pool {
        vkDestroyDescriptorPool(device, descriptor_set.pool, &allocator);
    }
}

bool set_current_command_buffer() {
    vkWaitForFences(device, 1, &in_flight_fences[frame_index], VK_TRUE, 0xFFFFFFFFFFFFFFFF);

    result := vkAcquireNextImageKHR(device, swap_chain, 0xFFFFFFFFFFFFFFFF, image_available_semaphores[frame_index], null, &image_index);

    if result == VkResult.VK_ERROR_OUT_OF_DATE_KHR {
        return false;
    }
    else if result != VkResult.VK_SUCCESS && result != VkResult.VK_SUBOPTIMAL_KHR {
        log("Failed to acquire swap chain image %\n", result);
        exit_program(1);
    }

    if images_in_flight[image_index] {
        vkWaitForFences(device, 1, &images_in_flight[image_index], VK_TRUE, 0xFFFFFFFFFFFFFFFF);
    }

    images_in_flight[image_index] = in_flight_fences[frame_index];

    command_buffer := command_buffers[frame_index];
    begin_info: VkCommandBufferBeginInfo;

    result = vkBeginCommandBuffer(command_buffer, &begin_info);
    if result != VkResult.VK_SUCCESS {
        log("Unable to begin recording command buffer %\n", result);
        exit_program(1);
    }

    current_command_buffer = command_buffer;
    return true;
}

begin_ui_render_pass() {
    clear_values: Array<VkClearValue>[1];
    clear_values[0].color.float32 = [0.3, 0.3, 0.3, 1.0]

    render_pass_info: VkRenderPassBeginInfo = {
        renderPass = ui_render_pass;
        framebuffer = ui_framebuffers[image_index];
        clearValueCount = clear_values.length;
        pClearValues = clear_values.data;
        renderArea = { extent = swap_chain_extent; }
    }

    vkCmdBeginRenderPass(current_command_buffer, &render_pass_info, VkSubpassContents.VK_SUBPASS_CONTENTS_INLINE);

    viewport: VkViewport = {
        x = 0.0; y = 0.0; width = cast(float, swap_chain_extent.width); height = cast(float, swap_chain_extent.height);
        minDepth = 0.0; maxDepth = 1.0;
    }
    vkCmdSetViewport(current_command_buffer, 0, 1, &viewport);

    scissor: VkRect2D = { extent = swap_chain_extent; }
    vkCmdSetScissor(current_command_buffer, 0, 1, &scissor);
}

bind_graphics_pipeline(ShaderName shader) {
    if shader == bound_graphics_pipeline return;

    assert(current_command_buffer != null);
    assert(shader != ShaderName.Invalid);
    pipeline := __graphics_pipelines.pipelines[cast(u32, shader)];

    vkCmdBindPipeline(current_command_buffer, VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.handle);
    bound_graphics_pipeline = shader;
}

bind_descriptor_set(DescriptorSet descriptor_set, Params<u32> offsets) {
    sets: Array<DescriptorSet> = [descriptor_set]
    bind_descriptor_sets(sets, offsets);
}

bind_descriptor_sets(Array<DescriptorSet> descriptor_sets, Params<u32> offsets) {
    assert(current_command_buffer != null);
    assert(bound_graphics_pipeline != ShaderName.Invalid);
    pipeline := __graphics_pipelines.pipelines[cast(u32, bound_graphics_pipeline)];

    set_handles: Array<VkDescriptorSet*>[descriptor_sets.length];
    each set, i in descriptor_sets {
        set_handles[i] = set.set;
    }

    vkCmdBindDescriptorSets(current_command_buffer, VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.layout, 0, set_handles.length, set_handles.data, offsets.length, offsets.data);
}

write_uniform_buffer<T>(Buffer buffer, T* data, u64 offset = 0) {
    ubo_size := size_of(T);

    ubo_data: void*;
    vkMapMemory(device, buffer.memory, offset, ubo_size - offset, 0, &ubo_data);
    memory_copy(ubo_data, data, ubo_size);
    vkUnmapMemory(device, buffer.memory);
}

set_push_constant_data<T>(T* data) {
    set_push_constant_data(data, size_of(T));
}

set_push_constant_data(void* data, u32 length) {
    assert(current_command_buffer != null);
    assert(bound_graphics_pipeline != ShaderName.Invalid);
    pipeline_index := cast(u32, bound_graphics_pipeline);
    layout := __graphics_pipelines.layouts[pipeline_index];
    pipeline := __graphics_pipelines.pipelines[pipeline_index];

    vkCmdPushConstants(current_command_buffer, pipeline.layout, stage_bits(layout.push_constant_stage), 0, length, data);
}

draw(int vertices, int instance_count = 1, int first_instance = 0, int buffer_length = 1, Params<Buffer> vertex_buffers) {
    if vertex_buffers.length {
        offset: u64;
        each vertex_buffer in vertex_buffers {
            vkCmdBindVertexBuffers(current_command_buffer, 0, 1, &vertex_buffer.buffer, &offset);

            instances := instance_count;
            if instances > buffer_length {
                instances = buffer_length;
                instance_count -= buffer_length;
            }
            vkCmdDraw(current_command_buffer, vertices, instances, 0, first_instance);
        }
        return;
    }

    vkCmdDraw(current_command_buffer, vertices, instance_count, 0, first_instance);
}

draw_quad(QuadInstanceData* quad_data, int instance_count = 1, DescriptorSet* texture = null) {
    texture_descriptor: DescriptorSet;
    if texture texture_descriptor = *texture;
    else       texture_descriptor = quad_default_texture_descriptor_set;

    buffer_offset: u64 = quad_instance_data_frame_offset * frame_index;
    if current_quad_texture.set != null && current_quad_texture.set != texture_descriptor.set {
        flush_quads(buffer_offset);
    }
    current_quad_texture = texture_descriptor;

    quad_index := 0;

    while instance_count > 0 {
        instance_buffer: InstanceBuffer;
        if quad_instance_buffers.length > quad_instances_index
            instance_buffer = quad_instance_buffers[quad_instances_index];
        else {
            instance_buffer.buffer = create_storage_buffer(quad_instance_data_buffer_length);

            descriptor: DescriptorSetInput = { buffer = &instance_buffer.buffer; }
            instance_buffer.descriptor_set = create_descriptor_set(ShaderName.quad, descriptor);
            instance_buffer.data = map_buffer_to_memory<u8>(instance_buffer.buffer, quad_instance_data_buffer_length);

            array_insert(&quad_instance_buffers, instance_buffer, allocate, reallocate);
        }

        max_copy_length := MAX_QUADS_PER_DRAW - quad_instance_count;
        quads_to_draw: int;
        flush := false;
        if instance_count >= max_copy_length {
            quads_to_draw = max_copy_length;
            instance_count -= max_copy_length;
            flush = true;
        }
        else {
            quads_to_draw = instance_count;
            instance_count = 0;
        }

        instance_offset := buffer_offset + quad_instance_count * size_of(QuadInstanceData);
        copy_length := quads_to_draw * size_of(QuadInstanceData);
        memory_copy(instance_buffer.data + instance_offset, quad_data + quad_index, copy_length);
        quad_instance_count += quads_to_draw;

        if flush {
            flush_quads(buffer_offset);
            quad_instance_start = 0;
            quad_instance_count = 0;
            quad_instances_index++;
        }

        quad_index += quads_to_draw;
    }
}

finish_quads() {
    buffer_offset: u64 = quad_instance_data_frame_offset * frame_index;
    flush_quads(buffer_offset);

    current_quad_texture.set = null;
    quad_instance_start = 0;
    quad_instance_count = 0;
    quad_instances_index = 0;
}

flush_quads(u64 buffer_offset) {
    if quad_instance_count - quad_instance_start == 0 return;

    bind_graphics_pipeline(ShaderName.quad);

    instance_buffer := quad_instance_buffers[quad_instances_index];
    descriptor_sets: Array<DescriptorSet> = [instance_buffer.descriptor_set, current_quad_texture]

    bind_descriptor_sets(descriptor_sets, buffer_offset);
    draw(VERTICES_PER_QUAD, quad_instance_count - quad_instance_start, quad_instance_start);

    quad_instance_start = quad_instance_count;
}

draw_indexed(u32 length, u32 instance_count = 1, u32 start_index = 0, u32 first_instance = 0) {
    vkCmdDrawIndexed(current_command_buffer, length, instance_count, start_index, 0, first_instance);
}

submit_frame() {
    finish_quads();

    vkCmdEndRenderPass(current_command_buffer);

    result := vkEndCommandBuffer(current_command_buffer);
    if result != VkResult.VK_SUCCESS {
        log("Unable to record command buffer %\n", result);
        exit_program(1);
    }

    submit_info: VkSubmitInfo = {
        waitSemaphoreCount = 1;
        pWaitSemaphores = &image_available_semaphores[frame_index];
        pWaitDstStageMask = wait_stages.data;
        commandBufferCount = 1;
        pCommandBuffers = &current_command_buffer;
        signalSemaphoreCount = 1;
        pSignalSemaphores = &render_finished_semaphores[frame_index];
    }

    vkResetFences(device, 1, &in_flight_fences[frame_index]);
    submit_to_graphics_queue(&submit_info, in_flight_fences[frame_index], 0);

    present_info: VkPresentInfoKHR = {
        waitSemaphoreCount = 1;
        pWaitSemaphores = &render_finished_semaphores[frame_index];
        swapchainCount = 1;
        pSwapchains = &swap_chain;
        pImageIndices = &image_index;
    }

    result = submit_present(&present_info);
    if result != VkResult.VK_SUCCESS && result != VkResult.VK_ERROR_OUT_OF_DATE_KHR && result != VkResult.VK_SUBOPTIMAL_KHR {
        log("Failed to present swap chain image %\n", result);
        exit_program(1);
    }

    frame_index = (frame_index + 1) % MAX_FRAMES_IN_FLIGHT;

    current_command_buffer = null;
    bound_graphics_pipeline = ShaderName.Invalid;
}

#if DEVELOPER {
    compile_shader(ShaderName shader) {
        shader_name := get_enum_name(shader);

        program_directory := get_program_directory();
        file_name := temp_string(program_directory, "/../src/shaders/", shader_name, ".glsl", "\0");
        output_directory := temp_string(program_directory, "/shaders");
        compile_shader(shader_name, file_name, file_name, output_directory, allocate, free_allocation);
    }

    #if SHADER_HOT_RELOADING {
        reload_updated_shaders() {
            each i in __graphics_pipelines.pipelines.length {
                shader := &__shader_library[i];
                last_updated := file_get_last_modified(shader.source);

                if last_updated > shader.last_updated {
                    // Rebuild pipeline if newer shader version
                    deinit_graphics_pipeline(i, true);

                    shader_name := cast(ShaderName, i);
                    compile_shader(shader_name);
                    create_graphics_pipeline(shader_name, true);

                    shader.last_updated = last_updated;
                }
            }
        }
    }
}

default_texture: Texture;

#private

shader_entrypoint := "main"; #const
image_index: u32;

max_ubo_size: u32;
ubo_offset_alignment: u64;
max_ssbo_size: u32;
ssbo_offset_alignment: u64;
max_push_constant_size: u32;
msaa_samples := VkSampleCountFlagBits.VK_SAMPLE_COUNT_1_BIT;

current_command_buffer: VkCommandBuffer*;
bound_graphics_pipeline := ShaderName.Invalid;

instance: VkInstance*;
surface: VkSurfaceKHR*;
physical_device: VkPhysicalDevice*;
device: VkDevice*;

command_buffers: Array<VkCommandBuffer*>[MAX_FRAMES_IN_FLIGHT];

graphics_command_pools: Array<VkCommandPool*>;
compute_command_pools: Array<VkCommandPool*>;
transfer_command_pools: Array<VkCommandPool*>;

graphics_queue_family: u32;
present_queue_family: u32;
compute_queue_family: u32;
transfer_queue_family: u32;
queue_family_flags: PhysicalDeviceQueueFlags;

graphics_queue: VkQueue*;
present_queue: VkQueue*;
graphics_queues: Array<VkQueue*>;
compute_queues: Array<VkQueue*>;
transfer_queues: Array<VkQueue*>;

graphics_queue_locks: Array<u8>;
compute_queue_locks: Array<u8>;
transfer_queue_locks: Array<u8>;

graphics_queue_semaphore: Semaphore;
compute_queue_semaphore: Semaphore;
transfer_queue_semaphore: Semaphore;
thread_fences: Array<VkFence*>;

interface SubmitCommandBuffer(VkSubmitInfo* submit_info, VkFence* fence, int thread)
submit_to_graphics_queue: SubmitCommandBuffer;
submit_to_compute_queue: SubmitCommandBuffer;
submit_to_transfer_queue: SubmitCommandBuffer;

interface VkResult SubmitPresent(VkPresentInfoKHR* present_info)
submit_present: SubmitPresent;

wait_stages: Array<VkPipelineStageFlagBits> = [VkPipelineStageFlagBits.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT]
depth_formats: Array<VkFormat> = [VkFormat.VK_FORMAT_D32_SFLOAT, VkFormat.VK_FORMAT_D32_SFLOAT_S8_UINT, VkFormat.VK_FORMAT_D24_UNORM_S8_UINT]
depth_format: VkFormat;

texture_sampler: VkSampler*;

// Synchronization
image_available_semaphores: Array<VkSemaphore*>[MAX_FRAMES_IN_FLIGHT];
render_finished_semaphores: Array<VkSemaphore*>[MAX_FRAMES_IN_FLIGHT];
in_flight_fences: Array<VkFence*>[MAX_FRAMES_IN_FLIGHT];
images_in_flight: Array<VkFence*>;

// Swap chain
swap_chain_format: VkSurfaceFormatKHR;
swap_chain_extent: VkExtent2D;
swap_chain: VkSwapchainKHR*;
swap_chain_images: Array<VkImage*>;
swap_chain_image_views: Array<VkImageView*>;
ui_framebuffers: Array<VkFramebuffer*>;

// Render pass data
ui_render_pass: VkRenderPass*;
color_image: VkImage*;
color_image_memory: VkDeviceMemory*;
color_image_view: VkImageView*;
depth_image: VkImage*;
depth_image_memory: VkDeviceMemory*;
depth_image_view: VkImageView*;

// Quad renderer
quad_default_texture_descriptor_set: DescriptorSet;
current_quad_texture: DescriptorSet;

MAX_QUADS_PER_DRAW := 10000; #const
struct QuadDataBuffer {
    objects: CArray<QuadInstanceData>[MAX_QUADS_PER_DRAW];
}

quad_instance_data_buffer_length: u64;
quad_instance_data_frame_offset: u64;
quad_instance_start := 0;
quad_instance_count := 0;
quad_instances_index := 0;
quad_instance_buffers: Array<InstanceBuffer>;

// Helper functions
create_command_pools(Array<VkCommandPool*>* command_pools, u32 family_index) {
    pool_info: VkCommandPoolCreateInfo = {
        queueFamilyIndex = family_index;
        flags = VkCommandPoolCreateFlagBits.VK_COMMAND_POOL_CREATE_TRANSIENT_BIT | VkCommandPoolCreateFlagBits.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    }

    array_resize(command_pools, thread_count, allocate, reallocate);
    each command_pool in *command_pools {
        result := vkCreateCommandPool(device, &pool_info, &allocator, &command_pool);
        if result != VkResult.VK_SUCCESS {
            log("Unable to create command pool %\n", result);
            exit_program(1);
        }
    }
}

create_queues_and_locks(u32 queue_family, Semaphore* semaphore, u32 queue_count, Array<u8>* locks, Array<VkQueue*>* queues) {
    create_semaphore(semaphore, queue_count, queue_count);

    array_resize(locks, queue_count, allocate);
    array_resize(queues, queue_count, allocate);

    each queue, i in *queues {
        vkGetDeviceQueue(device, queue_family, i, &queue);
    }
}

create_graphics_pipeline(ShaderName shader, bool use_existing = false) {
    pipeline_index := cast(u32, shader);
    layout := __graphics_pipelines.layouts[pipeline_index];

    // Create the shader modules
    #if BUNDLED_SHADERS {
        shader_code := __shader_codes[pipeline_index];
        shader_file: string = { length = shader_code.length; data = shader_code.data; }
    }
    else {
        shader_name := get_enum_name(shader);
        shader_file_path := temp_string(get_program_directory(), "/shaders/", shader_name, ".shader");
        found, shader_file := read_file(shader_file_path, allocate);
        if !found {
            assert(false, temp_string("Shader ", shader_name, " not found\n"));
        }

        defer free_allocation(shader_file.data);
    }

    shader_count := *cast(int*, shader_file.data);
    shader_stages := *cast(ShaderStage*, shader_file.data + 4);

    shader_stage_modules: Array<VkPipelineShaderStageCreateInfo>[shader_count];
    shader_index := 0;
    position: s64 = 8;

    stage_info: VkPipelineShaderStageCreateInfo = { pName = shader_entrypoint.data; }
    if shader_stages & ShaderStage.Vertex {
         stage_info = {
            stage = VkShaderStageFlagBits.VK_SHADER_STAGE_VERTEX_BIT;
            module = create_shader_module(shader_file, &position);
        }
        shader_stage_modules[shader_index++] = stage_info;
    }
    if shader_stages & ShaderStage.TessellationControl {
         stage_info = {
            stage = VkShaderStageFlagBits.VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT;
            module = create_shader_module(shader_file, &position);
        }
        shader_stage_modules[shader_index++] = stage_info;
    }
    if shader_stages & ShaderStage.TessellationEval {
         stage_info = {
            stage = VkShaderStageFlagBits.VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT;
            module = create_shader_module(shader_file, &position);
        }
        shader_stage_modules[shader_index++] = stage_info;
    }
    if shader_stages & ShaderStage.Geometry {
         stage_info = {
            stage = VkShaderStageFlagBits.VK_SHADER_STAGE_GEOMETRY_BIT;
            module = create_shader_module(shader_file, &position);
        }
        shader_stage_modules[shader_index++] = stage_info;
    }
    if shader_stages & ShaderStage.Fragment {
         stage_info = {
            stage = VkShaderStageFlagBits.VK_SHADER_STAGE_FRAGMENT_BIT;
            module = create_shader_module(shader_file, &position);
        }
        shader_stage_modules[shader_index++] = stage_info;
    }
    if shader_stages & ShaderStage.Compute {
         stage_info = {
            stage = VkShaderStageFlagBits.VK_SHADER_STAGE_COMPUTE_BIT;
            module = create_shader_module(shader_file, &position);
        }
        shader_stage_modules[shader_index++] = stage_info;
    }

    defer {
        each shader_stage in shader_stage_modules {
            vkDestroyShaderModule(device, shader_stage.module, &allocator);
        }
    }

    // Define input format
    attribute_description_count := 0;
    binding_descriptions: Array<VkVertexInputBindingDescription>[layout.vertex_bindings.length];
    each vertex_binding, i in layout.vertex_bindings {
        assert(vertex_binding.type.size > 0 && vertex_binding.type.type == TypeKind.Struct);
        type_info := cast(StructTypeInfo*, vertex_binding.type);
        attribute_description_count += type_info.fields.length;

        input_rate := VkVertexInputRate.VK_VERTEX_INPUT_RATE_VERTEX;
        if vertex_binding.instanced
            input_rate = VkVertexInputRate.VK_VERTEX_INPUT_RATE_INSTANCE;
        binding_descriptions[i] = { binding = i; stride = type_info.size; inputRate = input_rate; }
    }

    offset: u32;
    attribute_descriptions: Array<VkVertexInputAttributeDescription>[attribute_description_count];
    each vertex_binding, i in layout.vertex_bindings {
        type_info := cast(StructTypeInfo*, vertex_binding.type);

        each field, j in type_info.fields {
            format: VkFormat;
            switch field.type_info.size {
                case 4; {
                    switch field.type_info.type {
                        case TypeKind.Integer; format = VkFormat.VK_FORMAT_R32_UINT;
                        default;               format = VkFormat.VK_FORMAT_R32_SFLOAT;
                    }
                }
                case 8;
                    format = VkFormat.VK_FORMAT_R32G32_SFLOAT;
                case 12;
                    format = VkFormat.VK_FORMAT_R32G32B32_SFLOAT;
                case 16;
                    format = VkFormat.VK_FORMAT_R32G32B32A32_SFLOAT;
                default;
                    assert(false, "Undefined vertex type, please fix");
            }

            location := i + j;
            attribute_descriptions[location] = { binding = i; location = location; format = format; offset = offset + field.offset; }
        }

        offset += type_info.size;
    }

    vertex_input_info: VkPipelineVertexInputStateCreateInfo = {
        vertexBindingDescriptionCount = binding_descriptions.length;
        pVertexBindingDescriptions = binding_descriptions.data;
        vertexAttributeDescriptionCount = attribute_descriptions.length;
        pVertexAttributeDescriptions = attribute_descriptions.data;
    }

    input_assembly: VkPipelineInputAssemblyStateCreateInfo = {
        topology = cast(VkPrimitiveTopology, cast(int, layout.topology));
    }

    viewport_state: VkPipelineViewportStateCreateInfo = { viewportCount = 1; scissorCount = 1; }

    rasterizer: VkPipelineRasterizationStateCreateInfo = {
        depthClampEnable = VK_FALSE;
        rasterizerDiscardEnable = VK_FALSE;
        polygonMode = VkPolygonMode.VK_POLYGON_MODE_FILL;
        lineWidth = 1.0;
        cullMode = VkCullModeFlagBits.VK_CULL_MODE_BACK_BIT;
        frontFace = VkFrontFace.VK_FRONT_FACE_CLOCKWISE;
        depthBiasEnable = VK_FALSE;
    }

    multisampling: VkPipelineMultisampleStateCreateInfo = {
        rasterizationSamples = msaa_samples;
        sampleShadingEnable = VK_TRUE;
        minSampleShading = 0.2;
    }

    color_blend_attachment: VkPipelineColorBlendAttachmentState = {
        colorWriteMask = VkColorComponentFlagBits.VK_COLOR_COMPONENT_RGBA;
        blendEnable = VK_TRUE;
        srcColorBlendFactor = VkBlendFactor.VK_BLEND_FACTOR_SRC_ALPHA;
        dstColorBlendFactor = VkBlendFactor.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
        colorBlendOp = VkBlendOp.VK_BLEND_OP_ADD;
        srcAlphaBlendFactor = VkBlendFactor.VK_BLEND_FACTOR_ONE;
        dstAlphaBlendFactor = VkBlendFactor.VK_BLEND_FACTOR_ZERO;
        alphaBlendOp = VkBlendOp.VK_BLEND_OP_ADD;
    }

    color_blending: VkPipelineColorBlendStateCreateInfo = {
        logicOpEnable = VK_FALSE;
        logicOp = VkLogicOp.VK_LOGIC_OP_COPY;
        attachmentCount = 1;
        pAttachments = &color_blend_attachment;
    }

    dynamic_states: Array<VkDynamicState> = [VkDynamicState.VK_DYNAMIC_STATE_VIEWPORT, VkDynamicState.VK_DYNAMIC_STATE_SCISSOR]

    dynamic_state: VkPipelineDynamicStateCreateInfo = {
        dynamicStateCount = dynamic_states.length;
        pDynamicStates = dynamic_states.data;
    }

    pipeline_layout_info: VkPipelineLayoutCreateInfo;
    pipeline := &__graphics_pipelines.pipelines[pipeline_index];

    if layout.bindings.length {
        if !use_existing {
            array_resize(&pipeline.descriptor_set_layouts, layout.descriptor_set_layouts, allocate, reallocate);

            binding_index: int;
            layout_bindings: Array<VkDescriptorSetLayoutBinding>[layout.bindings.length];

            // Create descriptor set layouts
            each layout_index in 0..layout.descriptor_set_layouts - 1 {
                layout_binding_index := 0;

                while binding_index < layout_bindings.length {
                    binding := layout.bindings[binding_index];
                    if binding.descriptor_set_index != layout_index break;

                    layout_binding: VkDescriptorSetLayoutBinding = { binding = binding_index++; descriptorCount = 1; stageFlags = stage_bits(binding.stage); }

                    switch binding.binding_type {
                        case PipelineBindingType.Texture; {
                            layout_binding.descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
                        }
                        case PipelineBindingType.UniformBuffer; {
                            assert(binding.type != null);
                            layout_binding.descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
                        }
                        case PipelineBindingType.StorageBuffer; {
                            assert(binding.type != null);
                            layout_binding.descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
                        }
                        case PipelineBindingType.UniformBufferDynamic; {
                            assert(binding.type != null);
                            layout_binding.descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC;
                        }
                        case PipelineBindingType.StorageBufferDynamic; {
                            assert(binding.type != null);
                            layout_binding.descriptorType = VkDescriptorType.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC;
                        }
                        default;
                            assert(false, format_string("Unsupported pipeline binding type %", allocate, binding.binding_type));
                    }

                    layout_bindings[layout_binding_index++] = layout_binding;
                }

                layout_info: VkDescriptorSetLayoutCreateInfo = {
                    bindingCount = layout_binding_index; pBindings = layout_bindings.data;
                }
                result := vkCreateDescriptorSetLayout(device, &layout_info, &allocator, &pipeline.descriptor_set_layouts[layout_index]);
                if result != VkResult.VK_SUCCESS {
                    log("Failed to create descriptor set layout %", result);
                    exit_program(1);
                }
            }
        }

        pipeline_layout_info = { setLayoutCount = pipeline.descriptor_set_layouts.length; pSetLayouts = pipeline.descriptor_set_layouts.data; }
    }

    if layout.push_constant_type {
        assert(layout.push_constant_type.size <= max_push_constant_size, "Push constant size greater than the max size allowed");
        push_constant_range: VkPushConstantRange = {
            stageFlags = stage_bits(layout.push_constant_stage);
            size = layout.push_constant_type.size;
        }

        pipeline_layout_info = { pushConstantRangeCount = 1; pPushConstantRanges = &push_constant_range; }
    }

    result := vkCreatePipelineLayout(device, &pipeline_layout_info, &allocator, &pipeline.layout);
    if result != VkResult.VK_SUCCESS {
        log("Unable to create pipeline layout %\n", result);
        exit_program(1);
    }

    depth_stencil: VkPipelineDepthStencilStateCreateInfo = {
        depthTestEnable = VK_TRUE; depthWriteEnable = VK_TRUE;
        depthCompareOp = VkCompareOp.VK_COMPARE_OP_LESS; depthBoundsTestEnable = VK_FALSE;
        minDepthBounds = 0.0; maxDepthBounds = 1.0; stencilTestEnable = VK_FALSE;
    }

    pipeline_info: VkGraphicsPipelineCreateInfo = {
        stageCount = shader_stage_modules.length;
        pStages = shader_stage_modules.data;
        pVertexInputState = &vertex_input_info;
        pInputAssemblyState = &input_assembly;
        pViewportState = &viewport_state;
        pRasterizationState = &rasterizer;
        pMultisampleState = &multisampling;
        pDepthStencilState = &depth_stencil;
        pColorBlendState = &color_blending;
        pDynamicState = &dynamic_state;
        layout = pipeline.layout;
        subpass = 0;
        basePipelineHandle = null;
        basePipelineIndex = -1;
    }

    switch layout.render_pass {
        case RenderPass.UI;    pipeline_info.renderPass = ui_render_pass;
        default;               assert(false, "Invalid render pass");
    }

    result = vkCreateGraphicsPipelines(device, null, 1, &pipeline_info, &allocator, &pipeline.handle);
    if result != VkResult.VK_SUCCESS {
        log("Unable to create graphics pipeline %\n", result);
        exit_program(1);
    }
}

deinit_graphics_pipeline(int index, bool keep_existing = false) {
    wait_for_graphics_idle();
    pipeline := __graphics_pipelines.pipelines[index];

    if !keep_existing {
        each descriptor_set_layout in pipeline.descriptor_set_layouts {
            vkDestroyDescriptorSetLayout(device, descriptor_set_layout, &allocator);
        }
    }

    vkDestroyPipeline(device, pipeline.handle, &allocator);
    vkDestroyPipelineLayout(device, pipeline.layout, &allocator);
}

set_descriptor_set_buffer_data(int i, VkDescriptorType descriptor_type, Buffer* buffer, int binding_index, u32 range, Array<VkDescriptorPoolSize> pool_sizes, Array<VkWriteDescriptorSet> descriptor_writes, Array<VkDescriptorBufferInfo> buffer_infos) {
    pool_sizes[i] = { type = descriptor_type; descriptorCount = 1; }

    buffer_infos[i] = { buffer = buffer.buffer; offset = 0; range = range; }
    descriptor_write: VkWriteDescriptorSet = {
        descriptorCount = 1; dstBinding = binding_index; pBufferInfo = &buffer_infos[i];
        descriptorType = descriptor_type;
    }
    descriptor_writes[i] = descriptor_write;
}

allocator: VkAllocationCallbacks = { pfnAllocation = vulkan_allocate; pfnReallocation = vulkan_reallocate; pfnFree = vulkan_free; }

void* vulkan_allocate(void* pUserData, u64 size, u64 alignment, VkSystemAllocationScope allocationScope) {
    return allocate(size);
}

void* vulkan_reallocate(void* pUserData, void* pOriginal, u64 size, u64 alignment, VkSystemAllocationScope allocationScope) {
    if pOriginal {
        block := cast(MemoryBlock*, pOriginal) - 1;
        return reallocate(pOriginal, block.size, size);
    }

    return allocate(size);
}

vulkan_free(void* pUserData, void* pMemory) {
    free_allocation(pMemory);
}

VkShaderStageFlagBits stage_bits(ShaderStage stages) #inline {
    return cast(VkShaderStageFlagBits, cast(int, stages));
}

VkShaderModule* create_shader_module(string shader_file, s64* position) {
    pos := *position;
    length := *cast(s64*, shader_file.data + pos);

    pos += size_of(length);

    shader_create_info: VkShaderModuleCreateInfo = {
        codeSize = length;
        pCode = cast(u32*, shader_file.data + pos);
    }

    shader_module: VkShaderModule*;
    result := vkCreateShaderModule(device, &shader_create_info, &allocator, &shader_module);
    if result != VkResult.VK_SUCCESS {
        log("Unable to create shader module %\n", result);
        exit_program(1);
    }

    *position = pos + length;
    return shader_module;
}

Buffer create_buffer_and_copy<T>(Array<T> values, VkBufferUsageFlagBits flags, int index) {
    size := size_of(T) * values.length;

    staging_buffer := create_buffer(size, VkBufferUsageFlagBits.VK_BUFFER_USAGE_TRANSFER_SRC_BIT, VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);

    data: void*;
    vkMapMemory(device, staging_buffer.memory, 0, size, 0, &data);
    memory_copy(data, values.data, size);
    vkUnmapMemory(device, staging_buffer.memory);

    buffer := create_buffer(size, VkBufferUsageFlagBits.VK_BUFFER_USAGE_TRANSFER_DST_BIT | flags, VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);

    copy_buffer(staging_buffer.buffer, buffer.buffer, size, index);
    destroy_buffer(staging_buffer);

    return buffer;
}

Buffer create_buffer(u64 size, VkBufferUsageFlagBits usage, VkMemoryPropertyFlagBits properties) {
    assert(size > 0);
    buffer_info: VkBufferCreateInfo = {
        size = size;
        usage = usage;
        sharingMode = VkSharingMode.VK_SHARING_MODE_EXCLUSIVE;
    }

    buffer: Buffer = { length = size; }
    result := vkCreateBuffer(device, &buffer_info, &allocator, &buffer.buffer);
    if result != VkResult.VK_SUCCESS {
        log("Unable to create buffer %\n", result);
        exit_program(1);
    }

    memory_requirements: VkMemoryRequirements;
    vkGetBufferMemoryRequirements(device, buffer.buffer, &memory_requirements);

    alloc_info: VkMemoryAllocateInfo = {
        allocationSize = memory_requirements.size;
        memoryTypeIndex = find_memory_type(memory_requirements.memoryTypeBits, properties);
    }

    result = vkAllocateMemory(device, &alloc_info, &allocator, &buffer.memory);
    if result != VkResult.VK_SUCCESS {
        log("Unable to allocate buffer memory %\n", result);
        exit_program(1);
    }

    vkBindBufferMemory(device, buffer.buffer, buffer.memory, 0);

    return buffer;
}

copy_buffer(VkBuffer* source_buffer, VkBuffer* dest_buffer, u64 size, int index) {
    command_pool := transfer_command_pools[index];
    command_buffer := begin_single_time_commands(command_pool);

    copy_region: VkBufferCopy = { size = size; }
    vkCmdCopyBuffer(command_buffer, source_buffer, dest_buffer, 1, &copy_region);

    end_single_time_commands(command_buffer, command_pool, submit_to_transfer_queue, index);
}

create_swap_chain() {
    format_count: u32;
    vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &format_count, null);

    formats: Array<VkSurfaceFormatKHR>[format_count];
    vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &format_count, formats.data);

    format_set := false;
    each format in formats {
        if format.format == VkFormat.VK_FORMAT_B8G8R8A8_SRGB && format.colorSpace == VkColorSpaceKHR.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR {
            swap_chain_format = format;
            format_set = true;
        }
    }
    if !format_set swap_chain_format = formats[0];

    present_mode_count: u32;
    vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &present_mode_count, null);

    present_modes: Array<VkPresentModeKHR>[present_mode_count];
    vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &present_mode_count, present_modes.data);

    present_mode := VkPresentModeKHR.VK_PRESENT_MODE_FIFO_KHR;

    capabilities: VkSurfaceCapabilitiesKHR;
    vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &capabilities);

    if capabilities.currentExtent.width != 0xFFFFFFFF {
        swap_chain_extent = capabilities.currentExtent;
    }
    else {
        swap_chain_extent = {
            width = clamp(settings.window_width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width);
            height = clamp(settings.window_height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height);
        }
    }

    image_count: u32 = capabilities.minImageCount + 1;

    if capabilities.maxImageCount > 0 && image_count > capabilities.maxImageCount
        image_count = capabilities.maxImageCount;

    // Create the swap chain
    swapchain_create_info: VkSwapchainCreateInfoKHR = {
        surface = surface;
        minImageCount = image_count;
        imageFormat = swap_chain_format.format;
        imageColorSpace = swap_chain_format.colorSpace;
        imageExtent = swap_chain_extent;
        imageArrayLayers = 1;
        imageUsage = VkImageUsageFlagBits.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
        preTransform = capabilities.currentTransform;
        compositeAlpha = VkCompositeAlphaFlagBitsKHR.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
        presentMode = present_mode;
        clipped = VK_TRUE;
        oldSwapchain = swap_chain;
    }

    if graphics_queue_family == present_queue_family {
        swapchain_create_info.imageSharingMode = VkSharingMode.VK_SHARING_MODE_EXCLUSIVE;
    }
    else {
        queue_family_indices: CArray<u32> = [graphics_queue_family, present_queue_family]
        swapchain_create_info.imageSharingMode = VkSharingMode.VK_SHARING_MODE_CONCURRENT;
        swapchain_create_info.queueFamilyIndexCount = 2;
        swapchain_create_info.pQueueFamilyIndices = &queue_family_indices;
    }

    old_swap_chain := swap_chain;

    result := vkCreateSwapchainKHR(device, &swapchain_create_info, &allocator, &swap_chain);
    if result != VkResult.VK_SUCCESS {
        log("Unable to create swap chain %\n", result);
        exit_program(1);
    }

    vkDestroySwapchainKHR(device, old_swap_chain, &allocator);

    // Create swap chain images and image views
    vkGetSwapchainImagesKHR(device, swap_chain, &image_count, null);
    array_resize(&swap_chain_images, image_count, allocate, reallocate);
    vkGetSwapchainImagesKHR(device, swap_chain, &image_count, swap_chain_images.data);

    array_resize(&swap_chain_image_views, image_count, allocate, reallocate);
    view_create_info: VkImageViewCreateInfo = {
        viewType = VkImageViewType.VK_IMAGE_VIEW_TYPE_2D;
        format = swap_chain_format.format;
        subresourceRange = {
            aspectMask = VkImageAspectFlagBits.VK_IMAGE_ASPECT_COLOR_BIT;
            baseMipLevel = 0; levelCount = 1; baseArrayLayer = 0; layerCount = 1;
        }
    }

    each image, i in swap_chain_images {
        view_create_info.image = image;

        result = vkCreateImageView(device, &view_create_info, &allocator, &swap_chain_image_views[i]);
        if result != VkResult.VK_SUCCESS {
            log("Unable to create image view %\n", result);
            exit_program(1);
        }
    }

    // Create the UI render pass
    {
        color_attachment: VkAttachmentDescription = {
            format = swap_chain_format.format;
            samples = msaa_samples;
            loadOp = VkAttachmentLoadOp.VK_ATTACHMENT_LOAD_OP_CLEAR;
            storeOp = VkAttachmentStoreOp.VK_ATTACHMENT_STORE_OP_STORE;
            stencilLoadOp = VkAttachmentLoadOp.VK_ATTACHMENT_LOAD_OP_DONT_CARE;
            stencilStoreOp = VkAttachmentStoreOp.VK_ATTACHMENT_STORE_OP_DONT_CARE;
            initialLayout = VkImageLayout.VK_IMAGE_LAYOUT_UNDEFINED;
            finalLayout = VkImageLayout.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
        }

        color_attachment_resolve: VkAttachmentDescription = {
            format = swap_chain_format.format;
            samples = VkSampleCountFlagBits.VK_SAMPLE_COUNT_1_BIT;
            loadOp = VkAttachmentLoadOp.VK_ATTACHMENT_LOAD_OP_DONT_CARE;
            storeOp = VkAttachmentStoreOp.VK_ATTACHMENT_STORE_OP_STORE;
            stencilLoadOp = VkAttachmentLoadOp.VK_ATTACHMENT_LOAD_OP_DONT_CARE;
            stencilStoreOp = VkAttachmentStoreOp.VK_ATTACHMENT_STORE_OP_DONT_CARE;
            initialLayout = VkImageLayout.VK_IMAGE_LAYOUT_UNDEFINED;
            finalLayout = VkImageLayout.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
        }

        attachments: Array<VkAttachmentDescription> = [color_attachment, color_attachment_resolve]

        color_ref: VkAttachmentReference = {
            attachment = 0;
            layout = VkImageLayout.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
        }

        resolve_ref: VkAttachmentReference = {
            attachment = 1;
            layout = VkImageLayout.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
        }

        create_render_pass(&ui_render_pass, attachments, &color_ref, null, &resolve_ref);
    }

    // Create color image view
    color_format := swap_chain_format.format;

    create_image(swap_chain_extent.width, swap_chain_extent.height, color_format, VkImageTiling.VK_IMAGE_TILING_OPTIMAL, VkImageUsageFlagBits.VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT | VkImageUsageFlagBits.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT, VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, &color_image, &color_image_memory, samples = msaa_samples);

    color_view_create_info: VkImageViewCreateInfo = {
        image = color_image;
        viewType = VkImageViewType.VK_IMAGE_VIEW_TYPE_2D;
        format = color_format;
        subresourceRange = {
            aspectMask = VkImageAspectFlagBits.VK_IMAGE_ASPECT_COLOR_BIT;
            baseMipLevel = 0;
            levelCount = 1;
            baseArrayLayer = 0;
            layerCount = 1;
        }
    }

    result = vkCreateImageView(device, &color_view_create_info, &allocator, &color_image_view);
    if result != VkResult.VK_SUCCESS {
        log("Unable to create color image view %\n", result);
        exit_program(1);
    }

    // Create depth image view
    create_image(swap_chain_extent.width, swap_chain_extent.height, depth_format, VkImageTiling.VK_IMAGE_TILING_OPTIMAL, VkImageUsageFlagBits.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT, VkMemoryPropertyFlagBits.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, &depth_image, &depth_image_memory, samples = msaa_samples);

    depth_view_create_info: VkImageViewCreateInfo = {
        image = depth_image;
        viewType = VkImageViewType.VK_IMAGE_VIEW_TYPE_2D;
        format = depth_format;
        subresourceRange = {
            aspectMask = VkImageAspectFlagBits.VK_IMAGE_ASPECT_DEPTH_BIT;
            baseMipLevel = 0;
            levelCount = 1;
            baseArrayLayer = 0;
            layerCount = 1;
        }
    }

    result = vkCreateImageView(device, &depth_view_create_info, &allocator, &depth_image_view);
    if result != VkResult.VK_SUCCESS {
        log("Unable to create depth image view %\n", result);
        exit_program(1);
    }

    transition_image_layout(depth_image, depth_format, VkImageLayout.VK_IMAGE_LAYOUT_UNDEFINED, VkImageLayout.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL, 1);

    // Create framebuffers
    color_image_views: Array<VkImageView*> = [color_image_view]
    depth_image_views: Array<VkImageView*> = [depth_image_view]

    array_resize(&ui_framebuffers, image_count, allocate, reallocate);
    create_framebuffers(ui_framebuffers, ui_render_pass, color_image_views, swap_chain_image_views);
}

create_render_pass(VkRenderPass** render_pass, Array<VkAttachmentDescription> attachments, VkAttachmentReference* color, VkAttachmentReference* depth, VkAttachmentReference* resolve = null) {
    subpass: VkSubpassDescription = {
        pipelineBindPoint = VkPipelineBindPoint.VK_PIPELINE_BIND_POINT_GRAPHICS;
        colorAttachmentCount = 1;
        pColorAttachments = color;
        pResolveAttachments = resolve;
        pDepthStencilAttachment = depth;
    }

    dependency: VkSubpassDependency = {
        srcSubpass = VK_SUBPASS_EXTERNAL;
        dstSubpass = 0;
        srcStageMask = VkPipelineStageFlagBits.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | VkPipelineStageFlagBits.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
        srcAccessMask = VkAccessFlagBits.VK_ACCESS_NONE_KHR;
        dstStageMask = VkPipelineStageFlagBits.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | VkPipelineStageFlagBits.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
        dstAccessMask = VkAccessFlagBits.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | VkAccessFlagBits.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
    }

    render_pass_info: VkRenderPassCreateInfo = {
        attachmentCount = attachments.length;
        pAttachments = attachments.data;
        subpassCount = 1;
        pSubpasses = &subpass;
        dependencyCount = 1;
        pDependencies = &dependency;
    }

    result := vkCreateRenderPass(device, &render_pass_info, &allocator, render_pass);
    if result != VkResult.VK_SUCCESS {
        log("Unable to create render pass %\n", result);
        exit_program(1);
    }
}

create_framebuffers(Array<VkFramebuffer*> framebuffers, VkRenderPass* render_pass, Params<Array<VkImageView*>> attachments) {
    framebuffer_attachments: Array<VkImageView*>[attachments.length];
    framebuffer_info: VkFramebufferCreateInfo = {
        renderPass = render_pass;
        attachmentCount = framebuffer_attachments.length;
        pAttachments = framebuffer_attachments.data;
        width = swap_chain_extent.width;
        height = swap_chain_extent.height;
        layers = 1;
    }

    each framebuffer, i in framebuffers {
        each attachment, j in attachments {
            if attachment.length == framebuffers.length
                framebuffer_attachments[j] = attachment[i];
            else if attachment.length == 1
                framebuffer_attachments[j] = attachment[0];
            else
                assert(false, "Framebuffer attachment required but not provided");
        }

        result := vkCreateFramebuffer(device, &framebuffer_info, &allocator, &framebuffer);
        if result != VkResult.VK_SUCCESS {
            log("Unable to create framebuffer %\n", result);
            exit_program(1);
        }
    }
}

create_image(u32 width, u32 height, VkFormat format, VkImageTiling tiling, VkImageUsageFlagBits usage, VkMemoryPropertyFlagBits properties, VkImage** image, VkDeviceMemory** image_memory, u32 mip_levels = 1, VkSampleCountFlagBits samples = VkSampleCountFlagBits.VK_SAMPLE_COUNT_1_BIT) {
    image_info: VkImageCreateInfo = {
        imageType = VkImageType.VK_IMAGE_TYPE_2D; format = format; mipLevels = mip_levels; arrayLayers = 1; samples = samples;
        tiling = tiling; usage = usage; sharingMode = VkSharingMode.VK_SHARING_MODE_EXCLUSIVE; initialLayout = VkImageLayout.VK_IMAGE_LAYOUT_UNDEFINED;
        extent = { width = width; height = height; depth = 1; }
    }

    result := vkCreateImage(device, &image_info, &allocator, image);
    if result != VkResult.VK_SUCCESS {
        log("Failed to create image %\n", result);
        exit_program(1);
    }

    memory_requirements: VkMemoryRequirements;
    vkGetImageMemoryRequirements(device, *image, &memory_requirements);

    alloc_info: VkMemoryAllocateInfo = {
        allocationSize = memory_requirements.size;
        memoryTypeIndex = find_memory_type(memory_requirements.memoryTypeBits, properties);
    }

    result = vkAllocateMemory(device, &alloc_info, &allocator, image_memory);
    if result != VkResult.VK_SUCCESS {
        log("Failed to allocate image memory %\n", result);
        exit_program(1);
    }

    vkBindImageMemory(device, *image, *image_memory, 0);
}

u32 find_memory_type(u32 type_filter, VkMemoryPropertyFlagBits properties) {
    memory_properties: VkPhysicalDeviceMemoryProperties;
    vkGetPhysicalDeviceMemoryProperties(physical_device, &memory_properties);

    each i in 0..memory_properties.memoryTypeCount-1 {
        if (type_filter & (1 << i)) > 0 && (memory_properties.memoryTypes[i].propertyFlags & properties) == properties
            return i;
    }

    log("Failed to find a suitable memory type\n");
    exit_program(1);
    return 0;
}

VkCommandBuffer* begin_single_time_commands(VkCommandPool* command_pool) {
    alloc_info: VkCommandBufferAllocateInfo = {
        level = VkCommandBufferLevel.VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        commandPool = command_pool;
        commandBufferCount = 1;
    }

    command_buffer: VkCommandBuffer*;
    vkAllocateCommandBuffers(device, &alloc_info, &command_buffer);

    begin_info: VkCommandBufferBeginInfo = {
        flags = cast(u32, VkCommandBufferUsageFlagBits.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT);
    }

    vkBeginCommandBuffer(command_buffer, &begin_info);

    return command_buffer;
}

end_single_time_commands(VkCommandBuffer* command_buffer, VkCommandPool* command_pool, SubmitCommandBuffer submit, int index) {
    vkEndCommandBuffer(command_buffer);

    submit_info: VkSubmitInfo = {
        commandBufferCount = 1;
        pCommandBuffers = &command_buffer;
    }

    fence := thread_fences[index];
    vkResetFences(device, 1, &fence);
    submit(&submit_info, fence, index);
    vkWaitForFences(device, 1, &fence, VK_TRUE, 0xFFFFFFFFFFFFFFFF);

    vkFreeCommandBuffers(device, command_pool, 1, &command_buffer);
}

submit_command_buffer_to_single_graphics_queue(VkSubmitInfo* submit_info, VkFence* fence, int thread) {
    semaphore_wait(&graphics_queue_semaphore);
    defer semaphore_release(&graphics_queue_semaphore);

    result := vkQueueSubmit(graphics_queue, 1, submit_info, fence);
    if result != VkResult.VK_SUCCESS {
        log("Failed to submit command buffer to graphics queue: %\n", result);
        exit_program(1);
    }
}

submit_command_buffer_to_graphics_queue_by_thread(VkSubmitInfo* submit_info, VkFence* fence, int thread) {
    queue := graphics_queues[thread];

    result := vkQueueSubmit(queue, 1, submit_info, fence);
    if result != VkResult.VK_SUCCESS {
        log("Failed to submit command buffer to graphics queue: %\n", result);
        exit_program(1);
    }
}

submit_command_buffer_to_graphics_queue_by_lock(VkSubmitInfo* submit_info, VkFence* fence, int thread) {
    lock_and_submit_to_queue(&graphics_queue_semaphore, graphics_queues, graphics_queue_locks, submit_info, fence);
}

submit_command_buffer_to_compute_queue(VkSubmitInfo* submit_info, VkFence* fence, int thread) {
    lock_and_submit_to_queue(&compute_queue_semaphore, compute_queues, compute_queue_locks, submit_info, fence);
}

submit_command_buffer_to_transfer_queue(VkSubmitInfo* submit_info, VkFence* fence, int thread) {
    lock_and_submit_to_queue(&transfer_queue_semaphore, transfer_queues, transfer_queue_locks, submit_info, fence);
}

lock_and_submit_to_queue(Semaphore* semaphore, Array<VkQueue*> queues, Array<u8> locks, VkSubmitInfo* submit_info, VkFence* fence) {
    semaphore_wait(semaphore);
    defer semaphore_release(semaphore);

    while true {
        each lock, i in locks {
            if lock == 0 && compare_exchange(&lock, 1, 0) == 0 {
                result := vkQueueSubmit(queues[i], 1, submit_info, fence);
                if result != VkResult.VK_SUCCESS {
                    log("Failed to submit command buffer to queue: %\n", result);
                    exit_program(1);
                }

                lock = 0;
                return;
            }
        }
    }
}

VkResult submit_present_single_queue(VkPresentInfoKHR* present_info) {
    semaphore_wait(&graphics_queue_semaphore);
    defer semaphore_release(&graphics_queue_semaphore);

    return vkQueuePresentKHR(graphics_queue, present_info);
}

VkResult submit_present_first_graphics_queue(VkPresentInfoKHR* present_info) {
    return vkQueuePresentKHR(graphics_queues[0], present_info);
}

VkResult submit_present_dedicated_present_queue(VkPresentInfoKHR* present_info) {
    return vkQueuePresentKHR(present_queue, present_info);
}

VkResult submit_present_graphics_queue_by_lock(VkPresentInfoKHR* present_info) {
    return lock_and_submit_present(&graphics_queue_semaphore, graphics_queues, graphics_queue_locks, present_info);
}

VkResult submit_present_compute_queue(VkPresentInfoKHR* present_info) {
    return lock_and_submit_present(&compute_queue_semaphore, compute_queues, compute_queue_locks, present_info);
}

VkResult submit_present_transfer_queue(VkPresentInfoKHR* present_info) {
    return lock_and_submit_present(&transfer_queue_semaphore, transfer_queues, transfer_queue_locks, present_info);
}

VkResult lock_and_submit_present(Semaphore* semaphore, Array<VkQueue*> queues, Array<u8> locks, VkPresentInfoKHR* present_info) {
    semaphore_wait(semaphore);
    defer semaphore_release(semaphore);

    while true {
        each lock, i in locks {
            if lock == 0 && compare_exchange(&lock, 1, 0) == 0 {
                result := vkQueuePresentKHR(queues[i], present_info);
                lock = 0;
                return result;
            }
        }
    }

    // Should never happen
    return VkResult.VK_NOT_READY;
}

transition_image_layout(VkImage* image, VkFormat format, VkImageLayout old_layout, VkImageLayout new_layout, u32 mip_levels, int index = 0, VkCommandBuffer* command_buffer = null) {
    barrier: VkImageMemoryBarrier = {
        oldLayout = old_layout; newLayout = new_layout; image = image;
        srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED; dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        subresourceRange = { baseMipLevel = 0; levelCount = mip_levels; baseArrayLayer = 0; layerCount = 1; }
    }

    if new_layout == VkImageLayout.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL {
        barrier.subresourceRange.aspectMask = VkImageAspectFlagBits.VK_IMAGE_ASPECT_DEPTH_BIT;

        if format == VkFormat.VK_FORMAT_D32_SFLOAT_S8_UINT || format == VkFormat.VK_FORMAT_D24_UNORM_S8_UINT {
            barrier.subresourceRange.aspectMask |= VkImageAspectFlagBits.VK_IMAGE_ASPECT_STENCIL_BIT;
        }
    }
    else {
        barrier.subresourceRange.aspectMask = VkImageAspectFlagBits.VK_IMAGE_ASPECT_COLOR_BIT;
    }

    source_stage, destination_stage: VkPipelineStageFlagBits;

    if old_layout == VkImageLayout.VK_IMAGE_LAYOUT_UNDEFINED && new_layout == VkImageLayout.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL {
        barrier.dstAccessMask = VkAccessFlagBits.VK_ACCESS_TRANSFER_WRITE_BIT;
        source_stage = VkPipelineStageFlagBits.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
        destination_stage = VkPipelineStageFlagBits.VK_PIPELINE_STAGE_TRANSFER_BIT;
    }
    else if old_layout == VkImageLayout.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL && new_layout == VkImageLayout.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL {
        barrier.srcAccessMask = VkAccessFlagBits.VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.dstAccessMask = VkAccessFlagBits.VK_ACCESS_SHADER_READ_BIT;
        source_stage = VkPipelineStageFlagBits.VK_PIPELINE_STAGE_TRANSFER_BIT;
        destination_stage = VkPipelineStageFlagBits.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
    }
    else if old_layout == VkImageLayout.VK_IMAGE_LAYOUT_UNDEFINED && new_layout == VkImageLayout.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL {
        barrier.dstAccessMask = VkAccessFlagBits.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT | VkAccessFlagBits.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
        source_stage = VkPipelineStageFlagBits.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
        destination_stage = VkPipelineStageFlagBits.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
    }
    else {
        log("Unsupported layout transition\n");
        exit_program(1);
    }

    if command_buffer {
        vkCmdPipelineBarrier(command_buffer, source_stage, destination_stage, 0, 0, null, 0, null, 1, &barrier);
        return;
    }

    command_pool := graphics_command_pools[index];
    command_buffer = begin_single_time_commands(command_pool);

    vkCmdPipelineBarrier(command_buffer, source_stage, destination_stage, 0, 0, null, 0, null, 1, &barrier);

    end_single_time_commands(command_buffer, command_pool, submit_to_graphics_queue, index);
}

destroy_swap_chain(bool keep_old = false) {
    vkDestroyImageView(device, color_image_view, &allocator);
    vkDestroyImage(device, color_image, &allocator);
    vkFreeMemory(device, color_image_memory, &allocator);

    vkDestroyImageView(device, depth_image_view, &allocator);
    vkDestroyImage(device, depth_image, &allocator);
    vkFreeMemory(device, depth_image_memory, &allocator);

    each framebuffer in ui_framebuffers {
        vkDestroyFramebuffer(device, framebuffer, &allocator);
    }

    each image_view in swap_chain_image_views {
        vkDestroyImageView(device, image_view, &allocator);
    }

    vkDestroyRenderPass(device, ui_render_pass, &allocator);

    if !keep_old
        vkDestroySwapchainKHR(device, swap_chain, &allocator);
}

enum PhysicalDeviceQueueFlags {
    SingleQueue = 0x0;
    SingleGraphicsQueue = 0x1;
    DedicatedComputeQueueFamily = 0x2;
    DedicatedTransferQueueFamily = 0x4;
    CombinedComputeTransferQueueFamily = 0x8;
}

bool find_queue_families(VkPhysicalDevice* device, u32* graphics_family, u32* present_family, u32* compute_family, u32* transfer_family, PhysicalDeviceQueueFlags* queue_flags) {
    queue_family_count: u32;
    vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, null);

    families: Array<VkQueueFamilyProperties>[queue_family_count];
    vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, families.data);

    graphics_queue_count, compute_queue_count, transfer_queue_count, present_support: u32;
    each family, i in families {
        if graphics_queue_count == 0 {
            if family.queueFlags & VkQueueFlagBits.VK_QUEUE_GRAPHICS_BIT {
                *graphics_family = i;
                graphics_queue_count = family.queueCount;
            }
        }
        else {
            if compute_queue_count == 0 {
                if family.queueFlags & VkQueueFlagBits.VK_QUEUE_COMPUTE_BIT {
                    *compute_family = i;
                    compute_queue_count = family.queueCount;
                }
            }

            if family.queueFlags & VkQueueFlagBits.VK_QUEUE_TRANSFER_BIT {
                if transfer_queue_count == 0 || (compute_queue_count > 0 && *compute_family == *transfer_family) {
                    *transfer_family = i;
                    transfer_queue_count = family.queueCount;
                }
            }
        }

        if present_support == VK_FALSE {
            vkGetPhysicalDeviceSurfaceSupportKHR(device, i, surface, &present_support);

            if present_support {
                *present_family = i;
            }
        }
    }

    flags: PhysicalDeviceQueueFlags;
    if compute_queue_count > 0 && transfer_queue_count > 0 {
        if *compute_family == *transfer_family {
            flags |= PhysicalDeviceQueueFlags.CombinedComputeTransferQueueFamily;
        }
        else {
            flags |= PhysicalDeviceQueueFlags.DedicatedComputeQueueFamily | PhysicalDeviceQueueFlags.DedicatedTransferQueueFamily;
        }
    }
    else if compute_queue_count > 0 {
        flags |= PhysicalDeviceQueueFlags.DedicatedComputeQueueFamily;
        *transfer_family = *graphics_family;
    }
    else if transfer_queue_count > 0 {
        flags |= PhysicalDeviceQueueFlags.DedicatedTransferQueueFamily;
        *compute_family = *graphics_family;
    }

    if flags == PhysicalDeviceQueueFlags.SingleQueue {
        *compute_family = *graphics_family;
        *transfer_family = *graphics_family;
    }
    else if graphics_queue_count == 1 {
        flags |= PhysicalDeviceQueueFlags.SingleGraphicsQueue;
    }

    *queue_flags = flags;
    return graphics_queue_count > 0 && present_support == VK_TRUE;
}


#if DEVELOPER {
    device_extensions: Array<string> = ["VK_KHR_swapchain", "VK_KHR_fragment_shader_barycentric"]
}
else {
    device_extensions: Array<string> = ["VK_KHR_swapchain"]
}

bool check_device_extension_support(VkPhysicalDevice* device) {
    extension_count: u32;
    vkEnumerateDeviceExtensionProperties(device, null, &extension_count, null);

    available_extensions: Array<VkExtensionProperties>[extension_count];
    vkEnumerateDeviceExtensionProperties(device, null, &extension_count, available_extensions.data);

    each required_extension in device_extensions {
        found := false;

        each extension in available_extensions {
            name := convert_c_string(&extension.extensionName);

            if name == required_extension {
                found = true;
                break;
            }
        }

        if !found return false;
    }

    return true;
}

#if DEVELOPER {
    debug_messenger: VkDebugUtilsMessengerEXT*;
    validation_layers: Array<string> = ["VK_LAYER_KHRONOS_validation"]

    u32 debug_callback(VkDebugUtilsMessageSeverityFlagBitsEXT severity, VkDebugUtilsMessageTypeFlagBitsEXT type, VkDebugUtilsMessengerCallbackDataEXT* callback_data, void* user_data) {
        if severity == VkDebugUtilsMessageSeverityFlagBitsEXT.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT {
            log("Warning - %\n", convert_c_string(callback_data.pMessage));
        }
        else if severity == VkDebugUtilsMessageSeverityFlagBitsEXT.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT {
            log("Error - %\n", convert_c_string(callback_data.pMessage));
        }

        return VK_FALSE;
    }

}
