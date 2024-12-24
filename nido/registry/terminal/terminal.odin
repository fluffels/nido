package terminal

import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import "core:strings"

import vk "vendor:vulkan"

import "../../font"
import "../../gfx"
import "../../logext"
import "../../programs"

import "core:unicode/utf8"

Uniforms :: struct {
	ortho: gfx.mat4x4,
}

TerminalState :: struct {
    top_down: b32,
    line_offset: int,

    log_data: ^logext.Circular_Buffer_Logger_Data,
    fonts: [dynamic]font.Font,
    font_bitmap: []u8,
    font_sprite_sheet: gfx.VulkanImage,

    repack_required: b32,

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
                "ortho_xy_uv_rgb",
                "sampler_as_coverage",
            },
        },
    },
}

VERTEX_DESCRIPTION := gfx.VertexDescription {
    name = "terminal_vertex",
    attributes = []gfx.VertexAttributeDescription {
        {
            component_count = 2,
        },
        {
            component_count = 2,
        },
        {
            component_count = 3,
        },
    },
}

init :: proc (
    state: ^TerminalState,
    request: programs.Initialize,
) -> (
    new_state: ^TerminalState
) {
    allocator := request.allocator
    context.allocator = allocator
    vulkan := request.vulkan

    new_state = new(TerminalState)

    new_state.log_data = cast(^logext.Circular_Buffer_Logger_Data)request.user_data

    // NOTE(jan): Uniforms containing orthographic / perspective projection.
	gfx.ortho_stacked(vulkan.swap.extent.width, vulkan.swap.extent.height, &new_state.uniforms.ortho)
	new_state.uniform_buffer = gfx.vulkan_buffer_create_uniform(vulkan, size_of(new_state.uniforms))

    // NOTE(jan): Font.
    new_state.fonts = font.load_fonts()
    bitmap, ok := font.pack_fonts_into_texture(new_state.fonts)
    if !ok {
        fmt.panicf("Could not load font bitmap.")
    }
    // TODO(jan): Ownership?
    new_state.font_bitmap = bitmap[:]

    // NOTE(jan): Sampler for textures.
	new_state.linear_sampler = gfx.vulkan_sampler_create_linear(vulkan)

    // NOTE(jan): Texture.
    // TODO(jan): Store this with the bitmap.
    // NOTE(jan): Initial repack is required.
    new_state.repack_required = true
    extent := vk.Extent2D { 512, 512 }
    size := extent.height * extent.width
	new_state.font_sprite_sheet = gfx.vulkan_image_create_2d_monochrome_texture(vulkan, extent)

    return
}

resize_end :: proc (state: ^TerminalState, request: programs.ResizeEnd) {
    state.vulkan_pass = gfx.vulkan_pass_create(request.vulkan, PASS)
    state.repack_required = true
}

resize_begin :: proc (state: ^TerminalState, request: programs.ResizeBegin) {
    gfx.vulkan_pass_destroy(request.vulkan, &state.vulkan_pass)
}

prepare_frame :: proc (state: ^TerminalState, request: programs.PrepareFrame) {
    cmd := request.cmd
    vulkan := request.vulkan

    assert("textured" in state.vulkan_pass.pipelines)
    pipeline := state.vulkan_pass.pipelines["textured"]

    // NOTE(jan): Handle input.
    scroll_d := state.top_down == true ? -1 : 1
    if request.input_state.key_down.page_up == true do state.line_offset += 4 * scroll_d
    if request.input_state.key_down.page_down == true do state.line_offset -= 4 * scroll_d
    if request.input_state.key_down.home == true {
        state.top_down = true
        state.line_offset = 0
    }
    if request.input_state.key_down.end == true {
        state.top_down = false
        state.line_offset = 0
    }
    if request.input_state.key_down.up == true {
        if state.top_down && (state.line_offset > 0) do state.line_offset -= 1
        if !state.top_down do state.line_offset += 1
    }
    if request.input_state.key_down.down == true {
    }

    if state.line_offset < 0 do state.line_offset = 0

    // NOTE(jan): Update uniforms.
	gfx.ortho_stacked(vulkan.swap.extent.width, vulkan.swap.extent.height, &state.uniforms.ortho)
    gfx.vulkan_memory_copy(vulkan, state.uniform_buffer, &state.uniforms, size_of(state.uniforms))
    gfx.vulkan_descriptor_update_uniform(vulkan, pipeline.descriptor_sets[0], 0, state.uniform_buffer);

    // NOTE(jan): Update sampler.
    if state.repack_required {
        // TODO(jan): Delete.
        bitmap, ok := font.pack_fonts_into_texture(state.fonts)
        if !ok {
            fmt.panicf("Could not load font bitmap.")
        }
        // TODO(jan): Ownership?
        state.font_bitmap = bitmap[:]

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

        state.repack_required = false
    }

    // NOTE(jan): Update mesh.
    gfx.vulkan_mesh_destroy(vulkan, &state.mesh)
    state.mesh = gfx.vulkan_mesh_create(VERTEX_DESCRIPTION)
    
    // NOTE(jan): Background.
    state.mesh = gfx.vulkan_mesh_create(VERTEX_DESCRIPTION)
    background_color := gfx.base03[:3]
    vertices := [][][]f32 {
        {
            {-1, -1},
            {0, 0},
            background_color,
        },
        {
            {1, -1},
            {1, 0},
            background_color,
        },
        {
            {1, 0},
            {1, 1},
            background_color,
        },
        {
            {-1, 0},
            {0, 1},
            background_color,
        },
    }
    gfx.vulkan_mesh_push_vertices(&state.mesh, vertices)
    append(&state.mesh.indices, 0)
    append(&state.mesh.indices, 1)
    append(&state.mesh.indices, 2)
    append(&state.mesh.indices, 2)
    append(&state.mesh.indices, 3)
    append(&state.mesh.indices, 0)

    default_font := font.get_font(state.fonts[:], "default")
    version := default_font.versions[0]

    // TODO(jan): This isn't quite right. Should read current size #bytes from current read pointer
    ring_buffer_start := cast(^u8)state.log_data.ring_buffer
    ring_buffer_top := mem.ptr_offset(ring_buffer_start, state.log_data.top)
    end_index := cast(int)state.log_data.bottom
    log := strings.string_from_ptr(ring_buffer_start, end_index)

    // NOTE(jan): Compute text spans.
    text_spans := make([dynamic]font.TextSpan, context.temp_allocator)
    lines_to_skip := state.line_offset
    line_length := cast(f32)vulkan.swap.extent.width - 10
    if (state.top_down == true) {
        // NOTE(jan): Top-down, used if we HOME is pressed to go back to the beginning of the buffer.
        // TODO(jan): Wrap to the bottom when we go off the top edge, since the circular buffer isn't circular on that end
        index := 0
        for ; index < len(log); index += 1 {
            if log[index] != '\n' do continue
            else if lines_to_skip == 0 do break
            else do lines_to_skip -= 1
        }
        index += 1
        line_start := index

        baseline := version.size
        for ; index < len(log); index += 1 {
            if log[index] != '\n' do continue

            text_span := font.TextSpan {
                text = log[line_start:index],
                line_length = line_length,
            }

            font.translate_span(&text_span)
            repack_required := font.layout_span(default_font, &version, &text_span)

            if repack_required do state.repack_required = true

            baseline += text_span.extent.y
            append(&text_spans, text_span)

            if baseline > cast(f32)vulkan.swap.extent.height do break
            line_start = index + 1
        }
    } else {
        // NOTE(jan): Bottom-up, default and used END is pressed to go to the end of the buffer.
        baseline := cast(f32)vulkan.swap.extent.height
        for i := len(log) - 1; i >= 0; i -= 1 {
            if log[i] != '\n' do continue

            if lines_to_skip > 0 {
                lines_to_skip -= 1
                continue
            }

            line_end := i
            for j := i - 1; j >= 0; j -= 1 {
                if log[j] != '\n' do continue

                line_start := j + 1
                line := log[line_start:line_end]
                
                text_span := font.TextSpan {
                    text = line,
                    line_length = line_length,
                }
                font.translate_span(&text_span)
                repack_required := font.layout_span(default_font, &version, &text_span)

                if repack_required do state.repack_required = true

                baseline -= text_span.extent.y
                append(&text_spans, text_span)
                break
            }

            if baseline < 0 do break
        }
    }

    // NOTE(jan): Draw spans.
    text_color := gfx.base0[:3]
    x: f32 = 10
    y: f32 = f32(vulkan.swap.extent.height) / 2.0 - 10
    if state.top_down == true do y = version.size
    base_vert_index: u32 = state.mesh.vertex_count
    for span in text_spans {
        y -= span.baseline_offset * f32(scroll_d)

        for glyph in span.glyphs {
            q := glyph.quad
            vertices := [][][]f32 {
                {
                    {q.x0 + x, q.y0 + y},
                    {q.s0, q.t0},
                    text_color,
                },
                {
                    {q.x1 + x, q.y0 + y},
                    {q.s1, q.t0},
                    text_color,
                },
                {
                    {q.x1 + x, q.y1 + y},
                    {q.s1, q.t1},
                    text_color,
                },
                {
                    {q.x0 + x, q.y1 + y},
                    {q.s0, q.t1},
                    text_color,
                },
            }
            gfx.vulkan_mesh_push_vertices(&state.mesh, vertices)

            append(&state.mesh.indices, base_vert_index + 0)
            append(&state.mesh.indices, base_vert_index + 1)
            append(&state.mesh.indices, base_vert_index + 2)
            append(&state.mesh.indices, base_vert_index + 2)
            append(&state.mesh.indices, base_vert_index + 3)
            append(&state.mesh.indices, base_vert_index + 0)
            base_vert_index += 4
        }
    
        y -= version.size * f32(scroll_d)
    }

    gfx.vulkan_mesh_upload(vulkan, &state.mesh)
}

draw_frame :: proc (state: ^TerminalState, request: programs.DrawFrame) {
    cmd := request.cmd
    vulkan := request.vulkan
    vulkan_pass := state.vulkan_pass

    assert("textured" in vulkan_pass.pipelines)
    pipeline := vulkan_pass.pipelines["textured"]

    clears := [?]vk.ClearValue {
        vk.ClearValue { color = { float32 = gfx.base03}},
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

cleanup_frame :: proc (state: ^TerminalState, request: programs.CleanupFrame) { }

cleanup :: proc (state: ^TerminalState, request: programs.Cleanup) {
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
    state := (^TerminalState)(program.state)

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
        name = "terminal",
        handler = handler,
    }
}
