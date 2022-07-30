package dx11

import "core:fmt"
import libc "core:c/libc"
import D3D "vendor:directx/d3d11"
import DXGI "vendor:directx/dxgi"
import glm "core:math/linalg/glsl"
import os "core:os"
import mem "core:mem"
import SDL "vendor:sdl2"

Renderer :: struct {
  depth_buffer_view: ^D3D.IDepthStencilView,
  frame_buffer_view: ^D3D.IRenderTargetView,
  depth_stencil_state: ^D3D.IDepthStencilState,
  swapchain: ^DXGI.ISwapChain1,
  width: u32,
  height: u32,
}

create_renderer :: proc(window: ^SDL.Window, device: ^D3D.IDevice, renderer: ^Renderer) -> bool {
  window_system_info: SDL.SysWMinfo
  SDL.GetVersion(&window_system_info.version)

  if !SDL.GetWindowWMInfo(window, &window_system_info) {
    fmt.eprintln("Cannot get window WM Info")
    return false
  }

  // directx is windows only
  assert(window_system_info.subsystem == .WINDOWS)

  native_window := DXGI.HWND(window_system_info.info.win.window)

  // create swap chain
  dxgi_device : ^DXGI.IDevice
  if res := device->QueryInterface(DXGI.IDevice_UUID, (^rawptr)(&dxgi_device)); res != 0 {
    fmt.eprintf("Failed to query IDevice interface for dxgi_device. code: 0x{0:x}", res)
    return false
  }
  defer dxgi_device->Release()

  dxgi_adapter : ^DXGI.IAdapter
  if res := dxgi_device->GetAdapter(&dxgi_adapter); res != 0 {
    fmt.eprintf("failed to get adapter. code: 0x{0:x}", res)
    return false
  }
  defer dxgi_adapter->Release()

  dxgi_factory : ^DXGI.IFactory2
  if res := dxgi_adapter->GetParent(DXGI.IFactory2_UUID, (^rawptr)(&dxgi_factory)); res != 0 {
    fmt.eprintf("failed to get adapter parent. code: 0x{0:x}", res)
    return false
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
    return false
  }

  // create frame buffers
  framebuffer: ^D3D.ITexture2D
  if res := swapchain->GetBuffer(0, D3D.ITexture2D_UUID, (^rawptr)(&framebuffer)); res != 0 {
    fmt.eprintf("Unable to get buffer from swapchain. code: 0x{0:x}", res)
    swapchain->Release()
    return false
  }
  defer framebuffer->Release()

  framebuffer_view: ^D3D.IRenderTargetView
  if res := device->CreateRenderTargetView(framebuffer, nil, &framebuffer_view); res != 0 {
    fmt.eprintf("Unable to create framebuffer render target view. code: 0x{0:x}", res)
    framebuffer_view->Release()
    swapchain->Release()
    return false
  }

  // create depth buffer
  depth_buffer_desc: D3D.TEXTURE2D_DESC
  framebuffer->GetDesc(&depth_buffer_desc)
  depth_buffer_desc.Format = .D24_UNORM_S8_UINT
  depth_buffer_desc.BindFlags = .DEPTH_STENCIL

  depth_buffer: ^D3D.ITexture2D
  if res := device->CreateTexture2D(&depth_buffer_desc, nil, &depth_buffer); res != 0 {
    fmt.eprintf("Unable to create depth buffer texture 2D. code: 0x{0:x}", res)
    framebuffer_view->Release()
    swapchain->Release()
    return false
  }
  defer depth_buffer->Release()

  depth_buffer_view: ^D3D.IDepthStencilView
  if res := device->CreateDepthStencilView(depth_buffer, nil, &depth_buffer_view); res != 0 {
    fmt.eprintf("Unable to create stencil view. code: 0x{0:x}", res)
    framebuffer_view->Release()
    swapchain->Release()
    return false
  }

  depth_stencil_desc := D3D.DEPTH_STENCIL_DESC{
		DepthEnable    = true,
		DepthWriteMask = .ALL,
		DepthFunc      = .LESS,
	}
	depth_stencil_state: ^D3D.IDepthStencilState
	if res := device->CreateDepthStencilState(&depth_stencil_desc, &depth_stencil_state); res != 0 {
    fmt.eprintf("Unable to create depth stencil state. 0x{0:x}", res)
    framebuffer_view->Release()
    swapchain->Release()
    depth_buffer_view->Release()
    return false
  }

  renderer^ = Renderer {
    depth_stencil_state = depth_stencil_state,
    depth_buffer_view = depth_buffer_view,
    frame_buffer_view = framebuffer_view,
    swapchain = swapchain,
    width = depth_buffer_desc.Width,
    height = depth_buffer_desc.Height,
  }

  return true
}

render :: proc(renderer: ^Renderer, device_context: ^D3D.IDeviceContext, meshes: []Mesh) {
  // 6 float x 32bit(4 bytes)
  vertex_buffer_stride := u32(6 * 4)
	vertex_buffer_offset := u32(0)

  viewport := D3D.VIEWPORT {
    0, 0, 
    f32(renderer^.width), f32(renderer^.height),
    0, 1,
  }

  w := viewport.Width / viewport.Height
    h := f32(1)
    n := f32(1)
    f := f32(9)

  device_context->ClearRenderTargetView(renderer^.frame_buffer_view, &[4]f32{0, 0, 0, 1})
  device_context->ClearDepthStencilView(renderer^.depth_buffer_view, .DEPTH, 1, 0)
  
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

    device_context->OMSetRenderTargets(1, &renderer.frame_buffer_view, renderer^.depth_buffer_view)
    device_context->OMSetDepthStencilState(renderer^.depth_stencil_state, 0)
    
    device_context->DrawIndexed(u32(len(meshes[i].indices)), 0, 0)
  }

  renderer^.swapchain->Present(1, 0)
}

release_renderer :: proc(renderer: ^Renderer) {
  renderer.swapchain->Release()
  renderer.frame_buffer_view->Release()
  renderer.depth_buffer_view->Release()
  renderer.depth_stencil_state->Release()
}