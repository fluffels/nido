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
    image_count := len(vulkan.swap.views)

    new_state = new(Simple2DBackEnd)
    // NOTE(jan): One persistent uniform buffer per swapchain image.
    new_state.uniform_buffer = make([dynamic]gfx.VulkanBuffer, image_count)
    for i in 0..<image_count {
        new_state.uniform_buffer[i] = gfx.vulkan_buffer_create_uniform(vulkan, size_of(new_state.uniforms))
    }
    new_state.batches = make([dynamic][dynamic]gfx.RenderBatch, image_count)
    // NOTE(jan): Texture stuff.
    new_state.texture_registry.textures = make([dynamic]TextureRegistration)
    // NOTE(jan): Shared sampler.
	new_state.sampler = gfx.vulkan_sampler_create_nearest(vulkan)

    return
}

prepare_frame :: proc (state: ^Simple2DBackEnd, request: back_end.PrepareFrame) {
    frame := request.frame
    vulkan := request.vulkan
    image_index := frame.index

    // NOTE(jan): Translate commands to render batches.
    state.batches[image_index] = make([dynamic]gfx.RenderBatch, context.temp_allocator)
    for app_cmd_list in request.app_cmd_lists {
        cmd_list, ok := app_cmd_list.(^simple_2d_front_end.CommandList)
        if !ok {
            log.warnf("Command list %v is not supported by simple_2d_back_end", app_cmd_list)
            continue
        }
        for cmd in cmd_list.commands {
            switch c in cmd {
                case simple_2d_front_end.DrawBoxCommand:
                    cmd_draw_box(state, c, image_index)
                case simple_2d_front_end.DrawTriangleCommand:
                    cmd_draw_triangle(state, c, image_index)
                case simple_2d_front_end.RegisterTextureCommand:
                    cmd_register_texture(state, c)
                case simple_2d_front_end.UpdateTextureFromFileCommand:
                    cmd_update_texture_from_file(state, c, vulkan, frame)
                case simple_2d_front_end.DrawTexturedQuadCommand:
                    cmd_draw_textured_quad(state, c, image_index)
                case simple_2d_front_end.DrawGlyphCommand:
                    cmd_draw_glyph(state, c, image_index)
                case simple_2d_front_end.UpdateTextureFromBitmapCommand:
                    cmd_update_texture_from_bitmap(state, c, vulkan, frame)
            }
        }
    }

    // TODO(jan): From some command.
    cmd_post_process(state, image_index)

    // NOTE(jan): Upload meshes to GPU.
    for &batch in state.batches[image_index] {
        gfx.vulkan_mesh_upload(vulkan, &batch.mesh)
    }

    // NOTE(jan): Update uniforms.
    // TODO(jan): Dynamic uniform bindings.
	gfx.ortho_stacked(vulkan.swap.extent.width, vulkan.swap.extent.height, &state.uniforms.ortho)
    gfx.vulkan_memory_copy(vulkan, state.uniform_buffer[image_index], &state.uniforms, size_of(state.uniforms))

    for &batch in state.batches[image_index] {
        layout := batch.pipeline.descriptor_set_layouts[0]
        batch.descriptor_set = gfx.vulkan_descriptor_pool_allocate(vulkan, &frame.descriptor_pool, layout)

        if batch.pipeline.meta.name == POST_PASS_PIPELINE.name {
            gfx.vulkan_descriptor_update_combined_image_sampler(
                vulkan,
                batch.descriptor_set,
                0,
                []gfx.VulkanImage { state.main_pass.images[image_index] },
                state.sampler,
            )
            continue
        }

        // NOTE(jan): Assume that binding 0 is always uniforms.
        gfx.vulkan_descriptor_update_uniform(vulkan, batch.descriptor_set, 0, state.uniform_buffer[image_index])

        for texture_binding, i in batch.textures {
            for texture in state.texture_registry.textures {
                if texture.handle != texture_binding.texture_handle do continue
                gfx.vulkan_descriptor_update_combined_image_sampler(
                    vulkan,
                    batch.descriptor_set,
                    u32(i + 1),
                    []gfx.VulkanImage { texture.image },
                    state.sampler,
                )
                break
            }
        }
    }
}

draw_frame :: proc (state: ^Simple2DBackEnd, request: back_end.DrawFrame) {
    frame := request.frame
    cmd := frame.cmd
    vulkan := request.vulkan
    image_index := frame.index

    // NOTE(jan): Main pass.
    main_pass := state.main_pass
    {
        clears := [?]vk.ClearValue {
            vk.ClearValue { color = { float32 = gfx.gray }},
            vk.ClearValue { depthStencil = { depth = 0, stencil = 0 }},
        }
        vk_pass := vk.RenderPassBeginInfo {
            sType = vk.StructureType.RENDER_PASS_BEGIN_INFO,
            clearValueCount = u32(len(clears)),
            pClearValues = raw_data(&clears),
            framebuffer = main_pass.framebuffers[image_index],
            renderArea = vk.Rect2D {
                extent = vulkan.swap.extent,
                offset = {0, 0},
            },
            renderPass = main_pass.render_pass,
        }
        vk.CmdBeginRenderPass(cmd, &vk_pass, vk.SubpassContents.INLINE)
    }

    for &batch in state.batches[image_index] {
        // TODO(jan): Better way to skip post pass.
        if batch.pipeline.meta.name == "post" do continue
        vk.CmdBindPipeline(cmd, vk.PipelineBindPoint.GRAPHICS, batch.pipeline.handle)
        // TODO(jan): Dynamic uniform binding.
        descriptor_set := batch.descriptor_set
        vk.CmdBindDescriptorSets(
            cmd,
            vk.PipelineBindPoint.GRAPHICS,
            batch.pipeline.layout,
            0, 1,
            &descriptor_set,
            0, nil,
        )
        gfx.vulkan_mesh_bind(cmd, &batch.mesh)
        vk.CmdDrawIndexed(cmd, u32(len(batch.mesh.indices)), 1, 0, 0, 0)
    }

    vk.CmdEndRenderPass(cmd)

    // NOTE(jan): Post pass.
    post_pass := state.post_pass
    {
        clears := [?]vk.ClearValue {
            vk.ClearValue { color = { float32 = gfx.gray }},
            vk.ClearValue { depthStencil = { depth = 0, stencil = 0 }},
        }
        vk_pass := vk.RenderPassBeginInfo {
            sType = vk.StructureType.RENDER_PASS_BEGIN_INFO,
            clearValueCount = u32(len(clears)),
            pClearValues = raw_data(&clears),
            framebuffer = post_pass.framebuffers[image_index],
            renderArea = vk.Rect2D {
                extent = vulkan.swap.extent,
                offset = {0, 0},
            },
            renderPass = post_pass.render_pass
        }
        vk.CmdBeginRenderPass(cmd, &vk_pass, vk.SubpassContents.INLINE)
    }

    for &batch in state.batches[image_index] {
        // TODO(jan): Better way to skip non post pass.
        if batch.pipeline.meta.name != "post" do continue
        vk.CmdBindPipeline(cmd, vk.PipelineBindPoint.GRAPHICS, batch.pipeline.handle)
        descriptor_set := batch.descriptor_set
        vk.CmdBindDescriptorSets(
            cmd,
            vk.PipelineBindPoint.GRAPHICS,
            batch.pipeline.layout,
            0, 1,
            &descriptor_set,
            0, nil,
        )
        gfx.vulkan_mesh_bind(cmd, &batch.mesh)
        vk.CmdDrawIndexed(cmd, u32(len(batch.mesh.indices)), 1, 0, 0, 0)
    }

    vk.CmdEndRenderPass(cmd)
}

resize_begin :: proc (state: ^Simple2DBackEnd, request: back_end.ResizeBegin) {
    gfx.vulkan_pass_destroy(request.vulkan, &state.main_pass)
    gfx.vulkan_pass_destroy(request.vulkan, &state.post_pass)
}

resize_end :: proc (state: ^Simple2DBackEnd, request: back_end.ResizeEnd) {
    state.main_pass = gfx.vulkan_pass_create(request.vulkan, MAIN_PASS)
    state.post_pass = gfx.vulkan_pass_create(request.vulkan, POST_PASS)
}

cleanup_frame :: proc (state: ^Simple2DBackEnd, request: back_end.CleanupFrame) {
    image_index := request.frame.index
    if image_index >= len(state.batches) do return
    for &batch in state.batches[image_index] {
        gfx.render_batch_destroy(&batch, request.vulkan)
    }
    state.batches[image_index] = nil
}

cleanup :: proc (state: ^Simple2DBackEnd, request: back_end.Cleanup) {
    if state == nil do return

    vulkan := request.vulkan

    gfx.vulkan_sampler_destroy(vulkan, state.sampler)
    state.sampler = 0

    gfx.vulkan_mesh_destroy(vulkan, &state.box_mesh)
    gfx.vulkan_mesh_destroy(vulkan, &state.glyph_mesh)
    for &buffer in state.uniform_buffer {
        gfx.vulkan_buffer_destroy(vulkan, &buffer)
    }
    gfx.vulkan_pass_destroy(vulkan, &state.main_pass)
    gfx.vulkan_pass_destroy(vulkan, &state.post_pass)
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
