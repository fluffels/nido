package tile_app

import "core:log"
import "core:mem"
import "core:strings"
import "core:math/rand"

import "../../../app"
import "../../../font"
import "../../../gfx"
import fe "../../../gfx/simple_2d_front_end"

adjust_color_brightness :: proc(color: [4]f32, percent: f32) -> [4]f32 {
    p := clamp(percent, -100, 100)
    factor := 1.0 + (p / 100.0)
    
    return [4]f32{
        clamp(color[0] * factor, 0, 1),
        clamp(color[1] * factor, 0, 1),
        clamp(color[2] * factor, 0, 1),
        color[3],
    }
}

rand_blueish_color :: proc() -> gfx.Color {
    return gfx.Color {
        rand.float32() * 0.3,
        rand.float32() * 0.3,
        rand.float32() * 0.5 + 0.5,
        1.0,
    }
}

calc_perceived_brightness :: proc(color: [4]f32) -> f32 {
    return 0.2126 * color[0] + 0.7152 * color[1] + 0.0722 * color[2]
}

draw_tile :: proc(cmds: ^fe.CommandList, pos: [2]f32, size: [2]f32, tile: Tile, tile_length: f32) {
    f : f32 = 0

    left := pos[0] + f
    right := pos[0] + size[0] - f
    top := pos[1] + f
    bottom := pos[1] + size[1] - f

    top_left := [2]f32{ left, top }
    top_right := [2]f32{ right, top }
    bottom_right := [2]f32{ right, bottom }
    bottom_left := [2]f32{ left, bottom }
    middle := [2]f32{ (left + right) / 2, (top + bottom) / 2 }

    g : f32 = tile_length / 10
    fe.cmd_draw_triangle(cmds, { { left + g, top }, { right - g, top }, { middle.x, middle.y - g } }, tile.colors[Directions.NORTH], 0.99)
    fe.cmd_draw_triangle(cmds, { { right, top + g }, { right, bottom - g }, { middle.x + g, middle.y } }, tile.colors[Directions.EAST], 0.99)
    fe.cmd_draw_triangle(cmds, { { right - g, bottom }, { left + g, bottom }, { middle.x, middle.y + g } }, tile.colors[Directions.SOUTH], 0.99)
    fe.cmd_draw_triangle(cmds, { { left, bottom - g }, { left, top + g }, { middle.x - g, middle.y } }, tile.colors[Directions.WEST], 0.99)
    // fe.cmd_draw_triangle(cmds, { top_right, bottom_right, middle }, tile.colors[Directions.EAST], 0.99)
    // fe.cmd_draw_triangle(cmds, { bottom_right, bottom_left, middle }, tile.colors[Directions.SOUTH], 0.99)
    // fe.cmd_draw_triangle(cmds, { bottom_left, top_left, middle }, tile.colors[Directions.WEST], 0.99)
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

    state := cast(^State)a.state


    max_x := f32(input_state.screen.x)
    max_y := f32(input_state.screen.y)

    fe.cmd_draw_box(cmds, { [2]f32{0, 0}, [2]f32{max_x, max_y} }, {0, 0, 0, 1.0}, 0.0)

    if max_x > max_y do max_x = max_y
    if max_y > max_x do max_y = max_x

    tile_length := max_x / f32(state.tiles_per_side)
    
    tile_size := [2]f32{ tile_length, tile_length }
    for x in 0..<state.tiles_per_side {
        for y in 0..<state.tiles_per_side {
            tile_index := x + y * state.tiles_per_side
            tile := state.tiles[tile_index]
            pos := [2]f32{ f32(x) * tile_length, f32(y) * tile_length }
            draw_tile(cmds, pos, tile_size, tile, tile_length)
            for dir in 0..<int(Directions.MAX) {
                state.tiles[tile_index].colors[dir] = adjust_color_brightness(tile.colors[dir], -0.1)
            }
        }
    }

    for &worm in state.worms {
        tile_index := worm.tile[0] + worm.tile[1] * state.tiles_per_side
        tile := &state.tiles[tile_index]
        color := tile.colors[worm.direction]
        // color_adjust := rand.int_max(2) == 0 ? -10 : 10
        // tile.colors[worm.direction] = adjust_color_brightness(color, f32(color_adjust))
        tile.colors[worm.direction] = state.orig[tile_index].colors[worm.direction]
        if (worm.direction == Directions.NORTH) && (worm.tile.y > 0) {
            paired_tile := &state.tiles[worm.tile.x + (worm.tile.y - 1) * state.tiles_per_side]
            paired_dir := Directions.SOUTH
            paired_tile.colors[paired_dir] = tile.colors[worm.direction]
            // paired_tile.colors[paired_dir] = adjust_color_brightness(paired_tile.colors[paired_dir], f32(color_adjust))
        } else if (worm.direction == Directions.EAST) && (worm.tile.x < state.tiles_per_side - 1) {
            paired_tile := &state.tiles[worm.tile.x + 1 + worm.tile.y * state.tiles_per_side]
            paired_dir := Directions.WEST
            paired_tile.colors[paired_dir] = tile.colors[worm.direction]
            // paired_tile.colors[paired_dir] = adjust_color_brightness(paired_tile.colors[paired_dir], f32(color_adjust))
        } else if (worm.direction == Directions.SOUTH) && (worm.tile.y < state.tiles_per_side - 1) {
            paired_tile := &state.tiles[worm.tile.x + (worm.tile.y + 1) * state.tiles_per_side]
            paired_dir := Directions.NORTH
            paired_tile.colors[paired_dir] = tile.colors[worm.direction]
            // paired_tile.colors[paired_dir] = adjust_color_brightness(paired_tile.colors[paired_dir], f32(color_adjust))
        } else if (worm.direction == Directions.WEST) && (worm.tile.x > 0) {
            paired_tile := &state.tiles[worm.tile.x - 1 + worm.tile.y * state.tiles_per_side]
            paired_dir := Directions.EAST
            paired_tile.colors[paired_dir] = tile.colors[worm.direction]
            // paired_tile.colors[paired_dir] = adjust_color_brightness(paired_tile.colors[paired_dir], f32(color_adjust))
        }
        dir := Directions(rand.int_max(int(Directions.MAX)))
        if dir == worm.direction {
            if (dir == Directions.NORTH) && (worm.tile[1] > 0) {
                worm.tile.y -= 1
                worm.direction = Directions.SOUTH
            } else if (dir == Directions.EAST) && (worm.tile[0] < state.tiles_per_side - 1) {
                worm.tile.x += 1
                worm.direction = Directions.WEST
            } else if (dir == Directions.SOUTH) && (worm.tile[1] < state.tiles_per_side - 1) {
                worm.tile.y += 1
                worm.direction = Directions.NORTH
            } else if (dir == Directions.WEST) && (worm.tile[0] > 0) {
                worm.tile.x -= 1
                worm.direction = Directions.EAST
            }
        } else {
            worm.direction = dir
        }
    }

    // spark_count := rand.int_max(2)
    spark_count := 0
    for i in 0..<spark_count {
        x := rand.int_max(state.tiles_per_side)
        y := rand.int_max(state.tiles_per_side)
        tile_index := x + y * state.tiles_per_side
        tile := &state.tiles[tile_index]
        color := rand_blueish_color()
        dir := Directions(rand.int_max(int(Directions.MAX)))
        tile.colors[dir] = color
        if dir == Directions.NORTH && y > 0 {
            paired_tile := &state.tiles[x + (y - 1) * state.tiles_per_side]
            paired_tile.colors[Directions.SOUTH] = color
        } else if dir == Directions.EAST && x < state.tiles_per_side - 1 {
            paired_tile := &state.tiles[x + 1 + y * state.tiles_per_side]
            paired_tile.colors[Directions.WEST] = color
        } else if dir == Directions.SOUTH && y < state.tiles_per_side - 1 {
            paired_tile := &state.tiles[x + (y + 1) * state.tiles_per_side]
            paired_tile.colors[Directions.NORTH] = color
        } else if dir == Directions.WEST && x > 0 {
            paired_tile := &state.tiles[x - 1 + y * state.tiles_per_side]
            paired_tile.colors[Directions.EAST] = color
        }
    }

    if true && (input_state.ticks % 1 == 0) {
        lowest_brightness := f32(100)
        lowest_tile := [2]int { 0, 0 }
        lowest_dir := Directions.NORTH
        for y in 0..<state.tiles_per_side {
            for x in 0..<state.tiles_per_side {
                tile_index := x + y * state.tiles_per_side
                tile := state.tiles[tile_index]
                for dir in 0..<int(Directions.MAX) {
                    brightness := calc_perceived_brightness(tile.colors[dir])
                    if brightness < lowest_brightness {
                        lowest_brightness = brightness
                        lowest_tile = [2]int { x, y }
                        lowest_dir = Directions(dir)
                    }
                }
            }
        }
        lowest_index := lowest_tile[0] + lowest_tile[1] * state.tiles_per_side
        state.tiles[lowest_index].colors[lowest_dir] = rand_blueish_color()
        if lowest_dir == Directions.NORTH && lowest_tile[1] > 0 {
            paired_tile := &state.tiles[lowest_tile[0] + (lowest_tile[1] - 1) * state.tiles_per_side]
            paired_tile.colors[Directions.SOUTH] = state.tiles[lowest_index].colors[lowest_dir]
        } else if lowest_dir == Directions.EAST && lowest_tile[0] < state.tiles_per_side - 1 {
            paired_tile := &state.tiles[lowest_tile[0] + 1 + lowest_tile[1] * state.tiles_per_side]
            paired_tile.colors[Directions.WEST] = state.tiles[lowest_index].colors[lowest_dir]
        } else if lowest_dir == Directions.SOUTH && lowest_tile[1] < state.tiles_per_side - 1 {
            paired_tile := &state.tiles[lowest_tile[0] + (lowest_tile[1] + 1) * state.tiles_per_side]
            paired_tile.colors[Directions.NORTH] = state.tiles[lowest_index].colors[lowest_dir]
        } else if lowest_dir == Directions.WEST && lowest_tile[0] > 0 {
            paired_tile := &state.tiles[lowest_tile[0] - 1 + lowest_tile[1] * state.tiles_per_side]
            paired_tile.colors[Directions.EAST] = state.tiles[lowest_index].colors[lowest_dir]
        }
    }

    if (false) {
    // if (input_state.ticks % 3 == 0) {
        if state.wave.d == Directions.SOUTH {
            index := state.wave.x
            for index < len(state.tiles) {
                tile := &state.tiles[index]
                tile.colors[Directions.SOUTH] = rand_blueish_color()
                next_index := index + state.tiles_per_side
                if next_index < len(state.tiles) {
                    paired_tile := &state.tiles[next_index]
                    paired_tile.colors[Directions.NORTH] = tile.colors[Directions.SOUTH]
                }
                index = next_index
            }
            state.wave.d = Directions.EAST
        }
        if state.wave.d == Directions.EAST {
            index := state.wave.x
            for index < len(state.tiles) {
                tile := &state.tiles[index]
                tile.colors[Directions.EAST] = rand_blueish_color()
                next_index := index + 1
                if next_index < len(state.tiles) {
                    paired_tile := &state.tiles[next_index]
                    paired_tile.colors[Directions.WEST] = tile.colors[Directions.EAST]
                }
                index += state.tiles_per_side
            }
            state.wave.d = Directions.SOUTH
            state.wave.x = (state.wave.x + 1) % state.tiles_per_side
        }
    }

    return
}
