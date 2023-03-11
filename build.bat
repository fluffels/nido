@echo off
odin build . -debug -o:none
FOR %%I IN (.\shaders\*.frag .\shaders\*.vert) DO (
    %VULKAN_SDK%\\Bin\\glslc.exe %%I -o %%I.spv
)
