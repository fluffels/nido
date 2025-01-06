@echo off
FOR %%I IN (.\shaders\*.frag .\shaders\*.vert) DO (
    %VULKAN_SDK%\\Bin\\glslc.exe %%I -o %%I.spv
)
@REM odin build nido -debug -sanitize:address -o:none
odin build nido -debug -o:none
