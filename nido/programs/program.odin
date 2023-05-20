package programs

import "core:mem"
import vk "vendor:vulkan"

import gfx "../gfx"

Initialize :: struct {
    vulkan: ^gfx.Vulkan,
    allocator: mem.Allocator,
}

CreatePasses :: struct {
    vulkan: ^gfx.Vulkan,
}

DestroyPasses :: struct {
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
    allocator: mem.Allocator,
}

Request :: union {
    Initialize,
    CreatePasses,
    DestroyPasses,
    PrepareFrame,
    DrawFrame,
    CleanupFrame,
    Cleanup,
}

Program :: struct {
    name: string,
    handler: ProgramProc,
    state: rawptr,
}

ProgramProc :: #type proc (program: ^Program, request: Request)

initialize :: proc (program: ^Program, vulkan: ^gfx.Vulkan, allocator: mem.Allocator) {
    request := Initialize {
        vulkan = vulkan,
        allocator = allocator,
    }
    program.handler(program, request)
}

create_passes :: proc (program: ^Program, vulkan: ^gfx.Vulkan) {
    request := CreatePasses {
        vulkan = vulkan,
    }
    program.handler(program, request)
}

destroy_passes :: proc (program: ^Program, vulkan: ^gfx.Vulkan) {
    request := DestroyPasses {
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

cleanup :: proc (program: ^Program, vulkan: ^gfx.Vulkan, allocator: mem.Allocator) {
    request := Cleanup {
        vulkan = vulkan,
        allocator = allocator,
    }
    program.handler(program, request)
}
