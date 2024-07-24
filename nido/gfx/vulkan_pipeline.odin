package gfx

import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import path "core:path/filepath"
import "core:strings"
import vk "vendor:vulkan"

VulkanModuleMetadata :: struct {
    name: string,
    path: string,
}

VulkanPipelineMetadata :: struct {
    name: string,
    modules: []string,
}

VulkanModule :: struct {
    meta: VulkanModuleMetadata,
    description: ShaderModuleDescription,
    handle: vk.ShaderModule,
}

VulkanPipeline :: struct {
    meta: VulkanPipelineMetadata,
    handle: vk.Pipeline,
    descriptor_set_layouts: [dynamic]vk.DescriptorSetLayout,
    descriptor_pool: vk.DescriptorPool,
    descriptor_sets: [dynamic]vk.DescriptorSet,
    layout: vk.PipelineLayout,
    render_pass: vk.RenderPass,
}

vulkan_create_shader_modules :: proc(vulkan: ^Vulkan) {
    shader_pattern := path.join({".", "shaders", "*.spv"}, context.temp_allocator)
    module_paths := path.glob(shader_pattern) or_else panic("can't list module source files")

    vulkan.modules = make(map[string]VulkanModule, len(module_paths))

    for module_path in module_paths {
        meta := VulkanModuleMetadata {
            name = path.short_stem(module_path),
            path = module_path,
        }

        if meta.name in vulkan.modules {
            fmt.panicf("duplicate module named '%s'", meta.name)
        }

        module := VulkanModule {
            meta = meta,
        }

        log.infof("Loading shader module '%s' at '%s':", meta.name, meta.path)

        bytes: []u8 = os.read_entire_file_from_filename(meta.path, context.temp_allocator) or_else panic("can't read shader")
        words := cast(^u32)(raw_data(bytes[:]))
        module.description = parse(bytes) or_else panic("can't describe shader module")

        create := vk.ShaderModuleCreateInfo {
            sType = vk.StructureType.SHADER_MODULE_CREATE_INFO,
            codeSize = len(bytes),
            pCode = words,
        }
        check(
            vk.CreateShaderModule(vulkan.device, &create, nil, &module.handle),
            "could not create shader module",
        )
        log.infof("\t... module created.")

        vulkan.modules[meta.name] = module
    }
}

vulkan_pipelines_create :: proc(
    vulkan: ^Vulkan,
    metadata: []VulkanPipelineMetadata,
    render_pass: vk.RenderPass,
) -> (
    pipelines: map[string]VulkanPipeline,
) {
    allocator: mem.Allocator = vulkan.resize_allocator
    temp_allocator: mem.Allocator = context.temp_allocator

    pipelines = make(map[string]VulkanPipeline, 1, allocator)

    for meta in metadata {
        if meta.name in pipelines {
            fmt.panicf("duplicate pipeline named '%s'", meta.name)
        }

        log.infof("Creating pipeline '%s'...", meta.name)

        pipeline := VulkanPipeline {
            meta = meta,
        }

        modules := make([dynamic]VulkanModule, len(meta.modules), temp_allocator)
        for module_name, i in meta.modules {
            modules[i] = vulkan.modules[module_name] or_else fmt.panicf("no module '%s' is loaded", module_name)
        }

        stages := make([dynamic]vk.PipelineShaderStageCreateInfo, temp_allocator)
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

        // NOTE(jan): A descriptor set's binding can be specified in two modules: E.g. if one module is the vertex shader
        // and the other is the fragment shader and they both need access to it. In this case, we only set the info for
        // the binding once, and the second time around we just add a stage flag.
        descriptor_set_layout_binding_map := make(map[u32]map[u32]vk.DescriptorSetLayoutBinding, 1, temp_allocator)
        sizes := make([dynamic]vk.DescriptorPoolSize, temp_allocator)
        for module in modules {
            // NOTE(jan): Each binding needs to specify which shader stages can access it. Here we look through the module
            // and pick out each shader stage defined in it, and assume that if the uniform is in the same module as a
            // stage, then that means it needs to access it. This probably holds if you break up shader stages into separate
            // modules, but it probably breaks for HLSL etc.
            stage_flags := vk.ShaderStageFlags { }
            for shader in module.description.shaders {
                switch shader.type {
                    case ShaderType.Vertex:
                        stage_flags += { vk.ShaderStageFlag.VERTEX }
                    case ShaderType.Fragment:
                        stage_flags += { vk.ShaderStageFlag.FRAGMENT }
                    // TODO(jan): Other stages.
                }
            }
            for uniform in module.description.uniforms {
                binding_index := uniform.binding
                descriptor_set_index := uniform.descriptor_set

                if descriptor_set_index not_in descriptor_set_layout_binding_map {
                    descriptor_set_layout_binding_map[descriptor_set_index] = make(map[u32]vk.DescriptorSetLayoutBinding, 1, temp_allocator)
                }
                bindings := &descriptor_set_layout_binding_map[descriptor_set_index]

                type: vk.DescriptorType = determine_type(uniform.var.type)

                // NOTE(jan): Figure out the descriptor set layout binding first.
                descriptor_layout_binding, exists := bindings[binding_index]

                if (exists) {
                    // TODO(jan): Check which shader stages in the module actually use the uniform.
                    descriptor_layout_binding.stageFlags += stage_flags
                } else {
                    descriptor_layout_binding = vk.DescriptorSetLayoutBinding {
                        binding = u32(binding_index),
                        // TODO(jan): Allow for arrays of bindings.
                        descriptorCount = 1,
                        descriptorType = type,
                        // NOTE(jan): Not using immutable samplers.
                        pImmutableSamplers = nil,
                        // TODO(jan): Check which shader stages in the module actually use the uniform.
                        stageFlags = stage_flags,
                    }
                }

                bindings[binding_index] = descriptor_layout_binding

                // NOTE(jan): Allocate size in the descriptor pool.
                size_found := false
                for candidate, i in sizes {
                    if candidate.type == type {
                        sizes[i].descriptorCount += 1
                        size_found = true
                        break;
                    }
                }

                if !size_found do append(&sizes, vk.DescriptorPoolSize {
                    // TODO(jan): Handle arrays.
                    descriptorCount = 1,
                    type = type,
                })
            }
        }
        descriptor_set_count := u32(len(descriptor_set_layout_binding_map))

        pipeline.descriptor_set_layouts = make([dynamic]vk.DescriptorSetLayout, descriptor_set_count, allocator)
        for descriptor_set_index in 0..<descriptor_set_count {
            binding_map := descriptor_set_layout_binding_map[descriptor_set_index]

            bindings := make([dynamic]vk.DescriptorSetLayoutBinding, len(binding_map), temp_allocator)
            for binding_index in u32(0)..<u32(len(binding_map)) {
                bindings[binding_index] = binding_map[binding_index]
            }

            create := vk.DescriptorSetLayoutCreateInfo {
                sType = vk.StructureType.DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
                bindingCount = u32(len(bindings)),
                pBindings = raw_data(bindings),
                // pNext = &vk.DescriptorSetLayoutBindingFlagsCreateInfo {
                //     sType = vk.StructureType.DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO,
                //     bindingCount = u32(len(flags)),
                //     pBindingFlags = raw_data(flags),
                // },
            }

            check(
                vk.CreateDescriptorSetLayout(vulkan.device, &create, nil, &pipeline.descriptor_set_layouts[descriptor_set_index]),
                "could not create descriptor set layout",
            )
            log.infof("Created descriptor set layout #%d (%d).", descriptor_set_index, pipeline.descriptor_set_layouts[descriptor_set_index])
        }
        
        if (len(sizes) > 0) {
            create := vk.DescriptorPoolCreateInfo {
                sType = vk.StructureType.DESCRIPTOR_POOL_CREATE_INFO,
                maxSets = u32(len(descriptor_set_layout_binding_map)),
                poolSizeCount = u32(len(sizes)),
                pPoolSizes = raw_data(sizes),
            }

            check(
                vk.CreateDescriptorPool(vulkan.device, &create, nil, &pipeline.descriptor_pool),
                "could not allocate descriptor pool",
            )
        }

        pipeline.descriptor_sets = make([dynamic]vk.DescriptorSet, descriptor_set_count, allocator)
        {
            alloc := vk.DescriptorSetAllocateInfo {
                sType = vk.StructureType.DESCRIPTOR_SET_ALLOCATE_INFO,
                descriptorPool = pipeline.descriptor_pool,
                descriptorSetCount = descriptor_set_count,
                pSetLayouts = raw_data(pipeline.descriptor_set_layouts),
            }
            check(
                vk.AllocateDescriptorSets(vulkan.device, &alloc, raw_data(pipeline.descriptor_sets)),
                "could not allocate descriptor sets",
            )
        }

        {
            // TODO(jan): Create push constant ranges from description.
            create := vk.PipelineLayoutCreateInfo {
                sType = vk.StructureType.PIPELINE_LAYOUT_CREATE_INFO,
                setLayoutCount = u32(len(pipeline.descriptor_set_layouts)),
                pSetLayouts = raw_data(pipeline.descriptor_set_layouts),
            }

            check(
                vk.CreatePipelineLayout(vulkan.device, &create, nil, &pipeline.layout),
                "couldn't create pipeline layout",
            )
            log.infof("Created pipeline layout.")
        }

        // NOTE(jan): We allocate one buffer per vertex attribute for flexibility, hence each attribute
        // will have its own binding. Therefore, set binding = location.
        vertex_inputs := make([dynamic]vk.VertexInputBindingDescription, temp_allocator)
        vertex_attributes := make([dynamic]vk.VertexInputAttributeDescription, temp_allocator)
        for module in modules {
            for shader in module.description.shaders {
                if shader.type != ShaderType.Vertex do continue

                for input in shader.inputs {
                    found := false

                    for vertex_input in vertex_inputs do if vertex_input.binding == input.location do panic("duplicate input binding")
                    for vertex_attribute in vertex_attributes do if vertex_attribute.location == input.location do panic("duplicate input location")

                    input_desc := vk.VertexInputBindingDescription {
                        binding = input.location,
                        stride = determine_size(input.var.type),
                        inputRate = vk.VertexInputRate.VERTEX,
                    }
                    append(&vertex_inputs, input_desc)

                    attr_desc := vk.VertexInputAttributeDescription {
                        binding = input.location,
                        location = input.location,
                        format = determine_format(input.var.type),
                        // NOTE(jan): Zero offset since we aren't interleaving.
                        offset = 0,
                    }
                    append(&vertex_attributes, attr_desc)
                }
            }
        }

        create := vk.GraphicsPipelineCreateInfo {
            sType = vk.StructureType.GRAPHICS_PIPELINE_CREATE_INFO,
            stageCount = u32(len(stages)),
            pStages = raw_data(stages),
            renderPass = render_pass,
            layout = pipeline.layout,
            subpass = 0,
            pVertexInputState = &vk.PipelineVertexInputStateCreateInfo {
                sType = vk.StructureType.PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
                vertexBindingDescriptionCount = u32(len(vertex_inputs)),
                pVertexBindingDescriptions = raw_data(vertex_inputs),
                vertexAttributeDescriptionCount = u32(len(vertex_attributes)),
                pVertexAttributeDescriptions = raw_data(vertex_attributes),
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
                depthTestEnable = true,
                depthWriteEnable = true,
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

        check(
            vk.CreateGraphicsPipelines(vulkan.device, 0, 1, &create, nil, &pipeline.handle),
            "coult not create pipeline",
        )
        log.infof("Pipeline created.")

        pipelines[meta.name] = pipeline
    }

    return
}

vulkan_pipeline_destroy :: proc(vulkan: ^Vulkan, pipeline: ^VulkanPipeline) {
    vk.DestroyDescriptorPool(vulkan.device, pipeline.descriptor_pool, nil)
    clear(&pipeline.descriptor_sets)
    pipeline.descriptor_pool = 0

    for descriptor_set_layout in pipeline.descriptor_set_layouts {
        log.infof("Destroying descriptor set layout: %d", descriptor_set_layout)
        vk.DestroyDescriptorSetLayout(vulkan.device, descriptor_set_layout, nil)
    }
    clear(&pipeline.descriptor_set_layouts)

    vk.DestroyPipelineLayout(vulkan.device, pipeline.layout, nil)

    vk.DestroyPipeline(vulkan.device, pipeline.handle, nil)
}
