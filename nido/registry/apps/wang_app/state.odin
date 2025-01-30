package wang_app

import "../../../gfx"

WangTileColor :: enum {
    GREEN = 0,
    RED,
    BLUE,
    WHITE,
}

WangTile :: struct {
    north: WangTileColor,
    east: WangTileColor,
    south: WangTileColor,
    west: WangTileColor,
}

// colors := []gfx.Color {
//     gfx.green,
//     gfx.red,
//     gfx.blue,
//     gfx.white,
// }

colors := []gfx.Color {
    gfx.color_from_hex(0xBEE6CE),
    gfx.color_from_hex(0xBCFFDB),
    gfx.color_from_hex(0x8DFFCD),
    gfx.color_from_hex(0x68D89B),
}

wang_tiles := []WangTile {
    WangTile { WangTileColor.RED, WangTileColor.RED, WangTileColor.RED, WangTileColor.GREEN },
    WangTile { WangTileColor.BLUE, WangTileColor.RED, WangTileColor.BLUE, WangTileColor.GREEN },
    WangTile { WangTileColor.RED, WangTileColor.GREEN, WangTileColor.GREEN, WangTileColor.GREEN },
    WangTile { WangTileColor.WHITE, WangTileColor.BLUE, WangTileColor.RED, WangTileColor.BLUE },
    WangTile { WangTileColor.BLUE, WangTileColor.BLUE, WangTileColor.WHITE, WangTileColor.BLUE },
    WangTile { WangTileColor.WHITE, WangTileColor.WHITE, WangTileColor.RED, WangTileColor.WHITE },
    WangTile { WangTileColor.RED, WangTileColor.GREEN, WangTileColor.BLUE, WangTileColor.WHITE },
    WangTile { WangTileColor.BLUE, WangTileColor.WHITE, WangTileColor.BLUE, WangTileColor.RED },
    WangTile { WangTileColor.BLUE, WangTileColor.RED, WangTileColor.WHITE, WangTileColor.RED },
    WangTile { WangTileColor.GREEN, WangTileColor.GREEN, WangTileColor.BLUE, WangTileColor.RED },
    WangTile { WangTileColor.RED, WangTileColor.WHITE, WangTileColor.RED, WangTileColor.GREEN },
}

WangAppState:: struct { }
