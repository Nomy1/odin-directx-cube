package dx11

import "core:fmt"
import libc "core:c/libc"
import D3D "vendor:directx/d3d11"
import DXGI "vendor:directx/dxgi"
import glm "core:math/linalg/glsl"
import os "core:os"
import mem "core:mem"

Mesh :: struct {
  vertex_buffer: ^D3D.IBuffer,
  index_buffer: ^D3D.IBuffer,
  const_vp_buffer: ^D3D.IBuffer,
  material: RenderMaterial,
  vertices: []glm.vec3,
  position: glm.vec3,
  indices: []u32,
}

Const_VP :: struct #align 16 {
  transform: glm.mat4,
  projection: glm.mat4,
}

create_mesh :: proc(device: ^D3D.IDevice, shader: ^Shader, verts: []glm.vec3, indices: []u32, pos: glm.vec3, out_mesh: ^Mesh) -> bool {
  // create vertex buffer
  vertex_buffer_desc := D3D.BUFFER_DESC {
    ByteWidth = size_of_slice(glm.vec3, verts),
    Usage = .IMMUTABLE,
    BindFlags = .VERTEX_BUFFER,
  }

  vertex_subsource := D3D.SUBRESOURCE_DATA {
    pSysMem = &verts[0], 
    SysMemPitch = size_of(glm.vec3),
  }

  vertex_buffer: ^D3D.IBuffer
  if res := device->CreateBuffer(&vertex_buffer_desc, &vertex_subsource, &vertex_buffer); res != 0 {
    fmt.eprintf("Unable to create vertex buffer. code: 0x{0:x}", res)
    return false
  }

  // create index buffer
  index_buffer_subres := D3D.SUBRESOURCE_DATA {
    pSysMem = &indices[0],
    SysMemPitch = size_of_slice(u32, indices),
  }

  index_buffer_desc := D3D.BUFFER_DESC {
		ByteWidth = size_of_slice(u32, indices),
		Usage     = .IMMUTABLE,
		BindFlags = .INDEX_BUFFER,
	}
  
	index_buffer: ^D3D.IBuffer
	if res := device->CreateBuffer(&index_buffer_desc, &index_buffer_subres, &index_buffer); res != 0 {
    fmt.eprintf("Unable to create index buffer. code: 0x{0:x}", res)
    return false
  }

  constant_buffer_desc := D3D.BUFFER_DESC {
    ByteWidth = size_of(Const_VP),
    Usage = .DYNAMIC,
    BindFlags = .CONSTANT_BUFFER,
    CPUAccessFlags = .WRITE,
  }

  constant_buffer: ^D3D.IBuffer
  if res := device->CreateBuffer(&constant_buffer_desc, nil, &constant_buffer); res != 0 {
    fmt.eprintf("Unable to create constant buffer. code: 0x{0:x}", res)
    return false
  }

  out_mesh^ = Mesh {
    position = pos,
    vertices = verts,
    indices = indices,
    vertex_buffer = vertex_buffer,
    index_buffer = index_buffer,
    const_vp_buffer = constant_buffer,
    material = RenderMaterial{shader},
  }

  return true
}

release_mesh :: proc(mesh: ^Mesh) {
  mesh.vertex_buffer->Release()
  mesh.index_buffer->Release()
  mesh.const_vp_buffer->Release()
}