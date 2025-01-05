package terminal_app

import "../../../app"

Terminal :: struct {

}

init :: proc(state: ^Terminal, request: app.Initialize) -> (new_state: ^Terminal) {
    new_state = new(Terminal)

    return
}

cleanup :: proc(state: ^Terminal, request: app.Cleanup) { }

handler :: proc (a: ^app.App, request: app.Request) {
    state := (^Terminal)(a.state)

    context.allocator = a.allocator

    switch r in request {
        case app.Initialize:
            a.state = init(state, r)
        case app.Cleanup:
            cleanup(state, r)
        case:
            panic("unhandled request")
    }
}

make_app :: proc () -> app.App {
    return app.App {
        flags = {.System},
        name = "terminal",
        handler = handler,
        emit_commands_proc = emit_commands,
    }
}
