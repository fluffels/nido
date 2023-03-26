package nido

import "core:mem"
import vk "vendor:vulkan"

VulkanMesh :: struct {
    vertices: [dynamic]f32,
    vertex_buffer: VulkanBuffer,
    indices: [dynamic]u32,
    index_buffer: VulkanBuffer,
}

V2 :: struct {
    x: f32,
    y: f32,
}

AABox :: struct {
    left: f32,
    right: f32,
    top: f32,
    bottom: f32,
}

vulkan_mesh_push_v2 :: proc(
    mesh: ^VulkanMesh,
    v2: V2,
) {
    append(&mesh.vertices, v2.x);
    append(&mesh.vertices, v2.y);
    append(&mesh.vertices,    0);
    append(&mesh.vertices,    1);
}

vulkan_mesh_push_aabox :: proc(
    mesh: ^VulkanMesh,
    box: AABox,
) {
    base := u32(len(mesh.vertices))

    vulkan_mesh_push_v2(mesh, V2 {x = box.left , y = box.top   })
    vulkan_mesh_push_v2(mesh, V2 {x = box.right, y = box.top   })
    vulkan_mesh_push_v2(mesh, V2 {x = box.right, y = box.bottom})
    vulkan_mesh_push_v2(mesh, V2 {x = box.left,  y = box.bottom})

    append(&mesh.indices, base)
    append(&mesh.indices, base + 1)
    append(&mesh.indices, base + 2)
    append(&mesh.indices, base + 2)
    append(&mesh.indices, base + 3)
    append(&mesh.indices, base)
}

vulkan_mesh_upload :: proc(
    vulkan: Vulkan,
    mesh: ^VulkanMesh,
) {
    vertex_buffer_size := u64(len(mesh.vertices) * size_of(f32))
    mesh.vertex_buffer = vulkan_buffer_create_vertex(vulkan, vertex_buffer_size)

    memory: rawptr = vulkan_memory_map(vulkan, mesh.vertex_buffer.memory)
    mem.copy_non_overlapping(memory, raw_data(mesh.vertices), int(vertex_buffer_size))
    vulkan_memory_unmap(vulkan, mesh.vertex_buffer.memory)

    if (len(mesh.indices) > 0) {
        index_buffer_size := u64(len(mesh.indices) * size_of(u32))
        mesh.index_buffer = vulkan_buffer_create_index(vulkan, index_buffer_size)

        memory: rawptr = vulkan_memory_map(vulkan, mesh.index_buffer.memory)
        mem.copy_non_overlapping(memory, raw_data(mesh.indices), int(index_buffer_size))
        vulkan_memory_unmap(vulkan, mesh.index_buffer.memory)
    }
}

vulkan_mesh_destroy :: proc(
    vulkan: Vulkan,
    mesh: ^VulkanMesh,
) {
    vulkan_buffer_destroy(vulkan, mesh.vertex_buffer)
    vulkan_buffer_destroy(vulkan, mesh.index_buffer)
}
