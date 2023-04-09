package nido

import "core:fmt"
import "core:log"
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

vulkan_pipelines := [?]VulkanPipelineMetadata {
    {
        "stbtt",
        {
            "ortho_xy_uv_rgba",
            "text",
        },
    },
}

VulkanModule :: struct {
    meta: VulkanModuleMetadata,
    description: ShaderModuleDescription,
    handle: vk.ShaderModule,
}

VulkanPipeline :: struct {
    meta: VulkanPipelineMetadata,
    modules: [dynamic]VulkanModule,
    handle: vk.Pipeline,
    descriptor_set_layouts: [dynamic]vk.DescriptorSetLayout,
    descriptor_pool: vk.DescriptorPool,
    descriptor_set_handles: [dynamic]vk.DescriptorSet,
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

vulkan_create_pipelines :: proc(vulkan: ^Vulkan, render_pass: vk.RenderPass) {
    vulkan.pipelines = make(map[string]VulkanPipeline, len(vulkan_pipelines))

    for meta in vulkan_pipelines {
        if meta.name in vulkan.pipelines {
            fmt.panicf("duplicate pipeline named '%s'", meta.name)
        }

        log.infof("Creating pipeline '%s'...", meta.name)

        pipeline := VulkanPipeline {
            meta = meta,
        }

        modules := make([dynamic]VulkanModule, len(meta.modules), context.temp_allocator)
        for module_name, i in meta.modules {
            modules[i] = vulkan.modules[module_name] or_else fmt.panicf("no module '%s' is loaded", module_name)
        }

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

        // NOTE(jan): Maps a SPIR-V type to a Vulkan descriptor type.
        determine_type :: proc(type_description: TypeDescription) -> vk.DescriptorType {
            switch comp in type_description.component_type {
                case ScalarDescription:
                    switch comp.type {
                        case ScalarType.FLOAT:
                            return vk.DescriptorType.UNIFORM_BUFFER
                        case ScalarType.SIGNED_INT:
                            return vk.DescriptorType.UNIFORM_BUFFER
                        case ScalarType.UNSIGNED_INT:
                            return vk.DescriptorType.UNIFORM_BUFFER
                        case ScalarType.VOID:
                            return vk.DescriptorType.UNIFORM_BUFFER
                    }
                case StructDescription:
                    return vk.DescriptorType.UNIFORM_BUFFER
                case SamplerDescription:
                    return vk.DescriptorType.SAMPLER
                case SampledImageDescription:
                    return vk.DescriptorType.COMBINED_IMAGE_SAMPLER
                case ^TypeDescription:
                    return determine_type(comp^)
            }
            panic("cannot determine type")
        }

        // NOTE(jan): A descriptor set's binding can be specified in two modules: E.g. if one module is the vertex shader
        // and the other is the fragment shader and they both need access to it. In this case, we only set the info for
        // the binding once, and the second time around we just add a stage flag.
        descriptor_set_layout_binding_map := make(map[u32]map[u32]vk.DescriptorSetLayoutBinding, 1, context.temp_allocator)
        sizes := make([dynamic]vk.DescriptorPoolSize, context.temp_allocator)
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
            for uniform_index, uniform in module.description.uniforms {
                if uniform_index not_in descriptor_set_layout_binding_map {
                    descriptor_set_layout_binding_map[uniform_index] = make(map[u32]vk.DescriptorSetLayoutBinding, 1, context.temp_allocator)
                }
                bindings := &descriptor_set_layout_binding_map[uniform_index]

                for binding_index, binding in uniform {
                    type: vk.DescriptorType = determine_type(binding.type)

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
        }
        descriptor_set_count := u32(len(descriptor_set_layout_binding_map))

        pipeline.descriptor_set_layouts = make([dynamic]vk.DescriptorSetLayout, descriptor_set_count, context.temp_allocator)
        for descriptor_set_index in 0..<descriptor_set_count {
            binding_map := descriptor_set_layout_binding_map[descriptor_set_index]

            bindings := make([dynamic]vk.DescriptorSetLayoutBinding, len(binding_map), context.temp_allocator)
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
            log.infof("Created descriptor set layout #%d.", descriptor_set_index)
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

        pipeline.descriptor_set_handles = make([dynamic]vk.DescriptorSet, descriptor_set_count, context.allocator)
        {
            alloc := vk.DescriptorSetAllocateInfo {
                sType = vk.StructureType.DESCRIPTOR_SET_ALLOCATE_INFO,
                descriptorPool = pipeline.descriptor_pool,
                descriptorSetCount = descriptor_set_count,
                pSetLayouts = raw_data(pipeline.descriptor_set_layouts),
            }
            check(
                vk.AllocateDescriptorSets(vulkan.device, &alloc, raw_data(pipeline.descriptor_set_handles)),
                "could not allocate descriptor sets",
            )
        }

        pipeline_layout: vk.PipelineLayout
        {
            // TODO(jan): Create push constant ranges from description.
            create := vk.PipelineLayoutCreateInfo {
                sType = vk.StructureType.PIPELINE_LAYOUT_CREATE_INFO,
                setLayoutCount = u32(len(pipeline.descriptor_set_layouts)),
                pSetLayouts = raw_data(pipeline.descriptor_set_layouts),
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

        check(
            vk.CreateGraphicsPipelines(vulkan.device, 0, 1, &create, nil, &pipeline.handle),
            "coult not create pipeline",
        )
        log.infof("Pipeline created.")

        vulkan.pipelines[meta.name] = pipeline
    }
}

vulkan_destroy_pipelines :: proc(vulkan: ^Vulkan) {
    for name, pipeline in vulkan.pipelines {
        pipeline := vulkan.pipelines[name]

        for descriptor_set_layout in pipeline.descriptor_set_layouts do vk.DestroyDescriptorSetLayout(vulkan.device, descriptor_set_layout, nil)
        clear(&pipeline.descriptor_set_layouts)

        vk.DestroyDescriptorPool(vulkan.device, pipeline.descriptor_pool, nil)
        pipeline.descriptor_pool = 0

        vk.FreeDescriptorSets(vulkan.device, pipeline.descriptor_pool, u32(len(pipeline.descriptor_set_handles)), raw_data(pipeline.descriptor_set_handles))
        clear(&pipeline.descriptor_set_handles)

        vk.DestroyPipeline(vulkan.device, pipeline.handle, nil)

        vulkan.pipelines[name] = pipeline
    }
    clear(&vulkan.pipelines)
}
