package gfx

import "core:mem"

RenderBatchTextureMapping :: struct {
    texture_handle: u32,
    texture_index: u32,
}

RenderBatch :: struct {
    pipeline: VulkanPipeline,
    textures: [dynamic]RenderBatchTextureMapping,
    mesh: VulkanMesh,
    // TODO(jan): Handle Uniforms.
}

make_render_batch :: proc(pipeline: VulkanPipeline, desc: VertexDescription, allocator: mem.Allocator) -> RenderBatch {
    return RenderBatch {
        pipeline = pipeline,
        textures = make([dynamic]RenderBatchTextureMapping),
        mesh = vulkan_mesh_create(desc, allocator),
    }
}

render_batch_destroy :: proc(batch: ^RenderBatch, vulkan: ^Vulkan) {
    vulkan_mesh_destroy(vulkan, &batch.mesh)
}
