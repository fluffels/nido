package gfx

import vk "vendor:vulkan"

// NOTE(jan): A GPU descriptor pool bound to some lifetime, reset in bulk
// when that lifetime ends, rather than having its sets freed one at a time.
DescriptorPool :: struct {
    pool: vk.DescriptorPool,
}

vulkan_descriptor_pool_create :: proc(vulkan: ^Vulkan, max_sets: u32) -> DescriptorPool {
    sizes := [?]vk.DescriptorPoolSize {
        { type = vk.DescriptorType.UNIFORM_BUFFER, descriptorCount = max_sets },
        { type = vk.DescriptorType.COMBINED_IMAGE_SAMPLER, descriptorCount = max_sets },
    }

    create := vk.DescriptorPoolCreateInfo {
        sType = vk.StructureType.DESCRIPTOR_POOL_CREATE_INFO,
        maxSets = max_sets,
        poolSizeCount = u32(len(sizes)),
        pPoolSizes = raw_data(&sizes),
    }

    descriptor_pool: DescriptorPool
    check(
        vk.CreateDescriptorPool(vulkan.device, &create, nil, &descriptor_pool.pool),
        "could not create descriptor pool",
    )
    return descriptor_pool
}

vulkan_descriptor_pool_reset :: proc(vulkan: ^Vulkan, descriptor_pool: ^DescriptorPool) {
    check(
        vk.ResetDescriptorPool(vulkan.device, descriptor_pool.pool, {}),
        "could not reset descriptor pool",
    )
}

vulkan_descriptor_pool_destroy :: proc(vulkan: ^Vulkan, descriptor_pool: ^DescriptorPool) {
    vk.DestroyDescriptorPool(vulkan.device, descriptor_pool.pool, nil)
    descriptor_pool.pool = 0
}

vulkan_descriptor_pool_allocate :: proc(vulkan: ^Vulkan, descriptor_pool: ^DescriptorPool, layout: vk.DescriptorSetLayout) -> (set: vk.DescriptorSet) {
    layout := layout
    alloc := vk.DescriptorSetAllocateInfo {
        sType = vk.StructureType.DESCRIPTOR_SET_ALLOCATE_INFO,
        descriptorPool = descriptor_pool.pool,
        descriptorSetCount = 1,
        pSetLayouts = &layout,
    }
    check(
        vk.AllocateDescriptorSets(vulkan.device, &alloc, &set),
        "could not allocate descriptor set from descriptor pool",
    )
    return
}
