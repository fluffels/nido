package simple_2d_back_end

import "core:log"

import "../../../gfx"
import "../../../gfx/simple_2d_front_end"

cmd_post_process:: proc (state: ^Simple2DBackEnd) {
    batch_index := -1
    for b, i in state.batches {
        if b.pipeline.meta.name != POST_PASS_PIPELINE.name do continue
        batch_index = i
        break
    }

    if batch_index == -1 {
        pipeline, ok := state.post_pass.pipelines[POST_PASS_PIPELINE.name]
        if (!ok) {
            log.warnf("Missing pipeline: %s", POST_PASS_PIPELINE.name)
            return
        }
        // TODO(jan): Maybe add vertex to pipeline meta?
        append(&state.batches, gfx.make_render_batch(pipeline, TEXTURED_VERTEX, context.temp_allocator))
        batch_index = len(state.batches) - 1
    }

    mesh := &state.batches[batch_index].mesh
    first_index := mesh.vertex_count

    gfx.vulkan_mesh_push_vertex(
        mesh,
        {
            {-1, -1, 0},
            {0, 0},
        }
    );
    
    gfx.vulkan_mesh_push_vertex(
        mesh,
        {
            {1, -1, 0},
            {1, 0},
        }
    );

    gfx.vulkan_mesh_push_vertex(
        mesh,
        {
            {1, 1, 0},
            {1, 1},
        }
    );

    gfx.vulkan_mesh_push_vertex(
        mesh,
        {
            {-1, 1, 0},
            {0, 1},
        }
    );

    append(&mesh.indices, first_index + 0)
    append(&mesh.indices, first_index + 1)
    append(&mesh.indices, first_index + 2)
    append(&mesh.indices, first_index + 2)
    append(&mesh.indices, first_index + 3)
    append(&mesh.indices, first_index + 0)
}
