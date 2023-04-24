package map_editor

Frame :: struct {
    x: u32,
    y: u32,
}

Animation :: struct {
    frames: []Frame,
    frame_duration: u32,
}

Sprite :: union {
    Frame,
    Animation,
}

TERRAIN_SPRITES := []Frame {
    {0,  0}, {8,  0}, {16,  0}, {24,  0}, {32,  0}, {40,  0}, {48,  0}, {56,  0}, {60,  0}, {72,  0},
    {0,  8}, {8,  8}, {16,  8}, {24,  8}, {32,  8}, {40,  8}, {48,  8}, {56,  8}, {60,  8}, {72,  8},
    {0, 16}, {8, 16}, {16, 16},                     {40, 16}, {48, 16}, {56, 16},

    {40, 56}, {56, 56},
    {40, 72}, {56, 72},
}

RIVER_HORIZONTAL := Animation {
    frames = []Frame {
        {128, 0}, {136, 0}, {144, 0}, {152, 0}, {160, 0}, {168, 0}, {176, 0}, {184, 0},
    },
    frame_duration = 100,
}

RIVER_VERTICAL := Animation {
    frames = []Frame {
        {128, 8}, {136, 8}, {144, 8}, {152, 8}, {160, 8}, {168, 8}, {176, 8}, {184, 8},
    },
    frame_duration = 100,
}

WATER_BOTTOM_LEFT := Animation {
    frames = []Frame {
        {128, 16}, {136, 16}, {144, 16}, {152, 16}, {160, 16}, {168, 16}, {176, 16}, {184, 16},
    },
    frame_duration = 100,
}

SPRITES := []Sprite {
    TERRAIN_SPRITES[0], TERRAIN_SPRITES[1], TERRAIN_SPRITES[2], TERRAIN_SPRITES[3],
    TERRAIN_SPRITES[4], TERRAIN_SPRITES[5], TERRAIN_SPRITES[6], TERRAIN_SPRITES[7],
    TERRAIN_SPRITES[8], TERRAIN_SPRITES[9], TERRAIN_SPRITES[10], TERRAIN_SPRITES[11],
    TERRAIN_SPRITES[12], TERRAIN_SPRITES[13], TERRAIN_SPRITES[14], TERRAIN_SPRITES[15],
    TERRAIN_SPRITES[16], TERRAIN_SPRITES[17], TERRAIN_SPRITES[18], TERRAIN_SPRITES[19],
    TERRAIN_SPRITES[20], TERRAIN_SPRITES[21], TERRAIN_SPRITES[22], TERRAIN_SPRITES[23],
    TERRAIN_SPRITES[24], TERRAIN_SPRITES[25], TERRAIN_SPRITES[26], TERRAIN_SPRITES[27],
    RIVER_HORIZONTAL, RIVER_VERTICAL,
    TERRAIN_SPRITES[28], TERRAIN_SPRITES[29],
    WATER_BOTTOM_LEFT,
}
