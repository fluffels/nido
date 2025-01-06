package map_editor_app

import "../../../app"
import "../../../gfx/simple_2d_front_end"

emit_commands :: proc (a: ^app.App, events: []app.Event, input_state: app.InputState) -> (result: app.CommandList) {
    command_list: ^simple_2d_front_end.CommandList
    {
        // NOTE(jan): Commands only live for one frame.
        context.allocator = context.temp_allocator
        command_list = simple_2d_front_end.make_list()
    }

    tex_handle := simple_2d_front_end.cmd_register_texture(command_list, "tinyrts.png")

    result.type = "simple_2d_front_end"
    result.list = cast(rawptr)command_list

    return
}
