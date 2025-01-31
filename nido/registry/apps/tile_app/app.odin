package tile_app

import "core:math/rand"

import "../../../app"
import "../../../font"
import "../../../logext"

init :: proc(state: ^State, request: app.Initialize) {
    state.tiles_per_side = 20
    state.tiles = make([]Tile, state.tiles_per_side * state.tiles_per_side, context.allocator)
    state.orig = make([]Tile, state.tiles_per_side * state.tiles_per_side, context.allocator)

    for i in 0..<len(state.tiles[0].colors) {
        state.tiles[0].colors[i] = rand_blueish_color()
        state.orig[0].colors[i] = state.tiles[0].colors[i]
    }

    for x in 0..<state.tiles_per_side {
        for y in 0..<state.tiles_per_side {
            tile_index := x + y * state.tiles_per_side
            tile := &state.tiles[tile_index]

            if x > 0 {
                tile.colors[Directions.WEST] = state.tiles[(x-1) + y * state.tiles_per_side].colors[Directions.EAST]
            } else {
                tile.colors[Directions.WEST] = rand_blueish_color()
            }

            if y > 0 {
                tile.colors[Directions.NORTH] = state.tiles[x + (y-1) * state.tiles_per_side].colors[Directions.SOUTH]
            } else {
                tile.colors[Directions.NORTH] = rand_blueish_color()
            }

            tile.colors[Directions.EAST] = rand_blueish_color()
            tile.colors[Directions.SOUTH] = rand_blueish_color()

            for i in 0..<int(Directions.MAX) {
                state.orig[tile_index].colors[i] = tile.colors[i]
            }
        }
    }

    state.worms = make([]Worm, 3, context.allocator)
    for &worm in state.worms {
        worm.tile = [2]int{ rand.int_max(state.tiles_per_side), rand.int_max(state.tiles_per_side) }
        worm.direction = Directions(rand.int_max(int(Directions.MAX)))
    }
}

cleanup :: proc(state: ^State, request: app.Cleanup) { }

handler :: proc (a: ^app.App, request: app.Request) {
    state := (^State)(a.state)

    context.allocator = a.allocator

    switch r in request {
        case app.Initialize:
            state = new(State)
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
        name = "wang",
        handler = handler,
        emit_commands_proc = emit_commands,
    }
}
