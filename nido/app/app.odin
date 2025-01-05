package app

import "core:mem"
import "core:mem/virtual"

import vk "vendor:vulkan"

import "../gfx"

Initialize :: struct {
    user_data: rawptr,
}

Cleanup :: struct {
    user_data: rawptr,
}

Request :: union {
    Initialize,
    Cleanup,
}


AppFlag :: enum {
    // NOTE(jan): Always running.
    System,
}

AppFlags :: distinct bit_set[AppFlag; u32]

App :: struct {
    flags: AppFlags,
    arena: virtual.Arena,
    allocator: mem.Allocator,
    name: string,
    handler: AppProc,
    emit_commands_proc: EmitCommandsProc,
    state: rawptr,
}

is_system_app :: proc(app: ^App) -> bool {
    return .System in app.flags
}

CommandList :: struct {
    type: string,
    list: rawptr,
}

AppProc :: #type proc (app: ^App, request: Request)
EmitCommandsProc :: #type proc (app: ^App, events: []Event, input_state: InputState) -> CommandList

initialize :: proc (app: ^App, user_data: rawptr) {
    request := Initialize {
        user_data = user_data,
    }
    app.handler(app, request)
}

cleanup :: proc (app: ^App, user_data: rawptr) {
    request := Cleanup {
        user_data = user_data,
    }
    app.handler(app, request)
}
