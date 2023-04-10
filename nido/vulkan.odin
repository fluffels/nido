package nido

import "core:log"
import "core:mem"
import vk "vendor:vulkan"

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

    modules: map[string]VulkanModule,
    pipelines: map[string]VulkanPipeline,

	// NOTE(jan): Contains objects allocated between window resizes, i.e. swapchains, pipelines, etc.
	resize_pool: mem.Dynamic_Pool,
	resize_allocator: mem.Allocator,

    // NOTE(jan): To be free'd at the bottom of each frame.
    temp_buffers: [dynamic]VulkanBuffer,
}

vulkan_make :: proc() -> Vulkan {
    result: Vulkan
    result.swap.views = make([dynamic]vk.ImageView)
    result.framebuffers = make([dynamic]vk.Framebuffer)
    return result;
}
