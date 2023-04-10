package programs

import gfx "../gfx"

ProgramState :: struct { }

ProgramProc :: #type proc (state: ^ProgramState, vulkan: ^gfx.Vulkan)

Program :: struct {
    name: string,
    handler: ProgramProc,
    state: ProgramState,
}
