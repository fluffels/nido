package map_editor

import "core:log"
import "core:math"
import "core:mem"
import path "core:path/filepath"
import "core:os"

import image "vendor:stb/image"
import vk "vendor:vulkan"

import "../../gfx"
import "../../programs"

Uniforms :: struct {
	ortho: gfx.mat4x4,
}

MapEditorState :: struct {
    sprite_sheet: gfx.VulkanImage,

    sampler: vk.Sampler,

    colored_mesh: gfx.VulkanMesh,
    textured_mesh: gfx.VulkanMesh,

    uniforms: Uniforms,
    uniform_buffer: gfx.VulkanBuffer,

    vulkan_pass: gfx.VulkanPass,

    map_width: int,
    map_height: int,
    terrain: []int,
    selected_sprite: int,
    tile_width: f32,
    tile_height: f32,
    sprite_width: f32,
    sprite_height: f32,
    zoom: f32,
}

PIPELINES := []gfx.VulkanPipelineMetadata {
    {
        "colored",
        {
            "ortho_xy_rgba",
            "color",
        },
    },
    {
        "textured",
        {
            "ortho_xy_uv",
            "sampler",
        },
    },
}

COLORED_VERTEX := gfx.VertexDescription {
    name = "map_editor_colored",
    attributes = []gfx.VertexAttributeDescription {
        {
            component_count = 2,
        },
        {
            component_count = 4,
        },
    },
}

TEXTURED_VERTEX := gfx.VertexDescription {
    name = "map_editor_vertex",
    attributes = []gfx.VertexAttributeDescription {
        {
            component_count = 2,
        },
        {
            component_count = 2,
        },
    },
}

init :: proc (state: ^MapEditorState, request: programs.Initialize,) -> (new_state: ^MapEditorState) {
    allocator := request.allocator
    context.allocator = allocator
    vulkan := request.vulkan

    new_state = new(MapEditorState)

    // NOTE(jan): Uniforms containing orthographic projection.
	new_state.uniform_buffer = gfx.vulkan_buffer_create_uniform(vulkan, size_of(new_state.uniforms))

    // NOTE(jan): Sampler for textures.
	new_state.sampler = gfx.vulkan_sampler_create_nearest(vulkan)
    
    // NOTE(jan): Meshes.
    new_state.colored_mesh = gfx.vulkan_mesh_create(COLORED_VERTEX)
    new_state.textured_mesh = gfx.vulkan_mesh_create(TEXTURED_VERTEX)

    // NOTE(jan): Map.
    new_state.map_width = 256
    new_state.map_height = 256
    new_state.terrain = make([]int, new_state.map_width * new_state.map_height)
    for y in 0..<new_state.map_height {
        for x in 0..<new_state.map_width {
            new_state.terrain[y * new_state.map_width + x] = 0
        }
    }
    load_map(new_state)

    // NOTE(jan): Misc.
    new_state.zoom = 4.0

    return
}

create_passes :: proc (state: ^MapEditorState, request: programs.CreatePasses) {
    state.vulkan_pass = gfx.vulkan_pass_create(request.vulkan, PIPELINES)
}

destroy_passes :: proc (state: ^MapEditorState, request: programs.DestroyPasses) {
    gfx.vulkan_pass_destroy(request.vulkan, &state.vulkan_pass)
}

prepare_frame :: proc (state: ^MapEditorState, request: programs.PrepareFrame) {
    cmd := request.cmd
    vulkan := request.vulkan

    // NOTE(jan): Update uniforms.
	gfx.ortho(vulkan.swap.extent.width, vulkan.swap.extent.height, &state.uniforms.ortho)
    gfx.vulkan_memory_copy(vulkan, state.uniform_buffer, &state.uniforms, size_of(state.uniforms))
    for _, pipeline in state.vulkan_pass.pipelines {
        // NOTE(jan): Assume that descriptor set 0 is always uniforms.
        gfx.vulkan_descriptor_update_uniform(vulkan, pipeline.descriptor_sets[0], 0, state.uniform_buffer);
    }

    // NOTE(jan): Upload texture if necessary.
    if (state.sprite_sheet.handle == 0) {
        sprite_sheet_path := path.join({".", "textures", "tinyrts.png"}, context.temp_allocator)
        sprite_sheet_filename, _ := path.to_slash(sprite_sheet_path, context.temp_allocator)
        sprite_sheet_bytes, success := os.read_entire_file_from_filename(sprite_sheet_filename, context.temp_allocator)

        if !success {
            log.errorf("Failed to read file '%s'.", sprite_sheet_filename)
        }  else {
            x, y, n : i32 = 0, 0, 0
            sprite_sheet_pixels := image.load_from_memory(raw_data(sprite_sheet_bytes), i32(len(sprite_sheet_bytes)), &x, &y, &n, 4)

            if sprite_sheet_pixels == nil {
                log.errorf("Could not read PNG file '%s'.", sprite_sheet_filename)
            } else {
                extent := vk.Extent2D { u32(x), u32(y) }
                size := extent.height * extent.width * u32(n)

                pixels: []u8 = sprite_sheet_pixels[0:size]

                state.sprite_sheet = gfx.vulkan_image_create_2d_rgba_texture(vulkan, extent)
                gfx.vulkan_image_update_texture(
                    vulkan,
                    cmd,
                    pixels,
                    state.sprite_sheet,
                )
                image.image_free(sprite_sheet_pixels)

                state.tile_width = 8.0 * state.zoom
                state.tile_height = 8.0 * state.zoom

                state.sprite_width = 8.0 / f32(extent.width)
                state.sprite_height = 8.0 / f32(extent.height)
            }
        }
    }
    
    // NOTE(jan): Update sampler.
    textured_pipeline := state.vulkan_pass.pipelines["textured"] or_else panic("No textured pipeline")
    gfx.vulkan_descriptor_update_combined_image_sampler(
        vulkan,
        textured_pipeline.descriptor_sets[0],
        1,
        []gfx.VulkanImage { state.sprite_sheet },
        state.sampler,
    )

	// NOTE(jan): Upload meshes.
    gfx.vulkan_mesh_reset(&state.colored_mesh)
    gfx.vulkan_mesh_reset(&state.textured_mesh)

    draw(vulkan, state, request.events, request.input_state)

    gfx.vulkan_mesh_upload(vulkan, &state.colored_mesh)
	gfx.vulkan_mesh_upload(vulkan, &state.textured_mesh)
}

draw_frame :: proc (state: ^MapEditorState, request: programs.DrawFrame) {
    cmd := request.cmd
    vulkan := request.vulkan
    vulkan_pass := state.vulkan_pass

    clears := [?]vk.ClearValue {
        vk.ClearValue { color = { float32 = gfx.gray }},
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
        assert("colored" in vulkan_pass.pipelines)
        pipeline := vulkan_pass.pipelines["colored"]
        vk.CmdBindPipeline(cmd, vk.PipelineBindPoint.GRAPHICS, pipeline.handle)
        vk.CmdBindDescriptorSets(
            cmd,
            vk.PipelineBindPoint.GRAPHICS,
            pipeline.layout,
            0, u32(len(pipeline.descriptor_sets)),
            raw_data(pipeline.descriptor_sets),
            0, nil,
        )
        gfx.vulkan_mesh_bind(cmd, &state.colored_mesh)
        vk.CmdDrawIndexed(cmd, u32(len(state.colored_mesh.indices)), 1, 0, 0, 0)
    }

    // NOTE(jan): Draw textured stuff.
    {
        assert("textured" in vulkan_pass.pipelines)
        pipeline := vulkan_pass.pipelines["textured"]
        vk.CmdBindPipeline(cmd, vk.PipelineBindPoint.GRAPHICS, pipeline.handle)
        vk.CmdBindDescriptorSets(
            cmd,
            vk.PipelineBindPoint.GRAPHICS,
            pipeline.layout,
            0, u32(len(pipeline.descriptor_sets)),
            raw_data(pipeline.descriptor_sets),
            0, nil,
        )
        gfx.vulkan_mesh_bind(cmd, &state.textured_mesh)
        vk.CmdDrawIndexed(cmd, u32(len(state.textured_mesh.indices)), 1, 0, 0, 0)
    }

    vk.CmdEndRenderPass(cmd)
}

cleanup_frame :: proc (state: ^MapEditorState, request: programs.CleanupFrame) { }

cleanup :: proc (state: ^MapEditorState, request: programs.Cleanup) {
    if state == nil do return

    vulkan := request.vulkan

    gfx.vulkan_sampler_destroy(vulkan, state.sampler)
    state.sampler = 0

    gfx.vulkan_image_destroy(vulkan, &state.sprite_sheet)
    gfx.vulkan_mesh_destroy(vulkan, &state.colored_mesh)
    gfx.vulkan_mesh_destroy(vulkan, &state.textured_mesh)
    gfx.vulkan_buffer_destroy(vulkan, &state.uniform_buffer)
    gfx.vulkan_pass_destroy(vulkan, &state.vulkan_pass)

    save_map(state)
}

handler :: proc (program: ^programs.Program, request: programs.Request) {
    state := (^MapEditorState)(program.state)

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
            cleanup_frame(state, r)
        case programs.Cleanup:
            cleanup(state, r)
        case:
            panic("unhandled request")
    }
}

make_program :: proc () -> programs.Program {
    return programs.Program {
        name = "map_editor",
        handler = handler,
    }
}
