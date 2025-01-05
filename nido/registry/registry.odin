package registry

import "../app"
import "../back_end"

import "apps/map_editor_app"
import "apps/terminal_app"

import "back_ends/demo"
import "back_ends/map_editor"
import "back_ends/simple_2d_back_end"
import "back_ends/terminal"

Registry :: struct {
    current_app_index: int,
    current_back_end_index: int,
    back_end: [dynamic]back_end.BackEnd,
    app: [dynamic]app.App,
}

@(private)
register_back_end :: proc (registry: ^Registry, back_end: back_end.BackEnd) {
    append(&registry.back_end, back_end)
}

@(private)
register_app :: proc (registry: ^Registry, app: app.App) {
    append(&registry.app, app)
}

@(private)
register :: proc{register_app, register_back_end}

advance_back_end_index :: proc (registry: ^Registry) {
    registry.current_back_end_index = (registry.current_back_end_index + 1) % len(registry.back_end)
}

get_current_app :: proc (registry: Registry) -> app.App {
    return registry.app[registry.current_app_index]
}

get_current_back_end :: proc (registry: Registry) -> back_end.BackEnd {
    return registry.back_end[registry.current_back_end_index]
}

make :: proc () -> (registry: Registry) {
    register(&registry, map_editor_app.make_app())
    register(&registry, terminal_app.make_app())

    register(&registry, simple_2d_back_end.make_program())
    register(&registry, terminal.make_program())
    register(&registry, map_editor.make_program())
    register(&registry, demo.make_program())

    registry.current_app_index = 0
    registry.current_back_end_index = 0

    return
}
