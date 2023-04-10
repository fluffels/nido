package demo

import "core:log"
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

PIPELINES := []gfx.VulkanPipelineMetadata {
    {
        "stbtt",
        {
            "ortho_xy_uv_rgba",
            "text",
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
        {
            component_count = 4,
        },
    },
}

init :: proc (state: ^DemoState, request: programs.Initialize,) -> (new_state: ^DemoState) {
    allocator := request.allocator
    context.allocator = allocator
    vulkan := request.vulkan^

    new_state = new(DemoState)

    // NOTE(jan): Uniforms containing orthographic / perspective projection.
    gfx.identity(&new_state.uniforms.mvp)
	gfx.identity(&new_state.uniforms.ortho)
	new_state.uniform_buffer = gfx.vulkan_buffer_create_uniform(vulkan, size_of(new_state.uniforms))

    // NOTE(jan): Sampler for font texture.
	new_state.linear_sampler = gfx.vulkan_sampler_create(vulkan)

    // NOTE(jan): Glyph map.
    extent := vk.Extent2D { 512, 512 }
    size := extent.height * extent.width
	new_state.font_bitmap = make([]u8, size)
	// mem.set(raw_data(new_state.font_bitmap), 255, int(size))
    for i in 0..<512*512 {
        new_state.font_bitmap[i] = 255
    }
	new_state.font_sprite_sheet = gfx.vulkan_image_create_2d_monochrome_texture(vulkan, extent)

	// NOTE(jan): Upload mesh.
    new_state.mesh = gfx.vulkan_mesh_create(VERTEX_DESCRIPTION)
    vertices := [][][]f32 {
        {
            {-1, -1},
            {0, 0},
            {0, 1, 1, 1},
        },
        {
            {1, -1},
            {1, 0},
            {0, 1, 1, 1},
        },
        {
            {1, 1},
            {1, 1},
            {0, 1, 1, 1},
        },
        {
            {-1, 1},
            {0, 1},
            {0, 1, 1, 1},
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

create_passes :: proc (state: ^DemoState, request: programs.CreatePasses) {
    state.vulkan_pass = gfx.vulkan_pass_create(request.vulkan, PIPELINES)
}

destroy_passes :: proc (state: ^DemoState, request: programs.DestroyPasses) {
    gfx.vulkan_pass_destroy(request.vulkan, &state.vulkan_pass)
}

prepare_frame :: proc (state: ^DemoState, request: programs.PrepareFrame) {
    cmd := request.cmd
    vulkan := request.vulkan^

    assert("stbtt" in state.vulkan_pass.pipelines)
    pipeline := state.vulkan_pass.pipelines["stbtt"]

    // NOTE(jan): Update uniforms.
    gfx.vulkan_memory_copy(vulkan, state.uniform_buffer, &state.uniforms, size_of(state.uniforms))
    gfx.vulkan_descriptor_update_uniform(vulkan, pipeline.descriptor_sets[0], 0, state.uniform_buffer);

    // NOTE(jan): Update sampler.
    gfx.vulkan_image_update_texture(
        &vulkan,
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

    assert("stbtt" in vulkan_pass.pipelines)
    pipeline := vulkan_pass.pipelines["stbtt"]

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

handler :: proc (program: ^programs.Program, request: programs.Request) {
    state := (^DemoState)(program.state)

    switch r in request {
        case programs.Initialize:
            program.state = init(state, r)
        case programs.CreatePasses:
            create_passes(state, r)
        case programs.DestroyPasses:
            destroy_passes(state, r)
        case programs.PrepareFrame:
            prepare_frame(state, r)
        case programs.DrawFrame:
            draw_frame(state, r)
        case programs.CleanupFrame:
            log.infof("demo cleanup frame")
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
