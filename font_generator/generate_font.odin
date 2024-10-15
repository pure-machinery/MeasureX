package convert


import "core:os"
import "core:strings"
import "core:fmt"
import "core:strconv"
import "core:mem";
import "base:runtime"

import tty "vendor:stb/truetype"
import img "vendor:stb/image"

age_header :: struct {
	glyph_count: u32,
	max_height: f32,
}

glyph :: struct {
	charater: rune,

	min_x: f32,
	min_y: f32,
	max_x: f32,
	max_y: f32,
	x_offset: f32,
	y_offset: f32,
	x_advance: f32,	
}


main :: proc() {
	using tty;
	using img;
	
	context.allocator = context.temp_allocator;

	// Append the textures in use.
	text := #load("Roboto-Regular.ttf");
	icons := #load("icons.ttf");

	text_characters := "qwertyuiopasdfghjklzxcvbnm1234567890-=+,.";
	icon_characters := []rune { 0xe800, 0xe801, 0xe802, 0xe803 , 0xe804 };
	
	
	text_fontinfo := fontinfo {};
	icon_fontinfo := fontinfo {};

	pack_ctx := pack_context {};

	if result := InitFont(&text_fontinfo, raw_data(text), 0); result == false {
		fmt.println("Failed to initialize text font.", result);
		return; 
	}

	fmt.println("Text font: ", text_fontinfo);

	if result := InitFont(&icon_fontinfo, raw_data(icons), 0); result == false {
		fmt.println("Failed to initialize icons font.");
		return;
	}

	fmt.println("Icon font: ", icon_fontinfo);

	img_width : i32 = 1024 // 512;
	img_height : i32 = 512 // 256;
	line_height : f32 = 64;

	ascent : i32 = 0;
	descent : i32 = 0;
	line_gap : i32 = 0;

	SCALE : f32 : 48.0;

	GetFontVMetrics(&text_fontinfo, &ascent, &descent, &line_gap);
	//scale := ScaleForPixelHeight(&text_fontinfo, SCALE);
	scale := SCALE;
	STRIDE_IN_BYTES :: 4

	fmt.println(ascent, descent, line_gap);
	// Image buffer.
	pixels := make([]u8, img_width * img_height, context.temp_allocator);

	result := PackBegin(&pack_ctx, raw_data(pixels), img_width, img_height, 0, 1, nil); 
	defer PackEnd(&pack_ctx);

	assert(result == 1, "Failed to begin pack.")

	PackSetSkipMissingCodepoints(&pack_ctx, true);
//	PackSetOversampling(&pack_ctx, 2, 2);

	fmt.println(pack_ctx);

	first_ascii : i32 = 33;
	last_ascii : i32 = 126; 

	packed_text := make([]packedchar, last_ascii - first_ascii, context.temp_allocator);

	if result := PackFontRange(&pack_ctx, raw_data(text), 0, scale, first_ascii, last_ascii - first_ascii, &packed_text[0]); result == 0 {
		fmt.println("Failed to pack text font range.", result);
		return;
	}

	packed_icons := make([]packedchar, len(icon_characters), context.temp_allocator);
	GetFontVMetrics(&icon_fontinfo, &ascent, &descent, &line_gap);
	//scale = ScaleForPixelHeight(&icon_fontinfo, SCALE);

	if result := PackFontRange(&pack_ctx, raw_data(icons), 0, scale, cast(i32) icon_characters[0], cast(i32) len(icon_characters), &packed_icons[0]); result == 0 {
		fmt.println("Failed to pack icon font range.", result);
		return;
	}
	

	// Only generate 1 pixel channel bitmap hooray. How do I render this stuff ???
	CHANNELS :: 1
	
	// White pixel.
	pixels[0] = 0xFF;

	if result := write_png("asset.png", img_width, img_height, CHANNELS, raw_data(pixels), 0); result == 0 {
		fmt.println("Failed to write the png.");
		return;
	}


	fd, err := os.open("asset", os.O_CREATE | os.O_WRONLY | os.O_TRUNC, os.S_IRWXU);

 	if err != os.ERROR_NONE {
 		fmt.println("Failed to create file.", err);
 		return;
 	}

 	defer os.close(fd);

 	glyphs := make_dynamic_array_len_cap([dynamic]glyph, 0, len(packed_icons) + len(packed_text));

 	for packed, index in &packed_text {
 		g := PackedToGlyph(packed, cast(rune) (cast(i32) index + first_ascii));

		append(&glyphs, g);
 	}

 	for packed, index in &packed_icons {
 		g := PackedToGlyph(packed, cast(rune) icon_characters[index]);
		append(&glyphs, g);
 	}

 	header := age_header {};

	header.max_height = scale;
	header.glyph_count = cast(u32) (last_ascii - first_ascii + cast(i32) len(icon_characters));

	fmt.println("HEADER: ", header);

	os.write(fd, mem.byte_slice(&header, size_of(header)));
	os.write(fd, mem.slice_to_bytes(glyphs[:]));
}

PackedToGlyph :: proc(packed: tty.packedchar, ch: rune) -> glyph {
	g := glyph { 
		charater = ch,
		min_x = cast(f32) packed.x0,
		min_y = cast(f32) packed.y0,
		max_x = cast(f32) packed.x1,
		max_y = cast(f32) packed.y1,
		x_offset = packed.xoff,
		y_offset = packed.yoff,
		x_advance = packed.xadvance,	
	}; 

	return g;
}