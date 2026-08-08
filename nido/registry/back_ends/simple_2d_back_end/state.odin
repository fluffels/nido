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

    // NOTE(jan): batches[image_index] - one list per swapchain image.
    batches: [dynamic][dynamic]gfx.RenderBatch,
    post_pass_batch: [dynamic]gfx.RenderBatch,

    texture_registry: TextureRegistry,

    uniforms: Uniforms,
    // NOTE(jan): One persistent buffer per swapchain image.
    uniform_buffer: [dynamic]gfx.VulkanBuffer,

    main_pass: gfx.VulkanPass,
    post_pass: gfx.VulkanPass,
}
