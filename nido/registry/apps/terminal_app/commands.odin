package terminal_app

import "core:log"
import "core:mem"
import "core:strings"

import "../../../app"
import "../../../font"
import "../../../gfx"
import fe "../../../gfx/simple_2d_front_end"

emit_commands :: proc (a: ^app.App, events: []app.Event, input_state: app.InputState) -> (result: app.CommandList) {
    cmds: ^fe.CommandList
    {
        // NOTE(jan): Commands only live for one frame.
        context.allocator = context.temp_allocator
        cmds = fe.make_list()
    }

    result.type = "simple_2d_front_end"
    result.list = cast(rawptr)cmds

    state := cast(^Terminal)a.state

    if input_state.key_down.f1 == true {
        state.show = !state.show
    }

    if state.show == false {
        return
    }

    if state.sprite_sheet_handle == nil {
        state.sprite_sheet_handle = fe.cmd_register_texture(cmds)
    }

    // NOTE(jan): Handle input.
    scroll_d := state.top_down == true ? -1 : 1
    if input_state.key_down.page_up == true do state.line_offset += 4 * scroll_d
    if input_state.key_down.page_down == true do state.line_offset -= 4 * scroll_d
    if input_state.key_down.home == true {
        state.top_down = true
        state.line_offset = 0
    }
    if input_state.key_down.end == true {
        state.top_down = false
        state.line_offset = 0
    }
    if input_state.key_down.up == true {
        if state.top_down && (state.line_offset > 0) do state.line_offset -= 1
        if !state.top_down do state.line_offset += 1
    }
    if input_state.key_down.down == true {
        // TODO(jan): ???
    }

    if state.line_offset < 0 do state.line_offset = 0

    max_x := f32(input_state.screen.x)
    max_y := f32(input_state.screen.y)
    fe.cmd_draw_box(cmds, { { 0, 0 }, { max_x, max_y / 2 } }, gfx.base03, 0.98)

    default_font := font.get_font(state.fonts[:], "default")
    version := default_font.versions[0]
    
    // NOTE(jan): Repack.
    if state.repack_required {
        bitmap, width, height, ok := font.pack_fonts_into_texture(state.fonts)
        if !ok {
            log.panicf("Could not load font bitmap.")
        }
        fe.cmd_update_texture_from_bitmap(cmds, state.sprite_sheet_handle.?, bitmap[:], u32(width), u32(height), 1);

        state.repack_required = false
    }

    // TODO(jan): This isn't quite right. Should read current size #bytes from current read pointer
    ring_buffer_start := cast(^u8)state.log_data.ring_buffer
    ring_buffer_top := mem.ptr_offset(ring_buffer_start, state.log_data.top)
    end_index := cast(int)state.log_data.bottom
    log := strings.string_from_ptr(ring_buffer_start, end_index)

    // TODO(jan): Maybe this moves to the back end and we just say which glyphs to draw.
    // NOTE(jan): Compute text spans.
    text_spans := make([dynamic]font.TextSpan, context.temp_allocator)
    lines_to_skip := state.line_offset
    line_length := cast(f32)input_state.screen.x - 10
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

            {
                context.allocator = context.temp_allocator
                font.translate_span(&text_span)
                repack_required := font.layout_span(default_font, &version, &text_span)
                if repack_required do state.repack_required = true
            }

            baseline += text_span.extent.y
            append(&text_spans, text_span)

            if baseline > cast(f32)input_state.screen.y do break
            line_start = index + 1
        }
    } else {
        // NOTE(jan): Bottom-up, default and used END is pressed to go to the end of the buffer.
        baseline := cast(f32)input_state.screen.y
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
                
                {
                    context.allocator = context.temp_allocator
                    font.translate_span(&text_span)
                    repack_required := font.layout_span(default_font, &version, &text_span)
                    if repack_required do state.repack_required = true
                }

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
    y: f32 = f32(input_state.screen.y) / 2.0 - 10
    if state.top_down == true do y = version.size
    for span in text_spans {
        y -= span.baseline_offset * f32(scroll_d)

        for glyph in span.glyphs {
            q := glyph.quad

            fe.cmd_draw_glyph(cmds, state.sprite_sheet_handle.?, { {q.x0 + x, q.y0 + y}, {q.x1 - q.x0, q.y1 - q.y0} }, { {q.s0, q.t0}, {q.s1 - q.s0, q.t1 - q.t0} }, gfx.base0.rgb, 0.99)
        }
    
        y -= version.size * f32(scroll_d)
    }

    return
}
