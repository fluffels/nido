package wang_app

import "core:log"
import "core:mem"
import "core:strings"
import "core:math/rand"

import "../../../app"
import "../../../font"
import "../../../gfx"
import fe "../../../gfx/simple_2d_front_end"

draw_tile :: proc(cmds: ^fe.CommandList, pos: [2]f32, size: [2]f32, tile: WangTile) {
    top_left := pos
    top_right := [2]f32{ pos[0] + size[0], pos[1] }
    bottom_right := [2]f32{ pos[0] + size[0], pos[1] + size[1] }
    bottom_left := [2]f32{ pos[0], pos[1] + size[1] }
    middle := [2]f32{ pos[0] + size[0] / 2, pos[1] + size[1] / 2 }

    fe.cmd_draw_triangle(cmds, { top_left, top_right, middle }, colors[tile.north], 0.99)
    fe.cmd_draw_triangle(cmds, { top_right, bottom_right, middle }, colors[tile.east], 0.99)
    fe.cmd_draw_triangle(cmds, { bottom_right, bottom_left, middle }, colors[tile.south], 0.99)
    fe.cmd_draw_triangle(cmds, { bottom_left, top_left, middle }, colors[tile.west], 0.99)
}

emit_commands :: proc (a: ^app.App, events: []app.Event, input_state: app.InputState) -> (result: app.CommandList) {
    cmds: ^fe.CommandList
    {
        // NOTE(jan): Commands only live for one frame.
        context.allocator = context.temp_allocator
        cmds = fe.make_list()
    }

    result.type = "simple_2d_front_end"
    result.list = cast(rawptr)cmds

    state := cast(^WangAppState)a.state


    max_x := f32(input_state.screen.x)
    max_y := f32(input_state.screen.y)

    if max_x > max_y do max_x = max_y
    if max_y > max_x do max_y = max_x

    tiles_per_side := 14
    tiles := make([]WangTile, tiles_per_side * tiles_per_side, context.temp_allocator)
    tile_length := max_x / f32(tiles_per_side)

    tile_candidates := make([][dynamic]WangTile, tiles_per_side * tiles_per_side, context.temp_allocator)
    tile_candidates[0] = make([dynamic]WangTile, context.temp_allocator)
    for tile in wang_tiles {
        append(&tile_candidates[0], tile)
    }

    x, y := 0, 0
    for x < tiles_per_side && y < tiles_per_side {
        tile_index := x + y * tiles_per_side

        candidate_count := len(tile_candidates[tile_index])
        if candidate_count == 0 {
            // NOTE(jan): Need to backtrack.
            tile_candidates[tile_index] = nil
            if x > 0 {
                x -= 1
            } else {
                y -= 1
                x = tiles_per_side - 1
            }
            continue
        }

        random_index := rand.int_max(candidate_count)
        chosen_tile := tile_candidates[tile_index][random_index]
        tiles[tile_index] = chosen_tile

        ordered_remove(&tile_candidates[tile_index], random_index)

        // NOTE(jan): Advance
        next_x := x + 1
        next_y := y
        if next_x >= tiles_per_side {
            next_x = 0
            next_y += 1
        }

        if next_y < tiles_per_side {
            next_index := next_x + next_y * tiles_per_side
            
            // Note(jan): Initialize candidates for next position.
            tile_candidates[next_index] = make([dynamic]WangTile, context.temp_allocator)
            north_color := next_y > 0 ? tiles[next_x + (next_y-1) * tiles_per_side].south : WangTileColor.RED
            west_color := next_x > 0 ? tiles[(next_x-1) + next_y * tiles_per_side].east : WangTileColor.RED
            
            for candidate in wang_tiles {
                n := candidate.north
                w := candidate.west
                if ((next_y == 0) || (n == north_color)) && ((next_x == 0) || (w == west_color)) {
                    append(&tile_candidates[next_index], candidate)
                }
            }
        }
    
        x = next_x
        y = next_y
    }
    
    tile_size := [2]f32{ tile_length, tile_length }
    for x in 0..<tiles_per_side {
        for y in 0..<tiles_per_side {
            tile_index := x + y * tiles_per_side
            tile := tiles[tile_index]
            pos := [2]f32{ f32(x) * tile_length, f32(y) * tile_length }
            draw_tile(cmds, pos, tile_size, tile)
        }
    }

    return
}
