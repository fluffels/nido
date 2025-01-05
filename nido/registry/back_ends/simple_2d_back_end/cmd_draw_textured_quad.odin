package simple_2d_back_end

import "../../../gfx"
import "../../../gfx/simple_2d_front_end"

cmd_draw_textured_quad :: proc (state: ^Simple2DBackEnd, cmd: simple_2d_front_end.DrawTexturedQuadCommand) {
    gfx.vulkan_mesh_push_vertex(
        &state.textured_quad_mesh,
        {
            {cmd.quad.position.x, cmd.quad.position.y, cmd.z},
            {cmd.tex.position.x, cmd.tex.position.y}
        }
    );
    
    gfx.vulkan_mesh_push_vertex(
        &state.textured_quad_mesh,
        {
            {cmd.quad.position.x + cmd.quad.size.x, cmd.quad.position.y, cmd.z},
            {cmd.tex.position.x + cmd.tex.size.x, cmd.tex.position.y}
        }
    );

    gfx.vulkan_mesh_push_vertex(
        &state.textured_quad_mesh,
        {
            {cmd.quad.position.x + cmd.quad.size.x, cmd.quad.position.y + cmd.quad.size.y, cmd.z},
            {cmd.tex.position.x + cmd.tex.size.x, cmd.tex.position.y + cmd.tex.size.y}
        }
    );

    gfx.vulkan_mesh_push_vertex(
        &state.textured_quad_mesh,
        {
            {cmd.quad.position.x, cmd.quad.position.y + cmd.quad.size.y, cmd.z},
            {cmd.tex.position.x, cmd.tex.position.y + cmd.tex.size.y}
        }
    );
}
