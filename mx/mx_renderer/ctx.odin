package mx_renderer

import "core:image"
import "core:mem"
import "core:mem/virtual"
import "core:fmt"
import "base:runtime"
import "core:slice"

import "../mx_parser"

GREEN :: [4]f32 { 0.0, 1.0, 0.0, 1.0 };
RED :: [4]f32 { 1.0, 0.0, 0.0, 1.0 };
BLUE :: [4]f32 { 0.0, 0.0, 1.0, 1.0 };
BLACK :: [4]f32 { 0.0, 0.0, 0.0, 1.0 };


graphics_context :: struct {
	groups: [max(render_group_kind)] render_group,

	screen_width: i32,
	screen_height: i32,
	
	// Perhaps in future applications this would have to be separated from the graphics context?
	// It should reside only in the asset system - and then the graphics context fetches what it 
	// needs from the asset system? 
	character_map: map[rune]mx_parser.glyph,
	font_image: ^image.Image, 
	max_height: f32,
};


render_group_kind :: enum {
	// Can be used to render fonts, ui, ...
	RECTANGLE,
	OTHER,
}

MAX_TEXUTURES :: 4;



render_buffer :: struct {
	kind: buffer_kind,

	handle: u32,
	size: int,

	data: [dynamic]u8,
	stride: int, 
}

GetBuffer :: proc(group: ^render_group, kind: buffer_kind) -> ^render_buffer {
	assert(kind in group.usage_flags)

	buffer := &group.buffers[kind];

	return buffer;
}

render_group :: struct {
	kind: render_group_kind,
	
	usage_flags: buffer_usage_flags,
	// TODO(G): Get the max textures from the GPU info.
	textures: [max(texture_tag)]texture,

	vertex_attribute_array: u32,

	// In case we want to use a single buffer for multiple things.
	// gpu_vertex_buffer_offset: uint,
	// gpu_index_buffer_offset: uint,

	// CPU side buffers.
	buffers: [len(buffer_kind)] render_buffer,

	// This should contain a mesh instance.
	// Instance cound is within vertex buffer.
	instance_buffer_object: u32, 
	instance_count: u32, 

	shader_program: u32,

	active_texture: u32,
}

render_group_build_config :: struct {
	group_kind: render_group_kind,

	usage_flags: buffer_usage_flags,

	textures: []texture_config,

	shaders: shader_set,

	index_stride_kind: index_kind,

	initial_vertex_count: int,

	is_instanced: bool,
}

shader_kind :: enum {
	VERTEX,
	FRAGMENT,
}

shader_set :: struct {
	vertex_shader_source: cstring,
	fragment_shader_source: cstring,
}

texture :: struct {
	// Generated index in OpenGL.
	id: u32,
	
	width: i32,
	height: i32,

	data: []u8 `fmt:"p"`,
}

texture_tag :: enum {
	FONT,
	BLANK,
	OTHER,
}

texture_config :: struct {
	width: i32,
	height: i32,

	data: []u8 `fmt:"p"`,

	wrapping: texture_wrapping_mode,

	mipmap_levels: u8,

	min_filtering: texture_filtering_mode,
	// For OpenGL can only apply to LINEAR and NEAREST.
	mag_filtering: texture_filtering_mode,

	channel: texture_color_channel,

	tag: texture_tag,
}

texture_wrapping_mode :: enum {
	CLAMP_TO_EDGE,
	CLAMP_TO_BORDER,
	MIRRORED_REPEAT,
	REPEAT,
	MIRROR_CLAMP_TO_EDGE,
}

texture_filtering_mode :: enum {
	NEAREST,
	LINEAR,
	NEAREST_MIPMAP_NEAREST,
	LINEAR_MIPMAP_NEAREST,
	NEAREST_MIPMAP_LINEAR,
	LINEAR_MIPMAP_LINEAR,
}

texture_color_channel :: enum {
	R,
	RG,
	RGB,
	RGBA,
	ALPHA,
	DEPTH,
	STENCIL,
}

index_kind :: enum {
	U32 = size_of(u32),
	U64 = size_of(u64),
}

buffer_kind :: enum {
	VERTEX,
	INDEX,
	SHADER_STORAGE_BUFFER,
}

buffer_usage_flags :: bit_set [ buffer_kind ]; 

render_batch :: struct {
		offset: int,
		instances: int,
}
/*
GenerateVertexData :: proc(rect: rectangle, color: [4]f32, uv: [2][2]f32) -> [4]vertex {
	radius := [4]f32 { 20.0, 5.0, 5.0, 5.0 };
	//radius := [4]f32 {};
	
	data := [4]vertex {
			vertex {
				min = { rect.min_x, rect.min_y },
				max = { rect.max_x, rect.max_y },
				color = color,
				min_uv = uv[0],
				max_uv = uv[1],
				// temp
				radius = radius,
			},
			vertex {
				min = { rect.min_x, rect.min_y },
				max = { rect.max_x, rect.max_y },
				color = color,
				min_uv = uv[0],
				max_uv = uv[1],
				radius = radius,
			},
			vertex {
				min = { rect.min_x, rect.min_y },
				max = { rect.max_x, rect.max_y },
				color = color,
				min_uv = uv[0],
				max_uv = uv[1],
				radius = radius,
			},
			vertex {
				min = { rect.min_x, rect.min_y },
				max = { rect.max_x, rect.max_y },
				color = color,
				min_uv = uv[0],
				max_uv = uv[1],
				radius = radius,
			},
	};

	return data;
}*/

ResetGroupBuffers :: proc(group: ^render_group) {
	vbuffer := GetBuffer(group, .VERTEX);
	ibuffer := GetBuffer(group, .INDEX);

	clear(&vbuffer.data);
	clear(&ibuffer.data);
	group.instance_count = 0;
}


AppendIndices :: proc(group: ^render_group) {
	vbuffer := GetBuffer(group, .VERTEX);
	ibuffer := GetBuffer(group, .INDEX);

 	offset : int = len(vbuffer.data) / vbuffer.stride;
 	data := []u8 {};

	if ibuffer.stride == size_of(u32) {
		offset := cast(u32) offset;
		index_data := [6]u32 { 
			0 + offset, 1 + offset, 2 + offset,
			2 + offset, 0 + offset, 3 + offset,
		};

		data = slice.bytes_from_ptr(&index_data[0], size_of(index_data));
	} else {
		offset := cast(u64) offset;
		index_data := [6]u64 {
			0 + offset, 1 + offset, 2 + offset,
			2 + offset, 0 + offset, 3 + offset,
		};

		data = slice.bytes_from_ptr(&index_data[0], size_of(index_data));
	}

	append(&ibuffer.data, ..data[:]);
}