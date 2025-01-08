package map_editor_app

import "core:log"
import "core:math"

import "../../../app"
import "../../../gfx"
import "../../../back_end"
import fe "../../../gfx/simple_2d_front_end"

push_box :: proc(state: ^MapEditor, cmds: ^fe.CommandList, box: gfx.AABox, z: f32, color: gfx.Color) {
    fe.cmd_draw_box(cmds, { { box.left, box.top }, { box.right - box.left, box.bottom - box.top } }, color, z)
}

push_frame :: proc(state: ^MapEditor, cmds: ^fe.CommandList, x0: f32, y0: f32, z: f32, tile: Frame) -> gfx.AABox {
    s0 := f32(tile.x) / state.sprite_sheet_extent.x
    t0 := f32(tile.y) / state.sprite_sheet_extent.y

    fe.cmd_draw_textured_quad(cmds, { { x0, y0 }, { state.tile_width, state.tile_height } }, { { s0, t0 }, { state.sprite_width, state.sprite_height } }, z)

    x1 := x0 + state.tile_width
    y1 := y0 + state.tile_height

    return gfx.AABox {
        left = x0,
        top = y0,
        right = x1,
        bottom = y1,
    }
}

push_sprite :: proc(state: ^MapEditor, cmds: ^fe.CommandList, x0: f32, y0: f32, z: f32, sprite: Sprite, ticks: u32) -> gfx.AABox {
    switch s in sprite {
        case Frame:
            return push_frame(state, cmds, x0, y0, z, s)
        case Animation:
            t := ticks / s.frame_duration
            i := t % u32(len(s.frames))
            frame := s.frames[i]
            return push_frame(state, cmds, x0, y0, z, frame)
    }
    panic("Unknown type")
}

push_doodad :: proc(state: ^MapEditor, cmds: ^fe.CommandList, x0: f32, y0: f32, z: f32, doodad: Doodad, ticks: u32) -> gfx.AABox {
    result := gfx.AABox {
        left = x0,
        right = x0,
        top = y0,
        bottom = y0,
    }

    switch s in doodad.sprite {
        case Frame:
            for y in 0..<doodad.tile_height {
                for x in 0..<doodad.tile_width {
                    f := Frame {
                        x = s.x + u32(x * 8),
                        y = s.y + u32(y * 8),
                    }
                    x := x0 + f32(x) * state.tile_width
                    y := y0 + f32(y) * state.tile_height
                    box := push_frame(state, cmds, x, y, z, f)
                    result.left  = math.min(result.left, box.left)
                    result.right = math.max(result.right, box.right)
                    result.top    = math.min(result.top, box.top)
                    result.bottom = math.max(result.bottom, box.bottom)
                }
            }
        case Animation:
            panic("Not handled")
    }

    return result
}

clicked :: proc (box: gfx.AABox, events: []app.Event) -> bool {
    for event in events {
        #partial switch e in event {
            case app.Click:
                if (e.x >= box.left) && (e.x <= box.right) && (e.y >= box.top) && (e.y <= box.bottom) do return true
        }
    }

    return false
}

mouse_down :: proc (box: gfx.AABox, mouse: app.Mouse) -> bool {
    return mouse.left && (mouse.pos.x >= box.left) && (mouse.pos.x <= box.right) && (mouse.pos.y >= box.top) && (mouse.pos.y <= box.bottom)
}

mouse_down_middle :: proc (box: gfx.AABox, mouse: app.Mouse) -> bool {
    return mouse.middle && (mouse.pos.x >= box.left) && (mouse.pos.x <= box.right) && (mouse.pos.y >= box.top) && (mouse.pos.y <= box.bottom)
}

mouse_down_right :: proc (box: gfx.AABox, mouse: app.Mouse) -> bool {
    return mouse.right && (mouse.pos.x >= box.left) && (mouse.pos.x <= box.right) && (mouse.pos.y >= box.top) && (mouse.pos.y <= box.bottom)
}

mouse_over :: proc (box: gfx.AABox, mouse: app.Mouse) -> bool {
    return (mouse.pos.x >= box.left) && (mouse.pos.x <= box.right) && (mouse.pos.y >= box.top) && (mouse.pos.y <= box.bottom)
}

emit_commands :: proc (a: ^app.App, events: []app.Event, input_state: app.InputState) -> (result: app.CommandList) {
    state := cast(^MapEditor)a.state

    cmds: ^fe.CommandList
    {
        // NOTE(jan): Commands only live for one frame.
        context.allocator = context.temp_allocator
        cmds = fe.make_list()
    }
    result.type = "simple_2d_front_end"
    result.list = cast(rawptr)cmds

    if state.sprite_sheet_handle == nil {
        state.sprite_sheet_handle = fe.cmd_register_texture(cmds)
        fe.cmd_update_texture_from_file_command(cmds, state.sprite_sheet_handle.?, "tinyrts.png")
    }

    max_x := f32(input_state.screen.x)
    max_y := f32(input_state.screen.y)
    fe.cmd_draw_box(cmds, { { 0, 0 }, { max_x, max_y } }, { 1, 0, 1, 1 }, 0)

    map_layer : f32 = 0.1
    ui_layer : f32 = 0.2
    button_layer: f32 = 0.3
    mouse_layer: f32 = 0.4

    // NOTE(jan): UI.
    tile_selector := gfx.AABox {
        left = max_x - 4 * state.tile_width,
        top = 0,
        right = max_x,
        bottom = max_y,
    }
    push_box(state, cmds, tile_selector, ui_layer, gfx.base03)

    {
        x0 := tile_selector.left
        y0 := tile_selector.top

        for sprite, index in SPRITES {
            if index % 4 == 0 {
                x0 = tile_selector.left
                y0 += state.tile_height
            }

            sprite_box := push_sprite(state, cmds, x0, y0, button_layer, sprite, input_state.ticks)
            if clicked(sprite_box, events) {
                state.selected_doodad = -1
                state.selected_sprite = index
            }

            // NOTE(jan): Mouse cursor. 
            if mouse_over(sprite_box, input_state.mouse) do push_sprite(state, cmds, x0, y0, mouse_layer, CURSOR, input_state.ticks)

            x0 += state.tile_width
        }

        x0 = tile_selector.left
        y0 += state.tile_height

        for doodad, index in DOODADS {
            box := push_doodad(state, cmds, x0, y0, button_layer, doodad, input_state.ticks)
            if clicked(box, events) {
                state.selected_doodad = index
                state.selected_sprite = -1
            }

            // NOTE(jan): Mouse cursor. 
            if mouse_over(box, input_state.mouse) do push_sprite(state, cmds, x0, y0, mouse_layer, CURSOR, input_state.ticks)
        }
    }

    // NOTE(jan): Selected tile indicator
    // TODO(jan): This is broken.
    if state.selected_sprite != -1 {
        x := tile_selector.left + state.tile_width * 1.5
        y := tile_selector.top
        sprite := SPRITES[state.selected_sprite]
        push_sprite(state, cmds, x, y, ui_layer, sprite, input_state.ticks)
    }

    // NOTE(jan): Map.
    x_begin := int(state.scroll_offset.x / state.tile_width)
    y_begin := int(state.scroll_offset.y / state.tile_height)
    x_tiles := int(tile_selector.left / state.tile_width) + 1
    y_tiles := int(max_y / state.tile_height) + 1

    for y_index in y_begin..<y_begin+y_tiles {
        for x_index in x_begin..<x_begin+x_tiles {
            x0 := f32(x_index) * state.tile_width - state.scroll_offset[0]
            y0 := f32(y_index) * state.tile_height - state.scroll_offset[1]

            index := y_index * state.map_width + x_index
            if index < 0 do continue
            sprite_type := state.terrain[index]

            sprite := SPRITES[sprite_type]

            sprite_box := push_sprite(state, cmds, x0, y0, map_layer, sprite, input_state.ticks)

            if mouse_down(sprite_box, input_state.mouse) {
                if state.selected_doodad != -1 {
                    state.doodads[y_index * state.map_width + x_index] = state.selected_doodad
                } else if state.selected_sprite != -1 {
                    state.terrain[y_index * state.map_width + x_index] = state.selected_sprite
                }
            }

            if mouse_down_right(sprite_box, input_state.mouse) {
                state.selected_sprite = sprite_type
            }

            // NOTE(jan): Mouse cursor. 
            if mouse_over(sprite_box, input_state.mouse) && !(mouse_over(tile_selector, input_state.mouse)) do push_sprite(state, cmds, x0, y0, ui_layer, CURSOR, input_state.ticks)
        }
    }

    // NOTE(jan): Doodads.
    for y_index in 0..<y_tiles {
        for x_index in 0..<x_tiles {
            x0 := f32(x_index) * state.tile_width
            y0 := f32(y_index) * state.tile_height

            doodad_type := state.doodads[y_index * state.map_width + x_index]
            if (doodad_type != -1) {
                doodad := DOODADS[doodad_type]
                push_doodad(state, cmds, x0, y0, map_layer, doodad, input_state.ticks)
            }
        }
    }
    
    // NOTE(jan): Map scroll.
    time_scale := f32(input_state.slice) / 1000
    key_scroll_scale := 1000 * time_scale
    if input_state.keyboard.left do state.scroll_offset[0] -= key_scroll_scale
    if input_state.keyboard.right do state.scroll_offset[0] += key_scroll_scale
    if input_state.keyboard.up do state.scroll_offset[1] -= key_scroll_scale
    if input_state.keyboard.down do state.scroll_offset[1] += key_scroll_scale

    if state.scroll_offset.x < 0 do state.scroll_offset.x = 0
    if state.scroll_offset.x > f32(state.map_width) * state.tile_width - max_x do state.scroll_offset.x = f32(state.map_width) * state.tile_width - max_x
    if state.scroll_offset.y < 0 do state.scroll_offset.y = 0
    if state.scroll_offset.y > f32(state.map_height) * state.tile_height - max_y do state.scroll_offset.y = f32(state.map_height) * state.tile_height - max_y

    map_box := gfx.AABox {
        left = 0,
        top = 0,
        right = tile_selector.left,
        bottom = max_y,
    }

    if mouse_down_middle(map_box, input_state.mouse) {
        mouse_scroll_scale := -50 * time_scale
        state.scroll_offset += input_state.mouse.delta * mouse_scroll_scale
    }

    return
}
