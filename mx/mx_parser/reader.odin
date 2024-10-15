package mx_parser


import "core:mem"
import "core:os"
import "base:runtime"

binary_reader :: struct {
	data: []u8,
	offset: u64,
	last_offset: u64,
}


ReaderSetTempOffset :: #force_inline proc(reader: ^binary_reader, offset: u64) {
	reader.last_offset = reader.offset;

	reader.offset = offset;
}

ReaderResetTempOffset :: #force_inline proc(reader: ^binary_reader) {
	reader.offset = reader.last_offset;
}

ReadAdvance :: #force_inline proc(reader: ^binary_reader, bytes: u64) 
{
	reader.offset += bytes;
}

ReadValueAt :: #force_inline proc(reader: ^binary_reader, $T: typeid, at: u64) -> T
{
	value := cast(^T) (&reader.data[at]);

	return value^;
}

ReadValue :: #force_inline proc(reader: ^binary_reader, $T: typeid) -> T 
{
	value := cast(^T) (&reader.data[reader.offset]);

	reader.offset += size_of(T);

	return value^;
}

ReadValueCurrent :: #force_inline proc(reader: ^binary_reader, $T: typeid) -> T 
{
	value := cast(^T) (&reader.data[reader.offset]);
	
	return value^;
}


ReadArray :: #force_inline proc(reader: ^binary_reader, $T: typeid, items: int, advance : bool = false ) -> []T
{
	array_to_return := cast(^T) &reader.data[reader.offset];

	if advance do reader.offset += cast(u64) (items * size_of(T));

	return transmute([]T) runtime.Raw_Slice { data = array_to_return, len = items };
}


// Loads the file data as bytes for a given path.
LoadFileData :: proc(filename: string, read_only: bool = true) -> ([]u8, bool)
{
	data := []u8 {};

	usage := os.O_RDONLY;

	if !read_only {
		usage = os.O_RDWR;
	}

	file_handle, open_ok := os.open(filename, usage, 0); 
	defer os.close(file_handle);

	if open_ok != os.ERROR_NONE do return data, false;

	total_bytes, size_ok := os.file_size(file_handle);

	if size_ok != os.ERROR_NONE do return data, false;
	
	data = make([]u8, total_bytes);

	bytes_read, read_ok := os.read_full(file_handle, data);

	if read_ok != os.ERROR_NONE || bytes_read == 0 do return data, false;

	return data, true;
}