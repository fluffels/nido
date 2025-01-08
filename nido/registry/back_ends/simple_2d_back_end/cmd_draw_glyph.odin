package simple_2d_back_end

import "core:log"

import "../../../gfx"
import "../../../gfx/simple_2d_front_end"

cmd_draw_glyph :: proc (state: ^Simple2DBackEnd, cmd: simple_2d_front_end.DrawGlyphCommand) {
    batch_index := -1
    for b, i in state.batches {
        if b.pipeline.meta.name != GLYPH_PASS.name do continue
        batch_index = i
        break
    }

    if batch_index == -1 {
        pipeline, ok := state.vulkan_pass.pipelines[GLYPH_PASS.name]
        if (!ok) {
            log.warnf("Missing pipeline: %s", GLYPH_PASS.name)
            return
        }
        // TODO(jan): Maybe add vertex to pipeline meta?
        append(&state.batches, gfx.make_render_batch(pipeline, GLYPH_VERTEX, context.temp_allocator))
        batch_index = len(state.batches) - 1
        append(&state.batches[batch_index].textures, gfx.RenderBatchTextureMapping{cmd.texture_handle, 0})
    }

    mesh := &state.batches[batch_index].mesh
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
