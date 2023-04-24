package programs

Mouse :: struct {
    x: f32,
    y: f32,
    left: bool,
}

InputState :: struct {
    mouse: Mouse,
}
