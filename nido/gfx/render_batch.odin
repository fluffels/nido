package gfx

import "core:mem"
import vk "vendor:vulkan"

RenderBatchTextureMapping :: struct {
    texture_handle: u32,
    texture_index: u32,
}

RenderBatch :: struct {
    pipeline: VulkanPipeline,
    textures: [dynamic]RenderBatchTextureMapping,
    mesh: VulkanMesh,
    descriptor_set: vk.DescriptorSet,
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
