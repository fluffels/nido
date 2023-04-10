package gfx

import "core:log"

import vk "vendor:vulkan"

@(private)
vulkan_cmd_create_pool :: proc(
    vulkan: Vulkan,
    flags: vk.CommandPoolCreateFlags,
    queue_family_index: u32,
) -> (
    pool: vk.CommandPool,
) {
    create := vk.CommandPoolCreateInfo {
        sType = vk.StructureType.COMMAND_POOL_CREATE_INFO,
        flags = flags,
        queueFamilyIndex = vulkan.gfx_queue_family,
    }

    result := vk.CreateCommandPool(vulkan.device, &create, nil, &pool)

    if result != vk.Result.SUCCESS do panic("could not create command pool")
    else do log.infof("Created command pool.")

    return
}

vulkan_cmd_create_per_frame_pool :: proc (
    vulkan: Vulkan,
) -> (
    pool: vk.CommandPool,
) {
    flags := vk.CommandPoolCreateFlags {
        vk.CommandPoolCreateFlag.RESET_COMMAND_BUFFER,
    }

    pool = vulkan_cmd_create_pool(vulkan, flags, vulkan.gfx_queue_family)

    return
}

vulkan_cmd_create_transient_pool :: proc (
    vulkan: Vulkan,
) -> (
    pool: vk.CommandPool,
) {
    flags := vk.CommandPoolCreateFlags {
        vk.CommandPoolCreateFlag.TRANSIENT,
    }

    pool = vulkan_cmd_create_pool(vulkan, flags, vulkan.gfx_queue_family)

    return
}

vulkan_cmd_allocate_buffer :: proc (
    vulkan: Vulkan,
    cmd_pool: vk.CommandPool,
) -> (
    cmd: vk.CommandBuffer,
) {
    info := vk.CommandBufferAllocateInfo {
        sType = vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO,
        commandBufferCount = 1,
        commandPool = cmd_pool,
        level = vk.CommandBufferLevel.PRIMARY,
    }
    result := vk.AllocateCommandBuffers(vulkan.device, &info, &cmd)

    if result != vk.Result.SUCCESS do panic("could not allocate cmd buffer")

    return
}

vulkan_cmd_begin_transient :: proc (
    vulkan: Vulkan,
    cmd: vk.CommandBuffer,
) {
    info := vk.CommandBufferBeginInfo {
        sType = vk.StructureType.COMMAND_BUFFER_BEGIN_INFO,
        flags = { vk.CommandBufferUsageFlag.ONE_TIME_SUBMIT },
    }

    result := vk.BeginCommandBuffer(cmd, &info)
    
    if result != vk.Result.SUCCESS do panic("could not begin transient command buffer")
}

vulkan_cmd_submit :: proc(
    vulkan: Vulkan,
    cmd: ^vk.CommandBuffer,
) {
    info := vk.SubmitInfo {
        sType = vk.StructureType.SUBMIT_INFO,
        commandBufferCount = 1,
        pCommandBuffers = cmd,
    }

    result := vk.QueueSubmit(vulkan.gfx_queue, 1, &info, 0)

    if result != vk.Result.SUCCESS do panic("could not submit cmd buffer")
}

vulkan_cmd_allocate_and_begin_transient :: proc(
    vulkan: Vulkan,
    cmd_pool: vk.CommandPool,
) -> (
    cmd: vk.CommandBuffer,
) {
    cmd = vulkan_cmd_allocate_buffer(vulkan, cmd_pool)
    vulkan_cmd_begin_transient(vulkan, cmd)

    return
}

vulkan_cmd_end_and_submit :: proc(
    vulkan: Vulkan,
    cmd: ^vk.CommandBuffer,
) {
    vk.EndCommandBuffer(cmd^)
    vulkan_cmd_submit(vulkan, cmd)
}
