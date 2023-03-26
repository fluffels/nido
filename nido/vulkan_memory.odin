package nido

import vk "vendor:vulkan"

vulkan_memory_type_index :: proc(
    vulkan: Vulkan,
    requirements: vk.MemoryRequirements,
    extra_flags: vk.MemoryPropertyFlags,
 ) -> (index: u32) {
    found := false

    for i in 0..<vulkan.memories.memoryTypeCount {
        if (requirements.memoryTypeBits & (1 << i)) > 0 {
            if vulkan.memories.memoryTypes[i].propertyFlags >= extra_flags {
                found = true;
                index = i;
                break;
            }
        }
    }
    if (!found) {
        panic("could not find memory type");
    }
    return index;
}

vulkan_memory_map :: proc(
    vulkan: Vulkan,
    memory: vk.DeviceMemory,
) -> (pointer: rawptr) {
    size := vk.DeviceSize(vk.WHOLE_SIZE)
    flags := vk.MemoryMapFlags {}
    check(
        vk.MapMemory(vulkan.device, memory, 0, size, flags, &pointer),
        "could not map memory",
    )
    return pointer
}

vulkan_memory_unmap :: proc(
    vulkan: Vulkan,
    memory: vk.DeviceMemory,
) {
    vk.UnmapMemory(vulkan.device, memory)
}
