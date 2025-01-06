package terminal_app

import "../../../font"
import "../../../logext"

Terminal:: struct {
    top_down: b32,
    line_offset: int,

    log_data: ^logext.Circular_Buffer_Logger_Data,
    fonts: [dynamic]font.Font,
    sprite_sheet_handle: Maybe(u32),

    repack_required: b32,
}
