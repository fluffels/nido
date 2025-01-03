package demo

import "core:log"
import "core:math"
import "core:mem"

import vk "vendor:vulkan"

import "../../gfx"
import "../../programs"

Uniforms :: struct {
    mvp: gfx.mat4x4,
	ortho: gfx.mat4x4,
}

DemoState :: struct {
    font_bitmap: []u8,
    font_sprite_sheet: gfx.VulkanImage,

    linear_sampler: vk.Sampler,

    mesh: gfx.VulkanMesh,

    uniforms: Uniforms,
    uniform_buffer: gfx.VulkanBuffer,

    vulkan_pass: gfx.VulkanPass,
}

PASS := gfx.VulkanPassMetadata {
    enable_depth = false,
    pipelines = []gfx.VulkanPipelineMetadata {
        {
            name = "textured",
            modules = {
                "ortho_xy_uv",
                "sampler",
            },
        },
    },
}

VERTEX_DESCRIPTION := gfx.VertexDescription {
    name = "demo_vertex",
    attributes = []gfx.VertexAttributeDescription {
        {
            component_count = 2,
        },
        {
            component_count = 2,
        },
    },
}

init :: proc (state: ^DemoState, request: programs.Initialize,) -> (new_state: ^DemoState) {
    allocator := request.allocator
    context.allocator = allocator
    vulkan := request.vulkan

    new_state = new(DemoState)

    // NOTE(jan): Uniforms containing orthographic / perspective projection.
    gfx.identity(&new_state.uniforms.mvp)
	gfx.identity(&new_state.uniforms.ortho)
	new_state.uniform_buffer = gfx.vulkan_buffer_create_uniform(vulkan, size_of(new_state.uniforms))

    // NOTE(jan): Sampler for textures.
	new_state.linear_sampler = gfx.vulkan_sampler_create_linear(vulkan)

    // NOTE(jan): Texture.
    extent := vk.Extent2D { 512, 512 }
    size := extent.height * extent.width
	new_state.font_bitmap = make([]u8, size)
    for i in 0..<extent.height {
        for j in 0..<extent.width {
            s := (1 + math.cos_f32(f32(j) / 10)) / 2
            value := u8(s * 255)
            new_state.font_bitmap[i * extent.width + j] = value
        }
    }
	new_state.font_sprite_sheet = gfx.vulkan_image_create_2d_monochrome_texture(vulkan, extent)

	// NOTE(jan): Upload mesh.
    new_state.mesh = gfx.vulkan_mesh_create(VERTEX_DESCRIPTION)
    vertices := [][][]f32 {
        {
            {-1, -1},
            {0, 0},
        },
        {
            {1, -1},
            {1, 0},
        },
        {
            {1, 1},
            {1, 1},
        },
        {
            {-1, 1},
            {0, 1},
        },
    }
    append(&new_state.mesh.indices, 0)
    append(&new_state.mesh.indices, 1)
    append(&new_state.mesh.indices, 2)
    append(&new_state.mesh.indices, 2)
    append(&new_state.mesh.indices, 3)
    append(&new_state.mesh.indices, 0)
    gfx.vulkan_mesh_push_vertices(&new_state.mesh, vertices)
	gfx.vulkan_mesh_upload(vulkan, &new_state.mesh)

    return
}

resize_end :: proc (state: ^DemoState, request: programs.ResizeEnd) {
    state.vulkan_pass = gfx.vulkan_pass_create(request.vulkan, PASS)
}

resize_begin :: proc (state: ^DemoState, request: programs.ResizeBegin) {
    gfx.vulkan_pass_destroy(request.vulkan, &state.vulkan_pass)
}

prepare_frame :: proc (state: ^DemoState, request: programs.PrepareFrame) {
    cmd := request.cmd
    vulkan := request.vulkan

    assert("textured" in state.vulkan_pass.pipelines)
    pipeline := state.vulkan_pass.pipelines["textured"]

    // NOTE(jan): Update uniforms.
    gfx.vulkan_memory_copy(vulkan, state.uniform_buffer, &state.uniforms, size_of(state.uniforms))
    gfx.vulkan_descriptor_update_uniform(vulkan, pipeline.descriptor_sets[0], 0, state.uniform_buffer);

    // NOTE(jan): Update sampler.
    gfx.vulkan_image_update_texture(
        vulkan,
        cmd,
        state.font_bitmap,
        state.font_sprite_sheet,
    )
    gfx.vulkan_descriptor_update_combined_image_sampler(
        vulkan,
        pipeline.descriptor_sets[0],
        1,
        []gfx.VulkanImage { state.font_sprite_sheet },
        state.linear_sampler,
    )
}

draw_frame :: proc (state: ^DemoState, request: programs.DrawFrame) {
    cmd := request.cmd
    vulkan := request.vulkan
    vulkan_pass := state.vulkan_pass

    assert("textured" in vulkan_pass.pipelines)
    pipeline := vulkan_pass.pipelines["textured"]

    clears := [?]vk.ClearValue {
        vk.ClearValue { color = { float32 = {.5, .5, .5, 1}}},
    }

    pass := vk.RenderPassBeginInfo {
        sType = vk.StructureType.RENDER_PASS_BEGIN_INFO,
        clearValueCount = u32(len(clears)),
        pClearValues = raw_data(&clears),
        framebuffer = vulkan_pass.framebuffers[request.image_index],
        renderArea = vk.Rect2D {
            extent = vulkan.swap.extent,
            offset = {0, 0},
        },
        renderPass = vulkan_pass.render_pass,
    }

    vk.CmdBeginRenderPass(cmd, &pass, vk.SubpassContents.INLINE)

    vk.CmdBindPipeline(cmd, vk.PipelineBindPoint.GRAPHICS, pipeline.handle)
    
    vk.CmdBindDescriptorSets(
        cmd,
        vk.PipelineBindPoint.GRAPHICS,
        pipeline.layout,
        0, u32(len(pipeline.descriptor_sets)),
        raw_data(pipeline.descriptor_sets),
        0, nil,
    )

    gfx.vulkan_mesh_bind(cmd, &state.mesh)

    vk.CmdDrawIndexed(cmd, u32(len(state.mesh.indices)), 1, 0, 0, 0)

    vk.CmdEndRenderPass(cmd)
}

cleanup_frame :: proc (state: ^DemoState, request: programs.CleanupFrame) { }

cleanup :: proc (state: ^DemoState, request: programs.Cleanup) {
    if state == nil do return

    vulkan := request.vulkan

    gfx.vulkan_sampler_destroy(vulkan, state.linear_sampler)
    state.linear_sampler = 0

    gfx.vulkan_image_destroy(vulkan, &state.font_sprite_sheet)
    gfx.vulkan_mesh_destroy(vulkan, &state.mesh)
    gfx.vulkan_buffer_destroy(vulkan, &state.uniform_buffer)
    gfx.vulkan_pass_destroy(vulkan, &state.vulkan_pass)
}

handler :: proc (program: ^programs.Program, request: programs.Request) {
    state := (^DemoState)(program.state)

    switch r in request {
        case programs.Initialize:
            program.state = init(state, r)
        case programs.ResizeEnd:
            resize_end(state, r)
        case programs.ResizeBegin:
            resize_begin(state, r)
        case programs.PrepareFrame:
            prepare_frame(state, r)
        case programs.DrawFrame:
            draw_frame(state, r)
        case programs.CleanupFrame:
            cleanup_frame(state, r)
        case programs.Cleanup:
            cleanup(state, r)
        case:
            panic("unhandled request")
    }
}

make_program :: proc () -> programs.Program {
    return programs.Program {
        name = "demo",
        handler = handler,
    }
}