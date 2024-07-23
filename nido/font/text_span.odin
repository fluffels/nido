package font

import linalg "core:math/linalg"
import stbttf "vendor:stb/truetype"
import unicode "core:unicode/utf8"

Glyph :: struct {
    codepoint: rune,
    quad: stbttf.aligned_quad,
}

TextSpan :: struct {
    text: string,
    glyphs: [dynamic]Glyph,
    line_length: f32,
    extent: linalg.Vector2f32,
}

translate_span :: proc (
    span: ^TextSpan,
) {
    runes := unicode.string_to_runes(span.text, context.temp_allocator)
    span.glyphs = make([dynamic]Glyph, len(runes))

    for r, i in runes {
        span.glyphs[i].codepoint = r
    }
}

layout_span :: proc (
    font: ^Font,
    version: ^FontVersion,
    span: ^TextSpan,
) -> (
    repack_required: b32
) {
    repack_required = false

    x: f32 = 0
    y: f32 = 0

    for &glyph in span.glyphs {
        tab := glyph.codepoint == 9
        newline := glyph.codepoint == 10
        past_end := x > span.line_length
        if past_end || newline {
            y += 20
            x = 0
        }
        
        if newline do continue
        // TODO(jan): Fix
        if tab {
            x += 40
            continue
        }

        glyph.quad, repack_required = get_aligned_quad(
            font,
            version,
            &x, &y,
            glyph.codepoint
        )
        span.extent.y = min(span.extent.y, glyph.quad.y0)
    }

    span.extent.x = x

    return
}

delete_span :: proc (
    span: ^TextSpan
) {
    delete(span.glyphs)
}
