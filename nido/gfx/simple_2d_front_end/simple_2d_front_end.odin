package simple_2d_front_end

import "core:math/linalg"

Quad :: struct {
    position: linalg.Vector2f32,
    size: linalg.Vector2f32,
}

RegisterTextureCommand :: struct {
    handle: u32,
    fname: string,
}

DrawTexturedQuadCommand :: struct {
    texture_handle: u32,
    quad: Quad,
    tex: Quad,
    z: f32,
}

Command :: union {
    RegisterTextureCommand,
    DrawTexturedQuadCommand,
}

CommandList :: struct {
    last_texture_handle: u32,
    commands: [dynamic]Command,
}

cmd_register_texture :: proc (cmds: ^CommandList, fname: string) -> (handle: u32) {
    cmd := RegisterTextureCommand {
        handle = cmds.last_texture_handle,
        fname = fname
    }
    append(&cmds.commands, cmd)
    return cmd.handle
}

make_list :: proc () -> (result: ^CommandList) {
    result = new(CommandList)
    result.last_texture_handle = 0
    result.commands = make([dynamic]Command)
    return
}
