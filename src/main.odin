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

main :: proc() {
  // intiate SDL
  SDL.Init({.VIDEO})
  defer SDL.Quit()

  SDL.SetHintWithPriority(SDL.HINT_RENDER_DRIVER, "direct3d11", .OVERRIDE)

  // create SDL window
  window := SDL.CreateWindow(
    "Game", 
    SDL.WINDOWPOS_CENTERED, SDL.WINDOWPOS_CENTERED, 
    500, 500,
    {.ALLOW_HIGHDPI, .HIDDEN, .RESIZABLE},
  )
  defer SDL.DestroyWindow(window)

  window_system_info: SDL.SysWMinfo
  SDL.GetVersion(&window_system_info.version)

  if !SDL.GetWindowWMInfo(window, &window_system_info) {
    fmt.eprintln("Cannot get window WM Info")
    return 
  }

  // directx is windows only
  assert(window_system_info.subsystem == .WINDOWS)

  native_window := DXGI.HWND(window_system_info.info.win.window)

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

  // create swap chain
  dxgi_device : ^DXGI.IDevice
  if res := device->QueryInterface(DXGI.IDevice_UUID, (^rawptr)(&dxgi_device)); res != 0 {
    fmt.eprintf("Failed to query IDevice interface for dxgi_device. code: 0x{0:x}", res)
    return
  }
  defer dxgi_device->Release()

  dxgi_adapter : ^DXGI.IAdapter
  if res := dxgi_device->GetAdapter(&dxgi_adapter); res != 0 {
    fmt.eprintf("failed to get adapter. code: 0x{0:x}", res)
    return 
  }
  defer dxgi_adapter->Release()

  dxgi_factory : ^DXGI.IFactory2
  if res := dxgi_adapter->GetParent(DXGI.IFactory2_UUID, (^rawptr)(&dxgi_factory)); res != 0 {
    fmt.eprintf("failed to get adapter parent. code: 0x{0:x}", res)
    return
  }
  defer dxgi_factory->Release()

  swapchain_desc := DXGI.SWAP_CHAIN_DESC1{
    Width = 0,
    Height = 0,
    Format = .B8G8R8A8_UNORM_SRGB,
    Stereo = false,
    SampleDesc = {
      Count = 1,
      Quality = 0,
    },
    BufferUsage = .RENDER_TARGET_OUTPUT,
    BufferCount = 2,
    Scaling = .STRETCH,
    SwapEffect = .DISCARD,
    AlphaMode = .UNSPECIFIED,
    Flags = 0,
  }

  swapchain : ^DXGI.ISwapChain1
  if res := dxgi_factory->CreateSwapChainForHwnd(device, native_window, &swapchain_desc, nil, nil, &swapchain); res != 0 {
    fmt.eprintf("Unable to create swapchain. code: 0x{0:x}", res)
    return 
  }
  defer swapchain->Release()

  // create frame buffers
  framebuffer: ^D3D.ITexture2D
  if res := swapchain->GetBuffer(0, D3D.ITexture2D_UUID, (^rawptr)(&framebuffer)); res != 0 {
    fmt.eprintf("Unable to get buffer from swapchain. code: 0x{0:x}", res)
    return 
  }
  defer framebuffer->Release()

  framebuffer_view: ^D3D.IRenderTargetView
  if res := device->CreateRenderTargetView(framebuffer, nil, &framebuffer_view); res != 0 {
    fmt.eprintf("Unable to create framebuffer render target view. code: 0x{0:x}", res)
    return
  }
  defer framebuffer_view->Release()

  // create depth buffer
  depth_buffer_desc: D3D.TEXTURE2D_DESC
  framebuffer->GetDesc(&depth_buffer_desc)
  depth_buffer_desc.Format = .D24_UNORM_S8_UINT
  depth_buffer_desc.BindFlags = .DEPTH_STENCIL

  depth_buffer: ^D3D.ITexture2D
  if res := device->CreateTexture2D(&depth_buffer_desc, nil, &depth_buffer); res != 0 {
    fmt.eprintf("Unable to create depth buffer texture 2D. code: 0x{0:x}", res)
    return
  }
  defer depth_buffer->Release()

  depth_buffer_view: ^D3D.IDepthStencilView
  if res := device->CreateDepthStencilView(depth_buffer, nil, &depth_buffer_view); res != 0 {
    fmt.eprintf("Unable to create stencil view. code: 0x{0:x}", res)
    return 
  }
  defer depth_buffer_view->Release()

  depth_stencil_desc := D3D.DEPTH_STENCIL_DESC{
		DepthEnable    = true,
		DepthWriteMask = .ALL,
		DepthFunc      = .LESS,
	}
	depth_stencil_state: ^D3D.IDepthStencilState
	if res := device->CreateDepthStencilState(&depth_stencil_desc, &depth_stencil_state); res != 0 {
    fmt.eprintf("Unable to create depth stencil state. 0x{0:x}", res)
    return 
  }
  defer depth_stencil_state->Release()

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

  // 6 float x 32bit(4 bytes)
  vertex_buffer_stride := u32(6 * 4)
	vertex_buffer_offset := u32(0)

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

    viewport := D3D.VIEWPORT {
      0, 0, 
      f32(depth_buffer_desc.Width), f32(depth_buffer_desc.Height),
      0, 1,
    }

    w := viewport.Width / viewport.Height
      h := f32(1)
      n := f32(1)
      f := f32(9)

    device_context->ClearRenderTargetView(framebuffer_view, &[4]f32{0, 0, 0, 1})
    device_context->ClearDepthStencilView(depth_buffer_view, .DEPTH, 1, 0)
    
    device_context->RSSetViewports(1, &viewport)

    for _, i in meshes {
      meshes[i].position += glm.vec3{0, 0.001, 0}
      translate := glm.mat4Translate(meshes[i].position)

      mapped_subresource: D3D.MAPPED_SUBRESOURCE
      device_context->Map(meshes[i].const_vp_buffer, 0, .WRITE_DISCARD, 0, &mapped_subresource)
      {
        constants := (^Const_VP)(mapped_subresource.pData)
        constants.transform = translate
        constants.projection = {
          2 * n / w, 0,         0,           0,
          0,         2 * n / h, 0,           0,
          0,         0,         f / (f - n), n * f / (n - f),
          0,         0,         1,           0,
        }
      }
      device_context->Unmap(meshes[i].const_vp_buffer, 0)

      device_context->VSSetConstantBuffers(0, 1, &meshes[i].const_vp_buffer)

      device_context->IASetPrimitiveTopology(.TRIANGLELIST)
      device_context->IASetInputLayout(meshes[i].material.shader.input_layout)
      device_context->IASetVertexBuffers(0, 1, &meshes[i].vertex_buffer, &vertex_buffer_stride, &vertex_buffer_offset)
      device_context->IASetIndexBuffer(meshes[i].index_buffer, .R32_UINT, 0)
      device_context->VSSetShader(meshes[i].material.shader.vertex_shader, nil, 0)
      device_context->PSSetShader(meshes[i].material.shader.pixel_shader, nil, 0)

      device_context->OMSetRenderTargets(1, &framebuffer_view, depth_buffer_view)
      device_context->OMSetDepthStencilState(depth_stencil_state, 0)
      
      device_context->DrawIndexed(u32(len(meshes[i].indices)), 0, 0)
    }

    swapchain->Present(1, 0)
  }
}

size_of_slice :: proc($T: typeid, slice: []T) -> u32 {
  return u32(len(slice) * size_of(slice[0]))
}
