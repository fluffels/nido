package back_end

import "core:mem"
import "core:mem/virtual"

import "../app"
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
    // NOTE(jan): Which swapchain image this frame is for. frame.index tells
    // a back end where to find its own per-image resources (uniform buffer,
    // descriptor sets); frame.cmd/.transient_cmd are what to record into.
    frame: ^gfx.FrameResources,
    app_cmd_lists: []app.CommandList,
    // TODO(jan): Remove. These are moved to Apps.
    events: []app.Event,
    // TODO(jan): Remove.
    input_state: app.InputState,
}

DrawFrame :: struct {
    vulkan: ^gfx.Vulkan,
    frame: ^gfx.FrameResources,
}

CleanupFrame :: struct {
    vulkan: ^gfx.Vulkan,
    frame: ^gfx.FrameResources,
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

prepare_frame :: proc (program: ^BackEnd, vulkan: ^gfx.Vulkan, events: []app.Event, state: app.InputState, app_cmd_lists: []app.CommandList, frame: ^gfx.FrameResources) {
    request := PrepareFrame {
        vulkan = vulkan,
        events = events,
        input_state = state,
        frame = frame,
        app_cmd_lists = app_cmd_lists
    }
    program.handler(program, request)
}

draw_frame :: proc (program: ^BackEnd, vulkan: ^gfx.Vulkan, frame: ^gfx.FrameResources) {
    request := DrawFrame {
        vulkan = vulkan,
        frame = frame,
    }
    program.handler(program, request)
}

cleanup_frame :: proc (program: ^BackEnd, vulkan: ^gfx.Vulkan, frame: ^gfx.FrameResources) {
    request := CleanupFrame {
        vulkan = vulkan,
        frame = frame,
    }
    program.handler(program, request)
}

cleanup :: proc (program: ^BackEnd, vulkan: ^gfx.Vulkan) {
    request := Cleanup {
        vulkan = vulkan,
    }
    program.handler(program, request)
}
