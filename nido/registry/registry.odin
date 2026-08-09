package registry

import "core:mem"
import "core:mem/virtual"

import "../app"
import "../back_end"

import "apps/map_editor_app"
import "apps/terminal_app"
import "apps/tile_app"
import "apps/wang_app"

import "back_ends/demo"
import "back_ends/simple_2d_back_end"

Registry :: struct {
    arena: virtual.Arena,
    allocator: mem.Allocator,
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

// NOTE(jan): Cycles current_app_index among non-system apps. System apps
// (e.g. the console) always run and are never selected as "current".
advance_app_index :: proc (registry: ^Registry) {
    n := len(registry.app)
    if n == 0 do return
    for i in 1..=n {
        idx := (registry.current_app_index + i) % n
        if !app.is_system_app(&registry.app[idx]) {
            registry.current_app_index = idx
            return
        }
    }
}

get_current_app :: proc (registry: Registry) -> app.App {
    return registry.app[registry.current_app_index]
}

get_current_back_end :: proc (registry: Registry) -> back_end.BackEnd {
    return registry.back_end[registry.current_back_end_index]
}

make_registry :: proc () -> (registry: Registry) {
    registry.allocator = virtual.arena_allocator(&registry.arena)

    registry.app = make([dynamic]app.App, registry.allocator)
    registry.back_end = make([dynamic]back_end.BackEnd, registry.allocator)

    register(&registry, map_editor_app.make_app())
    register(&registry, tile_app.make_app())
    register(&registry, wang_app.make_app())
    register(&registry, terminal_app.make_app())

    register(&registry, simple_2d_back_end.make_program())
    register(&registry, demo.make_program())

    registry.current_app_index = 0
    registry.current_back_end_index = 0

    return
}
