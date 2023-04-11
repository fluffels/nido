package gfx

import "core:mem"
import vk "vendor:vulkan"

VulkanImage :: struct {
    handle: vk.Image,
    memory: vk.DeviceMemory,
    view: vk.ImageView,
    extent: vk.Extent2D,
}

vulkan_image_create :: proc(
    vulkan: ^Vulkan,
    type: vk.ImageType,
    view_type: vk.ImageViewType,
    extent: vk.Extent2D,
    layer_count: u32,
    family: u32,
    format: vk.Format,
    usage: vk.ImageUsageFlags,
    aspect: vk.ImageAspectFlags,
    flags: vk.ImageCreateFlags,
    samples: vk.SampleCountFlag,
    host_visible: bool,
) -> (image: VulkanImage) {
    // NOTE(jan): Create image.
    family := family
    vk.CreateImage(vulkan.device, &vk.ImageCreateInfo {
        sType = vk.StructureType.IMAGE_CREATE_INFO,
        flags = flags,
        imageType = type,
        extent = vk.Extent3D {
            width = extent.width,
            height = extent.height,
            depth = 1,
        },
        mipLevels = 1,
        arrayLayers = layer_count,
        format = format,
        tiling = vk.ImageTiling.OPTIMAL,
        initialLayout = vk.ImageLayout.UNDEFINED,
        queueFamilyIndexCount = 1,
        pQueueFamilyIndices = &family,
        sharingMode = vk.SharingMode.EXCLUSIVE,
        usage = usage,
        samples = { samples },
    }, nil, &image.handle)

    // NOTE(jan): Allocate image.
    reqs: vk.MemoryRequirements
    vk.GetImageMemoryRequirements(vulkan.device, image.handle, &reqs)
    flags: vk.MemoryPropertyFlags = host_visible ? { vk.MemoryPropertyFlag.HOST_VISIBLE } : {}
    mem_type := vulkan_memory_type_index(vulkan, reqs, flags)
    check(
        vk.AllocateMemory(vulkan.device, &vk.MemoryAllocateInfo {
            sType = vk.StructureType.MEMORY_ALLOCATE_INFO,
            allocationSize = reqs.size,
            memoryTypeIndex = mem_type,
        }, nil, &image.memory),
        "could not allocate memory for image",
    )
    check(
        vk.BindImageMemory(vulkan.device, image.handle, image.memory, 0),
        "could not bind image memory",
    )

    // NOTE(jan): Create image view.
    vk.CreateImageView(vulkan.device, &vk.ImageViewCreateInfo {
        sType = vk.StructureType.IMAGE_VIEW_CREATE_INFO,
        components = vk.ComponentMapping {
            r = vk.ComponentSwizzle.IDENTITY,
            g = vk.ComponentSwizzle.IDENTITY,
            b = vk.ComponentSwizzle.IDENTITY,
            a = vk.ComponentSwizzle.IDENTITY,
        },
        image = image.handle,
        format = format,
        viewType = view_type,
        subresourceRange = vk.ImageSubresourceRange {
            aspectMask = aspect,
            baseMipLevel = 0,
            levelCount = vk.REMAINING_MIP_LEVELS,
            baseArrayLayer = 0,
            layerCount = vk.REMAINING_ARRAY_LAYERS,
        },
    }, nil, &image.view)

    image.extent = extent

    return
}

vulkan_image_destroy :: proc(
    vulkan: ^Vulkan,
    image: ^VulkanImage,
) {
    if image.view != 0 do vk.DestroyImageView(vulkan.device, image.view, nil)
    image.view = 0
    if image.memory != 0 do vk.FreeMemory(vulkan.device, image.memory, nil)
    image.memory = 0
    if image.handle != 0 do vk.DestroyImage(vulkan.device, image.handle, nil)
    image.handle = 0
}

vulkan_image_create_2d_monochrome_texture :: proc(
    vulkan: ^Vulkan,
    extent: vk.Extent2D,
) -> (image: VulkanImage) {
    image = vulkan_image_create(
        vulkan,
        vk.ImageType.D2,
        vk.ImageViewType.D2,
        extent,
        1,
        vulkan.gfx_queue_family,
        vk.Format.R8_UNORM,
        { 
            vk.ImageUsageFlag.TRANSFER_DST,
            vk.ImageUsageFlag.SAMPLED,
        },
        { vk.ImageAspectFlag.COLOR },
        {},
        vk.SampleCountFlag._1,
        false,
    )
    return
}

vulkan_image_create_color_buffer :: proc(
    vulkan: ^Vulkan,
    extent: vk.Extent2D,
    format: vk.Format,
    samples: vk.SampleCountFlag,
) -> (image: VulkanImage) {
    return vulkan_image_create(
        vulkan,
        vk.ImageType.D2,
        vk.ImageViewType.D2,
        extent,
        1,
        vulkan.gfx_queue_family,
        format,
        { 
            vk.ImageUsageFlag.TRANSFER_SRC,
            vk.ImageUsageFlag.TRANSFER_DST,
            vk.ImageUsageFlag.SAMPLED,
            vk.ImageUsageFlag.COLOR_ATTACHMENT,
        },
        { vk.ImageAspectFlag.COLOR },
        {},
        samples,
        false,
    )
}

vulkan_image_create_depth_buffer :: proc(
    vulkan: ^Vulkan,
    extent: vk.Extent2D,
    samples: vk.SampleCountFlag,
) -> (image: VulkanImage) {
    return vulkan_image_create(
        vulkan,
        vk.ImageType.D2,
        vk.ImageViewType.D2,
        extent,
        1,
        vulkan.gfx_queue_family,
        vk.Format.D32_SFLOAT,
        { vk.ImageUsageFlag.DEPTH_STENCIL_ATTACHMENT },
        { vk.ImageAspectFlag.DEPTH },
        {},
        samples,
        false,
    )
}

vulkan_image_create_prepass :: proc(
    vulkan: ^Vulkan,
    extent: vk.Extent2D,
    format: vk.Format,
) -> (image: VulkanImage) {
    return vulkan_image_create(
        vulkan,
        vk.ImageType.D2,
        vk.ImageViewType.D2,
        extent,
        1,
        vulkan.gfx_queue_family,
        format,
        {
            vk.ImageUsageFlag.COLOR_ATTACHMENT,
             vk.ImageUsageFlag.SAMPLED,
        },
        { vk.ImageAspectFlag.COLOR },
        {},
        vk.SampleCountFlag._1,
        false,
    )
}

vulkan_image_copy_from_buffer :: proc(
    vulkan: Vulkan,
    cmd: vk.CommandBuffer,
    extent: vk.Extent2D,
    buffer: VulkanBuffer,
    image: VulkanImage,
) {
    vk.CmdPipelineBarrier(
        cmd,
        { vk.PipelineStageFlag.ALL_COMMANDS },
        { vk.PipelineStageFlag.ALL_COMMANDS },
        {},
        0, nil,
        0, nil,
        1, &vk.ImageMemoryBarrier {
            sType = vk.StructureType.IMAGE_MEMORY_BARRIER,
            oldLayout = vk.ImageLayout.UNDEFINED,
            newLayout = vk.ImageLayout.TRANSFER_DST_OPTIMAL,
            image = image.handle,
            subresourceRange = vk.ImageSubresourceRange {
                aspectMask = { vk.ImageAspectFlag.COLOR },
                baseArrayLayer = 0,
                layerCount = vk.REMAINING_ARRAY_LAYERS,
                baseMipLevel = 0,
                levelCount = vk.REMAINING_MIP_LEVELS,
            },
            srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
            dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
            srcAccessMask = {},
            dstAccessMask = { vk.AccessFlag.TRANSFER_WRITE },
        },
    )

    vk.CmdCopyBufferToImage(
        cmd,
        buffer.handle,
        image.handle,
        vk.ImageLayout.TRANSFER_DST_OPTIMAL,
        1, &vk.BufferImageCopy {
            bufferOffset = 0,
            bufferRowLength = 0,
            bufferImageHeight = 0,
            imageSubresource = vk.ImageSubresourceLayers {
                aspectMask = { vk.ImageAspectFlag.COLOR },
                mipLevel = 0,
                baseArrayLayer = 0,
                layerCount = 1,
            },
            imageOffset = vk.Offset3D { x = 0, y = 0, z = 0 },
            imageExtent = vk.Extent3D { width = extent.width, height = extent.height, depth = 1 },
        },
    )

    vk.CmdPipelineBarrier(
        cmd,
        { vk.PipelineStageFlag.ALL_COMMANDS },
        { vk.PipelineStageFlag.ALL_COMMANDS },
        {},
        0, nil,
        0, nil,
        1, &vk.ImageMemoryBarrier {
            sType = vk.StructureType.IMAGE_MEMORY_BARRIER,
            oldLayout = vk.ImageLayout.TRANSFER_DST_OPTIMAL,
            newLayout = vk.ImageLayout.SHADER_READ_ONLY_OPTIMAL,
            image = image.handle,
            subresourceRange = vk.ImageSubresourceRange {
                aspectMask = { vk.ImageAspectFlag.COLOR },
                baseArrayLayer = 0,
                layerCount = vk.REMAINING_ARRAY_LAYERS,
                baseMipLevel = 0,
                levelCount = vk.REMAINING_MIP_LEVELS,
            },
            srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
            dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
            srcAccessMask = { vk.AccessFlag.TRANSFER_WRITE },
            dstAccessMask = { vk.AccessFlag.SHADER_READ },
        },
    )
}

vulkan_image_update_texture :: proc(
    vulkan: ^Vulkan,
    cmd: vk.CommandBuffer,
    data: []u8,
    image: VulkanImage,
) {
    length := u64(len(data))
    staging: VulkanBuffer = vulkan_buffer_create_staging(vulkan, length)

    dst := vulkan_memory_map(vulkan, staging.memory)
        mem.copy_non_overlapping(dst, raw_data(data), len(data))
    vulkan_memory_unmap(vulkan, staging.memory)

    vulkan_image_copy_from_buffer(vulkan^, cmd, image.extent, staging, image)

    append(&vulkan.temp_buffers, staging)

    return
}

vulkan_image_upload_texture :: proc(
    vulkan: ^Vulkan,
    cmd: vk.CommandBuffer,
    format: vk.Format,
    data: []u8,
) -> (image: VulkanImage) {
    image = vulkan_image_create(
        vulkan,
        vk.ImageType.D2,
        vk.ImageViewType.D2,
        image.extent,
        1,
        vulkan.gfx_queue_family,
        format,
        {
            vk.ImageUsageFlag.TRANSFER_DST,
            vk.ImageUsageFlag.SAMPLED,
        },
        { vk.ImageAspectFlag.COLOR },
        {},
        vk.SampleCountFlag._1,
        false,
    )

    vulkan_image_update_texture(vulkan, cmd, data, image)

    return
}
