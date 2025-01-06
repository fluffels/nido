package simple_2d_back_end

import "../../../gfx"
import "../../../gfx/simple_2d_front_end"

cmd_draw_glyph :: proc (state: ^Simple2DBackEnd, cmd: simple_2d_front_end.DrawGlyphCommand) {
    mesh := &state.glyph_mesh

    first_index := mesh.vertex_count

    gfx.vulkan_mesh_push_vertex(
        mesh,
        {
            {cmd.quad.position.x, cmd.quad.position.y, cmd.z},
            {cmd.tex.position.x, cmd.tex.position.y},
            {cmd.color.r, cmd.color.g, cmd.color.b},
        }
    );
    
    gfx.vulkan_mesh_push_vertex(
        mesh,
        {
            {cmd.quad.position.x + cmd.quad.size.x, cmd.quad.position.y, cmd.z},
            {cmd.tex.position.x + cmd.tex.size.x, cmd.tex.position.y},
            {cmd.color.r, cmd.color.g, cmd.color.b},
        }
    );

    gfx.vulkan_mesh_push_vertex(
        mesh,
        {
            {cmd.quad.position.x + cmd.quad.size.x, cmd.quad.position.y + cmd.quad.size.y, cmd.z},
            {cmd.tex.position.x + cmd.tex.size.x, cmd.tex.position.y + cmd.tex.size.y},
            {cmd.color.r, cmd.color.g, cmd.color.b},
        }
    );

    gfx.vulkan_mesh_push_vertex(
        mesh,
        {
            {cmd.quad.position.x, cmd.quad.position.y + cmd.quad.size.y, cmd.z},
            {cmd.tex.position.x, cmd.tex.position.y + cmd.tex.size.y},
            {cmd.color.r, cmd.color.g, cmd.color.b},
        }
    );

    append(&mesh.indices, first_index + 0)
    append(&mesh.indices, first_index + 1)
    append(&mesh.indices, first_index + 2)
    append(&mesh.indices, first_index + 2)
    append(&mesh.indices, first_index + 3)
    append(&mesh.indices, first_index + 0)
}
