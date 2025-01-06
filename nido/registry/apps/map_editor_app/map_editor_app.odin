package map_editor_app

import "core:log"
import "core:path/filepath"
import "core:os"

import "vendor:stb/image"

import "../../../app"

MapEditor :: struct {
    scroll_offset: [2]f32,
    map_width: int,
    map_height: int,
    doodads: []int,
    terrain: []int,
    selected_doodad: int,
    selected_sprite: int,
    tile_width: f32,
    tile_height: f32,
    sprite_sheet_extent: [2]f32,
    sprite_width: f32,
    sprite_height: f32,
    zoom: f32,
}

init :: proc(state: ^MapEditor, request: app.Initialize) {
    // NOTE(jan): Misc.
    state.scroll_offset[0] = 0
    state.scroll_offset[1] = 0
    state.selected_doodad = -1
    state.selected_sprite = -1
    state.zoom = 4.0

    // NOTE(jan): Load sprite sheet info.
    sprite_sheet_path := filepath.join({".", "textures", "tinyrts.png"}, context.temp_allocator)
    sprite_sheet_filename, _ := filepath.to_slash(sprite_sheet_path, context.temp_allocator)
    sprite_sheet_bytes, success := os.read_entire_file_from_filename(sprite_sheet_filename, context.temp_allocator)

    if !success {
        log.errorf("Failed to read file '%s'.", sprite_sheet_filename)
    }  else {
        x, y, n : i32 = 0, 0, 0
        sprite_sheet_pixels := image.load_from_memory(raw_data(sprite_sheet_bytes), i32(len(sprite_sheet_bytes)), &x, &y, &n, 4)
        image.image_free(sprite_sheet_pixels)

        state.sprite_sheet_extent.x = f32(x)
        state.sprite_sheet_extent.y = f32(y)

        state.tile_width = 8.0 * state.zoom
        state.tile_height = 8.0 * state.zoom

        state.sprite_width = 8.0 / state.sprite_sheet_extent.x
        state.sprite_height = 8.0 / state.sprite_sheet_extent.y
    }

    // NOTE(jan): Map.
    state.map_width = 256
    state.map_height = 256
    state.doodads = make([]int, state.map_width * state.map_height)
    state.terrain = make([]int, state.map_width * state.map_height)
    for y in 0..<state.map_height {
        for x in 0..<state.map_width {
            state.doodads[y * state.map_width + x] = -1
            state.terrain[y * state.map_width + x] = 0
        }
    }
    load_map(state)

    return
}

cleanup :: proc(state: ^MapEditor, request: app.Cleanup) {
    save_map(state)
}

handler :: proc (a: ^app.App, request: app.Request) {
    state := (^MapEditor)(a.state)

    context.allocator = a.allocator

    switch r in request {
        case app.Initialize:
            state = new(MapEditor)
            init(state, r)
            a.state = state
        case app.Cleanup:
            cleanup(state, r)
        case:
            panic("unhandled request")
    }
}

make_app :: proc () -> app.App {
    return app.App {
        flags = {},
        name = "map_editor",
        handler = handler,
        emit_commands_proc = emit_commands,
    }
}
