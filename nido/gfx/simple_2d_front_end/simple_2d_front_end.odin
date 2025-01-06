package simple_2d_front_end

Quad :: struct {
    position: [2]f32,
    size: [2]f32,
}

RegisterTextureCommand :: struct {
    handle: u32,
}

UpdateTextureFromFileCommand :: struct {
    handle: u32,
    fname: string,
}

DrawBoxCommand :: struct {
    quad: Quad,
    color: [4]f32,
    z: f32,
}

DrawTexturedQuadCommand :: struct {
    texture_handle: u32,
    quad: Quad,
    tex: Quad,
    z: f32,
}

Command :: union {
    DrawBoxCommand,
    DrawTexturedQuadCommand,
    RegisterTextureCommand,
    UpdateTextureFromFileCommand,
}

CommandList :: struct {
    last_texture_handle: u32,
    commands: [dynamic]Command,
}

cmd_draw_box :: proc (cmds: ^CommandList, box: Quad, color: [4]f32, z: f32) {
    cmd := DrawBoxCommand {
        quad = box,
        color = color,
        z = z,
    }
    append(&cmds.commands, cmd)
}

cmd_draw_textured_quad :: proc (cmds: ^CommandList, box: Quad, tex: Quad, z: f32) {
    cmd := DrawTexturedQuadCommand {
        quad = box,
        tex = tex,
        z = z,
    }
    append(&cmds.commands, cmd)
}

cmd_register_texture :: proc (cmds: ^CommandList) -> (handle: u32) {
    cmd := RegisterTextureCommand {
        handle = cmds.last_texture_handle,
    }
    append(&cmds.commands, cmd)
    cmds.last_texture_handle += 1
    return cmd.handle
}

cmd_update_texture_from_file_command :: proc (cmds: ^CommandList, handle: u32, fname: string) {
    cmd := UpdateTextureFromFileCommand {
        handle = handle,
        fname = fname
    }
    append(&cmds.commands, cmd)
}

make_list :: proc () -> (result: ^CommandList) {
    result = new(CommandList)
    result.last_texture_handle = 0
    result.commands = make([dynamic]Command)
    return
}
