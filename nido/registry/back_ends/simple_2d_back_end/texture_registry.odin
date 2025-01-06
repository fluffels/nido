package simple_2d_back_end

import "../../../gfx"

TextureRegistration :: struct {
    handle: u32,
    image: gfx.VulkanImage,
}

TextureRegistry :: struct {
    textures: [dynamic]TextureRegistration
}
