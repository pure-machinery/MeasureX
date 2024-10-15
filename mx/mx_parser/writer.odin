package mx_parser


import "core:mem"
import "core:os"
import "base:runtime"

binary_writer :: struct {
	data: []u8,
	offset: u64,
	last_offset: u64,
}




WriteValueAt :: #force_inline proc(writer: ^binary_writer, $T: typeid, at: u64) -> T
{
	value := cast(^T) (&writer.data[at]);

	return value^;
}

WriteValue :: #force_inline proc(writer: ^binary_writer, $T: typeid) -> T 
{
	value := cast(^T) (&writer.data[reader.offset]);

	reader.offset += size_of(T);

	return value^;
}

WriteArray :: #force_inline proc(writer: ^binary_writer, $T: typeid, items: int, advance : bool = false ) -> []T
{
	array_to_return := cast(^T) &writer.data[writer.offset];

	if advance do writer.offset += cast(u64) (items * size_of(T));

	return transmute([]T) runtime.Raw_Slice { data = array_to_return, len = items * size_of(T)};
}