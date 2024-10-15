package mx_parser

import "core:os"
import "core:strings";
import "core:mem";
import "core:math";
import "core:fmt";

pdf_context :: struct {
	objects: [dynamic]object,

	major: u8,
	minor: u8,
}


object_type :: enum {
	BOOLEAN,
	NUMERIC,
	STRING,
	NAME,
	ARRAY,
	DICTIONARY,
	STREAM,
	NULL,
}

object :: struct {
	at: int,
	id: int,

	type: object_type,
	refs: []int,

	data: []u8,
}


InitPDF :: proc(major: u8, minor: u8, allocator := context.allocator) -> pdf_context {
	ctx := pdf_context {
		major = major,
		minor = minor, 
		objects = make_dynamic_array_len_cap([dynamic]object, 0, 1024),
	}; 

	return ctx;
}

AddObject :: proc(ctx: ^pdf_context, type: object_type, refs: []int, data: []u8) -> int {
	obj := object { 
		at = len(ctx.objects) * size_of(ctx.objects[0]),
		id = len(ctx.objects),
		type = type, 
		refs = refs,
		data = data,
	};

	append(&ctx.objects, obj);

	return obj.id;
}

AddDocumentCatalogue :: proc(ctx: ^pdf_context) {
	//AddObject(ctx, .DICTIONARY, )
}

WriteObject :: proc(builder: ^strings.Builder, obj: object) {
	using strings;

	write_int(builder, obj.id);
	write_int(builder, 0);
	write_string(builder, "obj << /Type");
	defer write_string(builder, ">> endobj\n");

	switch obj.type {
		case .BOOLEAN:
		case .NUMERIC:
		case .STRING:
		case .NAME:
		case .ARRAY:
		case .DICTIONARY:
		case .STREAM:
		case .NULL:
	}
}

WritePDF :: proc(ctx: ^pdf_context, allocator := context.allocator) -> string {
	using strings; 

 	builder : Builder = ---; 
	builder_init_len_cap(&builder, 0, mem.Kilobyte, allocator);
 	//defer builder_destroy(&builder);

 	write_string(&builder, fmt.tprintf("%PDF-%d.%d\n", ctx.major, ctx.minor));
 	defer write_string(&builder, "\n%%EOF");

 	for obj, index in ctx.objects {
 		WriteObject(&builder, obj);
 	}

 	return to_string(builder);
}