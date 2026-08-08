package gfx

import "core:mem"
import "core:mem/virtual"
import vk "vendor:vulkan"

// NOTE(jan): One per swapchain image. `fence` signals once the GPU is done
// with this image - nothing else here is safe to touch until then.
FrameResources :: struct {
    index: int,

    cmd: vk.CommandBuffer,
    transient_cmd: vk.CommandBuffer,

    render_finished: vk.Semaphore,
    fence: vk.Fence,

    temp_arena: virtual.Arena,
    temp_allocator: mem.Allocator,

    temp_buffers: [dynamic]VulkanBuffer,
    descriptor_pool: DescriptorPool,
}

// NOTE(jan): cmd_pool needs RESET_COMMAND_BUFFER - cmd/transient_cmd get
// re-begun every time an image comes around, not reallocated.
vulkan_frames_create :: proc(
    vulkan: ^Vulkan,
    cmd_pool: vk.CommandPool,
) {
    count := len(vulkan.swap.views)
    vulkan.frames = make([dynamic]FrameResources, count, vulkan.device_allocator)

    semaphore_create := vk.SemaphoreCreateInfo {
        sType = vk.StructureType.SEMAPHORE_CREATE_INFO,
    }

    for i in 0..<count {
        frame := &vulkan.frames[i]
        frame.index = i

        frame.cmd = vulkan_cmd_allocate_buffer(vulkan^, cmd_pool)
        frame.transient_cmd = vulkan_cmd_allocate_buffer(vulkan^, cmd_pool)

        check(
            vk.CreateSemaphore(vulkan.device, &semaphore_create, nil, &frame.render_finished),
            "could not create per-image render_finished semaphore",
        )

        // NOTE(jan): Create signaled so the first-ever use of each image doesn't block.
        fence_create := vk.FenceCreateInfo {
            sType = vk.StructureType.FENCE_CREATE_INFO,
            flags = { vk.FenceCreateFlag.SIGNALED },
        }
        check(
            vk.CreateFence(vulkan.device, &fence_create, nil, &frame.fence),
            "could not create per-image fence",
        )

        alloc_error := virtual.arena_init_growing(&frame.temp_arena)
        if alloc_error != virtual.Allocator_Error.None do panic("could not initialize per-image temp arena")
        frame.temp_allocator = virtual.arena_allocator(&frame.temp_arena)

        frame.temp_buffers = make([dynamic]VulkanBuffer, vulkan.device_allocator)

        frame.descriptor_pool = vulkan_descriptor_pool_create(vulkan, 256)
    }
}

vulkan_frames_destroy :: proc(
    vulkan: ^Vulkan,
    cmd_pool: vk.CommandPool,
) {
    for &frame in vulkan.frames {
        for &buffer in frame.temp_buffers do vulkan_buffer_destroy(vulkan, &buffer)
        clear(&frame.temp_buffers)

        vulkan_descriptor_pool_destroy(vulkan, &frame.descriptor_pool)

        vk.DestroyFence(vulkan.device, frame.fence, nil)
        vk.DestroySemaphore(vulkan.device, frame.render_finished, nil)

        cmd := frame.cmd
        vk.FreeCommandBuffers(vulkan.device, cmd_pool, 1, &cmd)
        transient_cmd := frame.transient_cmd
        vk.FreeCommandBuffers(vulkan.device, cmd_pool, 1, &transient_cmd)

        virtual.arena_destroy(&frame.temp_arena)
    }
    clear(&vulkan.frames)
}
