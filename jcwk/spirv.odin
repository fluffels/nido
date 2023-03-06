package jcwk

import "core:log"
import "core:strings"

/**********************
 * Types for export . *
 **********************/

Dimensionality :: enum {
    VOID = -1,
    SCALAR = 0,
    VECTOR = 1,
    MATRIX = 2,
}

ScalarType :: enum {
    SIGNED_INT,
    UNSIGNED_INT,
    FLOAT,
}

ScalarDescription :: struct {
    type: ScalarType,
    // NOTE(jan): in bytes
    width: int,
}

ComponentDescription :: union {
    ScalarDescription,
    ^TypeDescription,
}

TypeDescription :: struct {
    dimensions: Dimensionality,
    component_type: ComponentDescription,
}

/****************************
 * Types for internal use . *
 ****************************/

SpirvStorageClass :: enum u32 {
    UniformConstant = 0,
    Input = 1,
    Uniform = 2,
    Output = 3,
    // NOTE(jan): These are ones we need. There are many more.
    // SEE(jan): https://registry.khronos.org/SPIR-V/specs/unified1/SPIRV.html#Storage_Class
}

SpirvVoid :: struct {
    id: u32,
}

SpirvInt :: struct {
    id: u32,
    // NOTE(jan): Width in bits.
    width: u32,
    // NOTE(jan): 0 means unsigned, 1 means signed
    signed: u32,
}

SpirvFloat :: struct {
    id: u32,
    // NOTE(jan): Width in bits.
    width: u32,
}

SpirvVec :: struct {
    id: u32,
    component_type_id: u32,
    component_count: u32,
}

SpirvMatrix :: struct {
    id: u32,
    column_type_id: u32,
    column_count: u32,
}

SpirvType :: union {
    SpirvVoid,
    SpirvFloat,
    SpirvVec,
    SpirvMatrix,
}

SpirvPointer :: struct {
    id: u32,
    type_id: u32,
    storage_class: SpirvStorageClass,
}

SpirvVar :: struct {
    id: u32,
    type_id: u32,
    storage_class: SpirvStorageClass,
}

/**************************
 * Parsing related types. *
 **************************/

@(private)
OpCode :: enum u32 {
    Name = 5,
    TypeVoid = 2,
    TypeInt = 21,
    TypeFloat = 22,
    TypeVector = 23,
    TypeMatrix = 24,
    TypePointer = 32,
    Variable = 59,
    Decorate = 71,
    DecorateMember = 72,
}

@(private)
Endianness :: enum {
    Little,
    Big,
}

@(private)
DecorationLocation :: 30

@(private)
MagicHeader :: 0x07230203

@(private)
State :: struct {
    endianness: Endianness,
    index: int,
    bytes: []u8,
}

@(private)
advance_bytes :: proc(state: ^State, count: int) {
    using state

    index += count
}

@(private)
advance_words :: proc(state: ^State, count: int) {
    using state

    index += count*4
}

@(private)
get_bytes :: proc(state: ^State, count: int) -> (result: []u8) {
    using state

    result = bytes[index:][:count]
    advance_bytes(state, count)

    return result
}

@(private)
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

@(private)
done :: proc(state: ^State) -> bool {
    using state
    return index >= len(bytes)
}

parse :: proc(
    bytes: []u8,
) -> (
    ok: b32,
) {
    // loc_to_var := make(map[u32]u32, 1, context.temp_allocator)
    // var_to_type_pointer := make(map[u32]u32, 1, context.temp_allocator)
    // type_pointer_to_type := make(map[u32]u32, 1, context.temp_allocator)
    // type_to_data := make(map[u32]u64, 1, context.temp_allocator)
    types    := make(map[u32]SpirvType   , 1, context.temp_allocator)
    names    := make(map[u32]string      , 1, context.temp_allocator)
    vars     := make(map[u32]SpirvVar    , 1, context.temp_allocator)
    pointers := make(map[u32]SpirvPointer, 1, context.temp_allocator)

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
            // NOTE(jan): Declares the void type.
            case OpCode.TypeVoid:
                type: SpirvVoid;
                type.id = getw(&state)
                types[type.id] = type
                // log.infof("type #%d is void", result_id)
            // NOTE(jan): Declares a new int type.
            case OpCode.TypeInt:
                type: SpirvInt
                type.id = getw(&state)
                type.width = getw(&state)
                type.signed = getw(&state)
            // NOTE(jan): Declares a new float type.
            case OpCode.TypeFloat:
                type: SpirvFloat
                type.id = getw(&state);
                type.width = getw(&state);
                types[type.id] = type
                // log.infof("type #%d is an f%d", result_id, width)
            // NOTE(jan): Declares a new vector type.
            case OpCode.TypeVector:
                type: SpirvVec
                type.id = getw(&state)
                type.component_type_id = getw(&state)
                type.component_count = getw(&state)
                types[type.id] = type
                // log.infof("type #%d is a vec%d of type #%d", result_id, component_count, component_type_id)
            // NOTE(jan): Declares a new matrix type.
            case OpCode.TypeMatrix:
                type: SpirvMatrix
                type.id = getw(&state)
                type.column_type_id = getw(&state)
                type.column_count = getw(&state)
                types[type.id] = type
            case OpCode.TypePointer: {
                pointer: SpirvPointer
                pointer.id = getw(&state)
                pointer.storage_class = SpirvStorageClass(getw(&state))
                pointer.type_id = getw(&state)
                pointers[pointer.id] = pointer
            }
            // NOTE(jan): (Debug info) name for an id
            case OpCode.Name:
                target_id := getw(&state)

                byte_count := int((word_count-2)*4)
                bytes := get_bytes(&state, byte_count)
                name := odinize_string(bytes)
                
                names[target_id] = name
                log.infof("name %d = %s", target_id, name)
            // NOTE(jan): Declares a variable
            case OpCode.Variable:
                var: SpirvVar
                var.type_id = getw(&state)
                var.id = getw(&state)
                var.storage_class = SpirvStorageClass(getw(&state))
                words_left := word_count - 4
                if words_left > 0 do advance_words(&state, int(words_left))
                vars[var.id] = var
            // NOTE(jan): Unhandled opcode.
            case:
                advance_words(&state, int(word_count-1))
        }
    }

    for _, var in vars {
        if var.storage_class == SpirvStorageClass.Input {
            pointer := pointers[var.type_id]
            type := types[pointer.type_id]
            name := names[var.id]
            log.info(name)
            log.info(var)
            log.info(type)

            switch t in type {
                case SpirvVoid:
                    // NOTE(jan): don't have to do anything here
                case SpirvVec:
                    log.info("vec")
                case SpirvFloat:
                    // TODO(jan): implement
                case SpirvMatrix:
                    // TODO(jan): implement
                case:
                    panic("unknown type")
            }
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
