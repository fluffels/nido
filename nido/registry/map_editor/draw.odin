package map_editor

import "../../gfx"
import "../../programs"

push_box :: proc(state: ^MapEditorState, box: gfx.AABox, color: gfx.Color) {
    vertices := [][][]f32 {
        {
            {box.left, box.top},
            {color[0], color[1], color[2], color[3]},
        },
        {
            {box.right, box.top},
            {color[0], color[1], color[2], color[3]},
        },
        {
            {box.right, box.bottom},
            {color[0], color[1], color[2], color[3]},
        },
        {
            {box.left, box.bottom},
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

push_frame :: proc(state: ^MapEditorState, x0: f32, y0: f32, tile: Frame) -> gfx.AABox {
    x1 := x0 + state.tile_width
    y1 := y0 + state.tile_height

    s0 := f32(tile.x) / f32(state.sprite_sheet.extent.width)
    s1 := s0 + state.sprite_width

    t0 := f32(tile.y) / f32(state.sprite_sheet.extent.height)
    t1 := t0 + state.sprite_height

    vertices := [][][]f32 {
        {
            {x0, y0},
            {s0, t0},
        },
        {
            {x1, y0},
            {s1, t0},
        },
        {
            {x1, y1},
            {s1, t1},
        },
        {
            {x0, y1},
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

push_sprite :: proc(state: ^MapEditorState, x0: f32, y0: f32, sprite: Sprite, ticks: u32) -> gfx.AABox {
    switch s in sprite {
        case Frame:
            return push_frame(state, x0, y0, s)
        case Animation:
            t := ticks / s.frame_duration
            i := t % u32(len(s.frames))
            frame := s.frames[i]
            return push_frame(state, x0, y0, frame)
    }
    panic("Unknown type")
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
    return mouse.left && (mouse.x >= box.left) && (mouse.x <= box.right) && (mouse.y >= box.top) && (mouse.y <= box.bottom)
}

draw :: proc (vulkan: ^gfx.Vulkan, state: ^MapEditorState, events: []programs.Event, input_state: programs.InputState) {
    max_x := f32(vulkan.swap.extent.width)
    max_y := f32(vulkan.swap.extent.height)

    // NOTE(jan): UI.
    tile_selector := gfx.AABox {
        left = max_x - 4 * state.tile_width,
        top = 0,
        right = max_x,
        bottom = max_y,
    }
    push_box(state, tile_selector, gfx.base03)

    {
        x0 := tile_selector.left
        y0 := tile_selector.top

        for sprite, index in SPRITES {
            if index % 4 == 0 {
                x0 = tile_selector.left
                y0 += state.tile_height
            }

            sprite_box := push_sprite(state, x0, y0, sprite, input_state.ticks)
            if clicked(sprite_box, events) do state.selected_sprite = index

            x0 += state.tile_width
        }
    }

    // NOTE(jan): Selected tile indicator
    {
        x := tile_selector.left + state.tile_width * 1.5
        y := tile_selector.top
        sprite := SPRITES[state.selected_sprite]
        push_sprite(state, x, y, sprite, input_state.ticks)
    }

    // NOTE(jan): Map.
    x_tiles := int(tile_selector.left / state.tile_width)
    y_tiles := int(max_y / state.tile_height)
    for y_index in 0..<y_tiles {
        for x_index in 0..<x_tiles {
            x0 := f32(x_index) * state.tile_width
            y0 := f32(y_index) * state.tile_height
            sprite_type := state.terrain[y_index * state.map_width + x_index]
            sprite := SPRITES[sprite_type]

            sprite_box := push_sprite(state, x0, y0, sprite, input_state.ticks)

            if mouse_down(sprite_box, input_state.mouse) do state.terrain[y_index * state.map_width + x_index] = state.selected_sprite
        }
    }
}
