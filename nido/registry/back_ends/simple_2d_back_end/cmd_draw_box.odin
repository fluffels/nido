package simple_2d_back_end

import "../../../gfx"
import "../../../gfx/simple_2d_front_end"

cmd_draw_box :: proc (state: ^Simple2DBackEnd, cmd: simple_2d_front_end.DrawBoxCommand) {
    first_index := state.box_mesh.vertex_count

    gfx.vulkan_mesh_push_vertex(
        &state.box_mesh,
        {
            {cmd.quad.position.x, cmd.quad.position.y, cmd.z},
            {cmd.color.r, cmd.color.g, cmd.color.b, cmd.color.a},
        }
    );
    
    gfx.vulkan_mesh_push_vertex(
        &state.box_mesh,
        {
            {cmd.quad.position.x + cmd.quad.size.x, cmd.quad.position.y, cmd.z},
            {cmd.color.r, cmd.color.g, cmd.color.b, cmd.color.a},
        }
    );

    gfx.vulkan_mesh_push_vertex(
        &state.box_mesh,
        {
            {cmd.quad.position.x + cmd.quad.size.x, cmd.quad.position.y + cmd.quad.size.y, cmd.z},
            {cmd.color.r, cmd.color.g, cmd.color.b, cmd.color.a},
        }
    );

    gfx.vulkan_mesh_push_vertex(
        &state.box_mesh,
        {
            {cmd.quad.position.x, cmd.quad.position.y + cmd.quad.size.y, cmd.z},
            {cmd.color.r, cmd.color.g, cmd.color.b, cmd.color.a},
        }
    );

    append(&state.box_mesh.indices, first_index + 0)
    append(&state.box_mesh.indices, first_index + 1)
    append(&state.box_mesh.indices, first_index + 2)
    append(&state.box_mesh.indices, first_index + 2)
    append(&state.box_mesh.indices, first_index + 3)
    append(&state.box_mesh.indices, first_index + 0)
}
