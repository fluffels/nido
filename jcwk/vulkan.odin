package jcwk

import "core:strings"

vulkanize_strings :: proc(from: [dynamic]string) -> (to: [^]cstring) {
    to = make([^]cstring, len(from), context.temp_allocator)
    for s, i in from {
        to[i] = strings.clone_to_cstring(s, context.temp_allocator)
    }
    return to
}
