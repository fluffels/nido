package gfx

import "core:fmt"
import "core:log"
import "core:strings"
import vk "vendor:vulkan"

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

SamplerDescription :: struct { }

SampledImageDescription :: struct { }

ComponentDescription :: union {
    ScalarDescription,
    StructDescription,
    SamplerDescription,
    SampledImageDescription,
    ^TypeDescription,
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

InputDescription :: struct {
    var: VariableDescription,
    location: u32,
}

OutputDescription :: struct {
    var: VariableDescription,
    location: u32,
}

UniformDescription :: struct {
    var: VariableDescription,
    descriptor_set: u32,
    binding: u32,
}

ShaderDescription :: struct {
    name: string,
    type: ShaderType,
    inputs: [dynamic]InputDescription,
    outputs: [dynamic]OutputDescription,
}

ShaderModuleDescription :: struct {
    shaders: [dynamic]ShaderDescription,
    uniforms: [dynamic]UniformDescription,
}

// ********************
// * Helper functions *
// ********************

// Determines VkFormat of a SPIR-V vertex input attribute.
determine_format :: proc(type_description: TypeDescription) -> vk.Format {
    switch comp in type_description.component_type {
        case ScalarDescription:
            switch comp.type {
                case ScalarType.FLOAT: return vk.Format.R32_SFLOAT
                case ScalarType.SIGNED_INT: return vk.Format.R32_SINT
                case ScalarType.UNSIGNED_INT: return vk.Format.R32_UINT
                case ScalarType.VOID: panic("cannot determine format of void")
            }
        case ^TypeDescription:
            switch nested_comp in comp.component_type {
                case ScalarDescription:
                    switch nested_comp.type {
                        case ScalarType.FLOAT:
                            switch type_description.component_count {
                                case 1:
                                    return vk.Format.R32_SFLOAT
                                case 2:
                                    return vk.Format.R32G32_SFLOAT
                                case 3:
                                    return vk.Format.R32G32B32_SFLOAT
                                case 4:
                                    return vk.Format.R32G32B32A32_SFLOAT
                            }
                        case ScalarType.SIGNED_INT:
                            switch type_description.component_count {
                                case 1:
                                    return vk.Format.R32_SINT
                                case 2:
                                    return vk.Format.R32G32_SINT
                                case 3:
                                    return vk.Format.R32G32B32_SINT
                                case 4:
                                    return vk.Format.R32G32B32A32_SINT
                            }
                        case ScalarType.UNSIGNED_INT:
                            switch type_description.component_count {
                                case 1:
                                    return vk.Format.R32_UINT
                                case 2:
                                    return vk.Format.R32G32_UINT
                                case 3:
                                    return vk.Format.R32G32B32_UINT
                                case 4:
                                    return vk.Format.R32G32B32A32_UINT
                            }
                        case ScalarType.VOID:
                            panic("cannot determine format of void")
                    }
                case StructDescription:
                    panic("cannot determine format of struct")
                case SamplerDescription:
                    panic("cannot determine format of sampler")
                case SampledImageDescription:
                    panic("cannot determine format of sampled image")
                case ^TypeDescription:
                    panic("cannot determine format of matrix")
            }
        case StructDescription:
            panic("cannot determine format of struct")
        case SamplerDescription:
            panic("cannot determine format of sampler")
        case SampledImageDescription:
            panic("cannot determine format of sampled image")
    }
    panic("cannot determine format")
}

// Determines the size of a SPIR-V type in bytes.
determine_size :: proc(type_description: TypeDescription) -> u32 {
    switch comp in type_description.component_type {
        case ScalarDescription:
            return u32(type_description.component_count) * u32(comp.width)
        case StructDescription:
            size := u32(0)
            for field in comp.fields {
                size += determine_size(field)
            }
            return size
        case SamplerDescription:
            return 0
        case SampledImageDescription:
            return 0
        case ^TypeDescription:
            return u32(type_description.component_count) * determine_size(comp^)
    }
    panic("cannot determine size")
}

// Maps a SPIR-V type to a Vulkan descriptor type.
determine_type :: proc(type_description: TypeDescription) -> vk.DescriptorType {
    switch comp in type_description.component_type {
        case ScalarDescription:
            switch comp.type {
                case ScalarType.FLOAT:
                    return vk.DescriptorType.UNIFORM_BUFFER
                case ScalarType.SIGNED_INT:
                    return vk.DescriptorType.UNIFORM_BUFFER
                case ScalarType.UNSIGNED_INT:
                    return vk.DescriptorType.UNIFORM_BUFFER
                case ScalarType.VOID:
                    return vk.DescriptorType.UNIFORM_BUFFER
            }
        case StructDescription:
            return vk.DescriptorType.UNIFORM_BUFFER
        case SamplerDescription:
            return vk.DescriptorType.SAMPLER
        case SampledImageDescription:
            return vk.DescriptorType.COMBINED_IMAGE_SAMPLER
        case ^TypeDescription:
            return determine_type(comp^)
    }
    panic("cannot determine type")
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
SpirvDimensionality :: enum u32 {
    D1 = 0,
    D2 = 1,
    D3 = 2,
    CUBE = 3,
    RECT = 4,
    BUFFER = 5,
    SUBPASS_DATA = 6,
}

@(private)
SpirvDepth :: enum u32 {
    NO = 0,
    YES = 1,
    NO_INDICATION = 2,
}

@(private)
SpirvArrayed :: enum u32 {
    NO = 0,
    YES = 1,
}

@(private)
SpirvMultisampled :: enum u32 {
    NO = 0,
    YES = 1,
}

@(private)
SpirvSampled :: enum u32 {
    UNKNOWN = 0,
    SAMPLING_COMPATIBLE = 1,
    READ_WRITE_COMPATIBLE = 2,
}

@(private)
SpirvImageFormat :: enum u32 {
    UNKNOWN = 0,
    RGBA_32F = 1,
    RGBA_16F = 2,
    R_32F = 3,
    RGBA_8 = 4,
    RGBA_8_SNORM = 5,
    RG_32F = 6,
    RG_16F = 7,
    R11F_G11F_B10F = 8,
    R_16F = 9,
    RGBA_16 = 10,
    RGB_10_A2 = 11,
    RG_16 = 12,
    RG_8 = 13,
    R_16 = 14,
    R_8 = 15,
    RGBA_16_SNORM = 16,
    RG_16_SNORM = 17,
    RG_8_SNORM = 18,
    R_16_SNORM = 19,
    R_8_SNORM = 20,
    RGBA_32I = 21,
    RGBA_16I = 22,
    RGBA_8I = 23,
    R_32I = 24,
    RG_32I = 25,
    RG_16I = 26,
    RG_8I = 27,
    R_16I = 28,
    R_8I = 29,
    RGBA_32UI = 30,
    RGBA_16UI = 31,
    RGBA_8UI = 32,
    R_32UI = 33,
    RGB_10_A2_UI = 34,
    RG_32UI = 35,
    RG_16UI = 36,
    RG_8UI = 37,
    R_16UI = 38,
    R_8UI = 39,
    R_64UI = 40,
    R_64I = 41,
}

@(private)
SpirvAccessQualifier :: enum u32 {
    READ_ONLY = 0,
    WRITE_ONLY = 1,
    READ_WRITE = 2,
    UNSPECIFIED = 3,
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
SpirvImage :: struct {
    id: u32,
    sampled_type_id: u32,
    dim: SpirvDimensionality,
    depth: SpirvDepth,
    arrayed: SpirvArrayed,
    multisampled: SpirvMultisampled,
    sampled: SpirvSampled,
    image_format: SpirvImageFormat,
    access_qualifier: SpirvAccessQualifier,
}

@(private)
SpirvSampler :: struct {
    id: u32,
}

@(private)
SpirvSampledImage :: struct {
    id: u32,
    image_type_id: u32,
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
    SpirvImage,
    SpirvSampler,
    SpirvSampledImage,
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
    descriptor_set: u32,
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
    TypeImage = 25,
    TypeSampler = 26,
    TypeSampledImage = 27,
    TypeArray = 28,
    TypeStruct = 30,
    TypePointer = 32,
    TypeFunction = 33,
    Variable = 59,
    Decorate = 71,
    DecorateMember = 72,
}

@(private)
DecorationCode :: enum u32 {
    Location = 30,
    Binding = 33,
    DescriptorSet = 34,
}

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
        case SpirvImage:
            panic("SpirvImage only handled as part of sampler")
        case SpirvSampler:
            description.dimensions = Dimensionality.SCALAR
            description.component_type = SamplerDescription {}
            description.component_count = 1
        case SpirvSampledImage:
            description.dimensions = Dimensionality.SCALAR
            description.component_type = SampledImageDescription {}
            description.component_count = 1
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

    var_binding        := make(map[u32]u32             , 1, context.temp_allocator)
    var_descriptor_set := make(map[u32]u32             , 1, context.temp_allocator)
    var_location       := make(map[u32]u32             , 1, context.temp_allocator)
    entry_points       := make([dynamic]SpirvEntryPoint,    context.temp_allocator)
    types              := make(map[u32]SpirvType       , 1, context.temp_allocator)
    names              := make(map[u32]string          , 1, context.temp_allocator)
    vars               := make(map[u32]SpirvVar        , 1, context.temp_allocator)
    pointers           := make(map[u32]SpirvPointer    , 1, context.temp_allocator)

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
            case OpCode.TypeVoid:
                type: SpirvVoid
                type.id = getw(&state)
                types[type.id] = type
            case OpCode.TypeBool:
                type: SpirvBool
                type.id = getw(&state)
                types[type.id] = type
            case OpCode.TypeInt:
                type: SpirvInt
                type.id = getw(&state)
                type.width = getw(&state)
                type.signed = getw(&state)
            case OpCode.TypeFloat:
                type: SpirvFloat
                type.id = getw(&state);
                type.width = getw(&state);
                types[type.id] = type
            case OpCode.TypeVector:
                type: SpirvVec
                type.id = getw(&state)
                type.component_type_id = getw(&state)
                type.component_count = getw(&state)
                types[type.id] = type
            case OpCode.TypeMatrix:
                type: SpirvMatrix
                type.id = getw(&state)
                type.column_type_id = getw(&state)
                type.column_count = getw(&state)
                types[type.id] = type
            case OpCode.TypeImage:
                type: SpirvImage
                type.id = getw(&state)
                type.sampled_type_id = getw(&state)
                type.dim = SpirvDimensionality(getw(&state))
                type.depth = SpirvDepth(getw(&state))
                type.arrayed = SpirvArrayed(getw(&state))
                type.multisampled = SpirvMultisampled(getw(&state))
                type.sampled = SpirvSampled(getw(&state))
                type.image_format = SpirvImageFormat(getw(&state))
                if word_count > 9 {
                    type.access_qualifier = SpirvAccessQualifier(getw(&state))
                } else {
                    type.access_qualifier = SpirvAccessQualifier.UNSPECIFIED
                }
                types[type.id] = type
            case OpCode.TypeSampler:
                type: SpirvSampler
                type.id = getw(&state)
                types[type.id] = type
            case OpCode.TypeSampledImage:
                type: SpirvSampledImage
                type.id = getw(&state)
                type.image_type_id = getw(&state)
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
            case OpCode.TypePointer: {
                pointer: SpirvPointer
                pointer.id = getw(&state)
                pointer.storage_class = SpirvStorageClass(getw(&state))
                pointer.type_id = getw(&state)
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

                types[type.id] = type
            }
            case OpCode.Variable:
                var: SpirvVar
                var.type_id = getw(&state)
                var.id = getw(&state)
                var.storage_class = SpirvStorageClass(getw(&state))
                words_left := word_count - 4
                if words_left > 0 do advance_words(&state, int(words_left))
                vars[var.id] = var
            case OpCode.Decorate:
                var_id := getw(&state)
                decoration_code := DecorationCode(getw(&state))
                switch decoration_code {
                    case DecorationCode.Location:
                        var_location[var_id] = getw(&state)
                    case DecorationCode.Binding:
                        var_binding[var_id] = getw(&state)
                    case DecorationCode.DescriptorSet:
                        var_descriptor_set[var_id] = getw(&state)
                    case:
                        for i in 3..<word_count do getw(&state)
                }
            // NOTE(jan): Unhandled opcode.
            case:
                advance_words(&state, int(word_count-1))
        }
    }

    // NOTE(jan): Prepare variable descriptions.
    var_id_to_desc := make(map[u32]VariableDescription, len(vars), context.temp_allocator)
    for var_id, var in vars {
        switch var.storage_class {
            case SpirvStorageClass.Input:
            case SpirvStorageClass.Output:
            case SpirvStorageClass.UniformConstant:
            case SpirvStorageClass.Uniform:
                // NOTE(jan): We only care about these for now.
            case:
                continue
        }

        desc: VariableDescription
        desc.name = strings.clone(names[var.id])

        pointer_id := var.type_id
        pointer := pointers[pointer_id]
        type_id := pointer.type_id
        type := types[type_id]
        fill_type_description(type_id, types, &desc.type)

        var_id_to_desc[var_id] = desc
    }

    // NOTE(jan): Store uniforms.
    for var_id, var in vars {
        if (var.storage_class != SpirvStorageClass.UniformConstant) && (var.storage_class != SpirvStorageClass.Uniform) {
            continue
        }

        desc := var_id_to_desc[var_id]
        descriptor_set_index := var_descriptor_set[var_id] or_else fmt.panicf("no set for var %d", var_id)
        binding_index := var_binding[var_id] or_else fmt.panicf("no binding for var %d", var_id)

        append(&description.uniforms, UniformDescription {
            var = desc,
            descriptor_set = descriptor_set_index,
            binding = binding_index,
        })
    }

    // NOTE(jan): Extract shaders from entry points.
    description.shaders = make([dynamic]ShaderDescription, len(entry_points))
    for entry, i in entry_points {
        shader := &description.shaders[i]

        shader.name = strings.clone(entry.name)
        shader.inputs = make([dynamic]InputDescription)
        shader.outputs = make([dynamic]OutputDescription)

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

        for var_id in entry.interface_ids {
            var := vars[var_id]
            desc := var_id_to_desc[var_id]
            
            // NOTE(jan): SPIR-V sometimes generates outputs with no location.
            // These are presumably some internal GLSL thing.
            if var_id not_in var_location do continue
            location := var_location[var_id]

            switch var.storage_class {
                case SpirvStorageClass.Input:
                    append(&shader.inputs, InputDescription {
                        var = desc,
                        location = location,
                    })
                case SpirvStorageClass.Output:
                    append(&shader.outputs, OutputDescription {
                        var = desc,
                        location = location,
                    })
                case SpirvStorageClass.UniformConstant: fallthrough
                case SpirvStorageClass.Uniform:
                    panic("uniform specified in entry interface")
                case:
                    panic("unhandled storage class")
            }
        }
    }

    ok = true
    return
}
