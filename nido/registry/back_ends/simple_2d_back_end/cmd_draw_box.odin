package simple_2d_back_end

import "core:log"

import "../../../gfx"
import "../../../gfx/simple_2d_front_end"

cmd_draw_box :: proc (state: ^Simple2DBackEnd, cmd: simple_2d_front_end.DrawBoxCommand, image_index: int) {
    batch_index := -1
    for b, i in state.batches[image_index] {
        if b.pipeline.meta.name != TRIANGLE_PASS.name do continue
        batch_index = i
        break
    }

    if batch_index == -1 {
        pipeline, ok := state.main_pass.pipelines[TRIANGLE_PASS.name]
        if (!ok) {
            log.warnf("Missing pipeline: %s", TRIANGLE_PASS.name)
            return
        }
        // TODO(jan): Maybe add vertex to pipeline meta?
        append(&state.batches[image_index], gfx.make_render_batch(pipeline, COLOR_VERTEX, context.temp_allocator))
        batch_index = len(state.batches[image_index]) - 1
    }

    mesh := &state.batches[image_index][batch_index].mesh
    first_index := mesh.vertex_count

    gfx.vulkan_mesh_push_vertex(
        mesh,
        {
            {cmd.quad.position.x, cmd.quad.position.y, cmd.z},
            {cmd.color.r, cmd.color.g, cmd.color.b, cmd.color.a},
        }
    );
    
    gfx.vulkan_mesh_push_vertex(
        mesh,
        {
            {cmd.quad.position.x + cmd.quad.size.x, cmd.quad.position.y, cmd.z},
            {cmd.color.r, cmd.color.g, cmd.color.b, cmd.color.a},
        }
    );

    gfx.vulkan_mesh_push_vertex(
        mesh,
        {
            {cmd.quad.position.x + cmd.quad.size.x, cmd.quad.position.y + cmd.quad.size.y, cmd.z},
            {cmd.color.r, cmd.color.g, cmd.color.b, cmd.color.a},
        }
    );

    gfx.vulkan_mesh_push_vertex(
        mesh,
        {
            {cmd.quad.position.x, cmd.quad.position.y + cmd.quad.size.y, cmd.z},
            {cmd.color.r, cmd.color.g, cmd.color.b, cmd.color.a},
        }
    );

    append(&mesh.indices, first_index + 0)
    append(&mesh.indices, first_index + 1)
    append(&mesh.indices, first_index + 2)
    append(&mesh.indices, first_index + 2)
    append(&mesh.indices, first_index + 3)
    append(&mesh.indices, first_index + 0)
}
