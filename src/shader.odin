package dx11

import "core:fmt"
import libc "core:c/libc"
import D3D "vendor:directx/d3d11"
import DXGI "vendor:directx/dxgi"
import DCompile "vendor:directx/d3d_compiler"
import glm "core:math/linalg/glsl"
import os "core:os"
import mem "core:mem"

RenderMaterial :: struct {
  shader: ^Shader,
}

Shader :: struct {
  input_layout: ^D3D.IInputLayout,
  vertex_shader: ^D3D.IVertexShader,
  pixel_shader: ^D3D.IPixelShader,
}

create_shader :: proc(device: ^D3D.IDevice, shader_path: cstring, shader: ^Shader) -> bool {
  //fmt.printf("Attempting to open file {} in dir {}\n", string(shader_path), os.get_current_directory())

  f, err := os.open(string(shader_path))
  if err != os.ERROR_NONE {
    fmt.eprintf("Unable to open file. code: {}", err)
    return false
  }
  defer os.close(f)

  buffer := make([]byte, 1 * mem.Kilobyte)
  defer delete(buffer)

  n2, err2 := os.read(f, buffer)
  if err2 != os.ERROR_NONE {
    fmt.eprintf("Unable to read. code: {}", err2)
    return false
  }

  n := uint(n2)

  // create vertex shader
  vs_blob: ^D3D.IBlob
  if res := DCompile.Compile(raw_data(buffer), n, shader_path, nil, nil, "vs_main", "vs_5_0", 0, 0, &vs_blob, nil); res != 0 {
    fmt.eprintf("Unable to compile vertex shader. code: 0x{0:x}", res)
    return false
  }
  //defer vs_blob->Release()

  vshader: ^D3D.IVertexShader
  if res := device->CreateVertexShader(vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), nil, &vshader); res != 0 {
    fmt.eprintf("Unable to create vertex shader. code: 0x{0:x}", res)
    return false
  }

  // create pixel shader
  ps_blob: ^D3D.IBlob
  if res := DCompile.Compile(raw_data(buffer), n, shader_path, nil, nil, "ps_main", "ps_5_0", 0, 0, &ps_blob, nil); res != 0 {
    fmt.eprintf("Unable to compile pixel shader. code: 0x{0:x}", res)
    return false
  }
  //defer ps_blob->Release()
  assert(ps_blob != nil)

  pshader: ^D3D.IPixelShader
  if res := device->CreatePixelShader(ps_blob->GetBufferPointer(), ps_blob->GetBufferSize(), nil, &pshader); res != 0 {
    fmt.eprintf("Unable to create pixel shader. code: 0x{0:x}", res)
    return false
  }

  input_element_desc := [?]D3D.INPUT_ELEMENT_DESC {
    {"POS", 0, .R32G32B32_FLOAT, 0, 0,                          .VERTEX_DATA, 0},
    {"COL", 0, .R32G32B32_FLOAT, 0, D3D.APPEND_ALIGNED_ELEMENT, .VERTEX_DATA, 0},
  }

  input_layout: ^D3D.IInputLayout
  if res := device->CreateInputLayout(&input_element_desc[0], len(input_element_desc), vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), &input_layout); res != 0 {
    fmt.eprintf("Unable to create input layout for vertex shader. code: 0x{0:x}", res)
    return false
  }

  shader^ = Shader {
    input_layout = input_layout,
    vertex_shader = vshader,
    pixel_shader = pshader,
  }

  return true
}

release_shader :: proc(shader: ^Shader) {
  shader.input_layout->Release()
  shader.vertex_shader->Release()
  shader.pixel_shader->Release()
}