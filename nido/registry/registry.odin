package registry

import "../programs"
import "demo"

Registry :: struct {
    current_program_name: string,
    programs: map[string]programs.Program,
}

@(private)
register :: proc (registry: ^Registry, program: programs.Program) -> () {
    registry.programs[program.name] = program
}

make :: proc () -> (registry: Registry) {
    register(&registry, demo.make_program())

    registry.current_program_name = "demo"

    return
}
