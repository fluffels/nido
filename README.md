# Odin / Graphics Framework Experiments

So far, this project is an attempt at a basic 2D / 3D graphics framework / engine in Odin.

## Purpose

* Learn Odin.
* Understand what's required for creating a basic graphics engine:
    * How should pipelines be specified in a way that is both flexible and convenient?
    * How should the vertex format in a model be connected to the vertex format of the pipeline?

## Demos

### Map Editor / Dropdown Console

[20250108 122051.webm](https://github.com/user-attachments/assets/3209ef92-3017-4f47-906c-06c13ddac11e)

[20250108 133144.webm](https://github.com/user-attachments/assets/508a0ac0-953a-452d-a409-80e19b6a33a9)

## RenderBatch System

The RenderBatch system provides an efficient GPU rendering pipeline by organizing draw operations into discrete units of work. Each RenderBatch encapsulates the essential components needed for a single GPU draw call:

- A Vulkan pipeline configuration
- Texture mappings (connecting texture handles to descriptor indices)
- Mesh data (vertices and indices)
- Uniform data (planned)

### Operation

During frame preparation, the system converts front-end draw commands (boxes, textured quads, glyphs) into individual batches using a temporary allocator. These batches are recreated each frame.

The rendering process for each batch follows a standard sequence:
1. Pipeline binding
2. Descriptor set updates for textures
3. Mesh data binding
4. Draw call execution

### Texture Management

The system includes a texture registry that enables texture sharing across multiple batches. Textures can be:
- Registered into the system
- Loaded from files
- Updated from bitmap data

Current texture lookup is performed by searching the registry using texture handles.
