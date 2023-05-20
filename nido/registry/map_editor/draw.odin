package map_editor

import "core:math"

import vk "vendor:vulkan"

import "../../gfx"
import "../../programs"

push_box :: proc(cmd: vk.CommandBuffer, state: ^MapEditorState, box: gfx.AABox, color: gfx.Color) {
    vertices := [][][]f32 {
        {
            {box.left, box.top},
            {color[0], color[1], color[2], color[3]},
        },
        {
            {box.right, box.top},
            {color[0], color[1], color[2], color[3]},
        },
        {
            {box.right, box.bottom},
            {color[0], color[1], color[2], color[3]},
        },
        {
            {box.left, box.bottom},
            {color[0], color[1], color[2], color[3]},
        },
    }

    first_vertex := state.colored_mesh.vertex_count
    gfx.vulkan_mesh_push_vertices(&state.colored_mesh, vertices)

    first_index := u32(len(state.colored_mesh.indices))
    append(&state.colored_mesh.indices, first_vertex + 0)
    append(&state.colored_mesh.indices, first_vertex + 1)
    append(&state.colored_mesh.indices, first_vertex + 2)
    append(&state.colored_mesh.indices, first_vertex + 2)
    append(&state.colored_mesh.indices, first_vertex + 3)
    append(&state.colored_mesh.indices, first_vertex + 0)

    assert("colored" in state.vulkan_pass.pipelines)
    pipeline := state.vulkan_pass.pipelines["colored"]
    vk.CmdBindPipeline(cmd, vk.PipelineBindPoint.GRAPHICS, pipeline.handle)
    vk.CmdBindDescriptorSets(cmd, vk.PipelineBindPoint.GRAPHICS, pipeline.layout, 0, u32(len(pipeline.descriptor_sets)), raw_data(pipeline.descriptor_sets), 0, nil)
    gfx.vulkan_mesh_bind(cmd, &state.colored_mesh)
    vk.CmdDrawIndexed(cmd, 6, 1, first_index, 0, 0)
}

push_frame :: proc(cmd: vk.CommandBuffer, state: ^MapEditorState, x0: f32, y0: f32, tile: Frame) -> gfx.AABox {
    x1 := x0 + state.tile_width
    y1 := y0 + state.tile_height

    s0 := f32(tile.x) / f32(state.sprite_sheet.extent.width)
    s1 := s0 + state.sprite_width

    t0 := f32(tile.y) / f32(state.sprite_sheet.extent.height)
    t1 := t0 + state.sprite_height

    vertices := [][][]f32 {
        {
            {x0, y0},
            {s0, t0},
        },
        {
            {x1, y0},
            {s1, t0},
        },
        {
            {x1, y1},
            {s1, t1},
        },
        {
            {x0, y1},
            {s0, t1},
        },
    }

    first_vertex := state.textured_mesh.vertex_count
    gfx.vulkan_mesh_push_vertices(&state.textured_mesh, vertices)

    first_index := u32(len(state.textured_mesh.indices))
    append(&state.textured_mesh.indices, first_vertex + 0)
    append(&state.textured_mesh.indices, first_vertex + 1)
    append(&state.textured_mesh.indices, first_vertex + 2)
    append(&state.textured_mesh.indices, first_vertex + 2)
    append(&state.textured_mesh.indices, first_vertex + 3)
    append(&state.textured_mesh.indices, first_vertex + 0)

    assert("textured" in state.vulkan_pass.pipelines)
    pipeline := state.vulkan_pass.pipelines["textured"]
    vk.CmdBindPipeline(cmd, vk.PipelineBindPoint.GRAPHICS, pipeline.handle)
    vk.CmdBindDescriptorSets(cmd, vk.PipelineBindPoint.GRAPHICS, pipeline.layout, 0, u32(len(pipeline.descriptor_sets)), raw_data(pipeline.descriptor_sets), 0, nil)
    gfx.vulkan_mesh_bind(cmd, &state.textured_mesh)
    vk.CmdDrawIndexed(cmd, u32(len(state.textured_mesh.indices)), 1, 0, 0, 0)

    return gfx.AABox {
        left = x0,
        top = y0,
        right = x1,
        bottom = y1,
    }
}

push_sprite :: proc(cmd: vk.CommandBuffer, state: ^MapEditorState, x0: f32, y0: f32, sprite: Sprite, ticks: u32) -> gfx.AABox {
    switch s in sprite {
        case Frame:
            return push_frame(cmd, state, x0, y0, s)
        case Animation:
            t := ticks / s.frame_duration
            i := t % u32(len(s.frames))
            frame := s.frames[i]
            return push_frame(cmd, state, x0, y0, frame)
    }
    panic("Unknown type")
}

push_doodad :: proc(cmd: vk.CommandBuffer, state: ^MapEditorState, x0: f32, y0: f32, doodad: Doodad, ticks: u32) -> gfx.AABox {
    result := gfx.AABox {
        left = x0,
        right = x0,
        top = y0,
        bottom = y0,
    }

    switch s in doodad.sprite {
        case Frame:
            for y in 0..<doodad.tile_height {
                for x in 0..<doodad.tile_width {
                    f := Frame {
                        x = s.x + u32(x * 8),
                        y = s.y + u32(y * 8),
                    }
                    x := x0 + f32(x) * state.tile_width
                    y := y0 + f32(y) * state.tile_height
                    box := push_frame(cmd, state, x, y, f)
                    result.left  = math.min(result.left, box.left)
                    result.right = math.max(result.right, box.right)
                    result.top    = math.min(result.top, box.top)
                    result.bottom = math.max(result.bottom, box.bottom)
                }
            }
        case Animation:
            panic("Not handled")
    }

    return result
}

clicked :: proc (box: gfx.AABox, events: []programs.Event) -> bool {
    for event in events {
        #partial switch e in event {
            case programs.Click:
                if (e.x >= box.left) && (e.x <= box.right) && (e.y >= box.top) && (e.y <= box.bottom) do return true
        }
    }

    return false
}

mouse_down :: proc (box: gfx.AABox, mouse: programs.Mouse) -> bool {
    return mouse.left && (mouse.x >= box.left) && (mouse.x <= box.right) && (mouse.y >= box.top) && (mouse.y <= box.bottom)
}

mouse_over :: proc (box: gfx.AABox, mouse: programs.Mouse) -> bool {
    return (mouse.x >= box.left) && (mouse.x <= box.right) && (mouse.y >= box.top) && (mouse.y <= box.bottom)
}

draw :: proc (cmd: vk.CommandBuffer, vulkan: ^gfx.Vulkan, state: ^MapEditorState, events: []programs.Event, input_state: programs.InputState) {
    max_x := f32(vulkan.swap.extent.width)
    max_y := f32(vulkan.swap.extent.height)

    tile_selector := gfx.AABox {
        left = max_x - 4 * state.tile_width,
        top = 0,
        right = max_x,
        bottom = max_y,
    }

    // NOTE(jan): Map.
    x_tiles := int(tile_selector.left / state.tile_width) + 1
    y_tiles := int(max_y / state.tile_height) + 1

    for y_index in 0..<y_tiles {
        for x_index in 0..<x_tiles {
            x0 := f32(x_index) * state.tile_width - state.scroll_offset[0]
            y0 := f32(y_index) * state.tile_height - state.scroll_offset[1]

            sprite_type := state.terrain[y_index * state.map_width + x_index]
            sprite := SPRITES[sprite_type]

            sprite_box := push_sprite(cmd, state, x0, y0, sprite, input_state.ticks)

            if mouse_down(sprite_box, input_state.mouse) {
                if state.selected_doodad != -1 {
                    state.doodads[y_index * state.map_width + x_index] = state.selected_doodad
                } else if state.selected_sprite != -1 {
                    state.terrain[y_index * state.map_width + x_index] = state.selected_sprite
                }
            }

            // NOTE(jan): Mouse cursor. 
            if mouse_over(sprite_box, input_state.mouse) do push_sprite(cmd, state, x0, y0, CURSOR, input_state.ticks)
        }
    }

    for y_index in 0..<y_tiles {
        for x_index in 0..<x_tiles {
            x0 := f32(x_index) * state.tile_width
            y0 := f32(y_index) * state.tile_height

            doodad_type := state.doodads[y_index * state.map_width + x_index]
            if (doodad_type != -1) {
                doodad := DOODADS[doodad_type]
                push_doodad(cmd, state, x0, y0, doodad, input_state.ticks)
            }
        }
    }

    // NOTE(jan): UI.
    push_box(cmd, state, tile_selector, gfx.base03)

    {
        x0 := tile_selector.left
        y0 := tile_selector.top

        for sprite, index in SPRITES {
            if index % 4 == 0 {
                x0 = tile_selector.left
                y0 += state.tile_height
            }

            sprite_box := push_sprite(cmd, state, x0, y0, sprite, input_state.ticks)
            if clicked(sprite_box, events) {
                state.selected_doodad = -1
                state.selected_sprite = index
            }


            x0 += state.tile_width
        }

        x0 = tile_selector.left
        y0 += state.tile_height

        for doodad, index in DOODADS {
            box := push_doodad(cmd, state, x0, y0, doodad, input_state.ticks)
            if clicked(box, events) {
                state.selected_doodad = index
                state.selected_sprite = -1
            }
        }
    }

    // NOTE(jan): Selected tile indicator
    if state.selected_sprite != -1 {
        x := tile_selector.left + state.tile_width * 1.5
        y := tile_selector.top
        sprite := SPRITES[state.selected_sprite]
        push_sprite(cmd, state, x, y, sprite, input_state.ticks)
    }
}
