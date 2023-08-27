package programs

Mouse :: struct {
    x: f32,
    y: f32,
    left: bool,
    middle: bool,
    right: bool,
}

Keyboard :: struct {
    left: bool,
    right: bool,
    up: bool,
    down: bool,
}

InputState :: struct {
    ticks: u32,
    slice: u32,
    keyboard: Keyboard,
    mouse: Mouse,
}
