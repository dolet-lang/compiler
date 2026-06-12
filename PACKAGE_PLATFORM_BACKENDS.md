# Package Platform Backend Layout

Packages should expose a stable public API from their root module and keep OS
bindings out of package root files.

## Rule

- Raw OS / system-library declarations live under `library/platform/<os>/`.
- Package-owned platform implementations live under `packages/<name>/platform/<os>/`.
- Public package modules load the active backend through `{platform}`.
- User code should import the package, not the platform backend directly.

## Shape

```text
library/platform/windows/win32/user32.dlt
library/platform/windows/win32/gdi32.dlt
library/platform/windows/win32/winsock.dlt

packages/window/mod.dlt
packages/window/constants.dlt
packages/window/platform/windows/core.dlt
packages/window/platform/linux/core.dlt

packages/input/mod.dlt
packages/input/platform/windows/platform.dlt
packages/input/platform/windows/gamepad.dlt
```

Root `mod.dlt` files should look like:

```dolet
module window
load window/constants
load window/platform/{platform}/core
```

Backend files import raw OS bindings through registry names:

```dolet
import sys.windows.win32.user32
import sys.windows.win32.constants
```

## Current Migrations

- `window`: Win32 raw bindings moved to `library/platform/windows/win32`;
  Windows implementation moved to `window/platform/windows`.
- `input`: keyboard/mouse backend moved to `input/platform/windows`; XInput
  raw binding moved to `library/platform/windows/win32/xinput`.
- `net`: package backend moved to `net/platform/windows`; raw Winsock binding
  moved to `library/platform/windows/win32/winsock`.
- `frog`: Windows-specific input and Vulkan context files moved under
  `frog/core/platform/windows` and `frog/render/platform/windows`.
- `vulkan`: public module now loads `vulkan/platform/{platform}/vulkan`.
  Windows keeps `dolet-vulkan-1`, Linux links system `libvulkan`.
- `window`: Linux X11 backend added under `window/platform/linux`.
- `frog`: Linux input, time, and Xlib Vulkan context backends added.

## Linux Game Build Prerequisites

Frog's Linux path currently targets X11 + Vulkan:

```bash
sudo apt install libvulkan-dev libx11-dev vulkan-tools
```

Compile from the game project root:

```bash
doletc src/main.dlt -o build/app -O3 --target linux
./build/app
```

If the linker reports `unable to find library -lvulkan` or `-lX11`, install
the development packages above. Runtime-only packages are not enough because
the linker needs the `lib*.so` development symlinks.

## Follow-Ups

- Add Linux backend for package `net` if package-level `net` is revived.
- Add Wayland window/surface backend beside the current X11 backend.
- Make Linux fullscreen/window-mode changes real instead of metadata-only.
- Implement Linux software framebuffer present path if non-Vulkan renderers
  need it.
- Move renderer-specific native surface creation out of engines and behind a
  shared package API.
- Decide whether the old `packages/net` module should replace or coexist with
  `library/std/net`, because `import net` currently resolves to `std/net`.
- Make missing backend loads fail early with a clear compiler error instead of
  continuing until a later undefined/internal codegen failure.
