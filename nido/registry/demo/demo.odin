package demo

import "core:log"

import "../../gfx"
import "../../programs"

handler :: proc (state: ^programs.ProgramState, vulkan: ^gfx.Vulkan) {
    log.infof("Demo Program")
}

make_state :: proc() -> programs.ProgramState {
    return programs.ProgramState { }
}

make :: proc () -> programs.Program {
    return programs.Program {
        name = "demo",
        handler = handler,
        state = make_state(),
    }
}