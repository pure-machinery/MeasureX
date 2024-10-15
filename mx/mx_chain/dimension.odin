package mx_chain


import "core:mem"
import "core:math"
import "core:fmt"

DEFAULT_CHAIN_COUNT : int : 32;


dimension_edit_mode :: enum {
	//NONE,
	NOMINAL,
	FIELD,
	UPPER,
	LOWER,
}

dimension_state :: enum {
	ISO2862,
	ISO286,
	None,
}

dimension_node :: struct 
{
	next: ^dimension_node,
	prev: ^dimension_node,


	// The use can either use the ISO 2862 standard, ISO 286, or use custom input. 
	// Used for setting custom tolerances - meaning not using fields!
	state: dimension_state,

	nominal_value: f64,

	upper_tolerance: f64,
	lower_tolerance: f64,

	field: iso_field,
	grade: iso_grade,

	id: int,
}

dimension_chain :: struct 
{
	head: ^dimension_node,
	last: ^dimension_node,

	free: ^dimension_node, 
	data: ^u8,

	fixed_dimension: ^dimension_node, 

	chains_capacity: int,
	chains_occupied: int,

	designation: tolerance_class_designation,

	edit_mode: dimension_edit_mode,
}


InitializeChain :: proc(max_chains := DEFAULT_CHAIN_COUNT) -> (dimension_chain, bool)
{
	nodes, err := make([]dimension_node, max_chains);

	if err != mem.Allocator_Error.None {
		return {}, false;
	}

	chain := dimension_chain {
		head = nil,
		last = nil,

		free = nil,
		data = cast(^u8) raw_data(nodes),

		chains_capacity = max_chains,
		chains_occupied =  0,
	};

	ChainFreeAll(&chain);

	return chain, true;
}


ChainFreeAll :: proc(chain: ^dimension_chain) 
{
	for idx : int = chain.chains_capacity - 1; idx >= 0; idx -= 1 {
		node_ptr := cast(^dimension_node) mem.ptr_offset(cast(^u8) chain.data, idx * size_of(dimension_node));
		node_ptr.id = -1;
		node_ptr.next = chain.free; 
		chain.free = node_ptr; 
	}

	chain.head = nil;
	chain.last = nil;

	chain.chains_occupied = 0;
}


ChainFreeNode :: proc(chain: ^dimension_chain, node: ^dimension_node) -> ^dimension_node
{	
	selected : ^dimension_node = nil;
	// We should check if the ptr is in range of the free_list.
	if node == nil do return selected;

	if node == chain.head {
		if node.next != nil {
			chain.head = node.next;
			chain.head.prev = nil;

			selected = chain.head;
		} else {
			chain.head = nil;
			chain.last = nil;
		}
	} else if node != chain.last {
		next := node.next;
		prev := node.prev;

		// Reconnect adjacent nodes.
		next.prev = prev;
		prev.next = next;

		selected = prev;
	} else {
		chain.last = node.prev;
		chain.last.next = nil;

		selected = chain.last; 
	}
	
	old_free := chain.free;

	chain.free = node;
	chain.free.next = old_free;
	chain.free.prev = nil;

	chain.chains_occupied -= 1;

	return selected;
}

when ODIN_DEBUG {
	ChainIterAllFree :: proc(chain: ^dimension_chain)
	{
		for free_node := chain.free; free_node != nil; free_node = free_node.next {
			fmt.println(cast(rawptr) free_node, free_node);
		}
	}

}

ChainInsertNode :: proc(chain: ^dimension_chain, selected: ^dimension_node) -> ^dimension_node
{
	inserted : ^dimension_node = nil;

	inserted = chain.free;

	// No more space in the free list.
	if inserted == nil || chain.chains_occupied >= chain.chains_capacity {
		return nil;
	}

	// Advance next free node.
	chain.free = chain.free.next;

	inserted^ = {
		next = nil,
		id = chain.chains_occupied,
	};


	// This is the first allocation.
	if chain.head == nil {
		chain.head = inserted;
		chain.last = inserted; 
	} else if selected != nil && selected != chain.last {
		// We are in the middle of two nodes.
		inserted.next = selected.next;
		inserted.prev = selected;
		selected.next.prev = inserted;
		selected.next = inserted;
	} else {
		// Append to the last node.
		chain.last.next = inserted;
		inserted.prev = chain.last;
		chain.last = inserted; 
	}

	chain.chains_occupied += 1;

	return inserted;
}

ChainSetFixedDimension :: proc(chain: ^dimension_chain, fixed_node: ^dimension_node) 
{
	chain.fixed_dimension = fixed_node;
}



CalculateEndDimension :: proc(chain: dimension_chain) -> dimension_node
{
	total := dimension_node {};

	// If the memory is coherent then we can turn this into an array ez.
	for node := chain.head; node != nil; node = node.next {
		total.nominal_value += node.nominal_value;
		if IsPositiveF64(&node.nominal_value) {
			total.upper_tolerance += node.upper_tolerance;
			total.lower_tolerance += node.lower_tolerance;
		} else {
			total.upper_tolerance -= node.lower_tolerance;
			total.lower_tolerance -= node.upper_tolerance;
		}
	}

	return total;
}

// This is buggy. Doesn't work as expected.
CalculateFixedDimension :: proc(chain: ^dimension_chain)
{
	node := CalculateEndDimension(chain^);

	if chain.fixed_dimension != chain.last {
		chain.fixed_dimension.nominal_value = chain.last.nominal_value - node.nominal_value;
		chain.fixed_dimension.upper_tolerance = chain.last.upper_tolerance - node.upper_tolerance;
		chain.fixed_dimension.lower_tolerance = chain.last.lower_tolerance - node.lower_tolerance;
	} else {
		chain.last.upper_tolerance = node.upper_tolerance;
		chain.last.lower_tolerance = node.lower_tolerance;
		chain.last.nominal_value = node.nominal_value;
	}
}


IsPositiveF32 :: #force_inline proc(x: ^f32) -> b32 {
	return ((cast(^i32) x)^ >> 31) == 0; 
}

IsPositiveF64 :: #force_inline proc(x: ^f64) -> b32 {
	return ((cast(^i64) x)^ >> 63) == 0; 
}