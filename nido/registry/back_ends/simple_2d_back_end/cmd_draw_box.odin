package simple_2d_back_end

import "../../../gfx"
import "../../../gfx/simple_2d_front_end"

cmd_draw_box :: proc (state: ^Simple2DBackEnd, cmd: simple_2d_front_end.DrawBoxCommand) {
    gfx.vulkan_mesh_push_vertex(
        &state.textured_quad_mesh,
        {
            {cmd.quad.position.x, cmd.quad.position.y, cmd.z},
            {cmd.color.r, cmd.color.g, cmd.color.b},
        }
    );
    
    gfx.vulkan_mesh_push_vertex(
        &state.textured_quad_mesh,
        {
            {cmd.quad.position.x + cmd.quad.size.x, cmd.quad.position.y, cmd.z},
            {cmd.color.r, cmd.color.g, cmd.color.b},
        }
    );

    gfx.vulkan_mesh_push_vertex(
        &state.textured_quad_mesh,
        {
            {cmd.quad.position.x + cmd.quad.size.x, cmd.quad.position.y + cmd.quad.size.y, cmd.z},
            {cmd.color.r, cmd.color.g, cmd.color.b},
        }
    );

    gfx.vulkan_mesh_push_vertex(
        &state.textured_quad_mesh,
        {
            {cmd.quad.position.x, cmd.quad.position.y + cmd.quad.size.y, cmd.z},
            {cmd.color.r, cmd.color.g, cmd.color.b},
        }
    );
}
