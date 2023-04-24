package gfx

V2 :: struct {
    x: f32,
    y: f32,
}

V3 :: struct {
    x: f32,
    y: f32,
    z: f32,
}

V4 :: struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,
}

AABox :: struct {
    left: f32,
    right: f32,
    top: f32,
    bottom: f32,
}

mat4x4 :: [16]f32

// Set matrix to the identity matrix.
identity :: proc (m: ^mat4x4) {
    m [0] = 1
    m [1] = 0
    m [2] = 0
    m [3] = 0

    m [4] = 0
    m [5] = 1
    m [6] = 0
    m [7] = 0

    m [8] = 0
    m [9] = 0
    m[10] = 1
    m[11] = 0

    m[12] = 0
    m[13] = 0
    m[14] = 0
    m[15] = 1
}

ortho :: proc (screen_width: u32, screen_height: u32, m: ^mat4x4) {
    identity(m)

    ar := f32(screen_width) / f32(screen_height)

    m[0] = 2 / f32(screen_width)
    m[12] = -1
    m[5] = 2 / f32(screen_height)
    m[13] = -1
    m[10] = 0
}