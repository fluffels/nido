package map_editor_app

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

Doodad :: struct {
    sprite: Sprite,
    tile_width: int,
    tile_height: int,
}

TERRAIN_SPRITES := []Frame {
    // NOTE(jan): 0 -- 9
    {0,  0}, {8,  0}, {16,  0}, {24,  0}, {32,  0}, {40,  0}, {48,  0}, {56,  0}, {60,  0}, {72,  0},
    // NOTE(jan): 10 -- 19
    {0,  8}, {8,  8}, {16,  8}, {24,  8}, {32,  8}, {40,  8}, {48,  8}, {56,  8}, {60,  8}, {72,  8},
    // NOTE(jan): 20 -- 25
    {0, 16}, {8, 16}, {16, 16},                     {40, 16}, {48, 16}, {56, 16},

    // NOTE(jan): 26-29 (water corners)
    {40, 56}, {56, 56},
    {40, 72}, {56, 72},

    // NOTE(jan): 30 (rocks)
    {48, 64},

    // NOTE(jan): 31-33 water corners
                      {16,  32},
                      {16,  40},                              {48, 40},
    
    // NOTE(jan): 34-44 Misc
    {0, 48},  {8, 48},  {16, 48}, {24, 48},
    {32, 48}, {40, 48}, {48, 48}, {56, 48},
    {64, 48}, {0, 56}, {8, 56},

    // NOTE(jan): 45-57 (Roads).
    {96, 56}, {104, 56}, {112, 56}, {120, 56}, 
    {96, 64},                       {120, 64}, 
    {96, 72},            {112, 72}, {120, 72}, 
    {96, 80}, {104, 80}, {112, 80}, {120, 80},

    // NOTE(jan): 58-66 (Pit).
    {72, 56}, {80, 56}, {88, 56},
    {72, 64}, {80, 64}, {88, 64},
    {72, 72}, {80, 72}, {88, 72},
}

WATERFALL_BOTTOM := Animation {
    frames = []Frame {
        { 128, 48 }, { 136, 48 }, { 144, 48 }, { 152, 48 }, { 160, 48 }, { 168, 48 }, { 176, 48 }, { 184, 48 },
    },
    frame_duration = 100,
}

WATERFALL_TOP := Animation {
    frames = []Frame {
        { 128, 40 }, { 136, 40 }, { 144, 40 }, { 152, 40 }, { 160, 40 }, { 168, 40 }, { 176, 40 }, { 184, 40 },
    },
    frame_duration = 100,
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

CURSOR := Animation {
    frames = []Frame {
        {32, 80}, {40, 80}, {48, 80}, {56, 80}, {64, 80}, {72, 80}, {80, 80}, {88, 80},
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

                                              // NOTE(jan): Water corners.
    TERRAIN_SPRITES[24], TERRAIN_SPRITES[25], TERRAIN_SPRITES[26], TERRAIN_SPRITES[27],
    RIVER_HORIZONTAL, RIVER_VERTICAL,         TERRAIN_SPRITES[28], TERRAIN_SPRITES[29],

    // NOTE(jan): Last row of water stuff.
    WATER_BOTTOM_LEFT, WATERFALL_BOTTOM, WATERFALL_TOP, TERRAIN_SPRITES[30],
                         // NOTE(jan): Pit                                              
    TERRAIN_SPRITES[31], TERRAIN_SPRITES[58], TERRAIN_SPRITES[59], TERRAIN_SPRITES[60],
    TERRAIN_SPRITES[35], TERRAIN_SPRITES[61], TERRAIN_SPRITES[62], TERRAIN_SPRITES[63],
    TERRAIN_SPRITES[39], TERRAIN_SPRITES[64], TERRAIN_SPRITES[65], TERRAIN_SPRITES[66],
    
    // NOTE(jan): Roads
    TERRAIN_SPRITES[45], TERRAIN_SPRITES[46], TERRAIN_SPRITES[47], TERRAIN_SPRITES[48],
    TERRAIN_SPRITES[49], TERRAIN_SPRITES[44], TERRAIN_SPRITES[32], TERRAIN_SPRITES[50],
    TERRAIN_SPRITES[51], TERRAIN_SPRITES[33], TERRAIN_SPRITES[52], TERRAIN_SPRITES[53],
    TERRAIN_SPRITES[54], TERRAIN_SPRITES[55], TERRAIN_SPRITES[56], TERRAIN_SPRITES[57],
    
    
    
    

    // NOTE(jan): Misc.
    TERRAIN_SPRITES[34],
    TERRAIN_SPRITES[36], TERRAIN_SPRITES[37], TERRAIN_SPRITES[38],
    TERRAIN_SPRITES[40], TERRAIN_SPRITES[41], TERRAIN_SPRITES[42],
}

TREE1 := Doodad {
    sprite = Frame {
        x = 0,
        y = 24,
    },
    tile_width = 1,
    tile_height = 3,
}

TREE2 := Doodad {
    sprite = Frame {
        x = 8,
        y = 24,
    },
    tile_width = 1,
    tile_height = 3,
}

TREE3 := Doodad {
    sprite = Frame {
        x = 24,
        y = 24,
    },
    tile_width = 1,
    tile_height = 3,
}

TREE4 := Doodad {
    sprite = Frame {
        x = 24,
        y = 24,
    },
    tile_width = 1,
    tile_height = 3,
}

TREE5 := Doodad {
    sprite = Frame {
        x = 0,
        y = 64,
    },
    tile_width = 1,
    tile_height = 3,
}

TREE6 := Doodad {
    sprite = Frame {
        x = 56,
        y = 32,
    },
    tile_width = 1,
    tile_height = 2,
}

MAGE_TOWER := Doodad {
    sprite = Frame {
        x = 16,
        y = 112,
    },
    tile_width = 1,
    tile_height = 3,
}

MUSHROOMS := Doodad {
    sprite = Frame {
        x = 0,
        y = 56,
    },
    tile_width = 1,
    tile_height = 1,
}

LIGHT1 := Doodad {
    sprite = Frame {
        x = 0,
        y = 96,
    },
    tile_width = 1,
    tile_height = 1,
}

LIGHT2 := Doodad {
    sprite = Frame {
        x = 8,
        y = 96,
    },
    tile_width = 1,
    tile_height = 1,
}

LIGHT3 := Doodad {
    sprite = Frame {
        x = 16,
        y = 96,
    },
    tile_width = 1,
    tile_height = 1,
}

CAVE := Doodad {
    sprite = Frame {
        x = 24,
        y = 96,
    },
    tile_width = 1,
    tile_height = 1,
}

ROCKS := Doodad {
    sprite = Frame {
        x = 32,
        y = 96,
    },
    tile_width = 1,
    tile_height = 1,
}

CAULDRON := Doodad {
    sprite = Frame {
        x = 40,
        y = 96,
    },
    tile_width = 1,
    tile_height = 1,
}

PATH := Doodad {
    sprite = Frame {
        x = 48,
        y = 96,
    },
    tile_width = 1,
    tile_height = 1,
}

BRIDGE_EAST_WEST := Doodad {
    sprite = Frame {
        x = 56,
        y = 96,
    },
    tile_width = 1,
    tile_height = 1,
}

BRIDGE_NORTH_SOUTH := Doodad {
    sprite = Frame {
        x = 64,
        y = 96,
    },
    tile_width = 1,
    tile_height = 1,
}

CORPSE := Doodad {
    sprite = Frame {
        x = 72,
        y = 96,
    },
    tile_width = 1,
    tile_height = 1,
}

VILLAGE_HUMAN := Doodad {
    sprite = Frame {
        x = 0,
        y = 104,
    },
    tile_width = 1,
    tile_height = 1,
}

FORT_HUMAN := Doodad {
    sprite = Frame {
        x = 8,
        y = 104,
    },
    tile_width = 1,
    tile_height = 1,
}

VILLAGE_ORC1 := Doodad {
    sprite = Frame {
        x = 72,
        y = 104,
    },
    tile_width = 1,
    tile_height = 1,
}

VILLAGE_ORC2 := Doodad {
    sprite = Frame {
        x = 80,
        y = 104,
    },
    tile_width = 1,
    tile_height = 1,
}

FORT_ORC := Doodad {
    sprite = Frame {
        x = 88,
        y = 104,
    },
    tile_width = 1,
    tile_height = 1,
}

CASTLE_HUMAN := Doodad {
    sprite = Frame {
        x = 0,
        y = 120,
    },
    tile_width = 2,
    tile_height = 2,
}

TOWER_HUMAN := Doodad {
    sprite = Frame {
        x = 24,
        y = 120,
    },
    tile_width = 1,
    tile_height = 2,
}

CASTLE_ORC := Doodad {
    sprite = Frame {
        x = 72,
        y = 120,
    },
    tile_width = 2,
    tile_height = 2,
}

TOWER_ORC := Doodad {
    sprite = Frame {
        x = 88,
        y = 120,
    },
    tile_width = 1,
    tile_height = 2,
}

MINE := Doodad {
    sprite = Frame {
        x = 32,
        y = 120,
    },
    tile_width = 2,
    tile_height = 2,
}

WATERFALL_ABYSS := Doodad {
    sprite = Animation {
        frames = []Frame {
            { 128, 24 }, { 136, 24 }, { 144, 24 }, { 152, 24 }, { 160, 24 }, { 168, 24 }, { 176, 24 }, { 184, 24 },
        },
        frame_duration = 100,
    },
    tile_width = 1,
    tile_height = 2,
}

DOODADS := []Doodad {
    LIGHT1, LIGHT2, LIGHT3, CAVE,
    ROCKS, CAULDRON, PATH, BRIDGE_EAST_WEST,
    BRIDGE_NORTH_SOUTH, CORPSE, VILLAGE_HUMAN, FORT_HUMAN,
    MUSHROOMS, VILLAGE_ORC1, VILLAGE_ORC2, FORT_ORC,

    TREE1, TREE2, TREE3, TREE4,
    TREE5, TREE6, MAGE_TOWER, WATERFALL_ABYSS,
    
    TOWER_HUMAN, TOWER_ORC,
    
    CASTLE_HUMAN,
    CASTLE_ORC,
    MINE,
}
