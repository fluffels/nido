package map_editor

import "../../gfx"

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

push_tile :: proc(state: ^MapEditorState, x0: f32, y0: f32, tile: SpriteDescription) {
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
}

draw :: proc (vulkan: ^gfx.Vulkan, state: ^MapEditorState) {
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

    for tile, index in TERRAIN_SPRITES {
        x_index := index % 4
        y_index := index / 4

        x0 := tile_selector.left + f32(x_index) * state.tile_width
        y0 := tile_selector.top  + f32(y_index) * state.tile_height

        push_tile(state, x0, y0, tile)
    }

    // NOTE(jan): Map.
    for y_index in 0..<10 {
        for x_index in 0..<10 {
            x0 := f32(x_index) * state.tile_width
            y0 := f32(y_index) * state.tile_height
            tile := TERRAIN_SPRITES[0]

            push_tile(state, x0, y0, tile)
        }
    }
}
