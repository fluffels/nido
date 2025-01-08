package simple_2d_back_end

import "core:log"
import "core:math"
import linalg "core:math/linalg"
import "core:mem"

import vk "vendor:vulkan"

import "../../../gfx"
import "../../../gfx/simple_2d_front_end"
import "../../../back_end"

/*
    TODO(jan):
    - [ ] Handle multiple textures.
    - [ ] A system is required for allocating Vulkan buffers and freeing them at the end of the frame, similar to a memory arena.
*/

init :: proc (state: ^Simple2DBackEnd, request: back_end.Initialize,) -> (new_state: ^Simple2DBackEnd) {
    vulkan := request.vulkan

    new_state = new(Simple2DBackEnd)
    // NOTE(jan): Uniforms containing orthographic projection.
	new_state.uniform_buffer = gfx.vulkan_buffer_create_uniform(vulkan, size_of(new_state.uniforms))
    // NOTE(jan): Texture stuff.
    new_state.texture_registry.textures = make([dynamic]TextureRegistration)
    // NOTE(jan): Shared sampler.
	new_state.sampler = gfx.vulkan_sampler_create_nearest(vulkan)

    return
}

prepare_frame :: proc (state: ^Simple2DBackEnd, request: back_end.PrepareFrame) {
    cmd := request.cmd
    vulkan := request.vulkan

    // NOTE(jan): Translate commands to render batches.
    state.batches = make([dynamic]gfx.RenderBatch, context.temp_allocator)
    for app_cmd_list in request.app_cmd_lists {
        if app_cmd_list.type != "simple_2d_front_end" {
            log.warn("Command list of type '%v' is not supported by simple_2d_back_end", app_cmd_list.type)
            continue
        }
        cmd_list := cast(^simple_2d_front_end.CommandList)app_cmd_list.list
        for cmd in cmd_list.commands {
            switch c in cmd {
                case simple_2d_front_end.DrawBoxCommand:
                    cmd_draw_box(state, c)
                case simple_2d_front_end.RegisterTextureCommand:
                    cmd_register_texture(state, c, request)
                case simple_2d_front_end.UpdateTextureFromFileCommand:
                    cmd_update_texture_from_file(state, c, request)
                case simple_2d_front_end.DrawTexturedQuadCommand:
                    cmd_draw_textured_quad(state, c)
                case simple_2d_front_end.DrawGlyphCommand:
                    cmd_draw_glyph(state, c)
                case simple_2d_front_end.UpdateTextureFromBitmapCommand:
                    cmd_update_texture_from_bitmap(state, c, request)
            }
        }
    }

    // NOTE(jan): Upload meshes to GPU.
    for &batch in state.batches {
        gfx.vulkan_mesh_upload(vulkan, &batch.mesh)
    }

    // NOTE(jan): Update uniforms.
    // TODO(jan): Dynamic uniform bindings.
	gfx.ortho_stacked(vulkan.swap.extent.width, vulkan.swap.extent.height, &state.uniforms.ortho)
    gfx.vulkan_memory_copy(vulkan, state.uniform_buffer, &state.uniforms, size_of(state.uniforms))
    for _, pipeline in state.vulkan_pass.pipelines {
        // NOTE(jan): Assume that descriptor set 0 is always uniforms.
        gfx.vulkan_descriptor_update_uniform(vulkan, pipeline.descriptor_sets[0], 0, state.uniform_buffer);
    }
}

draw_frame :: proc (state: ^Simple2DBackEnd, request: back_end.DrawFrame) {
    cmd := request.cmd
    vulkan := request.vulkan
    vulkan_pass := state.vulkan_pass

    clears := [?]vk.ClearValue {
        vk.ClearValue { color = { float32 = gfx.gray }},
        vk.ClearValue { depthStencil = { depth = 0, stencil = 0 }},
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

    for &batch in state.batches {
        vk.CmdBindPipeline(cmd, vk.PipelineBindPoint.GRAPHICS, batch.pipeline.handle)
        // TODO(jan): Dynamic uniform binding.
        vk.CmdBindDescriptorSets(
            cmd,
            vk.PipelineBindPoint.GRAPHICS,
            batch.pipeline.layout,
            0, u32(len(batch.pipeline.descriptor_sets)),
            raw_data(batch.pipeline.descriptor_sets),
            0, nil,
        )
        // NOTE(jan): Bind textures.
        for texture_binding, i in batch.textures {
            for texture in state.texture_registry.textures {
                if texture.handle != texture_binding.texture_handle do continue
                gfx.vulkan_descriptor_update_combined_image_sampler(
                    vulkan,
                    batch.pipeline.descriptor_sets[0],
                    u32(i + 1),
                    []gfx.VulkanImage { texture.image },
                    state.sampler,
                )
                break
            }
        }
        gfx.vulkan_mesh_bind(cmd, &batch.mesh)
        vk.CmdDrawIndexed(cmd, u32(len(batch.mesh.indices)), 1, 0, 0, 0)
    }

    vk.CmdEndRenderPass(cmd)
}

resize_begin :: proc (state: ^Simple2DBackEnd, request: back_end.ResizeBegin) {
    gfx.vulkan_pass_destroy(request.vulkan, &state.vulkan_pass)
}

resize_end :: proc (state: ^Simple2DBackEnd, request: back_end.ResizeEnd) {
    state.vulkan_pass = gfx.vulkan_pass_create(request.vulkan, PASSES)
}

cleanup_frame :: proc (state: ^Simple2DBackEnd, request: back_end.CleanupFrame) {
    for &batch in state.batches {
        gfx.render_batch_destroy(&batch, request.vulkan)
    }
}

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
