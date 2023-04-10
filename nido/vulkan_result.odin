package nido

import vk "vendor:vulkan"

check :: proc(result: vk.Result, error: string) {
	if (result != vk.Result.SUCCESS) {
		panic(error)
	}
}
