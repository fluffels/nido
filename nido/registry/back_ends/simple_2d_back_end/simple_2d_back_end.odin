package simple_2d_back_end

import "core:log"
import "core:math"
import linalg "core:math/linalg"
import "core:mem"

import vk "vendor:vulkan"

import "../../../gfx"
import "../../../gfx/simple_2d_front_end"
import "../../../back_end"

Uniforms :: struct {
	ortho: gfx.mat4x4,
}

Simple2DBackEnd :: struct {
    sampler: vk.Sampler,

    box_mesh: gfx.VulkanMesh,
    textured_quad_mesh: gfx.VulkanMesh,
    glyph_mesh: gfx.VulkanMesh,

    texture_registry: TextureRegistry,

    uniforms: Uniforms,
    uniform_buffer: gfx.VulkanBuffer,

    vulkan_pass: gfx.VulkanPass,
}

PASS := gfx.VulkanPassMetadata {
    enable_depth = true,
    pipelines = []gfx.VulkanPipelineMetadata {
        // NOTE(jan): Pipeline for colored boxes.
        gfx.VulkanPipelineMetadata {
            name = "boxes",
            modules = {
                "ortho_xyz_rgba",
                "color",
            },
        },
        // NOTE(jan): Pipeline for textured quads.
        gfx.VulkanPipelineMetadata {
            name = "textured_quads",
            modules = {
                "ortho_xyz_uv",
                "sampler",
            },
        },
        // NOTE(jan): Pipeline for glyphs.
        gfx.VulkanPipelineMetadata {
            name = "glyphs",
            modules = {
                "ortho_xyz_uv_rgb",
                "sampler_as_coverage",
            },
        },
    },
}

COLOR_VERTEX := gfx.VertexDescription {
    name = "simple_2d_back_end_color_vertex",
    attributes = []gfx.VertexAttributeDescription {
        {
            // NOTE(jan): Screen-space position + z for layering.
            component_count = 3,
        },
        {
            // NOTE(jan): RGBA.
            component_count = 4,
        },
    },
}

TEXTURED_VERTEX := gfx.VertexDescription {
    name = "simple_2d_back_end_texture_vertex",
    attributes = []gfx.VertexAttributeDescription {
        {
            // NOTE(jan): Screen-space position + z for layering.
            component_count = 3,
        },
        {
            // NOTE(jan): Texture coords.
            component_count = 2,
        },
    },
}

init :: proc (state: ^Simple2DBackEnd, request: back_end.Initialize,) -> (new_state: ^Simple2DBackEnd) {
    vulkan := request.vulkan

    new_state = new(Simple2DBackEnd)

    // NOTE(jan): Uniforms containing orthographic projection.
	new_state.uniform_buffer = gfx.vulkan_buffer_create_uniform(vulkan, size_of(new_state.uniforms))

    // NOTE(jan): Texture stuff.
    new_state.texture_registry.textures = make([dynamic]TextureRegistration)

    // NOTE(jan): Sampler for glyph cache.
	new_state.sampler = gfx.vulkan_sampler_create_nearest(vulkan)
    
    // NOTE(jan): Meshes.
    new_state.box_mesh = gfx.vulkan_mesh_create(COLOR_VERTEX)
    new_state.glyph_mesh = gfx.vulkan_mesh_create(TEXTURED_VERTEX)

    return
}

resize_begin :: proc (state: ^Simple2DBackEnd, request: back_end.ResizeBegin) {
    gfx.vulkan_pass_destroy(request.vulkan, &state.vulkan_pass)
}

resize_end :: proc (state: ^Simple2DBackEnd, request: back_end.ResizeEnd) {
    state.vulkan_pass = gfx.vulkan_pass_create(request.vulkan, PASS)
}

prepare_frame :: proc (state: ^Simple2DBackEnd, request: back_end.PrepareFrame) {
    cmd := request.cmd
    vulkan := request.vulkan

    for app_cmd_list in request.app_cmd_lists {
        if app_cmd_list.type != "simple_2d_front_end" {
            log.panic("Command lists submitted to simple 2d back end must be created by simple 2d front end.")
        }
        cmd_list := cast(^simple_2d_front_end.CommandList)app_cmd_list.list
        for cmd in cmd_list.commands {
            switch c in cmd {
                case simple_2d_front_end.DrawBoxCommand:
                    cmd_draw_box(state, c)
                case simple_2d_front_end.RegisterTextureCommand:
                    cmd_register_texture(state, c, request)
                case simple_2d_front_end.DrawTexturedQuadCommand:
                    cmd_draw_textured_quad(state, c)
            }
        }
    }

    // NOTE(jan): Update uniforms.
	gfx.ortho_stacked(vulkan.swap.extent.width, vulkan.swap.extent.height, &state.uniforms.ortho)
    gfx.vulkan_memory_copy(vulkan, state.uniform_buffer, &state.uniforms, size_of(state.uniforms))
    for _, pipeline in state.vulkan_pass.pipelines {
        // NOTE(jan): Assume that descriptor set 0 is always uniforms.
        gfx.vulkan_descriptor_update_uniform(vulkan, pipeline.descriptor_sets[0], 0, state.uniform_buffer);
    }

	// NOTE(jan): Upload meshes.
    gfx.vulkan_mesh_reset(&state.box_mesh)
    gfx.vulkan_mesh_reset(&state.glyph_mesh)

    // draw(vulkan, state, request.events, request.input_state)

    gfx.vulkan_mesh_upload(vulkan, &state.box_mesh)
	gfx.vulkan_mesh_upload(vulkan, &state.glyph_mesh)
}

draw_frame :: proc (state: ^Simple2DBackEnd, request: back_end.DrawFrame) {
    cmd := request.cmd
    vulkan := request.vulkan
    vulkan_pass := state.vulkan_pass

    clears := [?]vk.ClearValue {
        vk.ClearValue { color = { float32 = gfx.gray }},
        vk.ClearValue { depthStencil = { depth = 1, stencil = 0 }},
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

    // NOTE(jan): Draw colored stuff.
    {
        assert("boxes" in vulkan_pass.pipelines)
        pipeline := vulkan_pass.pipelines["boxes"]
        vk.CmdBindPipeline(cmd, vk.PipelineBindPoint.GRAPHICS, pipeline.handle)
        vk.CmdBindDescriptorSets(
            cmd,
            vk.PipelineBindPoint.GRAPHICS,
            pipeline.layout,
            0, u32(len(pipeline.descriptor_sets)),
            raw_data(pipeline.descriptor_sets),
            0, nil,
        )
        gfx.vulkan_mesh_bind(cmd, &state.box_mesh)
        vk.CmdDrawIndexed(cmd, u32(len(state.box_mesh.indices)), 1, 0, 0, 0)
    }

    // NOTE(jan): Draw textured stuff.
    {
        assert("textured_quads" in vulkan_pass.pipelines)
        pipeline := vulkan_pass.pipelines["textured_quads"]
        vk.CmdBindPipeline(cmd, vk.PipelineBindPoint.GRAPHICS, pipeline.handle)
        vk.CmdBindDescriptorSets(
            cmd,
            vk.PipelineBindPoint.GRAPHICS,
            pipeline.layout,
            0, u32(len(pipeline.descriptor_sets)),
            raw_data(pipeline.descriptor_sets),
            0, nil,
        )
        gfx.vulkan_mesh_bind(cmd, &state.glyph_mesh)
        vk.CmdDrawIndexed(cmd, u32(len(state.glyph_mesh.indices)), 1, 0, 0, 0)
    }

    vk.CmdEndRenderPass(cmd)
}

cleanup_frame :: proc (state: ^Simple2DBackEnd, request: back_end.CleanupFrame) { }

cleanup :: proc (state: ^Simple2DBackEnd, request: back_end.Cleanup) {
    if state == nil do return

    vulkan := request.vulkan

    gfx.vulkan_sampler_destroy(vulkan, state.sampler)
    state.sampler = 0

    gfx.vulkan_mesh_destroy(vulkan, &state.box_mesh)
    gfx.vulkan_mesh_destroy(vulkan, &state.glyph_mesh)
    gfx.vulkan_buffer_destroy(vulkan, &state.uniform_buffer)
    gfx.vulkan_pass_destroy(vulkan, &state.vulkan_pass)
}

handler :: proc (program: ^back_end.BackEnd, request: back_end.Request) {
    state := (^Simple2DBackEnd)(program.state)

    context.allocator = program.allocator

    switch r in request {
        case back_end.Initialize:
            program.state = init(state, r)
        case back_end.ResizeEnd:
            resize_end(state, r)
        case back_end.ResizeBegin:
            resize_begin(state, r)
        case back_end.PrepareFrame:
            prepare_frame(state, r)
        case back_end.DrawFrame:
            draw_frame(state, r)
        case back_end.CleanupFrame:
            cleanup_frame(state, r)
        case back_end.Cleanup:
            cleanup(state, r)
        case:
            panic("unhandled request")
    }
}

make_program :: proc () -> back_end.BackEnd {
    return back_end.BackEnd {
        name = "map_editor",
        handler = handler,
    }
}
