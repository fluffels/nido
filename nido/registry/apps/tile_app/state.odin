package tile_app

import "../../../gfx"

Directions :: enum {
    NORTH = 0,
    EAST,
    SOUTH,
    WEST,
    MAX,
}

Tile :: struct {
    colors: [4]gfx.Color,
}

Worm :: struct {
    tile: [2]int,
    direction: Directions,
}

State :: struct {
    orig: []Tile,
    tiles: []Tile,
    worms: []Worm,
    tiles_per_side: int,
}
