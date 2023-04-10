package gfx

import "core:log"
import vk "vendor:vulkan"

VulkanPass :: struct {
    render_pass: vk.RenderPass,
    framebuffers: [dynamic]vk.Framebuffer,
    pipelines: map[string]VulkanPipeline,
    pipeline_metadata: []VulkanPipelineMetadata,
}

vulkan_pass_create :: proc(
	vulkan: ^Vulkan,
	pipeline_metadata: []VulkanPipelineMetadata,
) -> (
	vulkan_pass: VulkanPass,
) {
	allocator := vulkan.resize_allocator
    vulkan_pass = VulkanPass {
		pipeline_metadata = pipeline_metadata,
		framebuffers = make([dynamic]vk.Framebuffer, allocator),
	}

	// NOTE(jan): Create a render pass.
	{
		attachments  := make([dynamic]vk.AttachmentDescription, context.temp_allocator)
		color_refs   := make([dynamic]vk.AttachmentReference  , context.temp_allocator)
		subpasses    := make([dynamic]vk.SubpassDescription   , context.temp_allocator)
		dependencies := make([dynamic]vk.SubpassDependency    , context.temp_allocator)

		append(&attachments, vk.AttachmentDescription {
			format = vulkan.swap.format,
			// TODO(jan): multi sampling
			samples = { vk.SampleCountFlag._1 },
			loadOp = vk.AttachmentLoadOp.CLEAR,
			storeOp = vk.AttachmentStoreOp.STORE,
			stencilLoadOp = vk.AttachmentLoadOp.DONT_CARE,
			stencilStoreOp = vk.AttachmentStoreOp.DONT_CARE,
			initialLayout = vk.ImageLayout.UNDEFINED,
			finalLayout = vk.ImageLayout.PRESENT_SRC_KHR,
		})
		append(&color_refs, vk.AttachmentReference {
			attachment = u32(len(attachments)) - 1,
			layout = vk.ImageLayout.COLOR_ATTACHMENT_OPTIMAL,
		})

		append(&subpasses, vk.SubpassDescription {
			pipelineBindPoint = vk.PipelineBindPoint.GRAPHICS,
			colorAttachmentCount = u32(len(color_refs)),
			pColorAttachments = raw_data(color_refs),
		})

		append(&dependencies, vk.SubpassDependency {
			srcSubpass = vk.SUBPASS_EXTERNAL,
			dstSubpass = 0,
			srcStageMask = { vk.PipelineStageFlag.COLOR_ATTACHMENT_OUTPUT },
			dstStageMask = { vk.PipelineStageFlag.COLOR_ATTACHMENT_OUTPUT },
			srcAccessMask = { },
			dstAccessMask = { vk.AccessFlag.COLOR_ATTACHMENT_WRITE },
		})

		create := vk.RenderPassCreateInfo {
			sType = vk.StructureType.RENDER_PASS_CREATE_INFO,
			attachmentCount = u32(len(attachments)),
			pAttachments = raw_data(attachments),
			subpassCount = u32(len(subpasses)),
			pSubpasses = raw_data(subpasses),
			dependencyCount = u32(len(dependencies)),
			pDependencies = raw_data(dependencies),
		}
		check(
			vk.CreateRenderPass(vulkan.device, &create, nil, &vulkan_pass.render_pass),
			"could not create render pass",
		)
		log.infof("Created render pass.")
	}

    // NOTE(jan): Create pipelines.
	vulkan_pass.pipelines = vulkan_pipelines_create(vulkan, vulkan_pass.pipeline_metadata, vulkan_pass.render_pass)

    // NOTE(jan): Create framebuffers.
	log.infof("Creating framebuffers...")

    for view, i in vulkan.swap.views {
        create := vk.FramebufferCreateInfo {
            sType = vk.StructureType.FRAMEBUFFER_CREATE_INFO,
            attachmentCount = 1,
            pAttachments = raw_data(vulkan.swap.views[i:]),
            renderPass = vulkan_pass.render_pass,
            height = vulkan.swap.extent.height,
            width = vulkan.swap.extent.width,
            layers = 1,
        }
        handle: vk.Framebuffer
        check(
            vk.CreateFramebuffer(vulkan.device, &create, nil, &handle),
            "couldn't create framebuffer",
        )
        append(&vulkan_pass.framebuffers, handle)
        log.infof("\t\u2713 for swap chain image #%d", i)
    }

    log.infof("Created framebuffers.")

    return vulkan_pass
}

vulkan_pass_destroy :: proc(vulkan: ^Vulkan, vulkan_pass: ^VulkanPass) {
    for framebuffer in vulkan_pass.framebuffers {
        vk.DestroyFramebuffer(vulkan.device, framebuffer, nil)
    }
    clear(&vulkan_pass.framebuffers);

	for name, pipeline in vulkan_pass.pipelines {
		vulkan_pipeline_destroy(vulkan, &vulkan_pass.pipelines[name])
	}

	vk.DestroyRenderPass(vulkan.device, vulkan_pass.render_pass, nil)
	for framebuffer in vulkan_pass.framebuffers {
		vk.DestroyFramebuffer(vulkan.device, framebuffer, nil)
	}

	clear(&vulkan_pass.pipelines)
}
