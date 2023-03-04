package main

import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:slice"
import "vendor:sdl2"
import "vendor:vulkan"

main :: proc() {
	log_file_handle, log_file_error := os.open("log.txt", os.O_CREATE | os.O_WRONLY)
	context.logger = log.create_file_logger(h=log_file_handle, lowest=log.Level.Debug)
	log.infof("Logging initialized")

	// NOTE(jan): Initialize SDL2.
	sdl_init_error: i32 = sdl2.Init(sdl2.INIT_EVENTS | sdl2.INIT_TIMER | sdl2.INIT_VIDEO)
	if (sdl_init_error != 0) {
		log.errorf("Could not initialize SDL2")
	} else {
		log.infof("SDL2 initialized")
	}
	
	// NOTE(jan): Create window.
	sdl2.CreateWindow("nido", 100, 100, 640, 480, sdl2.WINDOW_SHOWN) //sdl2.WINDOW_VULKAN)

	// NOTE(jan): Main loop.
	done := false;
	for (!done) {
		sdl2.PumpEvents();
		for event: sdl2.Event; sdl2.PollEvent(&event); {
			fmt.println(event)
			if (event.type == sdl2.EventType.KEYDOWN) {
				event: sdl2.KeyboardEvent = event.key;
				if (event.keysym.sym == sdl2.Keycode.ESCAPE) {
					done = true;
				}
			}
		}
	}
}
