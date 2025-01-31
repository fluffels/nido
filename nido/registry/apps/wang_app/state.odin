package wang_app

import "../../../gfx"

WangTileColor :: enum {
    GREEN = 0,
    RED,
    BLUE,
    WHITE,
    BLACK,
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
//     gfx.black,
// }

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

// NOTE(jan): 11 tile set
// wang_tiles := []WangTile {
//     WangTile { WangTileColor.RED, WangTileColor.RED, WangTileColor.RED, WangTileColor.GREEN },
//     WangTile { WangTileColor.BLUE, WangTileColor.RED, WangTileColor.BLUE, WangTileColor.GREEN },
//     WangTile { WangTileColor.RED, WangTileColor.GREEN, WangTileColor.GREEN, WangTileColor.GREEN },
//     WangTile { WangTileColor.WHITE, WangTileColor.BLUE, WangTileColor.RED, WangTileColor.BLUE },
//     WangTile { WangTileColor.BLUE, WangTileColor.BLUE, WangTileColor.WHITE, WangTileColor.BLUE },
//     WangTile { WangTileColor.WHITE, WangTileColor.WHITE, WangTileColor.RED, WangTileColor.WHITE },
//     WangTile { WangTileColor.RED, WangTileColor.GREEN, WangTileColor.BLUE, WangTileColor.WHITE },
//     WangTile { WangTileColor.BLUE, WangTileColor.WHITE, WangTileColor.BLUE, WangTileColor.RED },
//     WangTile { WangTileColor.BLUE, WangTileColor.RED, WangTileColor.WHITE, WangTileColor.RED },
//     WangTile { WangTileColor.GREEN, WangTileColor.GREEN, WangTileColor.BLUE, WangTileColor.RED },
//     WangTile { WangTileColor.RED, WangTileColor.WHITE, WangTileColor.RED, WangTileColor.GREEN },
// }

// NOTE(jan): Custom 16 tile set
// wang_tiles := []WangTile {
//     // Base tiles with single color edges
//     WangTile{WangTileColor.RED, WangTileColor.RED, WangTileColor.RED, WangTileColor.RED},
//     WangTile{WangTileColor.BLUE, WangTileColor.BLUE, WangTileColor.BLUE, WangTileColor.BLUE},
//     WangTile{WangTileColor.GREEN, WangTileColor.GREEN, WangTileColor.GREEN, WangTileColor.GREEN},
//     WangTile{WangTileColor.WHITE, WangTileColor.WHITE, WangTileColor.WHITE, WangTileColor.WHITE},
    
//     // Mixed pairs
//     WangTile{WangTileColor.RED, WangTileColor.BLUE, WangTileColor.RED, WangTileColor.BLUE},
//     WangTile{WangTileColor.BLUE, WangTileColor.RED, WangTileColor.BLUE, WangTileColor.RED},
//     WangTile{WangTileColor.GREEN, WangTileColor.WHITE, WangTileColor.GREEN, WangTileColor.WHITE},
//     WangTile{WangTileColor.WHITE, WangTileColor.GREEN, WangTileColor.WHITE, WangTileColor.GREEN},
    
//     // Corner transitions
//     WangTile{WangTileColor.RED, WangTileColor.RED, WangTileColor.GREEN, WangTileColor.GREEN},
//     WangTile{WangTileColor.BLUE, WangTileColor.BLUE, WangTileColor.WHITE, WangTileColor.WHITE},
//     WangTile{WangTileColor.GREEN, WangTileColor.GREEN, WangTileColor.BLUE, WangTileColor.BLUE},
//     WangTile{WangTileColor.WHITE, WangTileColor.WHITE, WangTileColor.RED, WangTileColor.RED},
    
//     // Complex transitions
//     WangTile{WangTileColor.RED, WangTileColor.GREEN, WangTileColor.BLUE, WangTileColor.WHITE},
//     WangTile{WangTileColor.BLUE, WangTileColor.WHITE, WangTileColor.GREEN, WangTileColor.RED},
//     WangTile{WangTileColor.GREEN, WangTileColor.BLUE, WangTileColor.WHITE, WangTileColor.RED},
//     WangTile{WangTileColor.WHITE, WangTileColor.RED, WangTileColor.BLUE, WangTileColor.GREEN},
// }

// wang_tiles := []WangTile {
// }

WangAppState:: struct { }
