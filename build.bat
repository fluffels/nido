@echo off
FOR %%I IN (.\shaders\*.frag .\shaders\*.vert) DO (
    %VULKAN_SDK%\\Bin\\glslc.exe %%I -o %%I.spv
)
odin build . -debug -o:none
