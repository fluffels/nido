package gfx

import "core:log"
import "core:mem"
import "core:mem/virtual"
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

    // NOTE(jan): One entry per swapchain image, sized to len(swap.views).
    frames: [dynamic]FrameResources,

    // NOTE(jan): Semaphores for vkAcquireNextImageKHR.
    image_ready: [dynamic]VulkanSemaphore,

    modules: map[string]VulkanModule,

    // NOTE(jan): Contains objects that live for as long as the device, i.e. shader objects.
    device_arena: virtual.Arena,
    device_allocator: mem.Allocator,
	// NOTE(jan): Contains objects allocated between window resizes, i.e. swapchains, pipelines, etc.
	resize_pool: mem.Dynamic_Pool,
	resize_allocator: mem.Allocator,
}
