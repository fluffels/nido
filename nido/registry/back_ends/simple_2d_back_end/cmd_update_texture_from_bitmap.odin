package simple_2d_back_end

import "core:log"
import "core:os"
import path "core:path/filepath"

import image "vendor:stb/image"
import vk "vendor:vulkan"

import "../../../back_end"
import "../../../gfx"
import "../../../gfx/simple_2d_front_end"

cmd_update_texture_from_bitmap :: proc (state: ^Simple2DBackEnd, cmd: simple_2d_front_end.UpdateTextureFromBitmapCommand, request: back_end.PrepareFrame) {
    // NOTE(jan): Check if the texture has already been handled.
    for &registration in state.texture_registry.textures {
        if registration.handle == cmd.handle {
            sprite_sheet_pixels := cmd.bitmap

            extent := vk.Extent2D { cmd.width, cmd.height }
            size := extent.height * extent.width * cmd.depth

            pixels: []u8 = sprite_sheet_pixels[0:size]

            registration.image = gfx.vulkan_image_create_2d_monochrome_texture(request.vulkan, extent)
            gfx.vulkan_image_update_texture(
                request.vulkan,
                request.cmd,
                pixels,
                registration.image,
            )
            return
        }
    }

    log.errorf("No texture registered with handle %v", cmd.handle)

    // TODO(jan): This allocates memory on the video card. It should be deallocated when no longer needed.
}
