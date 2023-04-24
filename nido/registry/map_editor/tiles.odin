package map_editor

import "../../gfx"

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

    first_index := state.mesh.vertex_count
    gfx.vulkan_mesh_push_vertices(&state.mesh, vertices)

    append(&state.mesh.indices, first_index + 0)
    append(&state.mesh.indices, first_index + 1)
    append(&state.mesh.indices, first_index + 2)
    append(&state.mesh.indices, first_index + 2)
    append(&state.mesh.indices, first_index + 3)
    append(&state.mesh.indices, first_index + 0)
}
