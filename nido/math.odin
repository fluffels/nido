package nido

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
