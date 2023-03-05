package jcwk

import "core:log"
import "core:strings"

OpCode :: enum u32 {
    Name = 5,
    TypeVoid = 2,
    TypeFloat = 22,
    TypeVector = 23,
    TypeMatrix = 24,
    TypePointer = 32,
    Variable = 59,
    Decorate = 71,
    DecorateMember = 72,
}

Endianness :: enum {
    Little,
    Big,
}

DecorationLocation :: 30

MagicHeader :: 0x07230203

@(private)
State :: struct {
    endianness: Endianness,
    index: int,
    bytes: []u8,
}

advance_bytes :: proc(state: ^State, count: int) {
    using state

    index += count
}

advance_words :: proc(state: ^State, count: int) {
    using state

    index += count*4
}

get_bytes :: proc(state: ^State, count: int) -> (result: []u8) {
    using state

    result = bytes[index:][:count]
    advance_bytes(state, count)

    return result
}

getw :: proc(state: ^State) -> (word: u32) {
    using state

    word = 0

    if endianness == Endianness.Big {
        word = word | (u32(bytes[index])   << 24)
        word = word | (u32(bytes[index+1]) << 16)
        word = word | (u32(bytes[index+2]) <<  8)
        word = word | (u32(bytes[index+3]) <<  0)
    } else {
        word = word | (u32(bytes[index])   <<  0)
        word = word | (u32(bytes[index+1]) <<  8)
        word = word | (u32(bytes[index+2]) << 16)
        word = word | (u32(bytes[index+3]) << 24)
    }

    advance_words(state, 1)

    return word
}

done :: proc(state: ^State) -> bool {
    using state
    return index >= len(bytes)
}

parse :: proc(
    bytes: []u8
) -> (
    ok: b32
) {
    loc_to_var := make(map[u32]u32, 1, context.temp_allocator)
    var_to_type_pointer := make(map[u32]u32, 1, context.temp_allocator)
    type_pointer_to_type := make(map[u32]u32, 1, context.temp_allocator)
    type_to_data := make(map[u32]u64, 1, context.temp_allocator)
    id_to_string := make(map[u32]u64, 1, context.temp_allocator)
    types := make([dynamic]u32, 1, context.temp_allocator)
    names := make([dynamic]u32, 1, context.temp_allocator)

    state := State {
        endianness = Endianness.Big,
        index = 0,
        bytes = bytes,
    }
    using state

    magic := getw(&state)
    if magic != MagicHeader {
        endianness = Endianness.Little
        index = 0

        magic := getw(&state)
        if magic != MagicHeader {
            log.fatal("not a spirv file")
            return false
        }
    }

    version := getw(&state)
    generator := getw(&state)
    bound := getw(&state)
    instruction_schema := getw(&state)

    for !done(&state) {
        op_code := getw(&state)
        if done(&state) do break

        op_code_enumerant := OpCode(op_code & 0xFFFF)
        word_count: u32 = op_code >> 16

        #partial switch op_code_enumerant {
            case OpCode.Name:
                log.infof("word count %d", word_count)
                target_id := getw(&state)
                id_to_string[target_id] = u64(len(names))

                byte_count := int((word_count-2)*4)
                bytes := get_bytes(&state, byte_count)
                name := odinize_string(bytes)
                log.infof("name %d = %s", target_id, name)
            case:
                advance_words(&state, int(word_count-1))
        }
    }

    return true
}

//     while (!done) {
//         u32 opCode = getw();
//         if (done) break;

//         switch (opCodeEnumerant) {
//             case OpName:
//             {
//                 auto targetId = getw();
//                 hmput(idToString, targetId, arrlen(stringData));
//                 auto s = (char*)(buffer + currentWord);
//                 INFO("name %d %.*s", targetId, (wordCount - 2)*4, s);
//                 for (u32 i = 2; i < wordCount; i++) {
//                     auto word = getw();
//                     arrput(stringData, word);
//                 }
//             }
//             break;
//             case OpTypeVector:
//             case OpTypeFloat:
//             {
//                 // Supported types.
//                 auto resultId = getw();
//                 hmput(typeToData, resultId, arrlen(typeData));
//                 arrput(typeData, opCodeEnumerant);
//                 for (u32 i = 2; i < wordCount; i++) {
//                     auto word = getw();
//                     arrput(typeData, word);
//                 }
//                 INFO("type %d", resultId);
//             }
//             break;
//             case OpTypePointer: {
//                 auto resultId = getw();
//                 auto storage = getw();
//                 auto typeId = getw();
//                 INFO("type* %d -> typeId %d", resultId, typeId);
//                 hmput(typePointerToType, resultId, typeId);
//             }
//             break;
//             case OpVariable: {
//                 auto resultType = getw();
//                 auto resultId = getw();
//                 auto storageClass = getw();
//                 if (wordCount > 4) {
//                     auto initializer = getw();
//                     INFO("var %d: %d = initializer %d", resultId, resultType, initializer);
//                 } else {
//                     INFO("var %d: %d", resultId, resultType);
//                 }
//                 hmput(variableToTypePointer, resultId, resultType);
//             }
//             break;
//             case OpDecorate: {
//                 auto id = getw();
//                 auto decoration = getw();
//                 if ((decoration == DecorationLocation) && (wordCount > 3)) {
//                     auto location = getw();
//                     hmput(locationToVariable, location, id);
//                     INFO("%d is at location %d", id, location);
//                 } else {
//                     INFO("decorate %d with %d", id, decoration);
//                 }
//             }
//             break;
//             case OpDecorateMember: {
//                 auto stype = getw();
//                 auto member = getw();
//                 auto decoration = getw();
//                 INFO("decorate member %d of %d with %d", member, stype, decoration);
//             }
//             break;
//         }
//     }

//     auto outFile = openFile("out", "w");
//     for (i32 i = 0; i < hmlen(locationToVariable); i++) {
//         auto locationVariablePair = locationToVariable[i];
//         auto location = locationVariablePair.key;
//         auto variable = locationVariablePair.value;
//         auto typePointer = hmget(variableToTypePointer, variable);
//         auto type = hmget(typePointerToType, typePointer);
//         auto data = hmget(typeToData, type);

//         fprintf(outFile, "struct Vertex {\n");
//         if (OpTypeVector == typeData[data]) {
//             auto componentType = typeData[++data];
//             auto componentData = hmget(typeToData, componentType);
//             if (OpTypeFloat != typeData[componentData]) {
//                 FATAL("unsupported component type");
//             }
//             auto componentCount = typeData[++data];
//             auto stringIdx = hmget(idToString, variable);
//             auto string = (char*)(stringData + stringIdx);
//             fprintf(outFile, "    Vec%d %s;\n", componentCount, string);
//         }
//         fprintf(outFile, "};\n");
//     }

//     return 0;
// }
