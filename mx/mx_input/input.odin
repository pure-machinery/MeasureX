package mx_input



MAX_KEYS :: int(max(mx_key)) + 1

key_state :: enum {
	IDLE,
	PRESSED,
	RELEASED,
}

input_state :: struct {
	keys: [MAX_KEYS]key_state,
	last_keys: [MAX_KEYS]key_state,

	elapsed: [MAX_KEYS]f32,

	mouse_x: i32,
	mouse_y: i32,

	left_press: bool,
	right_press: bool,

	scroll: f32,
}

KeyIsDown :: #force_inline proc "contextless" (input: ^input_state, key: mx_key) -> (bool, f32)
{	
	return input.keys[key] == .PRESSED, input.elapsed[key];
}

KeysAreDown :: proc "contextless" (input: ^input_state, keys: []mx_key) -> bool 
{
	for key in keys {
		if is, _ := KeyIsDown(input, key); is == false {
			return false;
		}
	}

	return true;
}

KeysAreDownAny :: proc "contextless" (input: ^input_state, keys: []mx_key) -> (mx_key, f32) {
	for key in keys {
		if is, elapsed := KeyIsDown(input, key); is do return key, elapsed;
		}
		
	return mx_key.KEY_UNKNOWN, 0;
}

KeyJustReleased :: #force_inline proc "contextless" (input: ^input_state, key: mx_key) -> bool 
{
	return input.last_keys[key] == .PRESSED && input.keys[key] == .RELEASED;
}

// If this can return multiple keys at once then it doesn't work? 
KeysJustReleased :: proc "contextless" (input: ^input_state, keys: []mx_key) -> mx_key {
	for key in keys {
		if KeyJustReleased(input, key) do return key; 
	}

	return mx_key.KEY_UNKNOWN;
}

UpdateInputState :: #force_inline proc(input: ^input_state, key: mx_key, state: key_state) 
{
	input.keys[key] = state;
}

IsInCursorProximity :: proc(last_x, last_y, x, y: f32, radius: f32 = 4.0) -> bool {
	dx := abs(x - last_x);
	dy := abs(y - last_y);

	return dx <= radius || dy <= radius;
}

UpdateKeysPressed :: proc(input: ^input_state, dt: f32) {
	for key in mx_key {
		if input.keys[key] == .PRESSED {
			input.elapsed[key] += cast(f32) dt;
		} else {
			input.elapsed[key] = 0; 
		}
	}	
}

ALPHABET := []mx_key { 	
	.KEY_A,
	.KEY_B,
	.KEY_C,
	.KEY_D,
	.KEY_E,
	.KEY_F,
	.KEY_G,
	.KEY_H,
	.KEY_I,
	.KEY_J,
	.KEY_K,
	.KEY_L,
	.KEY_M,
	.KEY_N,
	.KEY_O,
	.KEY_P,
	.KEY_Q,
	.KEY_R,
	.KEY_S,
	.KEY_T,
	.KEY_U,
	.KEY_V,
	.KEY_W,
	.KEY_X,
	.KEY_Y,
	.KEY_Z,
	.KEY_SPACE,
}