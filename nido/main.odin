package nido

import "base:runtime"

import "core:dynlib"
import "core:fmt"
import "core:log"
import "core:math"
import "core:math/bits"
import linalg "core:math/linalg"
import "core:mem"
import "core:mem/virtual"
import "core:os"
import "core:slice"
import "core:strings"
import "vendor:sdl2"
import vk "vendor:vulkan"

import "app"
import "logext"
import "gfx"
import "back_end"
import "registry"

vulkan_debug :: proc "stdcall" (
	flags: vk.DebugReportFlagsEXT,
	object_type: vk.DebugReportObjectTypeEXT,
	object: u64,
	location: int,
	messageCode: i32,
	layer_prefix: cstring,
	message: cstring,
	user_data: rawptr,
) -> b32 {
	context_pointer := cast(^runtime.Context)user_data
	context = context_pointer^
	switch {
		case vk.DebugReportFlagEXT.ERROR in flags:
			log.errorf("[%s] %s", layer_prefix, message)
		case vk.DebugReportFlagEXT.WARNING in flags:
			log.warnf("[%s] %s", layer_prefix, message)
		case vk.DebugReportFlagEXT.PERFORMANCE_WARNING in flags:
			log.warnf("(performance) [%s] %s", layer_prefix, message)
		case vk.DebugReportFlagEXT.DEBUG in flags:
			log.debugf("[%s] %s", layer_prefix, message)
	}
	return false;
}

main :: proc() {
	// NOTE(jan): Set up logging.
	log_file_handle, log_file_error := os.open("log.txt", os.O_CREATE | os.O_WRONLY | os.O_TRUNC)
	file_logger := log.create_file_logger(h=log_file_handle, lowest=log.Level.Debug)

	mem_logger := logext.create_circular_buffer_logger(requested_size=1 * 1024 * 1024, lowest=log.Level.Debug)

	context.logger = log.create_multi_logger(file_logger, mem_logger)
	log.infof("Logging initialized")

	// NOTE(jan): Tacking allocator.
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				for _, entry in track.allocation_map {
					fmt.eprintf("%v leaked %v bytes\n", entry.location, entry.size)
				}
			}
			if len(track.bad_free_array) > 0 {
				for entry in track.bad_free_array {
					fmt.eprintf("%v bad free at %v\n", entry.location, entry.memory)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	// NOTE(jan): Load Vulkan functions.
	vk_dll := dynlib.load_library("vulkan-1.dll") or_else panic("Couldn't load vulkan-1.dll!")
	log.infof("Loaded vulkan-1.dll")

	vk_get_instance_proc_addr := dynlib.symbol_address(vk_dll, "vkGetInstanceProcAddr") or_else panic("vkGetInstanceProcAddr not found");
	vk.load_proc_addresses_global(vk_get_instance_proc_addr);
	log.infof("Loaded vulkan global functions")

	// NOTE(jan): Check Vulkan version.
	vk_version: u32 = 0
	{
		gfx.check(vk.EnumerateInstanceVersion(&vk_version), "Could not fetch VK version")

		major := vk_version >> 22
		minor := (vk_version >> 12) & 0x3ff;
		patch := vk_version & 0xfff;

		log.infof("Vulkan instance version: %d.%d.%d", major, minor, patch);
    
		if ((major < 1) || (minor < 2) || (patch < 141)) do panic("you need at least Vulkan 1.2.141");
	}

	// NOTE(jan): Nice-to-have layers.
	optional_layers := make([dynamic]string, context.temp_allocator);
	append(&optional_layers, "VK_LAYER_KHRONOS_validation");

	// NOTE(jan): Check if the layers we require are available.
	required_layers := make([dynamic]string, context.temp_allocator);
	{
		log.infof("Required layers: ")
		for layer in required_layers {
			log.infof("\t* %s", layer);
		}

		count: u32;
		gfx.check(
			vk.EnumerateInstanceLayerProperties(&count, nil),
			"could not count available layers",
		);

		available_layers := make([^]vk.LayerProperties, count, context.temp_allocator);
		gfx.check(
			vk.EnumerateInstanceLayerProperties(&count, available_layers),
			"could not fetch available layers",
		);

		log.infof("Available layers: ")
		available_layer_names := make([dynamic]string, context.temp_allocator)
		for i in 0..<count {
			layer := available_layers[i]
			name := gfx.odinize_string(layer.layerName[:])
			append(&available_layer_names, name)
			log.infof("\t* %s", name);
		}

		log.infof("Checking required layers: ")
		for required_layer in required_layers {
			if slice.contains(available_layer_names[:], required_layer) {
				log.infof("\t\u2713 %s", required_layer)
			} else {
				log.fatalf("\t\u274C %s", required_layer)
				fmt.panicf("Layer %s is required.", required_layer)
			}
		}

		log.infof("Checking optional layers: ")
		for optional_layer in optional_layers {
			if slice.contains(available_layer_names[:], optional_layer) {
				log.infof("\t\u2713 %s", optional_layer)
			} else {
				log.warnf("\t\u274C %s", optional_layer)
			}
		}
	}

	// NOTE(jan): Start collecting required extensions.
	required_extensions := make([dynamic]string, context.temp_allocator);

	// NOTE(jan): Initialize SDL2 so we can ask it which extensions it needs.
	sdl_init_error: i32 = sdl2.Init(sdl2.INIT_EVENTS | sdl2.INIT_TIMER | sdl2.INIT_VIDEO)
	if (sdl_init_error != 0) do panic ("Could not initialize SDL2")
	log.infof("SDL2 initialized")
	
	// NOTE(jan): Create a window so we can ask which extensions it needs.
	window: ^sdl2.Window = sdl2.CreateWindow("nido", 100, 100, 640, 480, sdl2.WINDOW_SHOWN | sdl2.WINDOW_VULKAN | sdl2.WINDOW_RESIZABLE)

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
		gfx.check(vk.EnumerateInstanceExtensionProperties(nil, &count, nil), "could not fetch vk extensions")
		available_extensions := make([^]vk.ExtensionProperties, count, context.temp_allocator)

		gfx.check(vk.EnumerateInstanceExtensionProperties(nil, &count, available_extensions), "can't fetch vk extensions")

		available_extension_names := make([dynamic]string, context.temp_allocator)
		for extension_index in 0..<count {
			extension := available_extensions[extension_index]
			name := gfx.odinize_string(extension.extensionName[:])
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
			log.fatalf("\t\u274C %s", required_extension)
			fmt.panicf("Extension %s is required.", required_extension)
		}
	}

	// NOTE(jan): Create Vulkan instance.
	vulkan: gfx.Vulkan
	{
		app := vk.ApplicationInfo {
			sType=vk.StructureType.APPLICATION_INFO,
			apiVersion=vk.API_VERSION_1_2,
		}

		create := vk.InstanceCreateInfo {
			sType = vk.StructureType.INSTANCE_CREATE_INFO,
			pApplicationInfo = &app,
			enabledExtensionCount = u32(len(required_extensions)),
			ppEnabledExtensionNames = gfx.vulkanize_strings(required_extensions),
			enabledLayerCount = u32(len(required_layers)),
			ppEnabledLayerNames = gfx.vulkanize_strings(required_layers),
		}

		#partial switch result := vk.CreateInstance(&create, nil, &vulkan.handle); result {
			case vk.Result.SUCCESS: log.infof("Vulkan instance created.")
			case vk.Result.ERROR_INITIALIZATION_FAILED: panic("could not init vulkan")
			case vk.Result.ERROR_LAYER_NOT_PRESENT: panic("layer not present")
			case vk.Result.ERROR_EXTENSION_NOT_PRESENT: panic("extension not present")
			case vk.Result.ERROR_INCOMPATIBLE_DRIVER: panic("incompatible driver")
			case: panic("couldn't create vulkan instance")
		}

		vk.load_proc_addresses_instance(vulkan.handle)
		log.infof("Loaded vulkan instance functions")
	}

	// NOTE(jan): Create debug callback
	// TODO(jan): Disable in prod
	debug_context := context
	{
		create := vk.DebugReportCallbackCreateInfoEXT {
			sType = vk.StructureType.DEBUG_REPORT_CALLBACK_CREATE_INFO_EXT,
			flags = {
				vk.DebugReportFlagEXT.PERFORMANCE_WARNING,
				vk.DebugReportFlagEXT.WARNING,
				vk.DebugReportFlagEXT.ERROR,
				vk.DebugReportFlagEXT.DEBUG,
			},
			pfnCallback = vulkan_debug,
			pUserData = &debug_context,
		}

		gfx.check(
			vk.CreateDebugReportCallbackEXT(vulkan.handle, &create, nil, &vulkan.debug_callback),
			"could not create debug callback",
		)
		log.infof("Created debug callback.")
	}

	// NOTE(jan): Create the surface so we can use it to help query GPU capabilities.
	{
		success := sdl2.Vulkan_CreateSurface(window, vulkan.handle, &vulkan.surface)
		if !success do panic("could not create surface")
	}

	// NOTE(jan): Gather required device extensions.
	required_device_extensions := make([dynamic]string, context.temp_allocator)
	append(&required_device_extensions, vk.KHR_SWAPCHAIN_EXTENSION_NAME)
	log.infof("App requires these device extensions:")
	for extension in required_device_extensions {
		log.infof("\t* %s", extension)
	}

	// NOTE(jan): Pick a GPU
	{
		count: u32;
		gfx.check(
			vk.EnumeratePhysicalDevices(vulkan.handle, &count, nil),
			"couldn't count gpus",
		)

		gpus := make([^]vk.PhysicalDevice, count, context.temp_allocator)
		gfx.check(
			vk.EnumeratePhysicalDevices(vulkan.handle, &count, gpus),
			"couldn't fetch gpus",
		)

		log.infof("%d physical device(s)", count)
		gpu_loop: for gpu, gpu_index in gpus[:count] {
			props: vk.PhysicalDeviceProperties
			vk.GetPhysicalDeviceProperties(gpu, &props)

			{
				name := gfx.odinize_string(props.deviceName[:])
				log.infof("GPU #%d \"%s\":", gpu_index, name)
			}

			// NOTE(jan): Check extensions.
			{
				count: u32;
				gfx.check(
					vk.EnumerateDeviceExtensionProperties(gpu, nil, &count, nil),
					"could not count device extension properties",
				)

				extensions := make([^]vk.ExtensionProperties, count, context.temp_allocator)
				gfx.check(
					vk.EnumerateDeviceExtensionProperties(gpu, nil, &count, extensions),
					"could not fetch device extension properties",
				)

				log.infof("\tAvailable device extensions:")
				extension_names := make([dynamic]string, context.temp_allocator)
				for i in 0..<count {
					name := gfx.odinize_string(extensions[i].extensionName[:])
					append(&extension_names, name)
					log.infof("\t\t* %s", name)
				}

				log.infof("\tChecking device extensions:")
				for required in required_device_extensions {
					if slice.contains(extension_names[:], required) {
						log.infof("\t\t\u2713 %s", required)
					} else {
						log.infof("\t\t\u274C %s", required)
						continue gpu_loop
					}
				}
			}

			// NOTE(jan): Find queue families.
			has_compute_queue := false;
			has_gfx_queue := false;
			compute_queue_family: u32;
			gfx_queue_family: u32;
			log.infof("\tChecking device queues:")
			{
				count: u32
				vk.GetPhysicalDeviceQueueFamilyProperties(gpu, &count, nil)

				families := make([^]vk.QueueFamilyProperties, count, context.temp_allocator)
				vk.GetPhysicalDeviceQueueFamilyProperties(gpu, &count, families)

				for i in 0..<count {
					family := families[i]
					if vk.QueueFlag.GRAPHICS in family.queueFlags {
						log.infof("\t\t\u2713 Found a graphics queue family...")

						is_present_queue: b32
						vk.GetPhysicalDeviceSurfaceSupportKHR(gpu, i, vulkan.surface, &is_present_queue)

						if is_present_queue {
							log.infof("\t\t\u2713 and it is a present queue.")
							has_gfx_queue = true
							gfx_queue_family = i
						} else {
							log.infof("\t\t\u274C but it is not a present queue.")
						}
					}
					if vk.QueueFlag.COMPUTE in family.queueFlags {
						log.infof("\t\t\u2713 Found a compute queue family.")
						has_compute_queue = true
						compute_queue_family = i
					}
				}
			}

			if !has_compute_queue {
				log.infof("\t\t\u274C No compute queue families.")
				continue gpu_loop
			}
			if !has_gfx_queue {
				log.infof("\t\t\u274C No graphics queue families.")
				continue gpu_loop
			}

			log.infof("Selected GPU #%d", gpu_index)
			vulkan.gpu = gpu
			vulkan.compute_queue_family = compute_queue_family
			vulkan.gfx_queue_family = gfx_queue_family
		}
	}

	// NOTE(jan): Fetch memory types.
	vk.GetPhysicalDeviceMemoryProperties(vulkan.gpu, &vulkan.memories);

	// NOTE(jan): Create device.
	{
		prio: f32 = 1.0
		queues := [?]vk.DeviceQueueCreateInfo {
			{
				sType = vk.StructureType.DEVICE_QUEUE_CREATE_INFO,
				queueCount = 1,
				queueFamilyIndex = vulkan.compute_queue_family,
				pQueuePriorities = &prio,
			},
			{
				sType = vk.StructureType.DEVICE_QUEUE_CREATE_INFO,
				queueCount = 1,
				queueFamilyIndex = vulkan.gfx_queue_family,
				pQueuePriorities = &prio,
			},
		}

		indexing := vk.PhysicalDeviceDescriptorIndexingFeatures {
			sType = vk.StructureType.PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_FEATURES,
			descriptorBindingPartiallyBound = true,
		}

		create := vk.DeviceCreateInfo {
			sType = vk.StructureType.DEVICE_CREATE_INFO,
			pNext = &indexing,
			queueCreateInfoCount = u32(len(queues)),
			pQueueCreateInfos = gfx.vulkanize(queues),
			enabledExtensionCount = u32(len(required_device_extensions)),
			ppEnabledExtensionNames = gfx.vulkanize_strings(required_device_extensions),
		}

		gfx.check(
			vk.CreateDevice(vulkan.gpu, &create, nil, &vulkan.device),
			"could not create device",
		)
		log.infof("Created Vulkan device.")

		vk.GetDeviceQueue(vulkan.device, vulkan.gfx_queue_family, 0, &vulkan.gfx_queue);
		vk.GetDeviceQueue(vulkan.device, vulkan.compute_queue_family, 0, &vulkan.compute_queue);
		log.infof("Fetched queues.")
	}

	// NOTE(jan): Get swap formats.
	{
		gfx.vulkan_swap_update_capabilities(&vulkan)
		gfx.vulkan_swap_update_extent(&vulkan)

		if vk.ImageUsageFlag.COLOR_ATTACHMENT not_in vulkan.swap.capabilities.supportedUsageFlags {
			panic("surface does not support color attachment")
		}
		if vk.CompositeAlphaFlagKHR.OPAQUE not_in vulkan.swap.capabilities.supportedCompositeAlpha {
			panic("surface does not support opaque composition")
		}

		// NOTE(jan): Find a surface color space & format.
		{
			count: u32;
			gfx.check(
				vk.GetPhysicalDeviceSurfaceFormatsKHR(vulkan.gpu, vulkan.surface, &count, nil),
				"could not count physical device surface formats",
			)

			formats := make([^]vk.SurfaceFormatKHR, count, context.temp_allocator)
			gfx.check(
				vk.GetPhysicalDeviceSurfaceFormatsKHR(vulkan.gpu, vulkan.surface, &count, formats),
				"could not fetch physical device surface formats",
			)

			found := false;
			for format in formats[:count] {
				if (format.colorSpace == vk.ColorSpaceKHR.SRGB_NONLINEAR) &&
						(format.format == vk.Format.B8G8R8A8_UNORM) {
					vulkan.swap.format = format.format;
					vulkan.swap.color_space = format.colorSpace;
					log.infof("Found a compatible color space & format: %d, %d", vulkan.swap.color_space, vulkan.swap.format)
					found = true;
					break;
				}
			}

			if !found do panic("no compatible color space & format")
		}

		// NOTE(jan): Pick a present mode.
		{
			count: u32;
			gfx.check(
				vk.GetPhysicalDeviceSurfacePresentModesKHR(vulkan.gpu, vulkan.surface, &count, nil),
				"could not count present modes",
			)

			modes := make([^]vk.PresentModeKHR, count, context.temp_allocator)
			gfx.check(
				vk.GetPhysicalDeviceSurfacePresentModesKHR(vulkan.gpu, vulkan.surface, &count, modes),
				"could not fetch present modes",
			)

			vulkan.swap.present_mode = vk.PresentModeKHR.FIFO
			for mode in modes[:count] {
				if mode == vk.PresentModeKHR.MAILBOX {
					vulkan.swap.present_mode = vk.PresentModeKHR.MAILBOX
					log.infof("Present mode switched to mailbox")
				}
			}
		}
	}

	// NOTE(jan): Allocator for all Vulkan objects that need to persist as long as the device does.
	{
		alloc_error := virtual.arena_init_growing(&vulkan.device_arena)
		if alloc_error != virtual.Allocator_Error.None do panic("could not initialize vulkan device allocator")
		vulkan.device_allocator = virtual.arena_allocator(&vulkan.device_arena)
	}
	
	// NOTE(jan): Create initial swap chain.
	gfx.vulkan_swap_create(&vulkan)

	// NOTE(jan): Create shader modules.
	// Shader modules live for the entire lifetime.
	gfx.vulkan_create_shader_modules(&vulkan)

	// Pipelines live between window resizes.
	mem.dynamic_pool_init(&vulkan.resize_pool,
                          context.allocator,
                          context.allocator,
                          mem.DYNAMIC_POOL_BLOCK_SIZE_DEFAULT,
                          mem.DYNAMIC_POOL_OUT_OF_BAND_SIZE_DEFAULT,
                          64)
	vulkan.resize_allocator = mem.dynamic_pool_allocator(&vulkan.resize_pool)

	// NOTE(jan): Create semaphores used to control presentation.
	image_ready, cmd_buffer_done : vk.Semaphore
	{
		create := vk.SemaphoreCreateInfo {
			sType = vk.StructureType.SEMAPHORE_CREATE_INFO,
		}
		gfx.check(
			vk.CreateSemaphore(vulkan.device, &create, nil, &image_ready),
			"could not create semaphore",
		)
		gfx.check(
			vk.CreateSemaphore(vulkan.device, &create, nil, &cmd_buffer_done),
			"could not create semaphore",
		)
	}
	log.infof("Semaphores created.")

	// NOTE(jan): Create command pools and per-frame buffer.
	transient_cmd_pool := gfx.vulkan_cmd_create_transient_pool(vulkan)
	cmd_pool := gfx.vulkan_cmd_create_per_frame_pool(vulkan)
	cmd      := gfx.vulkan_cmd_allocate_buffer(vulkan, cmd_pool)

	// NOTE(jan): Initialize registry.
	reg := registry.make_registry()

	// NOTE(jan): Create arena for each back_end.
	for _, i in reg.back_end {
		alloc_error := virtual.arena_init_growing(&reg.back_end[i].arena)
		if alloc_error != virtual.Allocator_Error.None do panic("could not initialize back end allocator")
		reg.back_end[i].allocator = virtual.arena_allocator(&reg.back_end[i].arena)
	}

	// NOTE(jan): Initialize Apps.
	for &a, i in reg.app {
		alloc_error := virtual.arena_init_growing(&a.arena)
		if alloc_error != virtual.Allocator_Error.None do panic("could not initialize app allocator")
		a.allocator = virtual.arena_allocator(&a.arena)

		if a.name == "terminal" {
			app.initialize(&a, mem_logger.data)
		} else {
			app.initialize(&a, nil)
		}
	}

	// NOTE(jan): Select current back end.
	current_back_end := registry.get_current_back_end(reg)
	current_app := registry.get_current_app(reg)

	// NOTE(jan): Main loop.
	done := false;
	isMinimized := false;
	// NOTE(jan): Initialize back end first time through.
	do_init := true
	do_resize := false;
	// NOTE(jan): Keep track of the last frame's time stamp.
	last_frame: u32 = 0;
	last_frame_mouse: linalg.Vector2f32;

	new_frame: for (!done) {
		free_all(context.temp_allocator)

		vulkan.temp_buffers = make([dynamic]gfx.VulkanBuffer, context.temp_allocator)

		// NOTE(jan): Handle events.
		events := make([dynamic]app.Event, context.temp_allocator)
		input_state: app.InputState

		sdl2.PumpEvents();
		for event: sdl2.Event; sdl2.PollEvent(&event); {
			#partial switch event.type {
				case sdl2.EventType.MOUSEBUTTONDOWN:
					event: sdl2.MouseButtonEvent = event.button;
					append(&events, app.Click {
						x = f32(event.x),
						y = f32(event.y),
					})
				case sdl2.EventType.KEYDOWN:
					event: sdl2.KeyboardEvent = event.key;
					#partial switch event.keysym.sym {
						case sdl2.Keycode.ESCAPE: done = true
						case sdl2.Keycode.TAB:
							back_end.cleanup(&current_back_end, &vulkan)
							free_all(current_back_end.allocator)

							registry.advance_back_end_index(&reg)
							current_back_end = registry.get_current_back_end(reg)
							do_resize = true
							do_init = true
						case sdl2.Keycode.HOME: input_state.key_down.home = true
						case sdl2.Keycode.END: input_state.key_down.end = true
						case sdl2.Keycode.PAGEDOWN: input_state.key_down.page_down = true
						case sdl2.Keycode.PAGEUP: input_state.key_down.page_up = true
						case sdl2.Keycode.DOWN: input_state.key_down.down = true
						case sdl2.Keycode.UP: input_state.key_down.up = true
					}
				case sdl2.EventType.QUIT:
					done = true;
				case sdl2.EventType.WINDOWEVENT:
					#partial switch event.window.event {
						case .MINIMIZED:
							isMinimized = true
						case .RESTORED:
							isMinimized = false
					}
			}
		}

		if isMinimized {
			sdl2.WaitEvent(nil)
			continue
		}

		// NOTE(jan): Fill out input state.
		{
			x, y: i32
			button := sdl2.GetMouseState(&x, &y)
			pos := linalg.Vector2f32 { f32(x), f32(y) }
			delta := pos - last_frame_mouse
			keys := sdl2.GetKeyboardState(nil)
			input_state.ticks = sdl2.GetTicks()
			input_state.keyboard = app.Keyboard {
				left = keys[sdl2.SCANCODE_LEFT] != 0,
				right = keys[sdl2.SCANCODE_RIGHT] != 0,
				up = keys[sdl2.SCANCODE_UP] != 0,
				down = keys[sdl2.SCANCODE_DOWN] != 0,
			}
			input_state.mouse = app.Mouse {
				pos = pos,
				delta = delta,
				left = ((button & sdl2.BUTTON_LMASK) != 0),
				middle = ((button & sdl2.BUTTON_MMASK) != 0),
				right = ((button & sdl2.BUTTON_RMASK) != 0),
			}
			input_state.slice = input_state.ticks - last_frame
			last_frame = input_state.ticks
			last_frame_mouse = pos
		}

		// NOTE(jan): Initialize current back end.
		if (do_init) {
			do_init = false

			back_end.cleanup(&current_back_end, &vulkan)
			free_all(current_back_end.allocator)
			log.infof("Initializing back end %s", current_back_end.name)
			
			if current_back_end.name == "terminal" {
				back_end.initialize(&current_back_end, &vulkan, mem_logger.data)
			} else {
				back_end.initialize(&current_back_end, &vulkan, nil)
			}

			// NOTE(jan): Create render passes first time through.
			back_end.resize_end(&current_back_end, &vulkan)
		}

		// NOTE(jan): Resize framebuffers and swap chain.
		if (do_resize) {
			do_resize = false

			gfx.vulkan_swap_update_capabilities(&vulkan)
			gfx.vulkan_swap_update_extent(&vulkan)

			if (vulkan.swap.extent.height == 0) || (vulkan.swap.extent.width == 0) {
				continue
			}

			vk.QueueWaitIdle(vulkan.gfx_queue)

			back_end.resize_begin(&current_back_end, &vulkan)

			gfx.vulkan_swap_destroy(&vulkan)
			free_all(vulkan.resize_allocator)

			gfx.vulkan_swap_create(&vulkan)

			back_end.resize_end(&current_back_end, &vulkan)
		}

		// NOTE(jan): Update input state screen res since it may have changed during resize.
		input_state.screen.x = vulkan.swap.extent.width
		input_state.screen.y = vulkan.swap.extent.height

		// NOTE(jan): Collect commands from all currently running apps.
		app_cmd_lists := make([dynamic]app.CommandList, context.temp_allocator)
		append(&app_cmd_lists, current_app.emit_commands_proc(&current_app, events[:], input_state))
		for &a in reg.app {
			if app.is_system_app(&a) {
				append(&app_cmd_lists, a.emit_commands_proc(&a, events[:], input_state))
			}
		}

		// NOTE(jan): Allocate a transient command buffer for before-frame actions like updating uniforms.
		transient_cmd := gfx.vulkan_cmd_allocate_and_begin_transient(vulkan, transient_cmd_pool)
		back_end.prepare_frame(&current_back_end, &vulkan, events[:], input_state, app_cmd_lists[:], transient_cmd)
		gfx.vulkan_cmd_end_and_submit(vulkan, &transient_cmd)

		// NOTE(jan): Acquire next swap image.
		swap_image_index: u32;
		{
			result := vk.AcquireNextImageKHR(
				vulkan.device,
				vulkan.swap.handle,
				bits.U64_MAX,
				image_ready,
				0,
				&swap_image_index,
			)
			#partial switch result {
				case vk.Result.SUBOPTIMAL_KHR:
					do_resize = true
					continue new_frame;
				case vk.Result.ERROR_OUT_OF_DATE_KHR:
					do_resize = true
					continue new_frame;
				case vk.Result.SUCCESS:
				case:
					fmt.panicf("could not acquire next swap image %d", result)
			}
		}

		// NOTE(jan): Record command buffer.
		begin := vk.CommandBufferBeginInfo {
			sType = vk.StructureType.COMMAND_BUFFER_BEGIN_INFO,
			flags = { vk.CommandBufferUsageFlag.ONE_TIME_SUBMIT },
		}
		gfx.check(
			vk.BeginCommandBuffer(cmd, &begin),
			"could not begin cmd buffer",
		)

		back_end.draw_frame(&current_back_end, &vulkan, cmd, swap_image_index)

		vk.EndCommandBuffer(cmd)

		// NOTE(jan): Submit command buffer.
		submit := vk.SubmitInfo {
			sType = vk.StructureType.SUBMIT_INFO,
			commandBufferCount = 1,
			pCommandBuffers = &cmd,
			waitSemaphoreCount = 1,
			pWaitSemaphores = &image_ready,
			pWaitDstStageMask = raw_data(&[?]vk.PipelineStageFlags {
				{ vk.PipelineStageFlag.COLOR_ATTACHMENT_OUTPUT },
			}),
			signalSemaphoreCount = 1,
			pSignalSemaphores = &cmd_buffer_done,
		}
		gfx.check(
			vk.QueueSubmit(vulkan.gfx_queue, 1, &submit, 0),
			"could not submit command buffer",
		)

		// NOTE(jan): Present.
		present := vk.PresentInfoKHR {
			sType = vk.StructureType.PRESENT_INFO_KHR,
			swapchainCount = 1,
			pSwapchains = &vulkan.swap.handle,
			waitSemaphoreCount = 1,
			pWaitSemaphores = &cmd_buffer_done,
			pImageIndices = &swap_image_index,
		}
		result := vk.QueuePresentKHR(vulkan.gfx_queue, &present);
		#partial switch result {
			case vk.Result.SUCCESS:
			case vk.Result.ERROR_DEVICE_LOST:
				panic("device lost while presenting")
			case vk.Result.ERROR_SURFACE_LOST_KHR:
				panic("surface lost while presenting")
			case vk.Result.ERROR_OUT_OF_DATE_KHR:
				do_resize = true
			case vk.Result.SUBOPTIMAL_KHR:
				do_resize = true
			case:
				panic("unknown error while presenting")
		}

		// NOTE(jan): Wait to be done.
		// PERF(jan): This might be slow.
		vk.QueueWaitIdle(vulkan.gfx_queue)

		back_end.cleanup_frame(&current_back_end, &vulkan)

		for buffer, i in vulkan.temp_buffers {
			gfx.vulkan_buffer_destroy(&vulkan, &vulkan.temp_buffers[i])
		}
		vk.FreeCommandBuffers(vulkan.device, transient_cmd_pool, 1, &transient_cmd)
	}

	for &a in reg.app {
		app.cleanup(&a, nil)
	}

	vk.DeviceWaitIdle(vulkan.device)
	back_end.cleanup(&current_back_end, &vulkan)

	// NOTE(jan): This fixes false positives in the leak without having to free unnecessarily in prod.
	when ODIN_DEBUG {
		for a in reg.app {
			free_all(a.allocator)
		}
		for b in reg.back_end {
			free_all(b.allocator)
		}
		free_all(reg.allocator)
		free_all(context.temp_allocator)
		free_all(vulkan.device_allocator)
	}
}
