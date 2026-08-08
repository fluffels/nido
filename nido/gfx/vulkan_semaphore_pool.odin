package gfx

import vk "vendor:vulkan"

VulkanSemaphore :: struct {
    handle: vk.Semaphore,
    // NOTE(jan): Fence that signals this semaphore is available.
    fence: vk.Fence,
}

vulkan_semaphore_pool_create :: proc(vulkan: ^Vulkan, count: int) -> (pool: [dynamic]VulkanSemaphore) {
    pool = make([dynamic]VulkanSemaphore, count, vulkan.device_allocator)

    create := vk.SemaphoreCreateInfo {
        sType = vk.StructureType.SEMAPHORE_CREATE_INFO,
    }
    for &entry in pool {
        check(
            vk.CreateSemaphore(vulkan.device, &create, nil, &entry.handle),
            "could not create semaphore pool entry",
        )
    }

    return
}

vulkan_semaphore_pool_destroy :: proc(vulkan: ^Vulkan, pool: ^[dynamic]VulkanSemaphore) {
    for &entry in pool {
        vk.DestroySemaphore(vulkan.device, entry.handle, nil)
    }
    clear(pool)
}

vulkan_semaphore_pool_acquire :: proc(vulkan: ^Vulkan, pool: []VulkanSemaphore) -> int {
    for &entry, i in pool {
        if entry.fence == 0 do return i
        if vk.GetFenceStatus(vulkan.device, entry.fence) == vk.Result.SUCCESS do return i
    }

    fences := make([dynamic]vk.Fence, len(pool), context.temp_allocator)
    for &entry, i in pool do fences[i] = entry.fence
    check(
        vk.WaitForFences(vulkan.device, u32(len(fences)), raw_data(fences), false, max(u64)),
        "could not wait for a semaphore pool entry to free up",
    )

    for &entry, i in pool {
        if vk.GetFenceStatus(vulkan.device, entry.fence) == vk.Result.SUCCESS do return i
    }
    panic("no semaphore pool entry became available after waiting")
}
