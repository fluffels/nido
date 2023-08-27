package map_editor

import "core:log"
import "core:math"

import "../../gfx"
import "../../programs"

push_box :: proc(state: ^MapEditorState, box: gfx.AABox, z: f32, color: gfx.Color) {
    vertices := [][][]f32 {
        {
            {box.left, box.top, z},
            {color[0], color[1], color[2], color[3]},
        },
        {
            {box.right, box.top, z},
            {color[0], color[1], color[2], color[3]},
        },
        {
            {box.right, box.bottom, z},
            {color[0], color[1], color[2], color[3]},
        },
        {
            {box.left, box.bottom, z},
            {color[0], color[1], color[2], color[3]},
        },
    }

    first_index := state.colored_mesh.vertex_count
    gfx.vulkan_mesh_push_vertices(&state.colored_mesh, vertices)

    append(&state.colored_mesh.indices, first_index + 0)
    append(&state.colored_mesh.indices, first_index + 1)
    append(&state.colored_mesh.indices, first_index + 2)
    append(&state.colored_mesh.indices, first_index + 2)
    append(&state.colored_mesh.indices, first_index + 3)
    append(&state.colored_mesh.indices, first_index + 0)
}

push_frame :: proc(state: ^MapEditorState, x0: f32, y0: f32, z: f32, tile: Frame) -> gfx.AABox {
    x1 := x0 + state.tile_width
    y1 := y0 + state.tile_height

    s0 := f32(tile.x) / f32(state.sprite_sheet.extent.width)
    s1 := s0 + state.sprite_width

    t0 := f32(tile.y) / f32(state.sprite_sheet.extent.height)
    t1 := t0 + state.sprite_height

    vertices := [][][]f32 {
        {
            {x0, y0, z},
            {s0, t0},
        },
        {
            {x1, y0, z},
            {s1, t0},
        },
        {
            {x1, y1, z},
            {s1, t1},
        },
        {
            {x0, y1, z},
            {s0, t1},
        },
    }

    first_index := state.textured_mesh.vertex_count
    gfx.vulkan_mesh_push_vertices(&state.textured_mesh, vertices)

    append(&state.textured_mesh.indices, first_index + 0)
    append(&state.textured_mesh.indices, first_index + 1)
    append(&state.textured_mesh.indices, first_index + 2)
    append(&state.textured_mesh.indices, first_index + 2)
    append(&state.textured_mesh.indices, first_index + 3)
    append(&state.textured_mesh.indices, first_index + 0)

    return gfx.AABox {
        left = x0,
        top = y0,
        right = x1,
        bottom = y1,
    }
}

push_sprite :: proc(state: ^MapEditorState, x0: f32, y0: f32, z: f32, sprite: Sprite, ticks: u32) -> gfx.AABox {
    switch s in sprite {
        case Frame:
            return push_frame(state, x0, y0, z, s)
        case Animation:
            t := ticks / s.frame_duration
            i := t % u32(len(s.frames))
            frame := s.frames[i]
            return push_frame(state, x0, y0, z, frame)
    }
    panic("Unknown type")
}

push_doodad :: proc(state: ^MapEditorState, x0: f32, y0: f32, z: f32, doodad: Doodad, ticks: u32) -> gfx.AABox {
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
                    box := push_frame(state, x, y, z, f)
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

clicked :: proc (box: gfx.AABox, events: []programs.Event) -> bool {
    for event in events {
        #partial switch e in event {
            case programs.Click:
                if (e.x >= box.left) && (e.x <= box.right) && (e.y >= box.top) && (e.y <= box.bottom) do return true
        }
    }

    return false
}

mouse_down :: proc (box: gfx.AABox, mouse: programs.Mouse) -> bool {
    return mouse.left && (mouse.pos.x >= box.left) && (mouse.pos.x <= box.right) && (mouse.pos.y >= box.top) && (mouse.pos.y <= box.bottom)
}

mouse_down_middle :: proc (box: gfx.AABox, mouse: programs.Mouse) -> bool {
    return mouse.middle && (mouse.pos.x >= box.left) && (mouse.pos.x <= box.right) && (mouse.pos.y >= box.top) && (mouse.pos.y <= box.bottom)
}

mouse_down_right :: proc (box: gfx.AABox, mouse: programs.Mouse) -> bool {
    return mouse.right && (mouse.pos.x >= box.left) && (mouse.pos.x <= box.right) && (mouse.pos.y >= box.top) && (mouse.pos.y <= box.bottom)
}

mouse_over :: proc (box: gfx.AABox, mouse: programs.Mouse) -> bool {
    return (mouse.pos.x >= box.left) && (mouse.pos.x <= box.right) && (mouse.pos.y >= box.top) && (mouse.pos.y <= box.bottom)
}

draw :: proc (vulkan: ^gfx.Vulkan, state: ^MapEditorState, events: []programs.Event, input_state: programs.InputState) {
    max_x := f32(vulkan.swap.extent.width)
    max_y := f32(vulkan.swap.extent.height)

    map_layer : f32 = 0.5
    ui_layer : f32 = 0.4
    button_layer: f32 = 0.3
    mouse_layer: f32 = 0.2

    // NOTE(jan): UI.
    tile_selector := gfx.AABox {
        left = max_x - 4 * state.tile_width,
        top = 0,
        right = max_x,
        bottom = max_y,
    }
    push_box(state, tile_selector, ui_layer, gfx.base03)

    {
        x0 := tile_selector.left
        y0 := tile_selector.top

        for sprite, index in SPRITES {
            if index % 4 == 0 {
                x0 = tile_selector.left
                y0 += state.tile_height
            }

            sprite_box := push_sprite(state, x0, y0, button_layer, sprite, input_state.ticks)
            if clicked(sprite_box, events) {
                state.selected_doodad = -1
                state.selected_sprite = index
            }

            // NOTE(jan): Mouse cursor. 
            if mouse_over(sprite_box, input_state.mouse) do push_sprite(state, x0, y0, mouse_layer, CURSOR, input_state.ticks)

            x0 += state.tile_width
        }

        x0 = tile_selector.left
        y0 += state.tile_height

        for doodad, index in DOODADS {
            box := push_doodad(state, x0, y0, button_layer, doodad, input_state.ticks)
            if clicked(box, events) {
                state.selected_doodad = index
                state.selected_sprite = -1
            }

            // NOTE(jan): Mouse cursor. 
            if mouse_over(box, input_state.mouse) do push_sprite(state, x0, y0, mouse_layer, CURSOR, input_state.ticks)
        }
    }

    // NOTE(jan): Selected tile indicator
    // TODO(jan): This is broken.
    if state.selected_sprite != -1 {
        x := tile_selector.left + state.tile_width * 1.5
        y := tile_selector.top
        sprite := SPRITES[state.selected_sprite]
        push_sprite(state, x, y, ui_layer, sprite, input_state.ticks)
    }

    // NOTE(jan): Map.
    // PERF(jan): Only draw displayed tiles.
    // x_tiles := int(tile_selector.left / state.tile_width) + 1
    // y_tiles := int(max_y / state.tile_height) + 1
    x_tiles := state.map_width
    y_tiles := state.map_height

    for y_index in 0..<y_tiles {
        for x_index in 0..<x_tiles {
            x0 := f32(x_index) * state.tile_width - state.scroll_offset[0]
            y0 := f32(y_index) * state.tile_height - state.scroll_offset[1]
            sprite_type := state.terrain[y_index * state.map_width + x_index]
            sprite := SPRITES[sprite_type]

            sprite_box := push_sprite(state, x0, y0, map_layer, sprite, input_state.ticks)

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
            if mouse_over(sprite_box, input_state.mouse) && !(mouse_over(tile_selector, input_state.mouse)) do push_sprite(state, x0, y0, ui_layer, CURSOR, input_state.ticks)
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
                push_doodad(state, x0, y0, map_layer, doodad, input_state.ticks)
            }
        }
    }
    
    // NOTE(jan): Map scroll.
    // TODO(jan): Figure out why scrolling seems so choppy.
    time_scale := f32(input_state.slice) / 1000
    key_scroll_scale := 1000 * time_scale
    if input_state.keyboard.left do state.scroll_offset[0] -= key_scroll_scale
    if input_state.keyboard.right do state.scroll_offset[0] += key_scroll_scale
    if input_state.keyboard.up do state.scroll_offset[1] -= key_scroll_scale
    if input_state.keyboard.down do state.scroll_offset[1] += key_scroll_scale

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
}
