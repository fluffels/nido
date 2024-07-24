package logext

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:sys/windows"

is_power_of_two :: proc (x: u32) -> b32 {
    return x & (x - 1) == 0
}

Level :: runtime.Logger_Level
Logger :: runtime.Logger
LoggerOption :: runtime.Logger_Option
LoggerOptions :: runtime.Logger_Options
LoggerProc :: runtime.Logger_Proc

Default_Circular_Buffer_Logger_Options :: LoggerOptions {
    .Date,
    .Time,
}

Circular_Buffer_Logger_Data :: struct {
    ring_buffer: rawptr,
    size: u64,
    top: u64,
    bottom: u64,
    written: u64,
}

circular_buffer_logger_proc :: proc (raw_data: rawptr, level: Level, text: string, options: LoggerOptions, location := #caller_location) {
    data := cast(^Circular_Buffer_Logger_Data)raw_data
    start := cast(^u8)data.ring_buffer
    write: ^u8 = mem.ptr_offset(start, data.bottom)

    buffer := mem.slice_ptr(write, int(data.size))
    line := fmt.bprintf(buffer, "%s\n", text)
    written := u64(len(line))

    data.written += written
    data.bottom = (data.bottom + written) % data.size

    if data.written >= data.size {
        data.top = (data.bottom + 1) % data.size
    }
}

create_circular_buffer_logger :: proc(requested_size: uint, lowest := Level.Debug, options := Default_Circular_Buffer_Logger_Options) -> Logger {
    data := new(Circular_Buffer_Logger_Data)
    
    info: windows.SYSTEM_INFO
    windows.GetSystemInfo(&info)
    if !is_power_of_two(info.dwAllocationGranularity) do fmt.panicf("System allocation size is not a power of two.")

    size: uint = ((requested_size / uint(info.dwAllocationGranularity)) + 1) * uint(info.dwAllocationGranularity)
    if size % uint(info.dwAllocationGranularity) != 0 do fmt.panicf("Invalid buffer size.")

    section: windows.HANDLE = windows.CreateFileMappingW(
        windows.INVALID_HANDLE_VALUE,
        nil,
        windows.PAGE_READWRITE,
        (u32)(size >> 32),
        (u32)(size & 0xffffffff),
        nil,
    )

    data.ring_buffer = nil
    for offset: uint = 0x40000000; offset < 0x400000000; offset += 0x1000000 {
        view1: rawptr = windows.MapViewOfFileEx(section, windows.FILE_MAP_ALL_ACCESS, 0, 0, size, rawptr(uintptr(offset)))
        view2: rawptr = windows.MapViewOfFileEx(section, windows.FILE_MAP_ALL_ACCESS, 0, 0, size, rawptr(uintptr(offset + size)))

        if (view1 != nil) && (view2 != nil) {
            data.ring_buffer = view1
            break
        }

        if view1 != nil do windows.UnmapViewOfFile(view1)
        if view2 != nil do windows.UnmapViewOfFile(view2)
    }

    if data.ring_buffer == nil do fmt.panicf("Could not allocate ringbuffer.")

    data.top = 0
    data.bottom = 0
    data.size = u64(size)

    return Logger{circular_buffer_logger_proc, data, lowest, options}
}

destroy_circular_buffer_logger :: proc(log: ^Logger) {
	data := cast(^Circular_Buffer_Logger_Data)log.data
    // TODO(jan): Free file mapping
	free(data)
}
