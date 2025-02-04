package simple_2d_back_end

import vk "vendor:vulkan"

import "../../../gfx"

Uniforms :: struct {
	ortho: gfx.mat4x4,
}

Simple2DBackEnd :: struct {
    sampler: vk.Sampler,

    box_mesh: gfx.VulkanMesh,
    textured_quad_mesh: gfx.VulkanMesh,
    glyph_mesh: gfx.VulkanMesh,

    batches: [dynamic]gfx.RenderBatch,
    post_pass_batch: [dynamic]gfx.RenderBatch,

    texture_registry: TextureRegistry,

    uniforms: Uniforms,
    uniform_buffer: gfx.VulkanBuffer,

    main_pass: gfx.VulkanPass,
    post_pass: gfx.VulkanPass,
}
