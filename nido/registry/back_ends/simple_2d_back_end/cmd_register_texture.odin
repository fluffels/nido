package simple_2d_back_end

import "../../../gfx/simple_2d_front_end"

cmd_register_texture :: proc (state: ^Simple2DBackEnd, command: simple_2d_front_end.RegisterTextureCommand) {
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
