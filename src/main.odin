package dx11

import "core:fmt"
import slice "core:slice"
import libc "core:c/libc"
import SDL "vendor:sdl2"
import D3D "vendor:directx/d3d11"
import DXGI "vendor:directx/dxgi"
import DCompile "vendor:directx/d3d_compiler"
import glm "core:math/linalg/glsl"
import os "core:os"
import mem "core:mem"

WindowPixelWidth :: 640
WindowPixelHeight :: 480

main :: proc() {
  // intiate SDL
  SDL.Init({.VIDEO})
  defer SDL.Quit()

  SDL.SetHintWithPriority(SDL.HINT_RENDER_DRIVER, "direct3d11", .OVERRIDE)

  // create window
  window := SDL.CreateWindow(
    "Snake!", 
    SDL.WINDOWPOS_CENTERED, SDL.WINDOWPOS_CENTERED, 
    WindowPixelWidth, WindowPixelHeight,
    {.ALLOW_HIGHDPI, .HIDDEN},
  )
  defer SDL.DestroyWindow(window)

  // create D3D11 device
  feature_levels := [?]D3D.FEATURE_LEVEL{._11_0}

  base_device: ^D3D.IDevice
  base_device_context: ^D3D.IDeviceContext

  if res := D3D.CreateDevice(nil, .HARDWARE, nil, {.BGRA_SUPPORT}, &feature_levels[0], 1, D3D.SDK_VERSION, &base_device, nil, &base_device_context,); res != 0 {
    fmt.eprintf("failed to create D3D device. code: 0x{0:x}", res)
    return
  }

  device : ^D3D.IDevice
  if res := base_device->QueryInterface(D3D.IDevice_UUID, (^rawptr)(&device)); res != 0 {
    base_device->Release()
    base_device_context->Release()
    fmt.eprintf("Failed to query IDevice interface for device. code: 0x{0:x}", res)
    return 
  }
  defer device->Release()

  // no longer need base device
  base_device->Release()

  device_context : ^D3D.IDeviceContext
  if res := base_device_context->QueryInterface(D3D.IDeviceContext_UUID, (^rawptr)(&device_context)); res != 0 {
    base_device_context->Release()
    fmt.eprintf("Failed to query IDeviceContext interface. code: 0x{0:x}", res)
    return
  }
  defer device_context->Release()

  // no longer need base device context
  base_device_context->Release()

  // create renderer
  renderer: Renderer
  if ok := create_renderer(window, device, &renderer); !ok {
    return
  }
  defer release_renderer(&renderer)

  // create shader
  shader: Shader
  if ok := create_shader(device, "shaders/default_shader.hlsl", &shader); !ok {
    return
  }
  defer release_shader(&shader)

  meshes: [dynamic]Mesh

  // mesh #1
  vertex_data1 := [?]glm.vec3 {
    glm.vec3{0.0, 0.5, -1.0 },  glm.vec3{1.0, 0.0, 0.0},
    glm.vec3{0.45, -0.5, -1.0 },  glm.vec3{0.0, 1.0, 0.0},
    glm.vec3{-0.45, -0.5, -1.0 },  glm.vec3{0.0, 0.0, 1.0},
  }
  index_data1 := [?]u32{
    0, 1, 2,
  }
  pos1 := glm.vec3{0, 0, 4}
  mesh1: Mesh
  if ok := create_mesh(device, &shader, vertex_data1[:], index_data1[:], pos1, &mesh1); !ok {
    return
  }
  defer release_mesh(&mesh1)

  append(&meshes, mesh1)

  // mesh #1
  vertex_data2 := [?]glm.vec3 {
    glm.vec3{0.0, 0.5, -1.0 },  glm.vec3{1.0, 0.0, 0.0},
    glm.vec3{0.45, -0.5, -1.0 },  glm.vec3{0.0, 1.0, 0.0},
    glm.vec3{-0.45, -0.5, -1.0 },  glm.vec3{0.0, 0.0, 1.0},
  }
  index_data2 := [?]u32{
    0, 1, 2,
  }
  pos2 := glm.vec3{0.5, 0, 4}
  mesh2: Mesh
  if ok := create_mesh(device, &shader, vertex_data2[:], index_data2[:], pos2, &mesh2); !ok {
    return
  }
  defer release_mesh(&mesh2)

  append(&meshes, mesh2)

  // display window
  SDL.ShowWindow(window)

  // game loop
  for quit := false; !quit; {
    for e: SDL.Event; SDL.PollEvent(&e); {
      #partial switch(e.type) {
        case .QUIT:
          quit = true
        case .KEYDOWN:
          if e.key.keysym.sym == .ESCAPE {
            quit = true
          }
      }
    }

    render(&renderer, device_context, meshes[:])
  }
}

size_of_slice :: proc($T: typeid, slice: []T) -> u32 {
  return u32(len(slice) * size_of(slice[0]))
}
