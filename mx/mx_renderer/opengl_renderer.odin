package mx_renderer


import gl "vendor:OpenGL"

import "core:strings"
import "base:runtime"
import "core:mem"
import "core:mem/virtual"
import "core:fmt"
import "core:math"
import "core:slice"
import "core:unicode/utf8"

import "../mx_parser"
import "../../profiler"

WHITE_PIXEL := [4]u8 { 0xFF, 0xFF, 0xFF, 0xFF };

// TODO(G): Move this into ctx.odin.
InitGraphicsContext :: proc(width, height: i32) -> graphics_context {
	ctx := graphics_context {
		screen_width = width,
		screen_height = height,
	};

	return ctx;
}

// TODO(G): Move this into ctx.odin.
BuildGraphicsContext :: proc(ctx: ^graphics_context) -> bool {

 	cfg := render_group_build_config {
		shaders = shader_set {
				vertex_shader_source = UI_VERTEX_SHADER,
				fragment_shader_source =  UI_FRAGMENT_SHADER,
		},

		textures = { 
			texture_config {
				width = cast(i32) ctx.font_image.width,
				height = cast(i32) ctx.font_image.height,

				data = ctx.font_image.pixels.buf[:],

				min_filtering = .LINEAR,
				mag_filtering = .LINEAR, 

				channel = .RGB,

				wrapping = .CLAMP_TO_EDGE,

				tag = .FONT,
			},
		},

		index_stride_kind = index_kind.U32,

		group_kind = render_group_kind.RECTANGLE,

		initial_vertex_count = 1024,

		usage_flags = { .VERTEX, .INDEX, .SHADER_STORAGE_BUFFER },

		is_instanced = true, 
	};

	if group, ok := BuildRenderGroup(cfg); ok {
		when ODIN_DEBUG do fmt.println("Building group: ", group);
		ctx.groups[cast(int) cfg.group_kind] = group;
	} else {
		when ODIN_DEBUG do fmt.println("Failed to build group: ", cfg);
		return false; 
	}

	return true;
} 

ClearBackgroundColor :: proc(r, g, b, a: f32) {
	gl.ClearColor(r, g, b, a);
	gl.Clear(gl.COLOR_BUFFER_BIT);
}

ResizeViewport :: proc(ctx: ^graphics_context, x, y, width, height: i32) {
	gl.Viewport(0, 0, width, height);
	ctx.screen_width = width;
	ctx.screen_height = height;
}


BuildRenderGroup :: proc(config: render_group_build_config) -> (render_group, bool)  {
	group := render_group {
		usage_flags = config.usage_flags,
	};

	// NOTE(G): Do we want to keep this buffers persistent or should we just use the temporary memory for this. 
	// We flush it to the buffer then copy the content to the GPU and violla we have the CPU side buffer back for 
	// another group to be drawn.
	
	#partial switch config.group_kind {
		case .RECTANGLE:
			if config.usage_flags & { .VERTEX } != {} {
				buffer := GetBuffer(&group, .VERTEX);

				buffer.stride = size_of(vertex);
				if data, err := make_dynamic_array_len_cap([dynamic]u8, 0, config.initial_vertex_count * buffer.stride); err == .None {
					buffer.data = data;
					buffer.size = cap(buffer.data);
				} else {
					fmt.printf("Failed to initialize vertex buffer of size: %d.", config.initial_vertex_count * buffer.stride);
					return {}, false;
				}

				gl.GenVertexArrays(1, &group.vertex_attribute_array);
				gl.BindVertexArray(group.vertex_attribute_array);

				gl.GenBuffers(1, cast([^]u32) &buffer.handle);
				gl.BindBuffer(gl.ARRAY_BUFFER, buffer.handle);
				gl.BufferData(gl.ARRAY_BUFFER, cap(buffer.data), raw_data(buffer.data), gl.DYNAMIC_DRAW);

				buffer_size: i32;
				gl.GetBufferParameteriv(gl.ARRAY_BUFFER, gl.BUFFER_SIZE, &buffer_size);

				fmt.println("Created buffer of size: ", buffer_size, "wanted: ", cap(buffer.data));

				BuildVertexAttributes(vertex, true);

				gl.BindBuffer(gl.ARRAY_BUFFER, 0);
			}

			if config.usage_flags & { .INDEX } != {} {
				buffer := GetBuffer(&group, .INDEX);

				buffer.stride = cast(int) config.index_stride_kind;
				size_to_allocate := buffer.stride * config.initial_vertex_count * 6; 
				
				if config.is_instanced {
					size_to_allocate = buffer.stride * 6;
				}

				if data, err := make_dynamic_array_len_cap([dynamic]u8, 0, size_to_allocate); err == .None {
					buffer.data = data;
					buffer.size = cap(buffer.data);
				} else {
					fmt.println("Failed to initialize index buffer.");
					return {}, false;
				}

				gl.GenBuffers(1, &buffer.handle);
				gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, buffer.handle);
				gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, cap(buffer.data), raw_data(buffer.data), gl.DYNAMIC_DRAW);

				buffer_size: i32;
				gl.GetBufferParameteriv(gl.ELEMENT_ARRAY_BUFFER, gl.BUFFER_SIZE, &buffer_size);

				fmt.println("Created index buffer of size: ", buffer_size, "wanted: ", cap(buffer.data));

				AppendIndices(&group);

				gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0);
			}

			if config.usage_flags & { .SHADER_STORAGE_BUFFER } != {} {
				buffer := GetBuffer(&group, .SHADER_STORAGE_BUFFER);

				// If needed I can supply only the corners of the rectangle and then do the 
				// computaton in the fragment shader.
				buffer.stride = size_of(rectangle);
				initial_count := 1024;
				if data, err := make_dynamic_array_len_cap([dynamic]u8, 0, initial_count * buffer.stride); err == .None {
					buffer.data = data;
					buffer.size = cap(buffer.data);
				} else {
					fmt.printf("Failed to initialize shader storage buffer of size: %d.", initial_count * buffer.stride);
					return {}, false;
				}


				gl.GenBuffers(1, &buffer.handle);
				gl.BindBuffer(gl.SHADER_STORAGE_BUFFER, buffer.handle);
				gl.BufferData(gl.SHADER_STORAGE_BUFFER, cap(buffer.data), raw_data(buffer.data),  gl.DYNAMIC_DRAW);
				// NOTE(G): Binding must be the same as in the shader!
				binding : u32 = 1;
				gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, binding, buffer.handle);
				gl.BindBuffer(gl.SHADER_STORAGE_BUFFER, 0);
			}
		case:
			unimplemented();
	}

	for idx := 0; idx < len(config.textures); idx += 1 {
		tx := config.textures[idx];

		fmt.println("Building texture: ", tx);

		group.textures[tx.tag] = BuildTexture(tx);
	}

	set := config.shaders;

	if len(set.vertex_shader_source) == 0 || len(set.fragment_shader_source) == 0 do return group, false;

	vertex_id := BuildShader(&group, &set.vertex_shader_source, .VERTEX);
	fragment_id := BuildShader(&group, &set.fragment_shader_source, .FRAGMENT);

	if vertex_id == 0 || fragment_id == 0 do return {}, false;

	defer { 
		gl.DeleteShader(vertex_id);
		gl.DeleteShader(fragment_id);
	};

	group.shader_program = gl.CreateProgram();

	gl.AttachShader(group.shader_program, vertex_id);
	gl.AttachShader(group.shader_program, fragment_id);
	gl.LinkProgram(group.shader_program);

	return group, true;
}



BuildShader :: proc(group: ^render_group, source: ^cstring, kind: shader_kind) -> u32 {
	shader : u32 = 0; 
	switch kind {
		case .VERTEX:  
			shader = gl.CreateShader(gl.VERTEX_SHADER);
		case .FRAGMENT:
			shader = gl.CreateShader(gl.FRAGMENT_SHADER);
	}

	gl.ShaderSource(shader, 1, cast([^]cstring) source, nil);
	gl.CompileShader(shader);

	when ODIN_DEBUG {
		success : i32 = 0;
		gl.GetShaderiv(shader, gl.COMPILE_STATUS, &success);
		if success == 0 { 
			info_log := [512]u8 {};
			gl.GetShaderInfoLog(shader, len(info_log) , nil, &info_log[0]);
			fmt.println(string(info_log[:]), #file, #line);
			return 0;
		}
	}

	return shader;
}

/*
InitShaderStorageBuffer :: proc(ctx: ^graphics_context, size: int) {
	shader_storage_object : u32 = 0;

	gl.GenBuffers(1, cast([^]u32) &shader_storage_object);
	gl.BindBuffer(gl.SHADER_STORAGE_BUFFER, shader_storage_object);
	gl.BufferData(gl.SHADER_STORAGE_BUFFER, cap(group.vertex_buffer), raw_data(group.vertex_buffer), gl.DYNAMIC_DRAW);
	gl.BindBuffer(0);
}
*/

PushRectangle :: proc(ctx: ^graphics_context, rect, clip: rectangle, color, uv, border_color, border_edges, shadow_edges, radius: [4]f32) {
	group := &ctx.groups[cast(int) render_group_kind.RECTANGLE];

	group.instance_count += 1;
	
	vertices := vertex {
				min = { rect.min_x, rect.min_y },
				max = { rect.max_x, rect.max_y },
				color = color,
				min_uv = uv.xy,
				max_uv = uv.zw,
				min_clip = { clip.min_x, clip.min_y },
				max_clip = { clip.max_x, clip.max_y },
				border_color = border_color,
				border_edges = border_edges,
				radius = radius,
	};

	data := slice.bytes_from_ptr(&vertices, size_of(vertices));

	buffer := GetBuffer(group, .VERTEX);

	append(&buffer.data, ..data[:]);
}

PushClipRectangle :: proc(ctx: ^graphics_context, rect: rectangle) {
	
}

// TODO(G): Replace this with shader (pixel) borders.
PushRectangleBorder :: proc(ctx: ^graphics_context, rect: rectangle, color: [4]f32, thickness: f32) {
	group := &ctx.groups[cast(int) render_group_kind.RECTANGLE];

	left_border := rectangle { 
		min_x = rect.min_x, 
		min_y = rect.min_y,
		max_x = rect.min_x + thickness,
		max_y = rect.max_y,
	};

	PushRectangle(ctx, left_border, {}, color, {}, {}, {}, {}, {});

	right_border := rectangle { 
		min_x = rect.max_x - thickness, 
		min_y = rect.min_y,
		max_x = rect.max_x,
		max_y = rect.max_y,
	};

	PushRectangle(ctx, right_border, {}, color, {}, {}, {}, {}, {});

	top_border := rectangle { 
		min_x = rect.min_x + thickness, 
		min_y = rect.min_y,
		max_x = rect.max_x - thickness,
		max_y = rect.min_y + thickness,
	};

	PushRectangle(ctx, top_border, {}, color, {}, {}, {}, {}, {});

	bottom_border := rectangle { 
		min_x = rect.min_x + thickness, 
		min_y = rect.max_y - thickness,
		max_x = rect.max_x - thickness,
		max_y = rect.max_y,
	};

	PushRectangle(ctx, bottom_border, {}, color, {}, {}, {}, {}, {});
}

GetCharacterWidth :: proc(ctx: ^graphics_context, ch: rune, font_size: f32) -> f32 {
	character := ctx.character_map[ch];

	scale := font_size / ctx.max_height;
	
	return character.x_advance * scale;
}

GetTextWidth :: proc(ctx: ^graphics_context, text: string, font_size: f32) -> f32 {
	//profiler.BeginRecordEntry(#procedure);
	//defer profiler.EndRecordEntry();

	length : f32 = 0;

	for c, idx in text {

		character := ctx.character_map[c];

		if c == ' ' {
			length += 0.25 * font_size;
			continue;
		}

		if idx == len(text) - 1 {
			length += character.x_offset + character.max_x - character.min_x;
		} else {
			// x_offset test.
			//length += character.x_offset + character.x_advance;
			length += character.x_advance;
		}
	}

	scale := font_size / ctx.max_height;
	
	return length * scale;
}


// This should be fixed imo. 
GetTextHeight :: proc(ctx: ^graphics_context, text: string, font_size: f32) -> f32 {
	max_upper : f32 = 0.0;
	max_lower : f32 = 0.0;

	height : f32 = 0.0;

	for c in text {
		character := ctx.character_map[c];

		// The Y-Axis is in reverse. The y_offset is negative because the y axis goes downwards
		// hence that the upper bound is in the negative value range.
		max_upper = min(max_upper, character.y_offset);
		max_lower = max(max_lower, character.max_y - character.min_y + character.y_offset);
	}

	scale := font_size / ctx.max_height;

	return (abs(max_upper) + max_lower)	 * scale;
}


STRING_JUSTIFICATION_TABLE := [3]f32 { -1.0, -0.5, 1.0 };

string_justify_kind :: enum {
	LEFT = 0,
	MIDDLE = 1,
	RIGHT = 2,
}

string_attributes :: struct {
	text: string,
	justify: string_justify_kind,
	font_size: f32, 
}

PushString :: proc(ctx: ^graphics_context, rect, clipping: rectangle, color: [4]f32 = { 1.0, 1.0, 1.0, 1.0 } , using attribs: string_attributes) 
{
	x := (rect.max_x - rect.min_x) * 0.5 + rect.min_x;
	y := (rect.max_y - rect.min_y) * 0.5 + rect.min_y;

	group := &ctx.groups[cast(int) render_group_kind.RECTANGLE];

	scale := font_size / ctx.max_height;

	// This is called twice once in the UI code and here? 
	// See if one can be removed.
	text_width := GetTextWidth(ctx, text, font_size);
	text_height := GetTextHeight(ctx, text, font_size);
	
	previous_x : f32 = x + text_width * STRING_JUSTIFICATION_TABLE[cast(int) justify];
	previous_y : f32 = y + text_height * 0.5;
	/*
	switch justify {
		case .LEFT:
			previous_x = x - text_width * 0.5;
		case .RIGHT:
			previous_x = x - text_width * 0.5;
		case .MIDDLE:
			previous_x = x - text_width * 0.5;
	}
	*/

	width_inv := 1.0 / cast(f32) ctx.font_image.width;
	height_inv := 1.0 / cast(f32) ctx.font_image.height;

	for c, idx in text {
		tglyph := ctx.character_map[c];

		if c == ' ' {
			previous_x += 0.25 * font_size;
			continue; 
		}

		glyph_width := tglyph.max_x - tglyph.min_x;
		glyph_height := tglyph.max_y - tglyph.min_y;
		
		// TODO(G): Generate these guys directly from the font texture
		// and then just multiply it by scale.
		min_x := previous_x + tglyph.x_offset * scale;
		min_y := previous_y + tglyph.y_offset * scale;
		max_x := min_x + glyph_width * scale;
		max_y := min_y + glyph_height * scale;

		//if idx == 0 do min_x = previous_x;

		bounding_box := rectangle {
			min_x,
			min_y,
			max_x,
			max_y,
		};

		min_u := (tglyph.min_x) * width_inv;
		min_v := (tglyph.min_y) * height_inv;
		max_u := (tglyph.max_x) * width_inv;
		max_v := (tglyph.max_y) * height_inv;

		// Get the UV's of the texture.
		uv := [4]f32 { min_u, min_v, max_u, max_v };

		PushRectangle(ctx, bounding_box, clipping, color, uv, {}, {}, {}, {});

		previous_x += tglyph.x_advance * scale; 	
	}
}

PushCharacter :: proc(ctx: ^graphics_context, x: f32, y: f32, color: [4]f32 = { 1.0, 1.0, 1.0, 1.0 } , char: rune, font_size: f32) 
{
	group := &ctx.groups[cast(int) render_group_kind.RECTANGLE];

	scale := font_size / ctx.max_height;

	width_inv := 1.0 / cast(f32) ctx.font_image.width;
	height_inv := 1.0 / cast(f32) ctx.font_image.height;

	tglyph := ctx.character_map[char];

	glyph_width := tglyph.max_x - tglyph.min_x;
	glyph_height := tglyph.max_y - tglyph.min_y;

	min_x := x + tglyph.x_offset * scale;
	min_y := y + tglyph.y_offset * scale;
	max_x := min_x + glyph_width * scale;
	max_y := min_y + glyph_height * scale;

	bounding_box := rectangle {
		min_x,
		min_y,
		max_x,
		max_y,
	};

	min_u := (tglyph.min_x) * width_inv;
	min_v := (tglyph.min_y) * height_inv;
	max_u := (tglyph.max_x) * width_inv;
	max_v := (tglyph.max_y) * height_inv;

	// Get the UV's of the texture.
	uv := [4]f32 { min_u, min_v, max_u, max_v };

	PushRectangle(ctx, bounding_box, {}, color, uv, {}, {}, {}, {});	
}

// Can go to the renderer ?
DrawUI :: proc(ctx: ^graphics_context, kind: render_group_kind) {
	group := &ctx.groups[kind];

	vbuffer := GetBuffer(group, .VERTEX);
	ibuffer := GetBuffer(group, .INDEX);

	// TODO(G): don't rebuild the buffer but reset the memory offset to 0 and push a draw call before reseting.
	if cap(vbuffer.data) > vbuffer.size {
		RebuildBuffers(group);
	} else { 
		UpdateBuffers(group);
	}

	gl.UseProgram(group.shader_program);
	defer gl.UseProgram(group.shader_program);

	resolution_pos := gl.GetUniformLocation(group.shader_program, "resolution");
	gl.Uniform2f(resolution_pos, cast(f32) ctx.screen_width, cast(f32) ctx.screen_height);

	gl.BindTexture(gl.TEXTURE_2D, group.textures[cast(int) texture_tag.FONT].id);
	defer gl.BindTexture(gl.TEXTURE_2D, 0);	
	
	gl.BindVertexArray(group.vertex_attribute_array);
	defer gl.BindVertexArray(0);

	gl.Enable(gl.BLEND);
	defer gl.Disable(gl.BLEND);

	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

	// Instance count will be per batch! so we can do scissors.
	/*
	// Step 1. - A batch will be a slice into the vertex buffer.
	// Step 2. - A batch will hold the flag if it needs to be scissored.
	// Step 3. - Bind the buffer that each batch holds. 
	// TODO(G): Ask around if this is possible with OpenGL 3.3 and with instancing as well.
	// glBindBufferRange (only for uniform buffers ?)
	*/

	gl.DrawElementsInstanced(
		gl.TRIANGLES, 
		cast(i32) (len(ibuffer.data) / ibuffer.stride), 
		gl.UNSIGNED_INT, 
		raw_data(ibuffer.data[:len(ibuffer.data)]), 
		cast(i32) group.instance_count,
	);

	// We don't clear the index buffer since it's set only once upon creation. 
	clear(&vbuffer.data);
	group.instance_count = 0;
}

// BeginFrame -> initializes the buffer and resets it.
// Push primitives.
// EndFrame -> initiates a draw call with the filled buffer.

// What should happen if we fail to map the buffer?
// Why can this fail?
UpdateBuffers :: proc(group: ^render_group) {
	if group.usage_flags & { .VERTEX } != {} {
		vbuffer := GetBuffer(group, .VERTEX);

		gl.BindBuffer(gl.ARRAY_BUFFER, vbuffer.handle);
		
		if data := gl.MapBuffer(gl.ARRAY_BUFFER, gl.WRITE_ONLY); data != nil {
			mem.copy(data, raw_data(vbuffer.data), len(vbuffer.data));
			gl.UnmapBuffer(gl.ARRAY_BUFFER);			
		}

		gl.BindBuffer(gl.ARRAY_BUFFER, 0);
	} 

	if group.usage_flags & { .INDEX } != {} {
		ibuffer := GetBuffer(group, .INDEX);

		gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibuffer.handle);

		if data := gl.MapBuffer(gl.ELEMENT_ARRAY_BUFFER, gl.WRITE_ONLY); data != nil {
			mem.copy(data, raw_data(ibuffer.data), len(ibuffer.data));
			gl.UnmapBuffer(gl.ELEMENT_ARRAY_BUFFER);
		}

		gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0);
	}
}

RebuildBuffers :: proc(group: ^render_group, location := #caller_location) {
	vbuffer := GetBuffer(group, .VERTEX);
	ibuffer := GetBuffer(group, .INDEX);

	fmt.printf("Calling rebuild: %s VB (%d/%d) IB (%d/%d) \n", location, 
		len(vbuffer.data), cap(vbuffer.data),
		len(ibuffer.data), cap(ibuffer.data) );

	if group.usage_flags & { .VERTEX } != {} {
		gl.BindBuffer(gl.ARRAY_BUFFER, vbuffer.handle);
		gl.BufferData(gl.ARRAY_BUFFER, cap(vbuffer.data), raw_data(vbuffer.data), gl.DYNAMIC_DRAW);
		gl.BindBuffer(gl.ARRAY_BUFFER, 0);

		vbuffer.size = cap(vbuffer.data);
	}

	if group.usage_flags & { .INDEX } != {} {
		gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibuffer.handle);
		gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, cap(ibuffer.data), raw_data(ibuffer.data), gl.DYNAMIC_DRAW);
		gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0);

		ibuffer.size = cap(ibuffer.data);
	}
}


BuildVertexAttributes :: proc(vertex_type: typeid, is_instanced : bool = false)
{
    vertex_base_type := runtime.type_info_base(type_info_of(vertex_type));
    vertex_type_info := vertex_base_type.variant.(runtime.Type_Info_Struct);
    
    fields := vertex_type_info.field_count; // len(vertex_type_info.types);
    stride := cast(i32) vertex_base_type.size;

    for field_idx : u32 = 0; field_idx < cast(u32) fields; field_idx += 1 {
    	variant := vertex_type_info.types[field_idx].variant;
    	field_offset := vertex_type_info.offsets[field_idx];

		when ODIN_DEBUG {
			fmt.println("Adding element: ", variant, field_idx);
		}

    	#partial switch _ in variant {
    		case runtime.Type_Info_Array:
    			array_info := variant.(runtime.Type_Info_Array);
    			attribute_element : u32 = 0;

    			#partial switch _ in array_info.elem.variant {
    				case runtime.Type_Info_Float: attribute_element = gl.FLOAT;
				    case runtime.Type_Info_Integer:  attribute_element = gl.INT;
		        }

				gl.VertexAttribPointer(
					field_idx,
					cast(i32) array_info.count,
					attribute_element,
					gl.FALSE,
					stride,
					field_offset,
				);
    		case runtime.Type_Info_Float:
		        gl.VertexAttribPointer(
		            field_idx,
		            1,
		            gl.FLOAT,
		            gl.FALSE,
		            stride,
		            field_offset,
		        );
		    case runtime.Type_Info_Integer:
		        gl.VertexAttribPointer(
		            field_idx,
		            1,
		            gl.INT,
		            gl.FALSE,
		            stride,
		            field_offset,
		        );	
		    case:
		    	unimplemented();	    	
    	}

        gl.EnableVertexAttribArray(field_idx);
        if is_instanced do gl.VertexAttribDivisor(field_idx, 1);
    }

    gl.BindVertexArray(0);
}


BuildTexture :: proc(cfg: texture_config) -> texture {
	assert(len(cfg.data) != 0, "No data found for a given texture.");

	result := texture {
		width = cfg.width,
		height = cfg.height, 

		data = cfg.data,
	};

	gl.GenTextures(1, &result.id);
	gl.BindTexture(gl.TEXTURE_2D, result.id);
	
	//gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1);

	switch cfg.channel {
		case .R:
			gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RED, result.width, result.height, 0, gl.RED, gl.UNSIGNED_BYTE, raw_data(result.data));
		case .RG:
			gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RG, result.width, result.height, 0, gl.RG, gl.UNSIGNED_BYTE, raw_data(result.data));
		case .RGB:
			gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB, result.width, result.height, 0, gl.RGB, gl.UNSIGNED_BYTE, raw_data(result.data));
		case .RGBA:
			gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, result.width, result.height, 0, gl.RGBA, gl.UNSIGNED_BYTE, raw_data(result.data));
		case .ALPHA:
			gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RED, result.width, result.height, 0, gl.RED, gl.UNSIGNED_BYTE, raw_data(result.data));
		case .DEPTH:
			gl.TexImage2D(gl.TEXTURE_2D, 0, gl.DEPTH_COMPONENT, result.width, result.height, 0, gl.DEPTH_COMPONENT, gl.UNSIGNED_BYTE, raw_data(result.data));
		case .STENCIL:
			gl.TexImage2D(gl.TEXTURE_2D, 0, gl.DEPTH_STENCIL, result.width, result.height, 0, gl.DEPTH_STENCIL, gl.UNSIGNED_BYTE, raw_data(result.data));
	}

	switch cfg.wrapping {
		case .CLAMP_TO_EDGE:
			gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
			gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
		case .CLAMP_TO_BORDER:
			gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_BORDER);
			gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_BORDER);
		case .MIRRORED_REPEAT:
			gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.MIRRORED_REPEAT);
			gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.MIRRORED_REPEAT);
		case .REPEAT:
			gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
			gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
		case .MIRROR_CLAMP_TO_EDGE:
			gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.MIRROR_CLAMP_TO_EDGE);
			gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.MIRROR_CLAMP_TO_EDGE);
	}

	switch cfg.min_filtering {
		case .LINEAR:
			gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
		case .NEAREST:
			gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
		case .NEAREST_MIPMAP_NEAREST:
			gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST_MIPMAP_NEAREST);
		case .LINEAR_MIPMAP_NEAREST:
			gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_NEAREST);	
		case .NEAREST_MIPMAP_LINEAR:
			gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST_MIPMAP_LINEAR);
		case .LINEAR_MIPMAP_LINEAR:
			gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
	}
	
	#partial switch cfg.mag_filtering {
		case .LINEAR: 
			gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
		case: 
			gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
	}

	if cfg.mipmap_levels > 0 do gl.GenerateMipmap(gl.TEXTURE_2D);

	gl.BindTexture(gl.TEXTURE_2D, 0);


	return result;
}


BeginScissors :: proc(ctx: ^graphics_context, rect: rectangle) {
	gl.Enable(gl.SCISSOR_TEST);
	gl.Scissor(cast(i32) rect.min_x, ctx.screen_height - cast(i32) (rect.max_y - rect.min_y) - cast(i32) rect.min_y, cast(i32) (rect.max_x - rect.min_x), cast(i32) (rect.max_y - rect.min_y));
}

EndScissors :: proc() {
	gl.Disable(gl.SCISSOR_TEST);
}