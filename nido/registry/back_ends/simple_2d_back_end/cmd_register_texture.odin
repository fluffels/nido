package simple_2d_back_end

import "core:log"
import "core:os"
import path "core:path/filepath"

import image "vendor:stb/image"
import vk "vendor:vulkan"

import "../../../back_end"
import "../../../gfx"
import "../../../gfx/simple_2d_front_end"

cmd_register_texture :: proc (state: ^Simple2DBackEnd, command: simple_2d_front_end.RegisterTextureCommand, request: back_end.PrepareFrame) {
    // NOTE(jan): Check if the texture has already been registered.
    for &registration in state.texture_registry.textures {
        if registration.handle == command.handle {
            return
        }
    }

    // NOTE(jan): Otherwise register the texture.
    registration := TextureRegistration {
        handle = command.handle
    }
    append(&state.texture_registry.textures, registration)
}
