package mx_ui


import "core:mem"
import "core:slice"
import "base:runtime"
import "core:strings"
import "core:math"
import "core:fmt"

// For current use case is ok.
// Would this be usefull for input (dynamic) strings? 
// MAX_GAP_SIZE :: 4


// Should this be rune? 
gap_buffer :: struct {
	base: []u8,
	gap_start: int,
	gap_size: int, 
}

InitGapBuffer :: proc(size: int, allocator := context.allocator) -> gap_buffer {
	buffer := gap_buffer {};

	// Empty buffer equals to an encapsulated gap.
	buffer.base = make([]u8, size);
	buffer.gap_size = size; 

	return buffer; 
} 

// This will only insert the character whereever the gap is.
// Another function will actually move the gap to the cursor position and swap the overlapping data.
InsertCharacter :: proc(buffer: ^gap_buffer, c: u8) -> bool {
	// If the gap buffer is full we can't insert any characters anymore. 
	if buffer.gap_size == 0 do return false;  

	buffer.base[buffer.gap_start] = c;

	buffer.gap_start += 1;
	buffer.gap_size -= 1; 

	return true;
}


IsCursorLeft :: #force_inline proc(buffer: ^gap_buffer, cursor: int) -> bool {
	return mem.ptr_sub(&buffer.base[cursor], &buffer.base[buffer.gap_start]) < 0;
}

IsCursorRight :: #force_inline proc(buffer: ^gap_buffer, cursor: int) -> bool {
	return mem.ptr_sub(&buffer.base[cursor], &buffer.base[buffer.gap_start]) > 0;
}


// TODO(G): See how to make this work correclty. Left side can be easly done but right not really? 
GapMove :: proc(buffer: ^gap_buffer, cursor: int) {
	// No characters left don't swap anything. 
	gap_end := buffer.gap_start + buffer.gap_size;

	cursor := math.clamp(cursor, 0, len(buffer.base) - buffer.gap_size);
	if IsCursorLeft(buffer, cursor) {
		diff := buffer.gap_start - cursor; 
		slice.swap_between(buffer.base[cursor:buffer.gap_start], buffer.base[gap_end - diff:gap_end]);
	} else if IsCursorRight(buffer, cursor) {
		diff := cursor - buffer.gap_start;
		slice.swap_between(buffer.base[gap_end:gap_end + diff], buffer.base[buffer.gap_start: buffer.gap_start + diff]);
	}

	buffer.gap_start = cursor;
}


RemoveCharacter :: proc(buffer: ^gap_buffer) {
	// Don't remove characters if there aren't any. 
	if buffer.gap_start == 0 do return;

	buffer.gap_start -= 1; 
	buffer.gap_size += 1; 
	buffer.base[buffer.gap_start] = 0;
}


MakeTempString :: proc(buffer: ^gap_buffer, allocator := context.temp_allocator) -> string {
	if buffer.gap_size == 0 || len(buffer.base) == buffer.gap_size + buffer.gap_start {
		return strings.string_from_ptr(&buffer.base[0], len(buffer.base));
	} else {
		gap_end := buffer.gap_start + buffer.gap_size;
		lhs := strings.string_from_ptr(&buffer.base[0], buffer.gap_start);
		rhs := strings.string_from_ptr(&buffer.base[gap_end], len(buffer.base) - gap_end);

		return strings.concatenate({lhs, rhs}, allocator);
	}
}

ResetGapBuffer :: proc(buffer: ^gap_buffer) {
	slice.zero(buffer.base[:]);

	buffer.gap_start = 0;
	buffer.gap_size = len(buffer.base);
}


InsertString :: proc(buffer: ^gap_buffer, s: string) -> int {
	copied := 0;
	for c in s {
		if InsertCharacter(buffer, cast(u8) c) {
			copied += 1;
		}
	}

	return copied;
}