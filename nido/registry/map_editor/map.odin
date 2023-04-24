package map_editor

import "core:log"
import "core:fmt"
import path "core:path/filepath"
import "core:os"

load_map :: proc (state: ^MapEditorState) {
    map_path := path.join({".", "map.dat"}, context.temp_allocator)
    map_filename, _ := path.to_slash(map_path, context.temp_allocator)
    map_bytes, success := os.read_entire_file_from_filename(map_filename, context.temp_allocator)

    if !success {
        log.warnf("Failed to open file %s", map_filename)
        return
    }

    for i in 0..<state.map_height*state.map_width {
        state.terrain[i] = int(map_bytes[i*4 + 0]) <<  0 |
                           int(map_bytes[i*4 + 1]) <<  8 |
                           int(map_bytes[i*4 + 2]) << 16 |
                           int(map_bytes[i*4 + 3]) << 24
    }
}

save_map :: proc (state: ^MapEditorState) {
    map_path := path.join({".", "map.dat"}, context.temp_allocator)
    map_filename, _ := path.to_slash(map_path, context.temp_allocator)

    f, errno := os.open(map_filename, os.O_WRONLY | os.O_TRUNC | os.O_CREATE)
    if errno != 0 do fmt.panicf("Failed to open file %s", map_filename)

    bytes := make([]u8, len(state.terrain) * 4, context.temp_allocator)
    for type, index in state.terrain {
        bytes[index*4 + 0] = u8((type      ) & 0xFF);
        bytes[index*4 + 1] = u8((type >>  8) & 0xFF);
        bytes[index*4 + 2] = u8((type >> 16) & 0xFF);
        bytes[index*4 + 3] = u8((type >> 24) & 0xFF);
    }

    os.write(f, bytes)
    os.close(f)
}
