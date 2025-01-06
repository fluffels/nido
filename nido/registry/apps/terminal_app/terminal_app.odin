package terminal_app

import "../../../app"
import "../../../font"
import "../../../logext"

init :: proc(state: ^Terminal, request: app.Initialize) {
    state.log_data = cast(^logext.Circular_Buffer_Logger_Data)request.user_data
    state.fonts = font.load_fonts()
    // NOTE(jan): Initial repack is required.
    state.repack_required = true
    return
}

cleanup :: proc(state: ^Terminal, request: app.Cleanup) { }

// TODO(jan): Repack on resize.

handler :: proc (a: ^app.App, request: app.Request) {
    state := (^Terminal)(a.state)

    context.allocator = a.allocator

    switch r in request {
        case app.Initialize:
            state = new(Terminal)
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
        flags = {.System},
        name = "terminal",
        handler = handler,
        emit_commands_proc = emit_commands,
    }
}
