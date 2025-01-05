package registry

import "../back_end"
import "demo"
import "map_editor"
import "terminal"

Registry :: struct {
    current_program_index: int,
    back_end: [dynamic]back_end.BackEnd,
}

@(private)
register :: proc (registry: ^Registry, program: back_end.BackEnd) {
    append(&registry.back_end, program)
}

advance_program_index :: proc (registry: ^Registry) {
    registry.current_program_index = (registry.current_program_index + 1) % len(registry.back_end)
}

get_current_program :: proc (registry: Registry) -> back_end.BackEnd {
    return registry.back_end[registry.current_program_index]
}

make :: proc () -> (registry: Registry) {
    register(&registry, terminal.make_program())
    register(&registry, map_editor.make_program())
    register(&registry, demo.make_program())

    registry.current_program_index = 0

    return
}
