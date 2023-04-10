package nido

import "core:mem"
import vk "vendor:vulkan"

VulkanMesh :: struct {
    vertex_count: u32,
    index_count: u32,

    positions: [dynamic]f32,
    position_buffer: VulkanBuffer,

    uv: [dynamic]f32,
    uv_buffer: VulkanBuffer,

    rgba: [dynamic]f32,
    rgba_buffer: VulkanBuffer,

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
    append(&mesh.positions, v2.x);
    append(&mesh.positions, v2.y);

    append(&mesh.uv, 1);
    append(&mesh.uv, 1);

    append(&mesh.rgba, 0);
    append(&mesh.rgba, 1);
    append(&mesh.rgba, 1);
    append(&mesh.rgba, 1);
}

vulkan_mesh_push_aabox :: proc(
    mesh: ^VulkanMesh,
    box: AABox,
) {
    base := mesh.vertex_count

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

    mesh.vertex_count += 4
    mesh.index_count += 6
}

vulkan_mesh_upload :: proc(
    vulkan: Vulkan,
    mesh: ^VulkanMesh,
) {
    position_buffer_size := u64(len(mesh.positions) * size_of(f32))
    mesh.position_buffer = vulkan_buffer_create_vertex(vulkan, position_buffer_size)

    memory: rawptr = vulkan_memory_map(vulkan, mesh.position_buffer.memory)
        mem.copy_non_overlapping(memory, raw_data(mesh.positions), int(position_buffer_size))
    vulkan_memory_unmap(vulkan, mesh.position_buffer.memory)

    if (len(mesh.uv) > 0) {
        size := u64(len(mesh.uv) * size_of(u32))
        mesh.uv_buffer = vulkan_buffer_create_vertex(vulkan, size)

        memory: rawptr = vulkan_memory_map(vulkan, mesh.uv_buffer.memory)
            mem.copy_non_overlapping(memory, raw_data(mesh.uv), int(size))
        vulkan_memory_unmap(vulkan, mesh.uv_buffer.memory)
    }

    if (len(mesh.rgba) > 0) {
        size := u64(len(mesh.rgba) * size_of(u32))
        mesh.rgba_buffer = vulkan_buffer_create_vertex(vulkan, size)

        memory: rawptr = vulkan_memory_map(vulkan, mesh.rgba_buffer.memory)
            mem.copy_non_overlapping(memory, raw_data(mesh.rgba), int(size))
        vulkan_memory_unmap(vulkan, mesh.rgba_buffer.memory)
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
    vulkan: Vulkan,
    mesh: ^VulkanMesh,
) {
    vulkan_buffer_destroy(vulkan, mesh.position_buffer)
    vulkan_buffer_destroy(vulkan, mesh.uv_buffer)
    vulkan_buffer_destroy(vulkan, mesh.rgba_buffer)
    vulkan_buffer_destroy(vulkan, mesh.index_buffer)
}
