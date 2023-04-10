package gfx

import vk "vendor:vulkan"

vulkan_descriptor_update_uniform :: proc(
    vulkan: Vulkan,
    descriptor_set: vk.DescriptorSet,
    binding: u32,
    buffer: VulkanBuffer,
) {
    info := vk.DescriptorBufferInfo {
        buffer = buffer.handle,
        offset = 0,
        range = vk.DeviceSize(vk.WHOLE_SIZE),
    }

    write := vk.WriteDescriptorSet {
        sType = vk.StructureType.WRITE_DESCRIPTOR_SET,
        descriptorCount = 1,
        descriptorType = vk.DescriptorType.UNIFORM_BUFFER,
        dstBinding = binding,
        dstSet = descriptor_set,
        pBufferInfo = &info,
    }

    vk.UpdateDescriptorSets(vulkan.device, 1, &write, 0, nil)
}

vulkan_descriptor_update_combined_image_sampler :: proc(
    vulkan: Vulkan,
    descriptor_set: vk.DescriptorSet,
    binding: u32,
    images: []VulkanImage,
    sampler: vk.Sampler,
) {
    infos := make([]vk.DescriptorImageInfo, len(images), context.temp_allocator)
    for i in 0..<len(images) {
        infos[i] = vk.DescriptorImageInfo {
            imageView = images[i].view,
            imageLayout = vk.ImageLayout.SHADER_READ_ONLY_OPTIMAL,
            sampler = sampler,
        }
    }

    write := vk.WriteDescriptorSet {
        sType = vk.StructureType.WRITE_DESCRIPTOR_SET,
        descriptorCount = u32(len(infos)),
        descriptorType = vk.DescriptorType.COMBINED_IMAGE_SAMPLER,
        dstSet = descriptor_set,
        dstBinding = binding,
        pImageInfo = &infos[0],
    }

    vk.UpdateDescriptorSets(vulkan.device, 1, &write, 0, nil)
}

vulkan_descriptor_update_storage_buffer :: proc(
    vulkan: Vulkan,
    descriptor_set: vk.DescriptorSet,
    binding: u32,
    buffer: VulkanBuffer,
) {
    info := vk.DescriptorBufferInfo {
        buffer = buffer.handle,
        offset = 0,
        range = vk.DeviceSize(vk.WHOLE_SIZE),
    }

    write := vk.WriteDescriptorSet {
        sType = vk.StructureType.WRITE_DESCRIPTOR_SET,
        descriptorCount = 1,
        descriptorType = vk.DescriptorType.STORAGE_BUFFER,
        dstBinding = binding,
        dstSet = descriptor_set,
        pBufferInfo = &info,
    }

    vk.UpdateDescriptorSets(vulkan.device, 1, &write, 0, nil)
}

vulkan_descriptor_update_uniform_texel_buffer :: proc(
    vulkan: Vulkan,
    descriptor_set: vk.DescriptorSet,
    binding: u32,
    view: ^vk.BufferView,
) {
    write := vk.WriteDescriptorSet {
        sType = vk.StructureType.WRITE_DESCRIPTOR_SET,
        descriptorCount = 1,
        descriptorType = vk.DescriptorType.UNIFORM_TEXEL_BUFFER,
        dstSet = descriptor_set,
        dstBinding = binding,
        pTexelBufferView = view,
    }

    vk.UpdateDescriptorSets(vulkan.device, 1, &write, 0, nil)
}
