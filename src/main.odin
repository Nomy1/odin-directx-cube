package dx11

import "core:fmt"
import slice "core:slice"
import libc "core:c/libc"
import SDL "vendor:sdl2"
import D3D "vendor:directx/d3d11"
import DXGI "vendor:directx/dxgi"
import DCompile "vendor:directx/d3d_compiler"
import glm "core:math/linalg/glsl"

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
    fmt.println("Cannot get window WM Info")
    return 
  }

  // directx is windows only
  assert(window_system_info.subsystem == .WINDOWS)

  native_window := DXGI.HWND(window_system_info.info.win.window)

  // create D3D11 device
  feature_levels := [?]D3D.FEATURE_LEVEL{._11_0}

  base_device: ^D3D.IDevice
  base_device_context: ^D3D.IDeviceContext

  if D3D.CreateDevice(
    nil, 
    .HARDWARE, 
    nil,
    {.BGRA_SUPPORT},
    &feature_levels[0],
    1,
    D3D.SDK_VERSION,
    &base_device,
    nil,
    &base_device_context,
  ) != 0 {
    fmt.println("failed to create D3D device")
    return
  }
  //defer base_device->Release()
  //defer base_device_context->Release()

  device : ^D3D.IDevice
  if base_device->QueryInterface(D3D.IDevice_UUID, (^rawptr)(&device)) != 0 {
    fmt.println("Failed to query IDevice interface for device")
    return 
  }
  //defer device->Release()

  device_context : ^D3D.IDeviceContext
  if base_device_context->QueryInterface(D3D.IDeviceContext_UUID, (^rawptr)(&device_context)) != 0 {
    fmt.println("Failed to query IDeviceContext interface")
    return
  }
  //defer device_context->Release()

  // create swap chain
  dxgi_device : ^DXGI.IDevice
  if device->QueryInterface(DXGI.IDevice_UUID, (^rawptr)(&dxgi_device)) != 0 {
    fmt.println("Failed to query IDevice interface for dxgi_device")
    return
  }
  //defer dxgi_device->Release()

  dxgi_adapter : ^DXGI.IAdapter
  if dxgi_device->GetAdapter(&dxgi_adapter) != 0 {
    fmt.println("failed to get adapter")
    return 
  }
  //defer dxgi_adapter->Release()

  dxgi_factory : ^DXGI.IFactory2
  if dxgi_adapter->GetParent(DXGI.IFactory2_UUID, (^rawptr)(&dxgi_factory)) != 0 {
    fmt.println("failed to get adapter parent")
    return
  }
  //defer dxgi_factory->Release()

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
  if dxgi_factory->CreateSwapChainForHwnd(device, native_window, &swapchain_desc, nil, nil, &swapchain) != 0 {
    fmt.println("Unable to create swapchain")
    return 
  }
  //defer swapchain->Release()

  // create frame buffers
  framebuffer: ^D3D.ITexture2D
  if swapchain->GetBuffer(0, D3D.ITexture2D_UUID, (^rawptr)(&framebuffer)) != 0 {
    fmt.println("Unable to get buffer from swapchain")
    return 
  }
  //defer framebuffer->Release()

  framebuffer_view: ^D3D.IRenderTargetView
  if device->CreateRenderTargetView(framebuffer, nil, &framebuffer_view) != 0 {
    fmt.println("Unable to create framebuffer render target view")
    return
  }
  //defer framebuffer_view->Release()

  // create depth buffer
  depth_buffer_desc: D3D.TEXTURE2D_DESC
  framebuffer->GetDesc(&depth_buffer_desc)
  depth_buffer_desc.Format = .D24_UNORM_S8_UINT
  depth_buffer_desc.BindFlags = .DEPTH_STENCIL

  depth_buffer: ^D3D.ITexture2D
  if device->CreateTexture2D(&depth_buffer_desc, nil, &depth_buffer) != 0 {
    fmt.println("Unable to create depth buffer texture 2D")
    return
  }
  //defer depth_buffer->Release()

  depth_buffer_view: ^D3D.IDepthStencilView
  if device->CreateDepthStencilView(depth_buffer, nil, &depth_buffer_view) != 0 {
    fmt.print("unable to create stencil view")
    return 
  }
  //defer depth_buffer_view->Release()

  // create vertex shader
  vs_blob: ^D3D.IBlob
  if DCompile.Compile(raw_data(shaders_hlsl), len(shaders_hlsl), "shaders.hlsl", nil, nil, "vs_main", "vs_5_0", 0, 0, &vs_blob, nil) != 0 {
    fmt.println("Unable to compile vertex shader")
    return
  }
  //defer vs_blob->Release()
  assert(vs_blob != nil)

  vertex_shader: ^D3D.IVertexShader
  if device->CreateVertexShader(vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), nil, &vertex_shader) != 0 {
    fmt.println("Unable to create vertex shader")
    return 
  }
  //defer vertex_shader->Release()

  input_element_desc := [?]D3D.INPUT_ELEMENT_DESC {
    {"POS", 0, .R32G32B32_FLOAT, 0, 0,                          .VERTEX_DATA, 0},
    {"COL", 0, .R32G32B32_FLOAT, 0, D3D.APPEND_ALIGNED_ELEMENT, .VERTEX_DATA, 0},
  }

  input_layout: ^D3D.IInputLayout
  if device->CreateInputLayout(&input_element_desc[0], len(input_element_desc), vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), &input_layout) != 0 {
    fmt.println("Unable to create input layout for vertex shader")
    return 
  }
  //defer input_layout->Release()

  // create pixel shader
  ps_blob: ^D3D.IBlob
  if DCompile.Compile(raw_data(shaders_hlsl), len(shaders_hlsl), "shaders.hlsl", nil, nil, "ps_main", "ps_5_0", 0, 0, &ps_blob, nil) != 0 {
    //fmt.eprintf("Unable to compile pixel shader. 0x%x\n", cast(windows.ULONG)result)
    fmt.println("Unable to compile pixel shader")
    return 
  }
  //defer ps_blob->Release()
  assert(ps_blob != nil)

  pixel_shader: ^D3D.IPixelShader
  if device->CreatePixelShader(ps_blob->GetBufferPointer(), ps_blob->GetBufferSize(), nil, &pixel_shader) != 0 {
    fmt.println("Unable to create pixel shader")
    return 
  }
  //defer pixel_shader->Release()

  depth_stencil_desc := D3D.DEPTH_STENCIL_DESC{
		DepthEnable    = true,
		DepthWriteMask = .ALL,
		DepthFunc      = .LESS,
	}
	depth_stencil_state: ^D3D.IDepthStencilState
	if device->CreateDepthStencilState(&depth_stencil_desc, &depth_stencil_state) != 0 {
    fmt.println("Unable to create depth stencil state")
    return 
  }
  //defer depth_stencil_state->Release()

  //create constant buffer
  Constants :: struct #align 16 {
    transform: glm.mat4,
    projection: glm.mat4,
  }

  constant_buffer_desc := D3D.BUFFER_DESC {
    ByteWidth = size_of(Constants),
    Usage = .DYNAMIC,
    BindFlags = .CONSTANT_BUFFER,
    CPUAccessFlags = .WRITE,
  }

  constant_buffer: ^D3D.IBuffer
  if device->CreateBuffer(&constant_buffer_desc, nil, &constant_buffer) != 0 {
    fmt.println("Unable to create constant buffer")
    return
  }
  //defer constant_buffer->Release()

  // create vertex buffer
  vertex_buffer_desc := D3D.BUFFER_DESC {
    ByteWidth = size_of(vertex_data),
    Usage = .IMMUTABLE,
    BindFlags = .VERTEX_BUFFER,
  }

  vertex_subsource := D3D.SUBRESOURCE_DATA {
    pSysMem = &vertex_data[0], 
    SysMemPitch = size_of(vertex_data),
  }

  vertex_buffer: ^D3D.IBuffer
  if device->CreateBuffer(&vertex_buffer_desc, &vertex_subsource, &vertex_buffer) != 0 {
    fmt.println("Unable to create vertex buffer")
    return
  }
  //defer vertex_buffer->Release()

  // create index buffer
  index_buffer_desc := D3D.BUFFER_DESC{
		ByteWidth = size_of(index_data),
		Usage     = .IMMUTABLE,
		BindFlags = .INDEX_BUFFER,
	}
	index_buffer: ^D3D.IBuffer
	device->CreateBuffer(&index_buffer_desc, &D3D.SUBRESOURCE_DATA{pSysMem = &index_data[0], SysMemPitch = size_of(index_data)}, &index_buffer)

  // 6 float x 32bit(4 bytes)
  vertex_buffer_stride := u32(6 * 4)
	vertex_buffer_offset := u32(0)

	model_translation := glm.vec3{0.0, 0.0, 4.0}

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

    translate := glm.mat4Translate(model_translation)

    mapped_subresource: D3D.MAPPED_SUBRESOURCE
		device_context->Map(constant_buffer, 0, .WRITE_DISCARD, 0, &mapped_subresource)
		{
			constants := (^Constants)(mapped_subresource.pData)
			constants.transform = translate
			constants.projection = {
				2 * n / w, 0,         0,           0,
				0,         2 * n / h, 0,           0,
				0,         0,         f / (f - n), n * f / (n - f),
				0,         0,         1,           0,
			}
		}
		device_context->Unmap(constant_buffer, 0)

    device_context->ClearRenderTargetView(framebuffer_view, &[4]f32{0.6, 0.2, 0.2, 1})
    device_context->ClearDepthStencilView(depth_buffer_view, .DEPTH, 1, 0)

    device_context->IASetPrimitiveTopology(.TRIANGLELIST)
    device_context->IASetInputLayout(input_layout)
    device_context->IASetVertexBuffers(0, 1, &vertex_buffer, &vertex_buffer_stride, &vertex_buffer_offset)
    device_context->IASetIndexBuffer(index_buffer, .R32_UINT, 0)

    device_context->VSSetShader(vertex_shader, nil, 0)
    device_context->VSSetConstantBuffers(0, 1, &constant_buffer)

    device_context->RSSetViewports(1, &viewport)
    device_context->PSSetShader(pixel_shader, nil, 0)

    device_context->OMSetRenderTargets(1, &framebuffer_view, depth_buffer_view)
    device_context->OMSetDepthStencilState(depth_stencil_state, 0)
    
    device_context->DrawIndexed(len(index_data), 0, 0)

    swapchain->Present(1, 0)
  }
}

vertex_data := [?]f32 {
  0.0, 0.5, -1.0,  1.0, 0.0, 0.0,
  0.45, -0.5, -1.0,  1.0, 0.0, 0.0,
  -0.45, -0.5, -1.0,  1.0, 0.0, 0.0,
}

index_data := [?]u32{
  0, 1, 2,
}


shaders_hlsl := `
cbuffer constants : register(b0) {
	float4x4 transform;
	float4x4 projection;
}
struct vs_in {
	float3 position : POS;
	float3 color    : COL;
};
struct vs_out {
	float4 position : SV_POSITION;
	float4 color    : COL;
};
vs_out vs_main(vs_in input) {
	vs_out output;
	output.position = mul(projection, mul(transform, float4(input.position, 1.0f)));
	//output.position = float4(0,0,0,0);
	output.color = float4(input.color.rgb, 1);
	return output;
}
float4 ps_main(vs_out input) : SV_TARGET {
	return float4(1, 1, 0, 1);
}
`