package nido

import vk "vendor:vulkan"

VulkanBuffer :: struct {
    handle: vk.Buffer,
    memory: vk.DeviceMemory,
}

vulkan_buffer_allocate :: proc(
    vulkan: Vulkan,
    memory_flags: vk.MemoryPropertyFlags,
    buffer: ^VulkanBuffer,
) {
    requirements: vk.MemoryRequirements
    vk.GetBufferMemoryRequirements(vulkan.device, buffer.handle, &requirements)

    type := vulkan_memory_type_index(vulkan, requirements, memory_flags)

    allocate := vk.MemoryAllocateInfo {
        sType = vk.StructureType.MEMORY_ALLOCATE_INFO,
        allocationSize = requirements.size,
        memoryTypeIndex = type,
    }

    check(
        vk.AllocateMemory(vulkan.device, &allocate, nil, &buffer.memory),
        "could not allocate buffer memory",
    )

    check(
        vk.BindBufferMemory(vulkan.device, buffer.handle, buffer.memory, 0),
        "could not bind buffer memory",
    )
}

vulkan_buffer_create :: proc(
    vulkan: Vulkan,
    family: u32,
    usage: vk.BufferUsageFlags,
    size: u64,
) -> VulkanBuffer {
    family := family

    create := vk.BufferCreateInfo {
        sType = vk.StructureType.BUFFER_CREATE_INFO,
        sharingMode = vk.SharingMode.EXCLUSIVE,
        usage = usage,
        queueFamilyIndexCount = 1,
        pQueueFamilyIndices = &family,
        size = vk.DeviceSize(size),
    }

    buffer: VulkanBuffer
    check(
        vk.CreateBuffer(vulkan.device, &create, nil, &buffer.handle),
        "could not create buffer",
    )
    return buffer
}

vulkan_buffer_create_index :: proc(
    vulkan: Vulkan,
    size: u64,
) -> (buffer: VulkanBuffer) {
    usage := vk.BufferUsageFlags {
        vk.BufferUsageFlag.INDEX_BUFFER,
    }
    buffer = vulkan_buffer_create(vulkan, vulkan.gfx_queue_family, usage, size)

    flags := vk.MemoryPropertyFlags {
        vk.MemoryPropertyFlag.HOST_VISIBLE,
        vk.MemoryPropertyFlag.HOST_COHERENT,
    }

    vulkan_buffer_allocate(vulkan, flags, &buffer)

    return buffer
}

vulkan_buffer_create_vertex :: proc(
    vulkan: Vulkan,
    size: u64,
) -> (buffer: VulkanBuffer) {
    usage := vk.BufferUsageFlags {
        vk.BufferUsageFlag.VERTEX_BUFFER,
    }
    buffer = vulkan_buffer_create(vulkan, vulkan.gfx_queue_family, usage, size)

    flags := vk.MemoryPropertyFlags {
        vk.MemoryPropertyFlag.HOST_VISIBLE,
        vk.MemoryPropertyFlag.HOST_COHERENT,
    }

    vulkan_buffer_allocate(vulkan, flags, &buffer)

    return buffer
}

vulkan_buffer_create_staging :: proc(
    vulkan: Vulkan,
    size: u64,
) -> (buffer: VulkanBuffer) {
    usage := vk.BufferUsageFlags {
        vk.BufferUsageFlag.TRANSFER_SRC,
    }
    buffer = vulkan_buffer_create(vulkan, vulkan.gfx_queue_family, usage, size)

    flags := vk.MemoryPropertyFlags {
        vk.MemoryPropertyFlag.HOST_VISIBLE,
        vk.MemoryPropertyFlag.HOST_COHERENT,
    }
    vulkan_buffer_allocate(vulkan, flags, &buffer)

    return buffer
}

vulkan_buffer_create_uniform :: proc(
    vulkan: Vulkan,
    size: u64,
) -> (buffer: VulkanBuffer) {
    usage := vk.BufferUsageFlags {
        vk.BufferUsageFlag.UNIFORM_BUFFER,
    }
    buffer = vulkan_buffer_create(vulkan, vulkan.gfx_queue_family, usage, size)

    flags := vk.MemoryPropertyFlags {
        vk.MemoryPropertyFlag.HOST_VISIBLE,
        vk.MemoryPropertyFlag.HOST_COHERENT,
    }
    vulkan_buffer_allocate(vulkan, flags, &buffer)

    return buffer
}

vulkan_buffer_destroy :: proc(
    vulkan: Vulkan,
    buffer: VulkanBuffer,
) {
    if buffer.memory != 0 do vk.FreeMemory(vulkan.device, buffer.memory, nil)
    if buffer.handle != 0 do vk.DestroyBuffer(vulkan.device, buffer.handle, nil)
}
