package nido

import "core:strings"

odinize_string :: proc(from: []u8) -> (to: string) {
    end := 0
    for char in from {
        if char != 0 do end += 1
        else do break
    }
    slice := from[:end]
    to = strings.clone_from_bytes(slice, context.temp_allocator)
    return to
}

vulkanize :: proc(from: [$N]$T) -> (to: [^]T) {
    to = make([^]T, len(from), context.temp_allocator)
    for i in 0..<len(from) {
        to[i] = from[i]
    }
    return to
}

vulkanize_strings :: proc(from: [dynamic]string) -> (to: [^]cstring) {
    to = make([^]cstring, len(from), context.temp_allocator)
    for s, i in from {
        to[i] = strings.clone_to_cstring(s, context.temp_allocator)
    }
    return to
}
