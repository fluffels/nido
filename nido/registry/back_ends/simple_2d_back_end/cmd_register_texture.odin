package simple_2d_back_end

import "core:log"
import "core:os"
import path "core:path/filepath"

import image "vendor:stb/image"
import vk "vendor:vulkan"

import "../../../back_end"
import "../../../gfx"
import "../../../gfx/simple_2d_front_end"

TextureRegistration :: struct {
    handle: u32,
    image: gfx.VulkanImage,
}

TextureRegistry :: struct {
    textures: [dynamic]TextureRegistration
}

cmd_register_texture :: proc (state: ^Simple2DBackEnd, command: simple_2d_front_end.RegisterTextureCommand, request: back_end.PrepareFrame) {
    // NOTE(jan): Check if the texture has already been handled.
    for &registration in state.texture_registry.textures {
        if registration.handle == command.handle {
            return
        }
    }

    registration := TextureRegistration {
        handle = command.handle
    }
    append(&state.texture_registry.textures, registration)

    sprite_sheet_path := path.join({".", "textures", command.fname}, context.temp_allocator)
    sprite_sheet_filename, _ := path.to_slash(sprite_sheet_path, context.temp_allocator)
    sprite_sheet_bytes, success := os.read_entire_file_from_filename(sprite_sheet_filename, context.temp_allocator)

    if !success {
        log.errorf("Failed to read file '%s'.", sprite_sheet_filename)
    }  else {
        x, y, n : i32 = 0, 0, 0
        sprite_sheet_pixels := image.load_from_memory(raw_data(sprite_sheet_bytes), i32(len(sprite_sheet_bytes)), &x, &y, &n, 4)

        if sprite_sheet_pixels == nil {
            log.errorf("Could not read PNG file '%s'.", sprite_sheet_filename)
        } else {
            extent := vk.Extent2D { u32(x), u32(y) }
            size := extent.height * extent.width * u32(n)

            pixels: []u8 = sprite_sheet_pixels[0:size]

            registration.image = gfx.vulkan_image_create_2d_rgba_texture(request.vulkan, extent)
            gfx.vulkan_image_update_texture(
                request.vulkan,
                request.cmd,
                pixels,
                registration.image,
            )
            image.image_free(sprite_sheet_pixels)
        }
    }

    // TODO(jan): This allocates memory on the video card. It should be deallocated when no longer needed.
}
