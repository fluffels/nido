package gfx

import "core:fmt"
import "core:log"
import vk "vendor:vulkan"

VulkanSwap :: struct {
    handle: vk.SwapchainKHR,
    capabilities: vk.SurfaceCapabilitiesKHR,
    extent: vk.Extent2D,
    format: vk.Format,
    color_space: vk.ColorSpaceKHR,
    present_mode: vk.PresentModeKHR,
    views: [dynamic]vk.ImageView,
}

vulkan_swap_create :: proc(vulkan: ^Vulkan) {
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

    result := vk.CreateSwapchainKHR(vulkan.device, &create, nil, &vulkan.swap.handle)
    e := ""
    #partial switch (result) {
        case vk.Result.ERROR_OUT_OF_HOST_MEMORY:
            e = "Could not create swapchain: host out of memory."
        case vk.Result.ERROR_OUT_OF_DEVICE_MEMORY:
            e = "Could not create swapchain: device out of memory."
        case vk.Result.ERROR_DEVICE_LOST:
            e = "Could not create swapchain: device lost."
        case vk.Result.ERROR_SURFACE_LOST_KHR:
            e = "Could not create swapchain: surface lost."
        case vk.Result.ERROR_NATIVE_WINDOW_IN_USE_KHR:
            e = "Could not create swapchain: window in use."
        case vk.Result.ERROR_INITIALIZATION_FAILED:
            e = "Could not create swapchain: initialization failed."
        case vk.Result.ERROR_COMPRESSION_EXHAUSTED_EXT:
            e = "Could not create swapchain: compression exhausted."
        case:
            e = fmt.aprintf("Could not create swapchain: unknown error (%d).", result)
    }
    if (result != vk.Result.SUCCESS) {
        log.error(e)
        panic(e)
    }
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

vulkan_swap_destroy :: proc(vulkan: ^Vulkan) {
    vk.DestroySwapchainKHR(vulkan.device, vulkan.swap.handle, nil)

    for view in vulkan.swap.views {
        vk.DestroyImageView(vulkan.device, view, nil)
    }
    clear(&vulkan.swap.views)   

    log.infof("Destroyed swapchain.")
}

vulkan_swap_update_capabilities :: proc(vulkan: ^Vulkan) {
    check(
        vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(vulkan.gpu, vulkan.surface, &vulkan.swap.capabilities),
        "could not fetch physical device surface capabilities",
    )
}

vulkan_swap_update_extent :: proc(vulkan: ^Vulkan) {
    vulkan.swap.extent = vulkan.swap.capabilities.currentExtent
}

@(private)
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
