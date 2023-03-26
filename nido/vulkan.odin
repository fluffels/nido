package nido

import "core:log"
import "core:strings"
import vk "vendor:vulkan"

VulkanShader :: struct {
    description: ShaderDescription,
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
}

// NOTE(jan): Global Vulkan-related state goes in one of these.
Vulkan :: struct {
    handle: vk.Instance,

    debug_callback: vk.DebugReportCallbackEXT,

    surface: vk.SurfaceKHR,

    device: vk.Device,
    gpu: vk.PhysicalDevice,

    gfx_queue: vk.Queue,
    gfx_queue_family: u32,

    compute_queue: vk.Queue,
    compute_queue_family: u32,

    swap: VulkanSwap,

    memories: vk.PhysicalDeviceMemoryProperties,
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
}

swap_destroy :: proc(vulkan: ^Vulkan) {
    vk.DestroySwapchainKHR(vulkan.device, vulkan.swap.handle, nil)
}

swap_resize :: proc(vulkan: ^Vulkan) {
    swap_update_capabilities(vulkan)
    swap_update_extent(vulkan)
    swap_destroy(vulkan)
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
