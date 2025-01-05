package back_end

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
    // TODO(jan): Remove. These are moved to Apps.
    events: []Event,
    // TODO(jan): Remove.
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

BackEnd :: struct {
    arena: virtual.Arena,
    allocator: mem.Allocator,
    name: string,
    handler: BackEndProc,
    state: rawptr,
}

BackEndProc :: #type proc (program: ^BackEnd, request: Request)

initialize :: proc (program: ^BackEnd, vulkan: ^gfx.Vulkan, user_data: rawptr) {
    request := Initialize {
        vulkan = vulkan,
        user_data = user_data,
    }
    program.handler(program, request)
}

resize_end :: proc (program: ^BackEnd, vulkan: ^gfx.Vulkan) {
    request := ResizeEnd {
        vulkan = vulkan,
    }
    program.handler(program, request)
}

resize_begin :: proc (program: ^BackEnd, vulkan: ^gfx.Vulkan) {
    request := ResizeBegin {
        vulkan = vulkan,
    }
    program.handler(program, request)
}

prepare_frame :: proc (program: ^BackEnd, vulkan: ^gfx.Vulkan, events: []Event, state: InputState, cmd: vk.CommandBuffer) {
    request := PrepareFrame {
        vulkan = vulkan,
        events = events,
        input_state = state,
        cmd = cmd,
    }
    program.handler(program, request)
}

draw_frame :: proc (program: ^BackEnd, vulkan: ^gfx.Vulkan, cmd: vk.CommandBuffer, image_index: u32) {
    request := DrawFrame {
        vulkan = vulkan,
        cmd = cmd,
        image_index = image_index,
    }
    program.handler(program, request)
}

cleanup_frame :: proc (program: ^BackEnd, vulkan: ^gfx.Vulkan) {
    request := CleanupFrame {
        vulkan = vulkan,
    }
    program.handler(program, request)
}

cleanup :: proc (program: ^BackEnd, vulkan: ^gfx.Vulkan) {
    request := Cleanup {
        vulkan = vulkan,
    }
    program.handler(program, request)
}
