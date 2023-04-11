package gfx

import "core:mem"
import vk "vendor:vulkan"

VertexAttributeDescription :: struct {
    component_count: u32,
}

VertexDescription :: struct {
    name: string,
    attributes: []VertexAttributeDescription,
}

VulkanMesh :: struct {
    description: VertexDescription,
    
    vertex_count: u32,

    attributes: [dynamic][dynamic]f32,
    attribute_buffers: [dynamic]VulkanBuffer,

    indices: [dynamic]u32,
    index_buffer: VulkanBuffer,
}

vulkan_mesh_create :: proc(desc: VertexDescription) -> (mesh: VulkanMesh) {
    mesh.description = desc

    mesh.attribute_buffers = make([dynamic]VulkanBuffer)

    mesh.attributes = make([dynamic][dynamic]f32, len(desc.attributes))
    for i in 0..<len(desc.attributes) {
        mesh.attributes[i] = make([dynamic]f32)
    }

    mesh.indices = make([dynamic]u32)

    return
}

vulkan_mesh_push_vertices :: proc(
    mesh: ^VulkanMesh,
    v: [][][]f32,
) {
    for i in 0..<len(v) {
        for j in 0..<len(v[i]) {
            for k in 0..<len(v[i][j]) {
                append(&mesh.attributes[j], v[i][j][k])
            }
        }
    }
    mesh.vertex_count += u32(len(v))
}

vulkan_mesh_push_vertex :: proc(
    mesh: ^VulkanMesh,
    v: [][]f32,
) {
    for i in 0..<len(v) {
        for j in 0..<len(v[i]) {
            append(&mesh.attributes[i], v[i][j])
        }
    }
    mesh.vertex_count += 1
}

vulkan_mesh_bind :: proc(
    cmd: vk.CommandBuffer,
    mesh: ^VulkanMesh,
) {
    offsets := [1]vk.DeviceSize {0}
    for i in 0..<len(mesh.attribute_buffers) {
        buffer := mesh.attribute_buffers[i]
        vk.CmdBindVertexBuffers(cmd, u32(i), 1, &buffer.handle, raw_data(offsets[:]))
    }

    if (mesh.index_buffer.handle != 0) {
        vk.CmdBindIndexBuffer(cmd, mesh.index_buffer.handle, 0, vk.IndexType.UINT32)
    }
}

vulkan_mesh_upload :: proc(
    vulkan: ^Vulkan,
    mesh: ^VulkanMesh,
) {
    for attribute_desc, i in mesh.description.attributes {
        data := mesh.attributes[i]
        size := u64(len(data)) * u64(attribute_desc.component_count) * size_of(f32)

        buffer := vulkan_buffer_create_vertex(vulkan, size)

        memory: rawptr = vulkan_memory_map(vulkan, buffer.memory)
            mem.copy_non_overlapping(memory, raw_data(data), int(size))
        vulkan_memory_unmap(vulkan, buffer.memory)

        append(&mesh.attribute_buffers, buffer)
    }

    if (len(mesh.indices) > 0) {
        index_buffer_size := u64(len(mesh.indices) * size_of(u32))
        mesh.index_buffer = vulkan_buffer_create_index(vulkan, index_buffer_size)

        memory: rawptr = vulkan_memory_map(vulkan, mesh.index_buffer.memory)
            mem.copy_non_overlapping(memory, raw_data(mesh.indices), int(index_buffer_size))
        vulkan_memory_unmap(vulkan, mesh.index_buffer.memory)
    }
}

vulkan_mesh_destroy :: proc(
    vulkan: ^Vulkan,
    mesh: ^VulkanMesh,
) {
    for buffer, i in mesh.attribute_buffers {
        if (buffer.handle != 0) {
            vulkan_buffer_destroy(vulkan, &mesh.attribute_buffers[i])
        }
    }

    if (mesh.index_buffer.handle != 0) {
        vulkan_buffer_destroy(vulkan, &mesh.index_buffer)
    }
}
