package simple_2d_front_end

last_texture_handle: u32 = 0

Quad :: struct {
    position: [2]f32,
    size: [2]f32,
}

Triangle :: struct {
    a: [2]f32,
    b: [2]f32,
    c: [2]f32,
}

RegisterTextureCommand :: struct {
    handle: u32,
}

UpdateTextureFromFileCommand :: struct {
    handle: u32,
    fname: string,
}

UpdateTextureFromBitmapCommand :: struct {
    handle: u32,
    bitmap: []u8,
    width: u32,
    height: u32,
    depth: u32,
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

DrawTriangleCommand :: struct {
    triangle: Triangle,
    color: [4]f32,
    z: f32,
}

DrawGlyphCommand :: struct {
    texture_handle: u32,
    quad: Quad,
    tex: Quad,
    color: [3]f32,
    z: f32,
}

Command :: union {
    DrawBoxCommand,
    DrawGlyphCommand,
    DrawTexturedQuadCommand,
    DrawTriangleCommand,
    RegisterTextureCommand,
    UpdateTextureFromFileCommand,
    UpdateTextureFromBitmapCommand,
}

CommandList :: struct {
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

cmd_draw_triangle :: proc (cmds: ^CommandList, triangle: Triangle, color: [4]f32, z: f32) {
    cmd := DrawTriangleCommand {
        triangle = triangle,
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

cmd_draw_glyph :: proc (cmds: ^CommandList, texture_handle: u32, box: Quad, tex: Quad, color: [3]f32, z: f32) {
    cmd := DrawGlyphCommand {
        texture_handle = texture_handle,
        quad = box,
        tex = tex,
        color = color,
        z = z,
    }
    append(&cmds.commands, cmd)
}

cmd_register_texture :: proc (cmds: ^CommandList) -> (handle: u32) {
    cmd := RegisterTextureCommand {
        handle = last_texture_handle,
    }
    append(&cmds.commands, cmd)
    last_texture_handle += 1
    return cmd.handle
}

cmd_update_texture_from_file_command :: proc (cmds: ^CommandList, handle: u32, fname: string) {
    cmd := UpdateTextureFromFileCommand {
        handle = handle,
        fname = fname
    }
    append(&cmds.commands, cmd)
}

cmd_update_texture_from_bitmap :: proc (cmds: ^CommandList, handle: u32, bitmap: []u8, width: u32, height: u32, depth: u32) {
    cmd := UpdateTextureFromBitmapCommand {
        handle = handle,
        bitmap = bitmap,
        width = width,
        height = height,
        depth = depth,
    }
    append(&cmds.commands, cmd)
}

make_list :: proc () -> (result: ^CommandList) {
    result = new(CommandList)
    result.commands = make([dynamic]Command)
    return
}
