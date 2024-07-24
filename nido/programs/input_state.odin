package programs

import linalg "core:math/linalg"

Mouse :: struct {
    pos: linalg.Vector2f32,
    delta: linalg.Vector2f32,
    left: bool,
    middle: bool,
    right: bool,
}

Keyboard :: struct {
    left: bool,
    right: bool,
    up: bool,
    down: bool,
    home: b32,
    end: b32,
    page_up: b32,
    page_down: b32,
}

InputState :: struct {
    ticks: u32,
    slice: u32,
    keyboard: Keyboard,
    key_up: Keyboard,
    key_down: Keyboard,
    mouse: Mouse,
}
