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
        if meta.name in vulkan.modules {
            fmt.panicf("duplicate pipeline named '%s'", meta.name)
        }

        log.infof("Creating pipeline '%s'...", meta.name)

        pipeline := VulkanPipeline {
            meta = meta,
        }

        modules := make([dynamic]VulkanModule, len(meta.modules), context.temp_allocator)
        for module_name in meta.modules {
            module := vulkan.modules[module_name] or_else fmt.panicf("no module '%s' is loaded", module_name)
            append(&modules, module)
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


        // NOTE(jan): A descriptor set's binding can be specified in two modules: E.g. if one module is the vertex shader
        // and the other is the fragment shader and they both need access to it. In this case, we only set the info for
        // the binding once, and the second time around we just add a stage flag.
        descriptor_set_specified := make([dynamic][dynamic]b32                          , context.temp_allocator)
        descriptor_sets          := make([dynamic][dynamic]vk.DescriptorSetLayoutBinding, context.temp_allocator)
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
            for descriptor_set, descriptor_set_index in module.description.uniforms {
                reserve(&descriptor_set_specified, descriptor_set_index + 1)
                reserve(&descriptor_sets         , descriptor_set_index + 1)

                if (descriptor_set_specified[descriptor_set_index] == nil) do descriptor_set_specified[descriptor_set_index] = make([dynamic]b32, context.temp_allocator)
                if (descriptor_sets         [descriptor_set_index] == nil) do descriptor_sets         [descriptor_set_index] = make([dynamic]vk.DescriptorSetLayoutBinding, context.temp_allocator)
                
                binding_specified := descriptor_set_specified[descriptor_set_index]
                bindings          := descriptor_sets[descriptor_set_index]

                for binding, binding_index in descriptor_set {
                    reserve_dynamic_array(&binding_specified, binding_index + 1)
                    reserve_dynamic_array(&bindings         , binding_index + 1)

                    if (binding_specified[binding_index]) {
                        // TODO(jan): Check which shader stages in the module actually use the uniform.
                        bindings[binding_index].stageFlags += stage_flags
                    } else {
                        bindings[binding_index] = vk.DescriptorSetLayoutBinding {
                            binding = u32(binding_index),
                            // TODO(jan): Allow for arrays of bindings.
                            descriptorCount = 1,
                            // TODO(jan): Allow for other types of descriptors.
                            descriptorType = vk.DescriptorType.SAMPLER,
                            // NOTE(jan): Not using immutable samplers.
                            pImmutableSamplers = nil,
                            // TODO(jan): Check which shader stages in the module actually use the uniform.
                            stageFlags = stage_flags,
                        }
                        binding_specified[binding_index] = true
                    }
                }
            }
        }

        descriptor_set_layout_handles := make([dynamic]vk.DescriptorSetLayout, len(descriptor_sets), context.temp_allocator)
        for bindings, descriptor_set_index in descriptor_sets {
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
                vk.CreateDescriptorSetLayout(vulkan.device, &create, nil, &descriptor_set_layout_handles[descriptor_set_index]),
                "could not create descriptor set layout",
            )
            log.info("Created descriptor set layout #%d.", descriptor_set_index)
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
                setLayoutCount = u32(len(descriptor_set_layout_handles)),
                pSetLayouts = raw_data(descriptor_set_layout_handles),
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
        vk.DestroyPipeline(vulkan.device, pipeline.handle, nil)
    }
    clear(&vulkan.pipelines)
}
