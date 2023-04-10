package nido

import "core:dynlib"
import "core:fmt"
import "core:log"
import "core:math"
import "core:math/bits"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import "core:runtime"
import "vendor:sdl2"
import vk "vendor:vulkan"

Uniforms :: struct {
	mvp: mat4x4,
	ortho: mat4x4,
}

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
	context.logger = log.create_file_logger(h=log_file_handle, lowest=log.Level.Debug)
	log.infof("Logging initialized")

	// NOTE(jan): Load Vulkan functions.
	vk_dll := dynlib.load_library("vulkan-1.dll") or_else panic("Couldn't load vulkan-1.dll!")
	log.infof("Loaded vulkan-1.dll")

	vk_get_instance_proc_addr := dynlib.symbol_address(vk_dll, "vkGetInstanceProcAddr") or_else panic("vkGetInstanceProcAddr not found");
	vk.load_proc_addresses_global(vk_get_instance_proc_addr);
	log.infof("Loaded vulkan global functions")

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

	// NOTE(jan): Check if the layers we require are available.
	required_layers := make([dynamic]string, context.temp_allocator);
	{
		append(&required_layers, "VK_LAYER_KHRONOS_validation")

		log.infof("Required layers: ")
		for layer in required_layers {
			log.infof("\t* %s", layer);
		}

		count: u32;
		check(
			vk.EnumerateInstanceLayerProperties(&count, nil),
			"could not count available layers",
		);

		available_layers := make([^]vk.LayerProperties, count, context.temp_allocator);
		check(
			vk.EnumerateInstanceLayerProperties(&count, available_layers),
			"could not fetch available layers",
		);

		log.infof("Available layers: ")
		available_layer_names := make([dynamic]string, context.temp_allocator)
		for i in 0..<count {
			layer := available_layers[i]
			name := odinize_string(layer.layerName[:])
			append(&available_layer_names, name)
			log.infof("\t* %s", name);
		}

		log.infof("Checking extensions: ")
		for required_layer in required_layers {
			if slice.contains(available_layer_names[:], required_layer) {
				log.infof("\t\u2713 %s", required_layer)
			} else {
				fmt.panicf("\t\u274C %s", required_layer)
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
		check(vk.EnumerateInstanceExtensionProperties(nil, &count, nil), "could not fetch vk extensions")
		available_extensions := make([^]vk.ExtensionProperties, count, context.temp_allocator)

		check(vk.EnumerateInstanceExtensionProperties(nil, &count, available_extensions), "can't fetch vk extensions")

		available_extension_names := make([dynamic]string, context.temp_allocator)
		for extension_index in 0..<count {
			extension := available_extensions[extension_index]
			name := odinize_string(extension.extensionName[:])
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
	vulkan: Vulkan
	{
		app := vk.ApplicationInfo {
			sType=vk.StructureType.APPLICATION_INFO,
			apiVersion=vk.API_VERSION_1_2,
		}

		create := vk.InstanceCreateInfo {
			sType = vk.StructureType.INSTANCE_CREATE_INFO,
			pApplicationInfo = &app,
			enabledExtensionCount = u32(len(required_extensions)),
			ppEnabledExtensionNames = vulkanize_strings(required_extensions),
			enabledLayerCount = u32(len(required_layers)),
			ppEnabledLayerNames = vulkanize_strings(required_layers),
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

		check(
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
		check(
			vk.EnumeratePhysicalDevices(vulkan.handle, &count, nil),
			"couldn't count gpus",
		)

		gpus := make([^]vk.PhysicalDevice, count, context.temp_allocator)
		check(
			vk.EnumeratePhysicalDevices(vulkan.handle, &count, gpus),
			"couldn't fetch gpus",
		)

		log.infof("%d physical device(s)", count)
		gpu_loop: for gpu, gpu_index in gpus[:count] {
			props: vk.PhysicalDeviceProperties
			vk.GetPhysicalDeviceProperties(gpu, &props)

			{
				name := odinize_string(props.deviceName[:])
				log.infof("GPU #%d \"%s\":", gpu_index, name)
			}

			// NOTE(jan): Check extensions.
			{
				count: u32;
				check(
					vk.EnumerateDeviceExtensionProperties(gpu, nil, &count, nil),
					"could not count device extension properties",
				)

				extensions := make([^]vk.ExtensionProperties, count, context.temp_allocator)
				check(
					vk.EnumerateDeviceExtensionProperties(gpu, nil, &count, extensions),
					"could not fetch device extension properties",
				)

				log.infof("\tAvailable device extensions:")
				extension_names := make([dynamic]string, context.temp_allocator)
				for i in 0..<count {
					name := odinize_string(extensions[i].extensionName[:])
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
			pQueueCreateInfos = vulkanize(queues),
			enabledExtensionCount = u32(len(required_device_extensions)),
			ppEnabledExtensionNames = vulkanize_strings(required_device_extensions),
		}

		check(
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
		vulkan_swap_update_capabilities(&vulkan)
		vulkan_swap_update_extent(&vulkan)

		if vk.ImageUsageFlag.COLOR_ATTACHMENT not_in vulkan.swap.capabilities.supportedUsageFlags {
			panic("surface does not support color attachment")
		}
		if vk.CompositeAlphaFlagKHR.OPAQUE not_in vulkan.swap.capabilities.supportedCompositeAlpha {
			panic("surface does not support opaque composition")
		}

		// NOTE(jan): Find a surface color space & format.
		{
			count: u32;
			check(
				vk.GetPhysicalDeviceSurfaceFormatsKHR(vulkan.gpu, vulkan.surface, &count, nil),
				"could not count physical device surface formats",
			)

			formats := make([^]vk.SurfaceFormatKHR, count, context.temp_allocator)
			check(
				vk.GetPhysicalDeviceSurfaceFormatsKHR(vulkan.gpu, vulkan.surface, &count, formats),
				"could not fetch physical device surface formats",
			)

			found := false;
			for format in formats[:count] {
				if (format.colorSpace == vk.ColorSpaceKHR.SRGB_NONLINEAR) &&
						(format.format == vk.Format.B8G8R8A8_UNORM) {
					vulkan.swap.format = format.format;
					vulkan.swap.color_space = format.colorSpace;
					log.infof("Found a compatible color space & format.")
					found = true;
					break;
				}
			}

			if !found do panic("no compatible color space & format")
		}

		// NOTE(jan): Pick a present mode.
		{
			count: u32;
			check(
				vk.GetPhysicalDeviceSurfacePresentModesKHR(vulkan.gpu, vulkan.surface, &count, nil),
				"could not count present modes",
			)

			modes := make([^]vk.PresentModeKHR, count, context.temp_allocator)
			check(
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

	vulkan_swap_create(&vulkan)

	// NOTE(jan): Create shader modules.
	// Shader modules live for the entire lifetime.
	vulkan_create_shader_modules(&vulkan)

	// Pipelines live between window resizes.
	mem.dynamic_pool_init(&vulkan.resize_pool,
                          context.allocator,
                          context.allocator,
                          mem.DYNAMIC_POOL_BLOCK_SIZE_DEFAULT,
                          mem.DYNAMIC_POOL_OUT_OF_BAND_SIZE_DEFAULT,
                          64)
	vulkan.resize_allocator = mem.dynamic_pool_allocator(&vulkan.resize_pool)

	image_ready, cmd_buffer_done : vk.Semaphore
	{
		create := vk.SemaphoreCreateInfo {
			sType = vk.StructureType.SEMAPHORE_CREATE_INFO,
		}
		check(
			vk.CreateSemaphore(vulkan.device, &create, nil, &image_ready),
			"could not create semaphore",
		)
		check(
			vk.CreateSemaphore(vulkan.device, &create, nil, &cmd_buffer_done),
			"could not create semaphore",
		)
	}
	log.infof("Semaphores created.")

	cmd_pool: vk.CommandPool
	{
		create := vk.CommandPoolCreateInfo {
			sType = vk.StructureType.COMMAND_POOL_CREATE_INFO,
			// TODO(jan): If we re-record each frame...
			flags = {
				// vk.CommandPoolCreateFlag.TRANSIENT,
				vk.CommandPoolCreateFlag.RESET_COMMAND_BUFFER,
			},
			queueFamilyIndex = vulkan.gfx_queue_family,
		}
		check(
			vk.CreateCommandPool(vulkan.device, &create, nil, &cmd_pool),
			"could not create command pool",
		)
		log.infof("Created command pool.")
	}

	cmd: vk.CommandBuffer
	{
		info := vk.CommandBufferAllocateInfo {
			sType = vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO,
			commandBufferCount = 1,
			commandPool = cmd_pool,
			level = vk.CommandBufferLevel.PRIMARY,
		}
		check(
			vk.AllocateCommandBuffers(vulkan.device, &info, &cmd),
			"could not allocate cmd buffer",
		)
		log.info("Created command buffer.")
	}

	transient_cmd_pool: vk.CommandPool
	{
		create := vk.CommandPoolCreateInfo {
			sType = vk.StructureType.COMMAND_POOL_CREATE_INFO,
			flags = {
				vk.CommandPoolCreateFlag.TRANSIENT,
			},
			queueFamilyIndex = vulkan.gfx_queue_family,
		}
		check(
			vk.CreateCommandPool(vulkan.device, &create, nil, &transient_cmd_pool),
			"could not create transient command pool",
		)
		log.infof("Created transient command pool.")
	}

	vulkan_pass := vulkan_pass_create(
		&vulkan,
		[]VulkanPipelineMetadata {
			{
				"stbtt",
				{
					"ortho_xy_uv_rgba",
					"text",
				},
			},
		},
	)

	linear_sampler := vulkan_sampler_create(vulkan)

	font_sprite_sheet_data := make([]u8, 512 * 512)
	mem.set(raw_data(font_sprite_sheet_data), 255, 512 * 512)
	font_sprite_sheet := vulkan_image_create_2d_monochrome_texture(vulkan, vk.Extent2D { 512, 512 })

	// NOTE(jan): Upload mesh.
	mesh := VulkanMesh {
		positions = make([dynamic]f32, context.temp_allocator),
		uv = make([dynamic]f32, context.temp_allocator),
		rgba = make([dynamic]f32, context.temp_allocator),
		indices = make([dynamic]u32, context.temp_allocator),
	}
	screen := AABox {
		left = -1,
		right = 1,
		top = 1,
		bottom = -1,
	}
	vulkan_mesh_push_aabox(&mesh, screen)
	vulkan_mesh_upload(vulkan, &mesh)

	uniforms: Uniforms
	identity(&uniforms.mvp)
	identity(&uniforms.ortho)
	uniform_buffer := vulkan_buffer_create_uniform(vulkan, size_of(uniforms))

	// NOTE(jan): Main loop.
	done := false;
	do_resize := false;
	new_frame: for (!done) {
		free_all(context.temp_allocator)

		vulkan.temp_buffers = make([dynamic]VulkanBuffer, context.temp_allocator)

		// NOTE(jan): Handle events.
		sdl2.PumpEvents();
		for event: sdl2.Event; sdl2.PollEvent(&event); {
			#partial switch event.type {
				case sdl2.EventType.KEYDOWN:
					event: sdl2.KeyboardEvent = event.key;
					if (event.keysym.sym == sdl2.Keycode.ESCAPE) {
						done = true;
					}
				case sdl2.EventType.QUIT:
					done = true;
			}
		}

		// NOTE(jan): Resize framebuffers and swap chain.
		if (do_resize) {
			vulkan_pass_destroy(&vulkan, &vulkan_pass)

			free_all(vulkan.resize_allocator)

			vulkan_swap_destroy(&vulkan)
			vulkan_swap_update_capabilities(&vulkan)
			vulkan_swap_update_extent(&vulkan)
			vulkan_swap_create(&vulkan)

			vulkan_pass = vulkan_pass_create(
				&vulkan,
				[]VulkanPipelineMetadata {
					{
						"stbtt",
						{
							"ortho_xy_uv_rgba",
							"text",
						},
					},
				},
			)
		}

		assert("stbtt" in vulkan_pass.pipelines)
		pipeline := vulkan_pass.pipelines["stbtt"]

		// NOTE(jan): Update uniforms.
		vulkan_memory_copy(vulkan, uniform_buffer, &uniforms, size_of(uniforms))
		vulkan_descriptor_update_uniform(vulkan, pipeline.descriptor_sets[0], 0, uniform_buffer);

		// NOTE(jan): Update sampler.
		{
			transient_cmd: vk.CommandBuffer
			info := vk.CommandBufferAllocateInfo {
				sType = vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO,
				commandBufferCount = 1,
				commandPool = transient_cmd_pool,
				level = vk.CommandBufferLevel.PRIMARY,
			}
			check(
				vk.AllocateCommandBuffers(vulkan.device, &info, &transient_cmd),
				"could not allocate cmd buffer",
			)

			check(
				vk.BeginCommandBuffer(transient_cmd, &vk.CommandBufferBeginInfo {
					sType = vk.StructureType.COMMAND_BUFFER_BEGIN_INFO,
					flags = { vk.CommandBufferUsageFlag.ONE_TIME_SUBMIT },
				}),
				"could not begin transient command buffer",
			)

			vulkan_image_update_texture(
				&vulkan,
				transient_cmd,
				vk.Extent2D { 512, 512 },
				font_sprite_sheet_data,
				font_sprite_sheet,
			)
			vulkan_descriptor_update_combined_image_sampler(
				vulkan,
				pipeline.descriptor_sets[0],
				1,
				[]VulkanImage { font_sprite_sheet },
				linear_sampler,
			)

			vk.EndCommandBuffer(transient_cmd)

			check(
				vk.QueueSubmit(
					vulkan.gfx_queue,
					1,
					&vk.SubmitInfo {
						sType = vk.StructureType.SUBMIT_INFO,
						commandBufferCount = 1,
						pCommandBuffers = &transient_cmd,
					},
					0,
				),
				"could not submit transient command buffer",
			)
		}

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
		check(
			vk.BeginCommandBuffer(cmd, &begin),
			"could not begin cmd buffer",
		)

		clears := [?]vk.ClearValue {
			vk.ClearValue { color = { float32 = {.5, .5, .5, 1}}},
		}

		pass := vk.RenderPassBeginInfo {
			sType = vk.StructureType.RENDER_PASS_BEGIN_INFO,
			clearValueCount = u32(len(clears)),
			pClearValues = raw_data(&clears),
			framebuffer = vulkan_pass.framebuffers[swap_image_index],
			renderArea = vk.Rect2D {
				extent = vulkan.swap.extent,
				offset = {0, 0},
			},
			renderPass = vulkan_pass.render_pass,
		}

		vk.CmdBeginRenderPass(cmd, &pass, vk.SubpassContents.INLINE)
		
		vk.CmdBindDescriptorSets(
			cmd,
			vk.PipelineBindPoint.GRAPHICS,
			pipeline.layout,
			0, u32(len(pipeline.descriptor_sets)),
			raw_data(pipeline.descriptor_sets),
			0, nil,
		)

		vk.CmdBindPipeline(cmd, vk.PipelineBindPoint.GRAPHICS, pipeline.handle)
		// vk.CmdBindDescriptorSets
		offsets := [1]vk.DeviceSize {0}
		vk.CmdBindVertexBuffers(cmd, 0, 1, &mesh.position_buffer.handle, raw_data(offsets[:]))
		vk.CmdBindVertexBuffers(cmd, 1, 1, &mesh.uv_buffer.handle, raw_data(offsets[:]))
		vk.CmdBindVertexBuffers(cmd, 2, 1, &mesh.rgba_buffer.handle, raw_data(offsets[:]))
		vk.CmdBindIndexBuffer(cmd, mesh.index_buffer.handle, 0, vk.IndexType.UINT32)
		vk.CmdDrawIndexed(cmd, u32(len(mesh.indices)), 1, 0, 0, 0)

		vk.CmdEndRenderPass(cmd)
		check(
			vk.EndCommandBuffer(cmd),
			"could not end command buffer",
		)

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
		check(
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

		for buffer in vulkan.temp_buffers {
			vulkan_buffer_destroy(vulkan, buffer)
		}
	}
}
