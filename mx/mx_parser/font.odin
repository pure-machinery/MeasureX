package mx_parser

import "core:os"
import "core:strings";
import "core:mem";
import "core:math";
import "core:fmt";

import "core:image/png";

//import "core:image";
//when ODIN_DEBUG do import "core:fmt";

/*
v2 :: struct {
	x: f32,
	y: f32,
}

table_directory :: struct {
	tag: [4]u8,
	check_sum: u32be,
	offset: u32be,
	table_length: u32be,
}

offset_subtable :: struct {
	scaler_type: u32be,
	num_tables: u16be,
	search_range: u16be,
	entry_selector: u16be,
	range_shift: u16be,
	records: []table_directory,
}


head_table :: struct {
	version: u32be,
	font_revision: f32be,

	checksum_ajdustment: u32be,
	magic_number: u32be,
	
	flags: u16be,
	units_per_em: u16be,
	
	time_created: i64be,
	time_modified: i32be,
	
	x_min: i16be,
	y_min: i16be,
	x_max: i16be,
	y_max: i16be,
	
	mac_style: u16be,
	lowest_rec_ppem: u16be,
	font_direction_hint: i16be,
	index_to_loc_format: i16be,
	glyph_data_format: i16be,
}


platform :: enum u16be {
	UNICODE = 0x0,
	MACINTOSH = 0x1,
	ISO = 0x2,
	WINDOWS = 0x3,
	CUSTOM = 0x4,
}

encoding :: enum u16be {
	UNICODE_1_0 = 0x0,
	UNICODE_1_1 = 0x1,
	IS0_IEC = 0x2,
	UNICODE_2_0_BMP_ONLY = 0x3,
	UNICODE_2_0_FULL = 0x4,
	UNICODE_VARIATION_SEQ = 0x5,
	UNICODE_FULL = 0x6,
}

encoding_subtable :: struct {
	platform_id: platform,
	encoding_id: encoding,
	subtable_offset: u32be,
}

cmap_table :: struct {
	version: u16be,
	table_count: u16be,
	record: []encoding_subtable,
}


cmap_subtable_format_4 :: struct {
	format: u16be,
	length: u16be,
	language: u16be,
	seg_count_x2: u16be,
	search_range: u16be,
	entry_selector: u16be,
	range_shift: u16be,
	reserved_pad: u16be,
	// (Seg count)
	end_code: []u16be,
	// (Seg count)
	start_code: []u16be,
	// (Seg count)
	id_delta: []u16be,
	// (Seg count)
	id_range_offsets: []u16be,
	glyph_id_array: []u16be,
}


hhea_table :: struct {
	major_version: u16be,
	minor_version: u16be,
	ascender: f32be,
	descender: f32be,
	line_gap: f32be,
	advance_width_max: f32be,
	min_left_side_bearing: f32be,
	min_right_side_bearing: f32be,
	x_max_extent: f32be,
	caret_slope_rise: i16be,
	caret_slope_run: i16be,
	caret_offset: i16be,
	reserved_data: i64be, 
	metric_data_format: i16be,
	//
}


glyph_desc :: struct {
	num_of_contours: i16be,
	x_min: i16be,
	y_min: i16be,
	x_max: i16be,
	y_max: i16be,
}

glyph_definition :: struct {
	desc: glyph_desc,

	end_points: []u16be,
	
	instruction_length: u16be,
	instructions: []u8,
	
	data: [dynamic]glyph_outline_point,
}

glyph_outline :: enum u8 {
	ON_CURVE = 0 << 0,
	X_SHORT = 1 << 0,
	Y_SHORT = 2 << 0,
	REPEAT = 3 << 0,
	X_IS_SAME = 4 << 0,
	Y_IS_SAME = 5 << 0,
	_IGNORED = 6 << 0,
	__IGNORED = 7 << 0,
};

glyph_outline_flags :: bit_set [ glyph_outline; u8 ];

glyph_outline_point :: struct 
{
	flags: glyph_outline_flags,

	x: i16be,
	y: i16be,
}

maxp_table :: struct 
{
	minor_version: i16be,
	major_version: i16be,
	glyph_count: u16be,
	max_points: u16be,
	max_contours: u16be,
	max_component_points: u16be,
	max_component_contours: u16be,
	max_zones: u16be,
	max_twillight_points: u16be,
	max_storage: u16be,
	max_function_defs: u16be,
	ma_instruction_defs: u16be,
	max_stack_elements: u16be,
	max_size_of_instructions: u16be,
	max_components_elements: u16be,
	max_component_depth: u16be,
}

font_directory :: struct {
	head: head_table,
	cmap: cmap_table,
	cmap_format: cmap_subtable_format_4,
	loca: u32be,
	glyf: u32be,
	maxp: maxp_table,
}



load_ttf :: proc(filename: string) -> (map[rune][]v2, [dynamic]v2, bool) 
{
	bytes, ok := LoadFileData(filename);
	defer delete(bytes);
	
	if !ok do return {}, {}, false;

	reader := binary_reader { data = bytes };

	font := font_directory {};

	subtable := offset_subtable {
		scaler_type = ReadValue(&reader, u32be),
		num_tables = ReadValue(&reader, u16be),
		search_range = ReadValue(&reader, u16be),
		entry_selector = ReadValue(&reader, u16be),
		range_shift = ReadValue(&reader, u16be),
	};

	subtable.records = ReadArray(&reader, table_directory, cast(int) subtable.num_tables);

	for idx : u16be = 0; idx < subtable.num_tables; idx += 1 {
		record := &subtable.records[idx];
		
		switch record.tag {
			case "head":
				font.head = ReadValueAt(&reader, head_table, cast(u64) record.offset);
			case "cmap":
				cmap := &font.cmap;
				
				{
					ReaderSetTempOffset(&reader, cast(u64) record.offset);
					defer ReaderResetTempOffset(&reader);

					cmap.version = ReadValue(&reader, u16be);
					cmap.table_count = ReadValue(&reader, u16be);
					cmap.record = ReadArray(&reader, encoding_subtable, cast(int) cmap.table_count);
				}

				for r in cmap.record {
					ReaderSetTempOffset(&reader, cast(u64) record.offset);
					defer ReaderResetTempOffset(&reader);

					if r.platform_id == platform.UNICODE {
						temp_offset := reader.offset + cast(u64) r.subtable_offset;
						ReadAdvance(&reader, cast(u64) r.subtable_offset);

						// use ReadArray to read this whole chunk ? 
						// eg. ReadArray(&reader, u16be, 8, true);
						// format = array[0]; etc .. ? 
						format_4 := cmap_subtable_format_4 {
								format = ReadValue(&reader, u16be),
								length = ReadValue(&reader, u16be),
								language = ReadValue(&reader, u16be),
								seg_count_x2 = ReadValue(&reader, u16be),
								search_range = ReadValue(&reader, u16be),
								entry_selector = ReadValue(&reader, u16be),
								range_shift = ReadValue(&reader, u16be),
								reserved_pad = ReadValue(&reader, u16be),
						};
						
						seg_count := cast(int) (format_4.seg_count_x2 / 2);

						format_4.end_code = ReadArray(&reader, u16be, seg_count, true);
						format_4.start_code = ReadArray(&reader, u16be, seg_count, true);
						format_4.id_delta = ReadArray(&reader, u16be, seg_count, true);
						format_4.id_range_offsets = ReadArray(&reader, u16be, seg_count, true);

						
						if diff := temp_offset + cast(u64) format_4.length; diff > reader.offset {
							format_4.glyph_id_array = ReadArray(&reader, u16be, cast(int) (diff / size_of(u16be)));
						}
						
						font.cmap_format = format_4;
					}
				}
			case "loca":
				font.loca = record.offset;
			case "glyf":
				font.glyf = record.offset;
			case "maxp":
				font.maxp = ReadValueAt(&reader, maxp_table, cast(u64) record.offset);
			case:
				continue;
		}
	}

	max_vertices := cast(int) (font.maxp.glyph_count * font.maxp.max_points * 3);

	// Return it from function.
	character_map := make(map[rune][]v2, cast(int) font.maxp.glyph_count);
	character_data := make_dynamic_array_len_cap([dynamic]v2, 0, max_vertices);

	english_alphabet := "ABCDEFGHIJGLMNOPQRSTUVWXYZ";

	glyph_data := make([dynamic]glyph_outline_point, 0, font.maxp.max_points);
	defer delete(glyph_data);

	glyph_desc := glyph_definition {}; 

	for c in english_alphabet {
		glpyh_id, ok := GetGlyphIndex(&font, cast(u16be) c);

		if !ok do continue;
		
		clear(&glyph_data);

		glyph_desc.data = glyph_data;
		// Make the data overwritable for glyph points.
		written := WriteGlyphOutline(&font, &glyph_desc, cast(u32be) glpyh_id, &reader);
		// IDEA(G): Make an asset file that contains the mesh for each glyph. Then load this 
		// file and draw the glyphs correctly.
		character_map[c] = GenerateGlyphMesh(&font, &character_data, glyph_data[:written]);
		array := character_map[c];

		when ODIN_DEBUG {
			fmt.println("Generated data: ", c, "id: ", glpyh_id, "written: ", written);

			for idx := 0; idx < len(array); idx += 3 {
				fmt.println(array[idx], array[idx + 1], array[idx+2]);
			}
		}
	}

	return character_map, character_data, true;
}



GetGlyphIndex :: proc(font: ^font_directory, code_point: u16be) -> (u16be, bool) {
	format := &font.cmap_format;
	seg_count := cast(int) (format.seg_count_x2 / 2);
	index := -1;

	for idx := 0; idx < seg_count; idx += 1 {
		if format.end_code[idx] > code_point {
			index = idx;
			break;
		}
	}

	if index == -1 do return 0, false;

	if start_code := format.start_code[index]; start_code <= code_point {
		id_delta := format.id_delta[index];

		if id_offset := &format.id_range_offsets[index]; id_offset^ != 0 {
			ptr := mem.ptr_offset(id_offset, cast(int) (id_offset^ / 2 + code_point - start_code));

			if ptr^ != 0 { 
				return ptr^ + id_delta, true;
			}
		} else {
			return code_point + id_delta, true;
		}
	}

	return 0, false;
}

GetGlyphOffset :: proc(font: ^font_directory, glyph_index: u32be, reader: ^binary_reader) -> u32be {
	assert(font.loca != 0 && (font.head.index_to_loc_format == 0 || font.head.index_to_loc_format == 1), "Failed to evaluate index to loc format.");

 	// If the index to loc format is 1 then we proceed reading the data as 32 bit integers otherwise we must read it as 16 bit integers!!
	if font.head.index_to_loc_format == 1 {
		offset := font.loca + glyph_index * size_of(u32be);
		base := ReadValueAt(reader, u32be, cast(u64) offset);
		return base;
	} else {
		offset := font.loca + glyph_index * size_of(u16be);
		base := ReadValueAt(reader, u16be, cast(u64) offset);
		return (cast(u32be)base) * 2;
	}
}

WriteGlyphOutline :: proc(font: ^font_directory, glyph: ^glyph_definition, glyph_index: u32be, reader: ^binary_reader) -> int {
	offset := GetGlyphOffset(font, glyph_index, reader);

	ReaderSetTempOffset(reader, cast(u64) (font.glyf + offset));
	defer ReaderResetTempOffset(reader);

	glyph.desc = ReadValue(reader, glyph_desc);
	glyph.end_points = ReadArray(reader, u16be, cast(int) glyph.desc.num_of_contours, true);
	glyph.instruction_length = ReadValue(reader, u16be);
	glyph.instructions = ReadArray(reader, u8, cast(int) glyph.instruction_length, true);

	last_index := glyph.end_points[len(glyph.end_points) - 1] + 1;

	for idx := 0; idx < cast(int) last_index; idx += 1 {
		glyph.data[idx].flags = ReadValue(reader, glyph_outline_flags);

		if glyph.data[idx].flags & { .REPEAT } != {} {
			repeat_count := cast(int) ReadValueCurrent(reader, u8);

			for repeat_idx := 0; repeat_idx < repeat_count; repeat_idx += 1 {
				idx += 1;
				glyph.data[idx].flags = glyph.data[idx - 1].flags;
			}

			ReadAdvance(reader, size_of(glyph_outline_flags));
		}
	}

	current_coord: i16be = 0;
	previous_coord : i16be = 0;

	for idx := 0; idx < cast(int) last_index; idx += 1 {
		is_short := glyph.data[idx].flags & { .X_SHORT } != {};
		is_same := glyph.data[idx].flags & { .X_IS_SAME } != {};

		if is_short {
			current_coord = cast(i16be) ReadValue(reader, u8);
			if !is_same {
				current_coord = -current_coord;
			}
		} else if is_same {
			current_coord = 0;
		} else {
			current_coord = ReadValue(reader, i16be);
		} 

		glyph.data[idx].x = current_coord + previous_coord;
		previous_coord = glyph.data[idx].x;
	}

	current_coord = 0;
	previous_coord = 0;

	for idx := 0; idx < cast(int) last_index; idx += 1 {
		is_short := glyph.data[idx].flags & { .Y_SHORT } != {};
		is_same := glyph.data[idx].flags & { .Y_IS_SAME } != {};

		if is_short {
			current_coord = cast(i16be) ReadValue(reader, u8);
			if !is_same {
				current_coord = -current_coord;
			}
		} else if is_same {
			current_coord = 0;
		} else {
			current_coord = ReadValue(reader, i16be);
		} 

		glyph.data[idx].y = current_coord + previous_coord;
		previous_coord = glyph.data[idx].y;
	}

	return cast(int) last_index;
}


GenerateGlyphMesh :: proc(font: ^font_directory, data: ^[dynamic]v2, outline: []glyph_outline_point) -> []v2 {
	// TODO(G): Generate vertex data as mentioned here:
	// https://medium.com/@evanwallace/easy-scalable-text-rendering-on-the-gpu-c3f4d782c5ac
	start_count := len(data); 

	for idx := 0; idx < len(outline); idx += 1 {
		glyph := outline[idx];
		// Temporary skip on curve points.
		if glyph.flags & { .ON_CURVE } == {} do continue; 
		if idx + 1 != len(outline) && outline[idx + 1].flags & { .ON_CURVE } == {} do continue;

		vt0 := v2 { 0.0, 0.0 };
		vt1 := v2 { cast(f32) glyph.x, cast(f32) glyph.y };
		vt2 := vt0;

		if idx + 1 != len(outline) {
			next_glyph := outline[idx + 1];

			vt2 = v2 { cast(f32) next_glyph.x, cast(f32) next_glyph.y };
		} else {
			vt2 = v2 { cast(f32) outline[0].x, cast(f32) outline[0].y };
		}
		// We might need the last element when idx == len(outline) ? 

		append_elems(data, vt0, vt1, vt2);
	}

	return data[start_count:len(data)];
}

// This will go on the gpu... ?
tesselate_quadratic_bezier :: proc(x0, y0: f32, x1, y1: f32, cpx, cpy: f32, segments : f32 = 4) -> []f32
{
	x : f32 = 0;
	y : f32 = 0;

	array := make([]f32, cast(int) segments * size_of(f32) );

	for idx := 0; idx < cast(int) segments; idx += 1 {
		t : f32 = 1 / segments;

		square := t * t;
		square_sub := 1 - 2 * t + square;

		x = cpx + square_sub * (x0 - cpx) + square * (x1 - cpx);
		y = cpx + square_sub * (x0 - cpx) + square * (x1 - cpx);

		array[idx] = x;
		array[idx + 1] = y;
	}

	return array;
}*/

age_header :: struct {
	glyph_count: u32,
	max_height: f32,
}

age_character :: struct {
	id: rune,
	g: glyph, 
}

// We could generate the UV's right here ?
glyph :: struct {
	min_x: f32,
	min_y: f32,
	max_x: f32,
	max_y: f32,
	x_offset: f32,
	y_offset: f32,
	x_advance: f32,	
}


ParseTTF :: proc(image_data: []u8, glyph_data: []u8) -> (^png.Image, map[rune]glyph, f32, bool)
{
	reader := binary_reader { data = glyph_data }; 

	header := ReadValue(&reader, age_header);

	character_map := make(map[rune]glyph, header.glyph_count);

	array := ReadArray(&reader, age_character, cast(int) header.glyph_count, true);

	for age in array do character_map[age.id] = age.g;

	opt := png.Options { };

	img, err := png.load_from_bytes(image_data[:]);

	if err != nil do return {}, {}, {}, false;

	fmt.println("HEADER: ", header);

	return img, character_map, header.max_height, true;
}