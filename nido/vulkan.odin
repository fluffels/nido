package nido

import "core:log"
import "core:strings"
import vk "vendor:vulkan"

VulkanModule :: struct {
    description: ShaderModuleDescription,
    handle: vk.ShaderModule,
    path: string,
}

VulkanSwap :: struct {
    handle: vk.SwapchainKHR,
    capabilities: vk.SurfaceCapabilitiesKHR,
    extent: vk.Extent2D,
    format: vk.Format,
    color_space: vk.ColorSpaceKHR,
    present_mode: vk.PresentModeKHR,
    views: [dynamic]vk.ImageView,
}

// NOTE(jan): Global Vulkan-related state goes in one of these.
Vulkan :: struct {
    handle: vk.Instance,

    debug_callback: vk.DebugReportCallbackEXT,

    surface: vk.SurfaceKHR,

    device: vk.Device,
    gpu: vk.PhysicalDevice,

    memories: vk.PhysicalDeviceMemoryProperties,

    gfx_queue: vk.Queue,
    gfx_queue_family: u32,

    compute_queue: vk.Queue,
    compute_queue_family: u32,

    swap: VulkanSwap,
    framebuffers: [dynamic]vk.Framebuffer,
}

odinize_string :: proc(from: []u8) -> (to: string) {
    end := 0
    for char in from {
        if char != 0 do end += 1
        else do break
    }
    slice := from[:end]
    to = strings.clone_from_bytes(slice, context.temp_allocator)
    return to
}

vulkanize :: proc(from: [$N]$T) -> (to: [^]T) {
    to = make([^]T, len(from), context.temp_allocator)
    for i in 0..<len(from) {
        to[i] = from[i]
    }
    return to
}

vulkanize_strings :: proc(from: [dynamic]string) -> (to: [^]cstring) {
    to = make([^]cstring, len(from), context.temp_allocator)
    for s, i in from {
        to[i] = strings.clone_to_cstring(s, context.temp_allocator)
    }
    return to
}

framebuffer_create :: proc(vulkan: ^Vulkan, render_pass: vk.RenderPass) {
	log.infof("Creating framebuffers...")

    for view, i in vulkan.swap.views {
        create := vk.FramebufferCreateInfo {
            sType = vk.StructureType.FRAMEBUFFER_CREATE_INFO,
            attachmentCount = 1,
            pAttachments = raw_data(vulkan.swap.views[i:]),
            renderPass = render_pass,
            height = vulkan.swap.extent.height,
            width = vulkan.swap.extent.width,
            layers = 1,
        }
        handle: vk.Framebuffer
        check(
            vk.CreateFramebuffer(vulkan.device, &create, nil, &handle),
            "couldn't create framebuffer",
        )
        append(&vulkan.framebuffers, handle)
        log.infof("\t\u2713 for swap chain image #%d", i)
    }

    log.infof("Created framebuffers.")
}

framebuffer_destroy :: proc(vulkan: ^Vulkan) {
    for framebuffer in vulkan.framebuffers {
        vk.DestroyFramebuffer(vulkan.device, framebuffer, nil)
    }
    clear(&vulkan.framebuffers);
    
    log.infof("Destroyed framebuffers.")
}

swap_create :: proc(vulkan: ^Vulkan) {
    create := vk.SwapchainCreateInfoKHR {
        sType = vk.StructureType.SWAPCHAIN_CREATE_INFO_KHR,
        surface = vulkan.surface,
        minImageCount = vulkan.swap.capabilities.minImageCount,
        imageExtent = vulkan.swap.capabilities.currentExtent,
        oldSwapchain = 0,
        imageFormat = vulkan.swap.format,
        imageColorSpace = vulkan.swap.color_space,
        imageArrayLayers = 1,
        imageUsage = { vk.ImageUsageFlag.COLOR_ATTACHMENT },
        presentMode = vulkan.swap.present_mode,
        preTransform = vulkan.swap.capabilities.currentTransform,
        compositeAlpha = { vk.CompositeAlphaFlagKHR.OPAQUE },
        clipped = false,
    }

    check(
        vk.CreateSwapchainKHR(vulkan.device, &create, nil, &vulkan.swap.handle),
        "could not create swapchain",
    )
    log.infof("Created swapchain.")

    count: u32;
    check(
        vk.GetSwapchainImagesKHR(vulkan.device, vulkan.swap.handle, &count, nil),
        "could not count swapchain images",
    )

    images := make([^]vk.Image, count, context.temp_allocator)
    check(
        vk.GetSwapchainImagesKHR(vulkan.device, vulkan.swap.handle, &count, images),
        "could not fetch swapchain images",
    )

    for i in 0..<count {
        view := view_create(
            vulkan^,
            images[i],
            vk.ImageViewType.D2,
            vulkan.swap.format,
            { vk.ImageAspectFlags.COLOR },
        ) or_else panic("couldn't create swapchain views")
        append(&vulkan.swap.views, view)
    }
}

swap_destroy :: proc(vulkan: ^Vulkan) {
    vk.DestroySwapchainKHR(vulkan.device, vulkan.swap.handle, nil)
    clear(&vulkan.swap.views)

    log.infof("Destroyed swapchain.")
}

swap_update_capabilities :: proc(vulkan: ^Vulkan) {
    check(
        vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(vulkan.gpu, vulkan.surface, &vulkan.swap.capabilities),
        "could not fetch physical device surface capabilities",
    )
}

swap_update_extent :: proc(vulkan: ^Vulkan) {
    vulkan.swap.extent = vulkan.swap.capabilities.currentExtent
}

pipeline_create :: proc(vulkan: ^Vulkan, modules: [dynamic]VulkanModule, render_pass: vk.RenderPass) -> vk.Pipeline {
    log.infof("Creating pipeline...")

    stages := make([dynamic]vk.PipelineShaderStageCreateInfo, context.temp_allocator)
    for module in modules {
        for shader in module.description.shaders {
            log.infof("\t... found a %s shader", shader.type)
            stage_flag: vk.ShaderStageFlag
            switch shader.type {
                case ShaderType.Vertex:
                    stage_flag = vk.ShaderStageFlag.VERTEX
                case ShaderType.Fragment:
                    stage_flag = vk.ShaderStageFlag.FRAGMENT
                case:
                    log.info("\t\t... \u274C which is currently unsupported, skipping")
            }
            append(&stages, vk.PipelineShaderStageCreateInfo {
                sType = vk.StructureType.PIPELINE_SHADER_STAGE_CREATE_INFO,
                module = module.handle,
                pName = strings.clone_to_cstring(shader.name, context.temp_allocator),
                stage = { stage_flag },
            })
        }
    }

    descriptor_layout: vk.DescriptorSetLayout
    {
        bindings := make([dynamic]vk.DescriptorSetLayoutBinding, context.temp_allocator)
        // TODO(jan): Fill this from descriptions.
        flags := make([dynamic]vk.DescriptorBindingFlags, context.temp_allocator)
        // TODO(jan): Fill this from descriptions.

        create := vk.DescriptorSetLayoutCreateInfo {
            sType = vk.StructureType.DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            bindingCount = u32(len(bindings)),
            pBindings = raw_data(bindings),
            pNext = &vk.DescriptorSetLayoutBindingFlagsCreateInfo {
                sType = vk.StructureType.DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO,
                bindingCount = u32(len(bindings)),
                pBindingFlags = raw_data(flags),
            },
        }

        check(
            vk.CreateDescriptorSetLayout(vulkan.device, &create, nil, &descriptor_layout),
            "could not create descriptor set layout",
        )
        log.info("Created descriptor set layout.")
    }

    pool: vk.DescriptorPool
    {
        // TODO(jan): Create descriptor pool.
        // sizes := make([dynamic]vk.DescriptorPoolSize, context.temp_allocator)
        pool = 0;
    }

    descriptor_set: vk.DescriptorSet
    {
        // TODO(jan): Create descriptor set.
        descriptor_set = 0;
    }

    pipeline_layout: vk.PipelineLayout
    {
        // TODO(jan): Create push constant ranges from description.
        create := vk.PipelineLayoutCreateInfo {
            sType = vk.StructureType.PIPELINE_LAYOUT_CREATE_INFO,
            setLayoutCount = 1,
            pSetLayouts = &descriptor_layout,
        }

        check(
            vk.CreatePipelineLayout(vulkan.device, &create, nil, &pipeline_layout),
            "couldn't create pipeline layout",
        )
        log.infof("Created pipeline layout.")
    }

    create := vk.GraphicsPipelineCreateInfo {
        sType = vk.StructureType.GRAPHICS_PIPELINE_CREATE_INFO,
        stageCount = u32(len(stages)),
        pStages = raw_data(stages),
        renderPass = render_pass,
        layout = pipeline_layout,
        subpass = 0,
        pVertexInputState = &vk.PipelineVertexInputStateCreateInfo {
            sType = vk.StructureType.PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            vertexBindingDescriptionCount = 1,
            pVertexBindingDescriptions = &vk.VertexInputBindingDescription {
                binding = 0,
                // TODO(jan): Read from description.
                stride = size_of(f32) * 4,
                // TODO(jan): Read from description.
                inputRate = vk.VertexInputRate.VERTEX,
            },
            vertexAttributeDescriptionCount = 1,
            pVertexAttributeDescriptions = &vk.VertexInputAttributeDescription {
                // TODO(jan): Read from description.
                location = 0,
                // TODO(jan): Read from description.
                binding = 0,
                // TODO(jan): Read from description.
                format = vk.Format.R32G32B32A32_SFLOAT,
                // TODO(jan): Read from description.
                offset = 0,
            },
        },
        pInputAssemblyState = &vk.PipelineInputAssemblyStateCreateInfo {
            sType = vk.StructureType.PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            // TODO(jan): Read from metadata.
            topology = vk.PrimitiveTopology.TRIANGLE_LIST,
            primitiveRestartEnable = false,
        },
        pViewportState = &vk.PipelineViewportStateCreateInfo {
            sType = vk.StructureType.PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            viewportCount = 1,
            pViewports = &vk.Viewport {
                height = f32(vulkan.swap.extent.height),
                width = f32(vulkan.swap.extent.width),
                minDepth = 0,
                maxDepth = 1,
                x = 0,
                y = 0,
            },
            scissorCount = 1,
            pScissors = &vk.Rect2D {
                offset = {
                    x = 0,
                    y = 0,
                },
                extent = vulkan.swap.extent,
            },
        },
        pRasterizationState = &vk.PipelineRasterizationStateCreateInfo {
            sType = vk.StructureType.PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
            frontFace = vk.FrontFace.CLOCKWISE,
            cullMode = vk.CullModeFlags_NONE,
            lineWidth = 1,
            polygonMode = vk.PolygonMode.FILL,
            rasterizerDiscardEnable = false,
            depthClampEnable = false,
            depthBiasEnable = false,
        },
        pMultisampleState = &vk.PipelineMultisampleStateCreateInfo {
            sType = vk.StructureType.PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
            sampleShadingEnable = false,
            // TODO(jan): multi sampling
            minSampleShading = 1,
            pSampleMask = nil,
            alphaToCoverageEnable = false,
            alphaToOneEnable = false,
            // TODO(jan): multi sampling
            rasterizationSamples = { vk.SampleCountFlag._1 },
        },
        pDepthStencilState = &vk.PipelineDepthStencilStateCreateInfo {
            sType = vk.StructureType.PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
            // TODO(jan): enable
            depthTestEnable = false,
            // TODO(jan): enable
            depthWriteEnable = false,
            depthCompareOp = vk.CompareOp.LESS,
            depthBoundsTestEnable = false,
        },
        pColorBlendState = &vk.PipelineColorBlendStateCreateInfo {
            sType = vk.StructureType.PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            logicOpEnable = false,
            logicOp = vk.LogicOp.COPY,
            attachmentCount = 1,
            pAttachments = &vk.PipelineColorBlendAttachmentState {
                colorWriteMask = {
                    vk.ColorComponentFlag.R,
                    vk.ColorComponentFlag.G,
                    vk.ColorComponentFlag.B,
                    vk.ColorComponentFlag.A,
                },
                blendEnable = true,
                srcColorBlendFactor = vk.BlendFactor.SRC_ALPHA,
                dstColorBlendFactor = vk.BlendFactor.ONE_MINUS_SRC_ALPHA,
                colorBlendOp = vk.BlendOp.ADD,
                srcAlphaBlendFactor = vk.BlendFactor.ONE,
                dstAlphaBlendFactor = vk.BlendFactor.ZERO,
                alphaBlendOp = vk.BlendOp.ADD,
            },
            blendConstants = [4]f32 {0, 0, 0, 0},
        },
    }

    pipeline: vk.Pipeline
    check(
        vk.CreateGraphicsPipelines(vulkan.device, 0, 1, &create, nil, &pipeline),
        "coult not create pipeline",
    )
    log.infof("Pipeline created.")
    return pipeline
}

view_create :: proc(
    vulkan: Vulkan,
    image: vk.Image,
    view_type: vk.ImageViewType,
    format: vk.Format,
    aspect_mask: vk.ImageAspectFlags,
) -> (
    view: vk.ImageView,
    ok: b32,
) {
    create := vk.ImageViewCreateInfo {
        sType = vk.StructureType.IMAGE_VIEW_CREATE_INFO,
        components = {
            a = vk.ComponentSwizzle.IDENTITY,
            b = vk.ComponentSwizzle.IDENTITY,
            g = vk.ComponentSwizzle.IDENTITY,
            r = vk.ComponentSwizzle.IDENTITY,
        },
        image = image,
        format = format,
        viewType = view_type,
        subresourceRange = {
            aspectMask = aspect_mask,
            layerCount = vk.REMAINING_ARRAY_LAYERS,
            levelCount = vk.REMAINING_MIP_LEVELS,
        },
    }

    code := vk.CreateImageView(vulkan.device, &create, nil, &view)
    ok = code == vk.Result.SUCCESS

    return view, ok
}

vulkan_make :: proc() -> Vulkan {
    result: Vulkan
    result.swap.views = make([dynamic]vk.ImageView)
    result.framebuffers = make([dynamic]vk.Framebuffer)
    return result;
}
