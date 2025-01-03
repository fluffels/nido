package font

import "core:log"
import "core:os"
import "core:unicode/utf8"

import stbttf "vendor:stb/truetype"

FontMetadata :: struct {
    name: string,
    path: string,
    size: f32,
    supersample: u32,
    // NOTE(jan): A list of glyphs that are known to be needed. These will always be marked for loading.
    glyphs: []rune,
}

DEFAULT_GLYPHS := [?]rune{
    0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x2b,
    0x2c, 0x2d, 0x2e, 0x2f, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37,
    0x38, 0x39, 0x3a, 0x3b, 0x3c, 0x3d, 0x3e, 0x3f, 0x40, 0x41, 0x42, 0x43,
    0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x4b, 0x4c, 0x4d, 0x4e, 0x4f,
    0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x5b,
    0x5c, 0x5d, 0x5e, 0x5f, 0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67,
    0x68, 0x69, 0x6a, 0x6b, 0x6c, 0x6d, 0x6e, 0x6f, 0x70, 0x71, 0x72, 0x73,
    0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x7b, 0x7c, 0x7d, 0x7e, 0xe5,
    0xe4, 0xf6, 0xc5, 0xc4, 0xd6,
}

FONT_METADATA := [?]FontMetadata{
    {
        name = "default",
        path = "./fonts/FiraCode-Bold.ttf",
        // path = "./fonts/AkkuratPro-Regular.ttf",
        size = 20,
        supersample = 2,
        glyphs = DEFAULT_GLYPHS[:],
    },
}

FontFlags :: enum {
    INVALID = 1 << 1,
    DIRTY   = 1 << 2,
}

FontVersion :: struct {
    flags: bit_set[FontFlags],
    size: f32,
    packedchars: map[rune]stbttf.packedchar,
    missing_packedchar: stbttf.packedchar,
}

Font :: struct {
    metadata: FontMetadata,
    flags: bit_set[FontFlags],
    ttf: []u8,
    info: stbttf.fontinfo,
    codepoints: map[rune]b32,
    versions: [dynamic]FontVersion,
}

get_font :: proc(
    fonts: []Font,
    name: string,
) -> (
    font: ^Font,
) {
    for &font in fonts do if font.metadata.name == name do return &font
    return nil
}

mark_codepoint_for_loading :: proc(
    font: ^Font,
    codepoint: rune
) {
    font.codepoints[codepoint] = true
}

load_fonts :: proc () -> [dynamic]Font {
    fonts := make([dynamic]Font, len(FONT_METADATA))
    for i in 0..<len(fonts) {
        font := &fonts[i]
        font.metadata = FONT_METADATA[i]

        read_success: bool
        font.ttf, read_success = os.read_entire_file_from_filename(font.metadata.path)
        if !read_success {
            log.errorf("Could not read file from %s.", font.metadata.path)
            font.flags |= {FontFlags.INVALID}
            continue
        }

        success := stbttf.InitFont(&font.info, raw_data(font.ttf), 0)
        if !success {
            log.errorf("Could not parse font info for font %s.", font.metadata.name)
            font.flags |= {FontFlags.INVALID}
            continue
        }

        for codepoint in font.metadata.glyphs {
            mark_codepoint_for_loading(font, codepoint)
        }

        append(&font.versions, FontVersion {
            size = font.metadata.size,
        })
    }

    return fonts
}

pack_fonts_into_texture :: proc (
    fonts: [dynamic]Font,
) -> (
    bitmap: [dynamic]u8,
    success: b32,
) {
    height: i32 = 512
    width: i32 = 512
    bitmap_size := height * width
    bitmap = make([dynamic]u8, bitmap_size)

    pack_context: stbttf.pack_context
    success = stbttf.PackBegin(&pack_context, raw_data(bitmap), width, height, 0, 1, nil) != 0
    if !success {
        log.errorf("Could not begin font pack.")
        return
    }

    max_x: f32 = 0
    max_y: f32 = 0

    for &font in fonts {
        stbttf.PackSetOversampling(&pack_context, font.metadata.supersample, font.metadata.supersample)

        for &version in font.versions {
            // NOTE(jan): Always load missing glyph marker. It is at index 0 by convention.
            stbttf.PackFontRange(
                &pack_context,
                raw_data(font.ttf),
                0,
                version.size,
                0, 1,
                &version.missing_packedchar,
            )

            for codepoint in font.codepoints {
                if font.codepoints[codepoint] == false do continue

                packedchar: stbttf.packedchar
                result := stbttf.PackFontRange(
                    &pack_context,
                    raw_data(font.ttf),
                    0,
                    version.size,
                    cast(i32)codepoint, 1,
                    &packedchar,
                )

                if result == 0 {
                    log.errorf("Could not pack %r.", codepoint)
                    font.codepoints[codepoint] = false
                    continue
                }

                version.packedchars[codepoint] = packedchar

                q: stbttf.aligned_quad
                x: f32 = 0
                y: f32 = 0
                stbttf.GetPackedQuad(
                    &packedchar, 
                    width, height,
                    0,
                    &x, &y,
                    &q,
                    false,
                )
                if q.s1 > max_x do max_x = q.s1
                if q.t1 > max_y do max_y = q.t1
            }
        }
    }
    
    if (max_x > .9) && (max_y > .9) {
        log.warnf("Font atlas nearly full: %f %f", max_x, max_y)
    }

    return
}

get_packedchar :: proc (
    font: ^Font,
    version: ^FontVersion,
    codepoint: rune,
) -> (
    packedchar: stbttf.packedchar,
    requires_repack: b32,
) {
    requires_repack = false
    
    if codepoint in version.packedchars {
        packedchar = version.packedchars[codepoint]
    } else {
        packedchar = version.missing_packedchar
        if codepoint in font.codepoints == false {
            log.warnf("Marking %r for loading.", codepoint)
            font.codepoints[codepoint] = true
        }
        requires_repack = font.codepoints[codepoint] == true
    }

    return
}

get_aligned_quad :: proc (
    font: ^Font,
    version: ^FontVersion,
    x: ^f32,
    y: ^f32,
    codepoint: rune,
) -> (
    aligned_quad: stbttf.aligned_quad,
    requires_repack: b32
) {
    packedchar: stbttf.packedchar
    packedchar, requires_repack = get_packedchar(font, version, codepoint)

    // TODO(jan): Link in texture here so we can read height and width from it.
    height: i32 = 512
    width: i32 = 512
    stbttf.GetPackedQuad(&packedchar, width, height, 0, x, y, &aligned_quad, false)

    return
}
