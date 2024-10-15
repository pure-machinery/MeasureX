package profiler


import "core:time"
import "core:strings"
import "core:os"
import "core:mem"
import "core:fmt"

profiler_ctx := profiler {};


profile_entry :: struct {
	// Procedure name.
	text: string,

	// In milliseconds.
	entry_time_avg: f32,
	entry_time_max: f32,
	entry_time_min: f32,

	iteration: u32,
	time_start: time.Time,
}


default_profile_entry := profile_entry {
	entry_time_avg = -1.0,
	entry_time_max = -1.0,
	entry_time_min = 1e9,
}

// TODO(G): Make it so that it supports nesting!
// Make it stack like ? 
profiler :: struct {
	entry_names: strings.Builder,
	entry_names_written: int, 

	entries: []profile_entry,
	entry_offset: int,
}


InitProfiler :: proc(entry_count: int, allocator := context.allocator) {
	profiler_ctx.entry_names = strings.builder_make_len(4 * mem.Megabyte, allocator);
	profiler_ctx.entries = make_slice([]profile_entry, entry_count, allocator);
}


BeginRecordEntry :: proc(text: string) {
	using strings;

	entry : ^profile_entry = &profiler_ctx.entries[profiler_ctx.entry_offset];

	offset := builder_len(profiler_ctx.entry_names);
	written := write_string(&profiler_ctx.entry_names, text);

	entry.text = string_from_ptr(&profiler_ctx.entry_names.buf[offset], written);

	profiler_ctx.entry_offset += 1;

	entry.time_start = time.now();
}

EndRecordEntry :: proc() {
	ac := &profiler_ctx.entries[profiler_ctx.entry_offset - 1];
	entry_time := 1e-6 * cast(f32) time.diff(ac.time_start, time.now());

	profiler_ctx.entry_offset -= 1;

	ac.iteration += 1;
	ac.entry_time_avg = (ac.entry_time_avg + entry_time) / cast(f32) ac.iteration;

	if entry_time < ac.entry_time_min {
		ac.entry_time_min = entry_time;
	}

	if entry_time > ac.entry_time_max {
		ac.entry_time_max = entry_time;
	}

	strings.builder_reset(&profiler_ctx.entry_names);

	fmt.println(ac);
}


/*
FlushToFile :: proc() -> bool {
	fd, err := os.open("profiler_log", os.O_CREATE | os.O_WRONLY | os.O_TRUNC, os.S_IRWXU);
	defer os.close(fd);

 	if err != os.ERROR_NONE {
 		return false;
 	}; 

 	builder := strings.builder_make_len(4096, context.temp_allocator);
 	defer strings.builder_destroy(&builder);

	for entry_name, entry in profiler_ctx.entries {
		strings.write_string(&builder, entry_name);
		strings.write_u64(&builder, cast(u64) entry.entry_count)
		strings.write_f32(&builder, entry.entry_time_min, 'f');
		strings.write_f32(&builder, entry.entry_time_max, 'f');
		strings.write_f32(&builder, entry.entry_time_avg, 'f');
	}

	os.write_string(fd, strings.to_string(builder));

	return true; 
}*/