package main

import "core:dynlib"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:slice"
import "vendor:sdl2"
import vk "vendor:vulkan"

check :: proc(result: vk.Result, error: string) {
	if (result != vk.Result.SUCCESS) {
		log.fatalf(error)
		os.exit(1)
	}
}

main :: proc() {
	log_file_handle, log_file_error := os.open("log.txt", os.O_CREATE | os.O_WRONLY | os.O_TRUNC)
	context.logger = log.create_file_logger(h=log_file_handle, lowest=log.Level.Debug)
	log.infof("Logging initialized")

	// NOTE(jan): Initialize SDL2.
	sdl_init_error: i32 = sdl2.Init(sdl2.INIT_EVENTS | sdl2.INIT_TIMER | sdl2.INIT_VIDEO)
	if (sdl_init_error != 0) {
		log.fatalf("Could not initialize SDL2")
		os.exit(1)
	} else {
		log.infof("SDL2 initialized")
	}
	
	// NOTE(jan): Create window.
	sdl_window: ^sdl2.Window = sdl2.CreateWindow("nido", 100, 100, 640, 480, sdl2.WINDOW_SHOWN | sdl2.WINDOW_VULKAN)

	// NOTE(jan): Create a surface.
	sdl_required_vulkan_extension_count: u32 = 0;
	sdl_get_extensions_success: sdl2.bool = sdl2.Vulkan_GetInstanceExtensions(sdl_window, &sdl_required_vulkan_extension_count, nil)
	sdl_required_vulkan_extensions := make([^]cstring, sdl_required_vulkan_extension_count, context.temp_allocator)
	sdl_get_extensions_success = sdl2.Vulkan_GetInstanceExtensions(sdl_window, &sdl_required_vulkan_extension_count, sdl_required_vulkan_extensions)
	if (!sdl_get_extensions_success) {
		log.fatalf("Could not get required Vulkan extensions")
		os.exit(1)
	}
	log.infof("SDL2 required vulkan extensions: ")
	for extension_index in 0..<sdl_required_vulkan_extension_count {
		extension: cstring = sdl_required_vulkan_extensions[extension_index]
		log.infof("\t* %s", extension)
	}

	// Loading Vulkan Functions.
	vk_dll := dynlib.load_library("vulkan-1.dll") or_else panic("Couldn't load vulkan-1.dll!")

	vk_get_instance_proc_addr := dynlib.symbol_address(vk_dll, "vkGetInstanceProcAddr") or_else panic("vkGetInstanceProcAddr not found");
	vk.load_proc_addresses_global(vk_get_instance_proc_addr);

	vk_version: u32 = 0
	check(vk.EnumerateInstanceVersion(&vk_version), "Could not fetch VK version")
	{
		major := vk_version >> 22
		minor := (vk_version >> 12) & 0x3ff;
		patch := vk_version & 0xfff;

		log.infof("Vulkan instance version: %d.%d.%d", major, minor, patch);
    
		if ((major < 1) || (minor < 2) || (patch < 141)) {
			panic("you need at least Vulkan 1.2.141");
		}
	}

	{
		vk_available_extension_count: u32 = 0;
		check(vk.EnumerateInstanceExtensionProperties(nil, &vk_available_extension_count, nil), "could not fetch vk extensions")
		vk_available_extensions := make([^]vk.ExtensionProperties, vk_available_extension_count, context.temp_allocator)
		check(vk.EnumerateInstanceExtensionProperties(nil, &vk_available_extension_count, vk_available_extensions), "can't fetch vk extensions")
		log.infof("Vulkan extensions available: ")
		for extension_index in 0..<vk_available_extension_count {
			extension := vk_available_extensions[extension_index]
			log.infof("\t* %s", extension.extensionName)
		}
	}

	// NOTE(jan): Main loop.
	// free_all(context.temp_allocator)
	// done := false;
	// for (!done) {
	// 	sdl2.PumpEvents();
	// 	for event: sdl2.Event; sdl2.PollEvent(&event); {
	// 		if (event.type == sdl2.EventType.KEYDOWN) {
	// 			event: sdl2.KeyboardEvent = event.key;
	// 			if (event.keysym.sym == sdl2.Keycode.ESCAPE) {
	// 				done = true;
	// 			}
	// 		}
	// 	}
	// }
}
