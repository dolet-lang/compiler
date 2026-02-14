# Dolet Vulkan Bindings

FFI (Foreign Function Interface) bindings for the Vulkan graphics API, written for the Dolet programming language.

## Overview

This library provides low-level bindings to the Vulkan API, enabling direct access to GPU hardware for:

- 3D graphics rendering
- Real-time graphics applications
- Game development
- GPU compute operations
- Video encoding/decoding

## Features

- Complete Vulkan core API bindings (698 functions)
- Auto-generated from `vulkan_core.h`
- Direct FFI calls to `vulkan-1` library
- Support for Vulkan extensions (KHR, EXT, NV, AMD, etc.)

## Usage

This library is used as a dependency in the [Qubic Engine](https://github.com/xRo0t/qubic-engine) for 3D rendering capabilities.

```dolet
import vulkan

# Example: Create Vulkan instance
let result = vkCreateInstance(pCreateInfo, pAllocator, pInstance)
```

## Requirements

- Vulkan SDK installed on your system
- `vulkan-1.dll` (Windows) or `libvulkan.so` (Linux) available in system path

## License

See LICENSE file for details.
