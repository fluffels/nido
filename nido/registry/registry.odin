package registry

import "../programs"
import "demo"
import "map_editor"
import "terminal"

Registry :: struct {
    current_program_index: int,
    programs: [dynamic]programs.Program,
}

@(private)
register :: proc (registry: ^Registry, program: programs.Program) {
    append(&registry.programs, program)
}

advance_program_index :: proc (registry: ^Registry) {
    registry.current_program_index = (registry.current_program_index + 1) % len(registry.programs)
}

get_current_program :: proc (registry: Registry) -> programs.Program {
    return registry.programs[registry.current_program_index]
}

make :: proc () -> (registry: Registry) {
    register(&registry, terminal.make_program())
    register(&registry, map_editor.make_program())
    register(&registry, demo.make_program())

    registry.current_program_index = 0

    return
}
