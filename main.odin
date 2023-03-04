package main

import "core:dynlib"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import "vendor:sdl2"
import vk "vendor:vulkan"

import "jcwk"

check :: proc(result: vk.Result, error: string) {
	if (result != vk.Result.SUCCESS) {
		panic(error)
	}
}

main :: proc() {
	// NOTE(jan): Set up logging.
	log_file_handle, log_file_error := os.open("log.txt", os.O_CREATE | os.O_WRONLY | os.O_TRUNC)
	context.logger = log.create_file_logger(h=log_file_handle, lowest=log.Level.Debug)
	log.infof("Logging initialized")

	// NOTE(jan): Load Vulkan functions.
	vk_dll := dynlib.load_library("vulkan-1.dll") or_else panic("Couldn't load vulkan-1.dll!")

	vk_get_instance_proc_addr := dynlib.symbol_address(vk_dll, "vkGetInstanceProcAddr") or_else panic("vkGetInstanceProcAddr not found");
	vk.load_proc_addresses_global(vk_get_instance_proc_addr);

	// NOTE(jan): Check Vulkan version.
	vk_version: u32 = 0
	{
		check(vk.EnumerateInstanceVersion(&vk_version), "Could not fetch VK version")

		major := vk_version >> 22
		minor := (vk_version >> 12) & 0x3ff;
		patch := vk_version & 0xfff;

		log.infof("Vulkan instance version: %d.%d.%d", major, minor, patch);
    
		if ((major < 1) || (minor < 2) || (patch < 141)) do panic("you need at least Vulkan 1.2.141");
	}

	// NOTE(jan): Start collecting required extensions.
	required_extensions := make([dynamic]string, context.temp_allocator);

	// NOTE(jan): Initialize SDL2 so we can ask it which extensions it needs.
	sdl_init_error: i32 = sdl2.Init(sdl2.INIT_EVENTS | sdl2.INIT_TIMER | sdl2.INIT_VIDEO)
	if (sdl_init_error != 0) do panic ("Could not initialize SDL2")
	log.infof("SDL2 initialized")
	
	// NOTE(jan): Create a window so we can ask which extensions it needs.
	window: ^sdl2.Window = sdl2.CreateWindow("nido", 100, 100, 640, 480, sdl2.WINDOW_SHOWN | sdl2.WINDOW_VULKAN)

	// NOTE(jan): Figure out which extensions are required by SDL2.
	{
		count: u32 = 0;
		success: sdl2.bool = false;

		success = sdl2.Vulkan_GetInstanceExtensions(window, &count, nil)
		if (!success) do panic("Could not get required Vulkan extensions")
		extensions := make([^]cstring, count, context.temp_allocator)

		success = sdl2.Vulkan_GetInstanceExtensions(window, &count, extensions)
		if (!success) do panic("Could not get required Vulkan extensions")

		log.infof("SDL2 requires these vulkan extensions: ")
		for extension_index in 0..<count {
			extension: string = strings.clone_from_cstring(extensions[extension_index], context.temp_allocator)
			append(&required_extensions, extension)
			log.infof("\t* %s", extension)
		}
	}

	// NOTE(jan): Figure out which extensions are required by the app.
	{
		log.infof("App requires these vulkan extensions: ")
		extensions := [?]cstring{
			vk.EXT_DEBUG_REPORT_EXTENSION_NAME,
			vk.KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME,
		}
		for extension in extensions {
			append(&required_extensions, strings.clone_from_cstring(extension, context.temp_allocator))
			log.infof("\t* %s", extension)
		}
	}

	// NOTE(jan): Check if all extensions are available.
	{
		count: u32 = 0;
		check(vk.EnumerateInstanceExtensionProperties(nil, &count, nil), "could not fetch vk extensions")
		available_extensions := make([^]vk.ExtensionProperties, count, context.temp_allocator)

		check(vk.EnumerateInstanceExtensionProperties(nil, &count, available_extensions), "can't fetch vk extensions")

		available_extension_names := make([dynamic]string, context.temp_allocator)
		for extension_index in 0..<count {
			extension := available_extensions[extension_index]
			end := 0
			for char in extension.extensionName {
				if char != 0 do end += 1
				else do break
			}
			name_slice := extension.extensionName[:end]
			name := strings.clone_from_bytes(name_slice, context.temp_allocator)
			name = strings.trim_right_null(name)
			append(&available_extension_names, name)
		}

		log.infof("Vulkan extensions available: ")
		for extension_name in available_extension_names {
			log.infof("\t* %s", extension_name)
		}

		log.infof("Checking extensions: ")
		outer_loop: for required_extension in required_extensions {
			for available_name in available_extension_names {
				if (required_extension == available_name) {
					log.infof("\t\u2713 %s", required_extension)
					continue outer_loop
				}
			}
			fmt.panicf("\t\u274C %s", required_extension)
		}
	}

	// NOTE(jan): Create Vulkan instance.
	{
		app := vk.ApplicationInfo {
			sType=vk.StructureType.APPLICATION_INFO,
			apiVersion=vk.API_VERSION_1_2,
		}

		create := vk.InstanceCreateInfo {
			sType = vk.StructureType.INSTANCE_CREATE_INFO,
			pApplicationInfo = &app,
			enabledExtensionCount = u32(len(required_extensions)),
			ppEnabledExtensionNames = jcwk.vulkanize_strings(required_extensions),

			// createInfo.enabledLayerCount = vk.layers.size();
			// auto enabledLayerNames = stringVectorToC(vk.layers);
			// createInfo.ppEnabledLayerNames = enabledLayerNames;

			// createInfo.enabledExtensionCount = vk.extensions.size();
			// auto enabledExtensionNames = stringVectorToC(vk.extensions);
			// createInfo.ppEnabledExtensionNames = enabledExtensionNames;
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
