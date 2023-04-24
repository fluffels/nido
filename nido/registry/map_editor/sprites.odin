package map_editor

SpriteDescription :: struct {
    x: u32,
    y: u32,
}

TERRAIN_SPRITES := []SpriteDescription {
    {0,  0}, {8,  0}, {16,  0}, {24,  0}, {32,  0}, {40,  0}, {48,  0}, {56,  0}, {60,  0}, {72,  0},
    // {0,  8}, {8,  8}, {16,  8}, {24,  8}, {32,  8}, {40,  8}, {48,  8}, {56,  8}, {60,  8}, {72,  8},
    // {0, 16}, {8, 16}, {16, 16},                     {40, 16}, {48, 16}, {56, 16},
}
