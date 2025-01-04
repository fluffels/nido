package programs

import "core:mem"
import "core:mem/virtual"
import vk "vendor:vulkan"

import gfx "../gfx"

Initialize :: struct {
    vulkan: ^gfx.Vulkan,
    user_data: rawptr,
}

ResizeEnd :: struct {
    vulkan: ^gfx.Vulkan,
}

ResizeBegin :: struct {
    vulkan: ^gfx.Vulkan,
}

PrepareFrame :: struct {
    vulkan: ^gfx.Vulkan,
    cmd: vk.CommandBuffer,
    events: []Event,
    input_state: InputState,
}

DrawFrame :: struct {
    vulkan: ^gfx.Vulkan,
    cmd: vk.CommandBuffer,
    image_index: u32,
}

CleanupFrame :: struct {
    vulkan: ^gfx.Vulkan,
}

Cleanup :: struct {
    vulkan: ^gfx.Vulkan,
}

Request :: union {
    Initialize,
    ResizeEnd,
    ResizeBegin,
    PrepareFrame,
    DrawFrame,
    CleanupFrame,
    Cleanup,
}

Program :: struct {
    arena: virtual.Arena,
    allocator: mem.Allocator,
    name: string,
    handler: ProgramProc,
    state: rawptr,
}

ProgramProc :: #type proc (program: ^Program, request: Request)

initialize :: proc (program: ^Program, vulkan: ^gfx.Vulkan, user_data: rawptr) {
    request := Initialize {
        vulkan = vulkan,
        user_data = user_data,
    }
    program.handler(program, request)
}

resize_end :: proc (program: ^Program, vulkan: ^gfx.Vulkan) {
    request := ResizeEnd {
        vulkan = vulkan,
    }
    program.handler(program, request)
}

resize_begin :: proc (program: ^Program, vulkan: ^gfx.Vulkan) {
    request := ResizeBegin {
        vulkan = vulkan,
    }
    program.handler(program, request)
}

prepare_frame :: proc (program: ^Program, vulkan: ^gfx.Vulkan, events: []Event, state: InputState, cmd: vk.CommandBuffer) {
    request := PrepareFrame {
        vulkan = vulkan,
        events = events,
        input_state = state,
        cmd = cmd,
    }
    program.handler(program, request)
}

draw_frame :: proc (program: ^Program, vulkan: ^gfx.Vulkan, cmd: vk.CommandBuffer, image_index: u32) {
    request := DrawFrame {
        vulkan = vulkan,
        cmd = cmd,
        image_index = image_index,
    }
    program.handler(program, request)
}

cleanup_frame :: proc (program: ^Program, vulkan: ^gfx.Vulkan) {
    request := CleanupFrame {
        vulkan = vulkan,
    }
    program.handler(program, request)
}

cleanup :: proc (program: ^Program, vulkan: ^gfx.Vulkan) {
    request := Cleanup {
        vulkan = vulkan,
    }
    program.handler(program, request)
}
