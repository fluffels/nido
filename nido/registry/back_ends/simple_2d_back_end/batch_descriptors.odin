package simple_2d_back_end

import "../../../gfx"

// NOTE(jan): Pipeline for colored triangles.
TRIANGLE_PASS := gfx.VulkanPipelineMetadata {
    name = "triangles",
    modules = {
        "ortho_xyz_rgba",
        "color",
    },
}

// NOTE(jan): Pipeline for textured quads.
TEXTURED_QUAD_PASS := gfx.VulkanPipelineMetadata {
    name = "textured_quads",
    modules = {
        "ortho_xyz_uv",
        "sampler",
    },
}

// NOTE(jan): Pipeline for glyphs.
GLYPH_PASS := gfx.VulkanPipelineMetadata {
    name = "glyphs",
    modules = {
        "ortho_xyz_uv_rgb",
        "sampler_as_coverage",
    },
}

// NOTE(jan): Pipeline for post-processing.
POST_PASS_PIPELINE := gfx.VulkanPipelineMetadata {
    name = "post",
    modules = {
        "ndc_xyz_uv",
        "contrast",
    },
}

MAIN_PASS := gfx.VulkanPassMetadata {
    enable_depth = true,
    write_to_texture = true,
    read_from_texture = false,
    pipelines = []gfx.VulkanPipelineMetadata {
        TRIANGLE_PASS,
        TEXTURED_QUAD_PASS,
        GLYPH_PASS,
    },
}

POST_PASS := gfx.VulkanPassMetadata {
    enable_depth = false,
    write_to_texture = false,
    read_from_texture = true,
    pipelines = []gfx.VulkanPipelineMetadata {
        POST_PASS_PIPELINE,
    },
}

COLOR_VERTEX := gfx.VertexDescription {
    name = "simple_2d_back_end_color_vertex",
    attributes = []gfx.VertexAttributeDescription {
        {
            // NOTE(jan): Screen-space position + z for layering.
            component_count = 3,
        },
        {
            // NOTE(jan): RGB.
            component_count = 3,
        },
    },
}

TEXTURED_VERTEX := gfx.VertexDescription {
    name = "simple_2d_back_end_texture_vertex",
    attributes = []gfx.VertexAttributeDescription {
        {
            // NOTE(jan): Screen-space position + z for layering.
            component_count = 3,
        },
        {
            // NOTE(jan): Texture coords.
            component_count = 2,
        },
    },
}

GLYPH_VERTEX := gfx.VertexDescription {
    name = "simple_2d_back_end_glyph_vertex",
    attributes = []gfx.VertexAttributeDescription {
        {
            // NOTE(jan): Screen-space position + z for layering.
            component_count = 3,
        },
        {
            // NOTE(jan): Texture coords.
            component_count = 2,
        },
        {
            // NOTE(jan): RGB.
            component_count = 3,
        },
    },
}
