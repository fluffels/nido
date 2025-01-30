package wang_app

import "../../../app"
import "../../../font"
import "../../../logext"

init :: proc(state: ^WangAppState, request: app.Initialize) { }

cleanup :: proc(state: ^WangAppState, request: app.Cleanup) { }

handler :: proc (a: ^app.App, request: app.Request) {
    state := (^WangAppState)(a.state)

    context.allocator = a.allocator

    switch r in request {
        case app.Initialize:
            state = new(WangAppState)
            init(state, r)
            a.state = state
        case app.Cleanup:
            cleanup(state, r)
        case:
            panic("unhandled request")
    }
}

make_app :: proc () -> app.App {
    return app.App {
        name = "wang",
        handler = handler,
        emit_commands_proc = emit_commands,
    }
}
