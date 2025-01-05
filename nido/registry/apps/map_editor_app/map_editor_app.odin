package map_editor_app

import "../../../app"

MapEditor :: struct {

}

init :: proc(state: ^MapEditor, request: app.Initialize) -> (new_state: ^MapEditor) {
    new_state = new(MapEditor)

    return
}

cleanup :: proc(state: ^MapEditor, request: app.Cleanup) { }

handler :: proc (a: ^app.App, request: app.Request) {
    state := (^MapEditor)(a.state)

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
        flags = {},
        name = "map_editor",
        handler = handler,
        emit_commands_proc = emit_commands,
    }
}
