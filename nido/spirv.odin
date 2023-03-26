package nido

import "core:log"
import "core:strings"

/**********************
 * Types for export . *
 **********************/

Endianness :: enum {
    Little,
    Big,
}

Dimensionality :: enum {
    VOID = -1,
    SCALAR = 0,
    VECTOR = 1,
    MATRIX = 2,
    ARRAY = 3,
    STRUCT = 4,
}

ScalarType :: enum {
    VOID = -1,
    SIGNED_INT = 0,
    UNSIGNED_INT = 1,
    FLOAT = 2,
}

ScalarDescription :: struct {
    type: ScalarType,
    // NOTE(jan): in bytes
    width: int,
}

StructDescription :: struct {
    fields: [dynamic]TypeDescription,
}

ComponentDescription :: union {
    ScalarDescription,
    ^TypeDescription,
    StructDescription,
}

TypeDescription :: struct {
    dimensions: Dimensionality,
    component_type: ComponentDescription,
    component_count: int,
}

VariableDescription :: struct {
    name: string,
    type: TypeDescription,
}

ShaderType :: enum {
    Vertex,
    Fragment,
}

ShaderDescription :: struct {
    name: string,
    type: ShaderType,
    inputs: [dynamic]VariableDescription,
    outputs: [dynamic]VariableDescription,
    uniforms: [dynamic]VariableDescription,
}

ShaderModuleDescription :: struct {
    endianness: Endianness,
    shaders: [dynamic]ShaderDescription,
}

/****************************
 * Types for internal use . *
 ****************************/

@(private)
SpirvExecutionModel :: enum u32 {
    Vertex = 0,
    TesselationControl = 1,
    TesselationEvaluation = 2,
    Geometry = 3,
    Fragment = 4,
    Compute = 5,
    Kernel = 6,
}

@(private)
SpirvStorageClass :: enum u32 {
    UniformConstant = 0,
    Input = 1,
    Uniform = 2,
    Output = 3,
    // NOTE(jan): These are ones we need. There are many more.
    // SEE(jan): https://registry.khronos.org/SPIR-V/specs/unified1/SPIRV.html#Storage_Class
}

@(private)
SpirvEntryPoint :: struct {
    id: u32,
    name: string,
    execution_model: SpirvExecutionModel,
    interface_ids: [dynamic]u32,
}

@(private)
SpirvVoid :: struct {
    id: u32,
}

@(private)
SpirvBool :: struct {
    id: u32,
}

@(private)
SpirvInt :: struct {
    id: u32,
    // NOTE(jan): Width in bits.
    width: u32,
    // NOTE(jan): 0 means unsigned, 1 means signed
    signed: u32,
}

@(private)
SpirvFloat :: struct {
    id: u32,
    // NOTE(jan): Width in bits.
    width: u32,
}

@(private)
SpirvVec :: struct {
    id: u32,
    component_type_id: u32,
    component_count: u32,
}

@(private)
SpirvMatrix :: struct {
    id: u32,
    column_type_id: u32,
    column_count: u32,
}

@(private)
SpirvArray :: struct {
    id: u32,
    element_type_id: u32,
    length: u32,
}

@(private)
SpirvStruct :: struct {
    id: u32,
    element_type_ids: [dynamic]u32,
}

@(private)
SpirvFunction :: struct {
    id: u32,
    return_type_id: u32,
    parameter_type_ids: [dynamic]u32,
}

@(private)
SpirvType :: union {
    SpirvVoid,
    SpirvBool,
    SpirvFloat,
    SpirvVec,
    SpirvMatrix,
    SpirvArray,
    SpirvStruct,
    SpirvFunction,
}

@(private)
SpirvPointer :: struct {
    id: u32,
    type_id: u32,
    storage_class: SpirvStorageClass,
}

@(private)
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
    EntryPoint = 15,
    TypeVoid = 19,
    TypeBool = 20,
    TypeInt = 21,
    TypeFloat = 22,
    TypeVector = 23,
    TypeMatrix = 24,
    TypeArray = 28,
    TypeStruct = 30,
    TypePointer = 32,
    TypeFunction = 33,
    Variable = 59,
    Decorate = 71,
    DecorateMember = 72,
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
get_string :: proc(state: ^State) -> (result: string, words_read: u32) {
    using state

    length := 0
    for bytes[index + length] != 0 {
        length += 1
    }
    // NOTE(jan): One more for the null terminator.
    length += 1
    for length % 4 != 0 {
        length += 1
    }

    result = odinize_string(get_bytes(state, length))
    words_read = u32(length / 4)
    return
}

@(private)
done :: proc(state: ^State) -> bool {
    using state
    return index >= len(bytes)
}

fill_type_description :: proc(
    type_id: u32,
    types: map[u32]SpirvType,
    description: ^TypeDescription,
) {
    log.infof("fill %d", type_id)
    type := types[type_id]
    switch t in type {
        case SpirvVoid:
            description.dimensions = Dimensionality.VOID
            description.component_type = ScalarDescription {
                ScalarType.VOID,
                0,
            }
            description.component_count = 0
        case SpirvBool:
            description.dimensions = Dimensionality.SCALAR
            description.component_type = ScalarDescription {
                ScalarType.SIGNED_INT,
                4,
            }
            description.component_count = 1
        case SpirvFloat:
            description.dimensions = Dimensionality.SCALAR
            description.component_type = ScalarDescription {
                ScalarType.FLOAT,
                4,
            }
            description.component_count = 1
        case SpirvVec:
            description.dimensions = Dimensionality.VECTOR
            scalar_type_id := t.component_type_id
            scalar_type := new(TypeDescription)
            fill_type_description(scalar_type_id, types, scalar_type)
            description.component_type = scalar_type
            description.component_count = int(t.component_count)
        case SpirvMatrix:
            description.dimensions = Dimensionality.MATRIX
            vector_type_id := t.column_type_id
            vector_type := new(TypeDescription)
            fill_type_description(vector_type_id, types, vector_type)
            description.component_type = vector_type
            description.component_count = int(t.column_count)
        case SpirvArray:
            description.dimensions = Dimensionality.ARRAY
            scalar_type_id := t.element_type_id
            scalar_type := new(TypeDescription)
            fill_type_description(scalar_type_id, types, scalar_type)
            description.component_type = scalar_type
            description.component_count = int(t.length)
        case SpirvStruct:
            struct_description := StructDescription {
                fields = make([dynamic]TypeDescription),
            }
            for element_type_id in t.element_type_ids {
                field_index := len(struct_description.fields)
                append(&struct_description.fields, TypeDescription {})
                field := struct_description.fields[field_index]
                fill_type_description(element_type_id, types, &field)
            }
            description.dimensions = Dimensionality.STRUCT
            description.component_type = struct_description
            description.component_count = len(t.element_type_ids)
        case SpirvFunction:
            panic("function types not handled")
        case:
            panic("unknown type")
    }
}

parse :: proc(
    bytes: []u8,
) -> (
    description: ShaderModuleDescription,
    ok: b32,
) {
    ok = false

    entry_points := make([dynamic]SpirvEntryPoint,    context.temp_allocator)
    types        := make(map[u32]SpirvType       , 1, context.temp_allocator)
    names        := make(map[u32]string          , 1, context.temp_allocator)
    vars         := make(map[u32]SpirvVar        , 1, context.temp_allocator)
    pointers     := make(map[u32]SpirvPointer    , 1, context.temp_allocator)

    state := State {
        endianness = Endianness.Big,
        index = 0,
        bytes = bytes,
    }
    using state

    if (len(bytes) % 4 != 0) {
        log.fatal("file does not contain an even count of words")
        return
    }

    magic := getw(&state)
    if magic != MagicHeader {
        endianness = Endianness.Little
        index = 0

        magic := getw(&state)
        if magic != MagicHeader {
            log.fatal("not a spirv file")
            return
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
            // NOTE(jan): (Debug info) name for an id
            case OpCode.Name:
                target_id := getw(&state)

                byte_count := int((word_count-2)*4)
                bytes := get_bytes(&state, byte_count)
                name := odinize_string(bytes)
                
                names[target_id] = name
            case OpCode.EntryPoint:
                entry: SpirvEntryPoint
                entry.execution_model = SpirvExecutionModel(getw(&state))
                entry.id = getw(&state)

                string_words: u32
                entry.name, string_words = get_string(&state)

                entry.interface_ids = make([dynamic]u32, context.temp_allocator)
                for i in 3+string_words..<word_count {
                    append(&entry.interface_ids, getw(&state))
                }

                append(&entry_points, entry)
            // NOTE(jan): Declares the void type.
            case OpCode.TypeVoid:
                type: SpirvVoid
                type.id = getw(&state)
                types[type.id] = type
                log.infof("void %d", type.id)
            // NOTE(jan): Declares a new bool type.
            case OpCode.TypeBool:
                type: SpirvBool
                type.id = getw(&state)
                types[type.id] = type
                log.infof("bool %d", type.id)
            // NOTE(jan): Declares a new int type.
            case OpCode.TypeInt:
                type: SpirvInt
                type.id = getw(&state)
                type.width = getw(&state)
                type.signed = getw(&state)
                log.infof("int %d %d %d", type.id, type.width, type.signed)
            // NOTE(jan): Declares a new float type.
            case OpCode.TypeFloat:
                type: SpirvFloat
                type.id = getw(&state);
                type.width = getw(&state);
                types[type.id] = type
                log.infof("float %d %d", type.id, type.width)
            // NOTE(jan): Declares a new vector type.
            case OpCode.TypeVector:
                type: SpirvVec
                type.id = getw(&state)
                type.component_type_id = getw(&state)
                type.component_count = getw(&state)
                log.infof("vector %d %d %d", type.id, type.component_type_id, type.component_count)
                types[type.id] = type
            // NOTE(jan): Declares a new matrix type.
            case OpCode.TypeMatrix:
                type: SpirvMatrix
                type.id = getw(&state)
                type.column_type_id = getw(&state)
                type.column_count = getw(&state)
                log.infof("matrix %d %d %d", type.id, type.column_type_id, type.column_count)
                types[type.id] = type
            case OpCode.TypeArray:
                type: SpirvArray
                type.id = getw(&state)
                type.element_type_id = getw(&state)
                type.length = getw(&state)
                types[type.id] = type
            case OpCode.TypeStruct:
                type: SpirvStruct
                type.id = getw(&state)
                type.element_type_ids = make([dynamic]u32, context.temp_allocator)

                for i in 2..<word_count {
                    append(&type.element_type_ids, getw(&state))
                }

                types[type.id] = type
                log.infof("struct %d", type.id)
            case OpCode.TypePointer: {
                pointer: SpirvPointer
                pointer.id = getw(&state)
                pointer.storage_class = SpirvStorageClass(getw(&state))
                pointer.type_id = getw(&state)
                log.infof("pointer %d %d %d", pointer.id, pointer.storage_class, pointer.type_id)
                pointers[pointer.id] = pointer
            }
            case OpCode.TypeFunction: {
                type: SpirvFunction
                type.id = getw(&state)
                type.return_type_id = getw(&state)
                type.parameter_type_ids = make([dynamic]u32, context.temp_allocator)

                for i in 3..<word_count {
                    append(&type.parameter_type_ids, getw(&state))
                }

                log.infof("function %d %d %d", type.id, type.return_type_id, len(type.parameter_type_ids))
                types[type.id] = type
            }
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

    description.shaders = make([dynamic]ShaderDescription)
    for entry in entry_points {
        // TODO(jan): Copy all names to the other allocator

        shader := ShaderDescription {
            name = entry.name,
            inputs = make([dynamic]VariableDescription),
            outputs = make([dynamic]VariableDescription),
            uniforms = make([dynamic]VariableDescription),
        }

        for var_id in entry.interface_ids {
            desc: VariableDescription

            var := vars[var_id]
            desc.name = names[var.id]

            pointer_id := var.type_id
            pointer := pointers[pointer_id]
            type_id := pointer.type_id
            type := types[type_id]
            fill_type_description(type_id, types, &desc.type)

            switch var.storage_class {
                case SpirvStorageClass.Input:
                    append(&shader.inputs, desc)
                case SpirvStorageClass.Output:
                    append(&shader.outputs, desc)
                case SpirvStorageClass.UniformConstant:
                    // TODO(jan) what even is this
                    fallthrough
                case SpirvStorageClass.Uniform:
                    append(&shader.uniforms, desc)
            }
        }

        switch entry.execution_model {
            case SpirvExecutionModel.Vertex:
                shader.type = ShaderType.Vertex
            case SpirvExecutionModel.Fragment:
                shader.type = ShaderType.Fragment
            case SpirvExecutionModel.Compute: fallthrough
            case SpirvExecutionModel.Geometry: fallthrough
            case SpirvExecutionModel.Kernel: fallthrough
            case SpirvExecutionModel.TesselationControl: fallthrough
            case SpirvExecutionModel.TesselationEvaluation: fallthrough
            case:
                panic("unhandled shader type")
        }

        append(&description.shaders, shader)
    }

    ok = true
    description.endianness = endianness

    return
}
