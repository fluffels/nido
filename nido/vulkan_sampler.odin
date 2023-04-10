package nido

import vk "vendor:vulkan"

vulkan_sampler_create :: proc(vulkan: Vulkan) -> (sampler: vk.Sampler) {
    check(
        vk.CreateSampler(
            vulkan.device,
            &vk.SamplerCreateInfo{
                sType = vk.StructureType.SAMPLER_CREATE_INFO,
                magFilter = vk.Filter.LINEAR,
                minFilter = vk.Filter.LINEAR,
                mipmapMode = vk.SamplerMipmapMode.NEAREST,
                addressModeU = vk.SamplerAddressMode.REPEAT,
                addressModeV = vk.SamplerAddressMode.REPEAT,
                addressModeW = vk.SamplerAddressMode.REPEAT,
                anisotropyEnable = false,
                compareEnable = false,
            },
            nil,
            &sampler,
        ),
        "could not create sampler",
    )
    return
}

vulkan_sampler_destroy :: proc(vulkan: Vulkan, sampler: vk.Sampler) {
    vk.DestroySampler(vulkan.device, sampler, nil)
}


// void createVulkanSamplerCube(
//     VkDevice device,
//     VkPhysicalDeviceMemoryProperties& memories,
//     VkExtent2D extent,
//     uint32_t family,
//     VulkanSampler& sampler
// ) {
//     createVulkanSampler(
//         device,
//         memories,
//         VK_IMAGE_TYPE_2D,
//         VK_IMAGE_VIEW_TYPE_CUBE,
//         extent,
//         6,
//         family,
//         VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT,
//         VK_SAMPLE_COUNT_1_BIT,
//         sampler
//     );
// }