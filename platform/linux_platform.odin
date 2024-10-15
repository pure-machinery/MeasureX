package platform


//import x11 "vendor:xlib"
import x11    "vendor:x11/xlib";
import xrandr "vendor:xrandr"
import gl     "vendor:OpenGL"
import glx    "vendor:glx"

import "../mx/mx_input"
import "../mx/mx_core"
import "../mx/mx_renderer"
import "../mx/mx_parser"

import "core:time"
import "base:runtime"
import "core:strings"
import "core:mem"
import "core:fmt"
import "core:os"
import "core:slice"

DEFAULT_WIDTH :: 800;
DEFAULT_HEIGHT :: 640;	

scratch: mem.Scratch_Allocator;

PropModeReplace :: 1
XA_ATOM :: x11.Atom(4)
XA_CARDINAL :: x11.Atom(6)

main :: proc() {
	using x11;

	mem.scratch_allocator_init(&scratch, 8 * mem.Megabyte, context.allocator)
	context.temp_allocator = mem.scratch_allocator(&scratch)
	defer mem.scratch_allocator_destroy(&scratch)
	
	display := OpenDisplay(nil);
	defer CloseDisplay(display);

	if display == nil {
		// TODO(G): Logging.
		return;
	};	

	default_screen := DefaultScreen(display);
	root_window := DefaultRootWindow(display);

	screen_height := DisplayHeight(display, default_screen);
	screen_width := DisplayWidth(display, default_screen);

	// Other attributes are set by default to proper values.
	// No need for DEPTH and STENCIL buffers.
	attribute_list := []i32 {
		glx.RED_SIZE, 8,
		glx.GREEN_SIZE, 8,
		glx.BLUE_SIZE, 8,
		glx.ALPHA_SIZE, 8,
		glx.BUFFER_SIZE, 32,
		glx.DOUBLEBUFFER, 1,
		None,
	}; 

	config_count : i32 = 0;
	fb_configs := glx.ChooseFBConfig(cast(^glx._XDisplay) display, DefaultScreen(display), raw_data(attribute_list), &config_count);
	defer x11.Free(fb_configs);

	if fb_configs == nil { 
		when ODIN_DEBUG do fmt.println("Requested config not found: ", attribute_list);
		return;
	}
	
	best_config_idx : i32 = -1; 
	max_samples : i32 = -1; 
	config_array := slice.from_ptr(fb_configs, cast(int) config_count);
	for config, index in config_array {
		// Why do we need it if we don't use it? Can a display have no visual - perhaps over the network (doesn't make sense) ? 
		info := glx.GetVisualFromFBConfig(cast(^glx._XDisplay) display, config);
		defer x11.Free(info);

		if info != nil {
			sample_buffers, samples: i32;
			glx.GetFBConfigAttrib(cast(^glx._XDisplay) display, config, glx.SAMPLE_BUFFERS,  &sample_buffers);
			glx.GetFBConfigAttrib(cast(^glx._XDisplay) display, config, glx.SAMPLES, &samples);

			if sample_buffers > 0 && samples > max_samples { 
				max_samples = samples;
				best_config_idx = cast(i32) index; 
			}
		}
	}

	config : glx.GLXFBConfig = config_array[best_config_idx];

	visual_info := cast(^x11.XVisualInfo) glx.GetVisualFromFBConfig(cast(^glx._XDisplay) display, config);
	defer x11.Free(visual_info);

	when ODIN_DEBUG do fmt.println("Visual info picked:", visual_info);

	if visual_info == nil do return;
	
	window_attributes : x11.XSetWindowAttributes = {};
	window_attributes.border_pixel = 0;
	// Setting a CWBackPixmap mask for this flickers the window....
	window_attributes.background_pixel = 0;
	window_attributes.colormap = CreateColormap(display, root_window, visual_info.visual, ColormapAlloc.AllocNone);
    window_attributes.bit_gravity = Gravity.NorthWestGravity;
	window_attributes.event_mask = EventMask { 
		.ButtonPress,
		.ButtonRelease,
		.KeyPress, 
		.KeyRelease,
		.PointerMotion,
		.StructureNotify, 
		.SubstructureNotify };

	window := CreateWindow(
		display, 
		root_window, 
		screen_width >> 1, 
		screen_height >> 1, 
		DEFAULT_WIDTH,
		DEFAULT_HEIGHT,
		0,
		visual_info.depth,
		WindowClass.InputOutput, // CopyFromParent,
		visual_info.visual, 
		WindowAttributeMask { .CWColormap, .CWEventMask}, 
		&window_attributes);

	defer DestroyWindow(display, window);

	width, height, refresh := GetMonitorInfo(display, window);
	fmt.println("Primary monitor: ", width, "x", height, "@", refresh, "Hz");
	
	gl_context, context_ok := InitOpenGL(display, window, default_screen, config);
	defer glx.DestroyContext(cast(^glx._XDisplay) display, gl_context);

	if !context_ok {
		// TODO(G): Logging. 
		return; 
	}

	TITLE :: "MeasureX"

	WriteDesktopEntry(TITLE);
	SetWindowName(display, window, TITLE);
	//SetWindowFrameExtents(display, window, 20);
	SetWindowType(display, window);
	//MakeBorderless(display, window);
	//SetOtherProperties(display, window);

	// TODO: Clipboard data.
	close_window_atom := InternAtom(display, "WM_DELETE_WINDOW", false);
	// clipboard_atom := InternAtom(display , "CLIPBOARD", False);
	// target_atom := InternAtom(display , "TARGETS", False);
	// utf8_string_atom := InternAtom(display, "UTF8_STRING", False);

	window_hints_atom := InternAtom(display, "WM_SIZE_HINTS", false);
	hints := XSizeHints {
		flags = SizeHints { .PMinSize },
		min_width = 640, 
		min_height = 640,
	};

	SetWMProtocols(display, window, &close_window_atom, 1);
	SetWMNormalHints(display, window, &hints);

	ClearWindow(display, window);
	MapWindow(display, window);
	Flush(display);

	renderer := mx_renderer.InitGraphicsContext(DEFAULT_WIDTH, DEFAULT_HEIGHT);
	state := mx_core.state_data {};
	input := mx_input.input_state {};

	image_data := #load("asset.png");
	glyph_data := #load("asset");

	if font_image, font_map, max_height, success := mx_parser.ParseTTF(image_data, glyph_data); success {
		renderer.font_image = font_image;
		renderer.character_map = font_map;		
		renderer.max_height = max_height;
	}

	if ok := mx_renderer.BuildGraphicsContext(&renderer); !ok {
		when ODIN_DEBUG do fmt.println("Failed to build renderer.");
		// TODO(G): Logging!
		return;
	}



	// CPU tick time.
	state.desired_dt = 1.0 / cast(f64) min(refresh, 60);
	desired_dt := cast(time.Duration) (state.desired_dt * 1e9);
	previous_ms := time.now();

	//track: mem.Tracking_Allocator = {};
	//mem.tracking_allocator_init(&track, context.allocator);
	//context.allocator = mem.tracking_allocator(&track);
	for signal := &state.signal; !signal.should_close ; {
		defer mem.free_all(context.temp_allocator);

		current_ms := time.now();
		frame_time := time.diff(previous_ms, current_ms); 
		previous_ms = current_ms;

		state.dt = cast(f64) time.duration_nanoseconds(frame_time) * 1e-9;

		copy_slice(input.last_keys[:], input.keys[:]);

		for EventsQueued(display, .QueuedAfterReading) != 0 {
			event := XEvent {};
			NextEvent(display, &event);

			#partial switch event.type {
				case EventType.MotionNotify:
					motion : XMotionEvent = event.xmotion;
					input.mouse_x = motion.x;
					input.mouse_y = motion.y;

					signal.absolute_x = motion.x_root;
					signal.absolute_y = motion.y_root;
				case EventType.ButtonPress:
					pressed_button : XButtonEvent = event.xbutton;
					
					// What about right click?
					if      pressed_button.button == MouseButton.Button1 && (pressed_button.state & InputMask { .Button1Mask } == {}) do input.left_press = true;
					else if pressed_button.button == MouseButton.Button3 && (pressed_button.state & InputMask { .Button3Mask } == {}) do input.right_press = true; 
					else if pressed_button.button == MouseButton.Button4 && (pressed_button.state & InputMask { .Button4Mask } == {}) do input.scroll = 1.0; 
				case EventType.ButtonRelease:
					released_button : XButtonEvent = event.xbutton;

					if      released_button.button == MouseButton.Button1 && (released_button.state & InputMask { .Button1Mask } != {}) do input.left_press = false;
					else if released_button.button == MouseButton.Button3 && (released_button.state & InputMask { .Button3Mask } != {}) do input.right_press = false; 
					else if released_button.button == MouseButton.Button5 && (released_button.state & InputMask { .Button5Mask } != {}) do input.scroll = -1.0; 
				case EventType.KeyPress:
					pressed_key : XKeyEvent = event.xkey;

					key := TranslateKey(KeycodeToKeysym(display, cast(u8) pressed_key.keycode, 0));
					mx_input.UpdateInputState(&input, key, .PRESSED);
				case EventType.KeyRelease:
					released_key : XKeyEvent = event.xkey;

					if EventsQueued(display, .QueuedAfterReading) != 0 {
						next_event := XEvent {};
						PeekEvent(display, &next_event)

						is_keypress := next_event.type == EventType.KeyPress;
						same_time := next_event.xkey.time == released_key.time;
						same_code := next_event.xkey.keycode == released_key.keycode;

						if is_keypress && same_time && same_code do break;
					}
					
					key := TranslateKey(KeycodeToKeysym(display, cast(u8) released_key.keycode, 0));
					mx_input.UpdateInputState(&input, key, mx_input.key_state.RELEASED);

					if key == mx_input.mx_key.KEY_F12 {
						signal.should_fullscreen = !signal.should_fullscreen;
					}
				case EventType.ConfigureNotify:
					config_event := event.xconfigure;

					root_window := Window {};
					child_window := Window {};
					root_x : i32 = 0;
					root_y : i32 = 0;

					mouse_x : i32 = 0;
					mouse_y : i32 = 0;

					mask := KeyMask {};

					result := QueryPointer(
						display, 
						window, 
						&root_window, 
						&child_window,
						&root_x, 
						&root_y, 
						&mouse_x, 
						&mouse_y, 
						&mask,
					); 

					if result == true {
						input.mouse_x = mouse_x;
						input.mouse_y = mouse_y;
					} 
				case EventType.ClientMessage:
					client_event := event.xclient;

					if (client_event.data.l[0] == cast(int) close_window_atom) {
						signal.should_close = true;
						break;
					}
			}

			//continue;
		} 

		attrib := XWindowAttributes {};
		
		GetWindowAttributes(display, window, &attrib);
		

		if renderer.screen_width != attrib.width || renderer.screen_height != attrib.height {
			mx_renderer.ResizeViewport(&renderer, 0, 0, attrib.width, attrib.height);
		}

		input.mouse_x, input.mouse_y = GetPointerCoordinates(display, window);
		// We accumulate frames - if the total time is higher then the desired we reset the accumulator.
		// TODO(G): If the refresh rate of the screen is lower then the desired tick then use the lower 
		// value.

		mx_core.RunApplication(&input, &renderer, &state);
		// Needs to be done after update because we want to have a zero pressed time 
		// or we can look into the previous key time.
		mx_input.UpdateKeysPressed(&input, cast(f32) state.dt);


		if signal.should_fullscreen {	
			ToggleFullscreen(display, window, &signal.fullscreen);
			signal.should_fullscreen = false; 
		}

		glx.SwapBuffers(cast(^glx._XDisplay) display, cast(u64) window);
		gl.Finish();

		state.elapsed += state.dt;	
		state.frame += 1;	

		if diff := abs(desired_dt - frame_time); diff > 0 {
			time.accurate_sleep(diff);
		}
	}
}

TranslateKey :: proc(keycode: x11.KeySym) -> mx_input.mx_key {
	using mx_input;
	using mx_key;
	using x11;

	#partial switch(keycode) {
		case .XK_A, .XK_a: return KEY_A;
		case .XK_B, .XK_b: return KEY_B;
		case .XK_C, .XK_c: return KEY_C;
		case .XK_D, .XK_d: return KEY_D;
		case .XK_E, .XK_e: return KEY_E;
		case .XK_F, .XK_f: return KEY_F;
		case .XK_G, .XK_g: return KEY_G;
		case .XK_H, .XK_h: return KEY_H;
		case .XK_I, .XK_i: return KEY_I;
		case .XK_J, .XK_j: return KEY_J;
		case .XK_K, .XK_k: return KEY_K;
		case .XK_L, .XK_l: return KEY_L; 
		case .XK_M, .XK_m: return KEY_M;
		case .XK_N, .XK_n: return KEY_N;
		case .XK_O, .XK_o: return KEY_O;
		case .XK_P, .XK_p: return KEY_P;
		case .XK_Q, .XK_q: return KEY_Q;
		case .XK_R, .XK_r: return KEY_R;
		case .XK_S, .XK_s: return KEY_S;
		case .XK_T, .XK_t: return KEY_T;
		case .XK_U, .XK_u: return KEY_U;
		case .XK_V, .XK_v: return KEY_V;
		case .XK_W, .XK_w: return KEY_W;
		case .XK_X, .XK_x: return KEY_X;
		case .XK_Y, .XK_y: return KEY_Y;
		case .XK_Z, .XK_z: return KEY_Z;

	 	case .XK_period:   return KEY_PERIOD;
		case .XK_0:        return KEY_0;
		case .XK_1:        return KEY_1;
		case .XK_2:        return KEY_2;
		case .XK_3:        return KEY_3;
		case .XK_4:        return KEY_4;
		case .XK_5:        return KEY_5;
		case .XK_6:        return KEY_6;
		case .XK_7:        return KEY_7;
		case .XK_8:        return KEY_8;
		case .XK_9:        return KEY_9;

		case .XK_F1:       return KEY_F1;
		case .XK_F2:       return KEY_F2;
		case .XK_F3:       return KEY_F3;
		case .XK_F4:       return KEY_F4;
		case .XK_F5:       return KEY_F5;
		case .XK_F6:       return KEY_F6;
		case .XK_F7:       return KEY_F7;
		case .XK_F8:       return KEY_F8;
		case .XK_F9:       return KEY_F9;
		case .XK_F10:      return KEY_F10;
		case .XK_F11:      return KEY_F11;
		case .XK_F12:      return KEY_F12;


		case .XK_Tab:       return KEY_TAB;
		case .XK_Shift_L:   return KEY_LSHIFT;
		case .XK_Control_L: return KEY_LCTRL;
		case .XK_Escape:    return KEY_ESC;
		case .XK_Delete:    return KEY_DELETE;
		case .XK_BackSpace: return KEY_BACKSPACE;
		case .XK_minus:     return KEY_DASH;
		case .XK_Left:      return KEY_LEFT;
		case .XK_Right:     return KEY_RIGHT;
		case .XK_space:     return KEY_SPACE;

		case: return KEY_UNKNOWN;
	}
}


DESKTOP_ENTRY_FILE :: 
`[Desktop Entry]
Type=Application
Name=%s
Exec="%s"
Terminal=false
`;

// TODO(G): Write an icon somewhere on the system. 48 x 48 bytes.
WriteDesktopEntry :: proc(title: string) {
	dir := os.get_current_directory();
	arg := os.args[0];

	path_to_binary : string = {};

	if strings.has_prefix(arg, ".") {
		path_to_binary = strings.concatenate({ dir, arg[1:] }, context.temp_allocator);
	} else {
		path_to_binary = strings.concatenate({ dir, arg }, context.temp_allocator);
	}

    // "~/.local/share/applications";
	home_dir := os.get_env("HOME", context.temp_allocator);
	local_dir := "/.local/share/applications"; 
	write_to := strings.concatenate({ home_dir, local_dir }, context.temp_allocator);

	os_err := os.set_current_directory(write_to);
	defer os.set_current_directory(dir);

	if os_err != os.ERROR_NONE do return;

	desktop_entry_name := strings.concatenate({title, ".desktop"}, context.temp_allocator);

	if os.exists(desktop_entry_name) do return; 

	fd, err := os.open(desktop_entry_name, os.O_CREATE | os.O_WRONLY | os.O_TRUNC, os.S_IRWXU);
	defer os.close(fd);

 	if err != os.ERROR_NONE {
 		fmt.println("Failed to open file: ", err);
 		return;
 	}; 

 	os.write_string(fd, fmt.tprintf(DESKTOP_ENTRY_FILE, title, path_to_binary));
}

SetWindowName :: proc(display: ^x11.Display, window: x11.Window, title: string) {
	using x11;

	name := InternAtom(display, "_NET_WM_NAME", false);
	icon_name := InternAtom(display, "_NET_WM_ICON_NAME", false);
	utf_string := InternAtom(display, "UTF8_STRING", false);

	ChangeProperty(display, window, name, utf_string, 8, PropModeReplace, raw_data(title), cast(i32) len(title));
	ChangeProperty(display, window, icon_name, utf_string, 8, PropModeReplace, raw_data(title), cast(i32) len(title));

	hint := XClassHint { 
		res_class = strings.clone_to_cstring(title, context.temp_allocator),
		res_name = strings.clone_to_cstring(strings.to_lower(title, context.temp_allocator)),
	};

	strings.clone_to_cstring(strings.to_lower(title, context.temp_allocator))

	SetClassHint(display, window, &hint);
}

SetOtherProperties :: proc(display: ^x11.Display, window: x11.Window) {
	using x11;

	window_type := InternAtom(display, "_NET_WM_WINDOW_TYPE", false);
	normal_type := InternAtom(display, "_NET_WM_WINDOW_TYPE_NORMAL", false);
	atom_ := InternAtom(display, "ATOM", false);
	
	allowed_actions := InternAtom(display, "_NET_WM_ALLOWED_ACTIONS", false);
	requested_actions := []cstring {
		"_NET_WM_ACTION_MOVE",
		"_NET_WM_ACTION_RESIZE",
		"_NET_WM_ACTION_MINIMIZE",
		"_NET_WM_ACTION_SHADE",
		"_NET_WM_ACTION_STICK",
		"_NET_WM_ACTION_MAXIMIZE_HORZ",
		"_NET_WM_ACTION_MAXIMIZE_VERT",
		"_NET_WM_ACTION_FULLSCREEN",
		"_NET_WM_ACTION_CHANGE_DESKTOP",
		"_NET_WM_ACTION_CLOSE",
		"_NET_WM_ACTION_ABOVE",
		"_NET_WM_ACTION_BELOW",
	};

	allowed_atoms := make([]Atom, len(requested_actions));
	defer delete(allowed_atoms);

	InternAtoms(display, raw_data(requested_actions), cast(i32) len(requested_actions), &allowed_atoms[0]);

	ChangeProperty(display, window, allowed_actions, allowed_actions, 32, PropModeReplace, cast(^u8) raw_data(allowed_atoms) , cast(i32) len(requested_actions));
	ChangeProperty(display, window, window_type, atom_, 32, PropModeReplace, cast(^u8) &normal_type, 1);
}


SetWindowType :: proc(display: ^x11.Display, window: x11.Window) {
	using x11; 

	window_type_atom := InternAtom(display, "_NET_WM_WINDOW_TYPE", false);
	splash_type := InternAtom(display, 	"_NET_WM_WINDOW_TYPE_NORMAL", false);

	ChangeProperty(display, window, window_type_atom, XA_ATOM, 32, PropModeReplace, cast(^u8) &splash_type, 1);
}

SetWindowFrameExtents :: proc(display: ^x11.Display, window: x11.Window, size: f32) {
	using x11; 

	frame_atom := InternAtom(display, "_NET_FRAME_EXTENTS", false);
	frames := [4]f32 { size, size, size, size };

	ChangeProperty(display, window, frame_atom, XA_CARDINAL, 32, PropModeReplace, cast(^u8) &frames[0], 4);
}

MakeBorderless :: proc(display: ^x11.Display, window: x11.Window) {
	using x11;

	MwmHints :: struct {
	    flags: mwm_flags,
	    functions : mwm_functions,
	    decorations: mwm_decorations,
	    input_mode: mwm_input_mode,
	    status: mwm_status,
	};

	/* bit definitions for MwmHints.flags */
	mwm_flags :: enum u8 {
		FUNCTIONS   = 1 << 0,
		DECORATIONS = 1 << 1,
		INPUT_MODE  = 1 << 2,
		STATUS      = 1 << 3, 
	};
	mwm_functions :: enum u8 {
		ALL      = 1 << 0,
		RESIZE   = 1 << 1,
		MOVE     = 1 << 2,
		MINIMIZE = 1 << 3,
		MAXIMIZE = 1 << 4,
		CLOSE    = 1 << 5,
	};

	mwm_decorations :: enum u8 {
		ALL      = 1 << 0,
		BORDER   = 1 << 1,
		RESIZEH  = 1 << 2,
		TITLE    = 1 << 3,
		MENU     = 1 << 4,
		MINIMIZE = 1 << 5,
		MAXIMIZE = 1 << 6,
	};

	// Does not act like a bit set.
	mwm_input_mode :: enum u8 {
		MODELESS = 0,
		PRIMIARY_APPLICATION_MODAL = 1,
		SYSTEM_MODAL = 2,
		APPLICATION_MODAL = 3,
	};

	mwm_status :: enum u8 {
		TEAROFF_WINDOW = 1 << 0,
	};

	mwmHintsProperty := InternAtom(display, "_MOTIF_WM_HINTS", true);
	window_hints := MwmHints {};
	window_hints.flags = .DECORATIONS | .FUNCTIONS;
	window_hints.decorations = .RESIZEH | .BORDER;
	window_hints.functions = .ALL;
	//window_hints.decorations = .BORDER;

	fmt.println(window_hints, size_of(window_hints));

	ChangeProperty(display, window, mwmHintsProperty, mwmHintsProperty, 8, PropModeReplace, cast(^u8) &window_hints, 5);
}

ToggleFullscreen :: proc(display: ^x11.Display, window: x11.Window, is_fullscreen: ^bool)
{	
	using x11;

	event := XEvent {};
	state_atom := InternAtom(display, "_NET_WM_STATE", false);
	fullscreen_atom := InternAtom(display, "_NET_WM_STATE_FULLSCREEN", false);

	PropertyAction :: enum {
		REMOVE = 0x0,
		SET_OR_ADD = 0x1,
		TOGGLE = 0x2,
	};

	action : i64 = ---; 

	if is_fullscreen^ {
		action = i64(PropertyAction.REMOVE);
		is_fullscreen^ = false;
		UngrabPointer(display, CurrentTime);
	} else {
		action = i64(PropertyAction.SET_OR_ADD);
		is_fullscreen^ = true; 
		GrabPointer(display, window, true, EventMask {}, GrabMode.GrabModeAsync, GrabMode.GrabModeAsync, window, None, CurrentTime);
	}

	event.xclient.type = EventType.ClientMessage;
	event.xclient.serial = 0;
	event.xclient.send_event = true;
	event.xclient.window = window;
	event.xclient.message_type = state_atom;
	event.xclient.format = 32;
	event.xclient.data.l[ 0 ] = cast(int) action;
	event.xclient.data.l[ 1 ] = cast(int) fullscreen_atom;
	event.xclient.data.l[ 2 ] = 0;
	event.xclient.data.l[ 3 ] = 0;

	SendEvent(display, DefaultRootWindow(display), false, EventMask { .SubstructureRedirect, .SubstructureNotify }, &event);
	Sync(display);
}
/*
// Is there an event we can listen to?
CurrentAttachedScreens :: proc(display: ^x11.XDisplay) -> [16]int {
	using x11;

	for screen_idx : i32 = 0; screen_idx < ScreenCount(display); screen_idx += 1 {
		screen_ptr := ScreenOfXDisplay(display, screen_idx);

		screen_height := XDisplayHeight(display, screen_idx);
		screen_width := XDisplayWidth(display, screen_idx);

		// xrandr ! If you want to get the names / vendor information.
	}

	return [16]int {};
}
*/

CopyToClipboard :: proc(display: ^x11.Display, window: x11.Window, data: []u8) {
	// TODO(G)
}


InitOpenGL :: proc(display: ^x11.Display, window: x11.Window, screen: i32, config: glx.GLXFBConfig) -> (glx.GLXContext, bool)
{
	using x11;

	temp_query := glx.QueryExtensionsString(cast(^glx._XDisplay) display, screen);
	gl_extensions := strings.clone_from_cstring(temp_query, context.temp_allocator);

	gl_context : glx.GLXContext = glx.CreateNewContext(cast(^glx._XDisplay) display, config, glx.RGBA_TYPE, nil, 1);
	if gl_context == nil do return nil, false; 

	proc_name : cstring = "glXCreateContextAttribsARB";
	CreateContextAttribsARBProc := cast(CreateContextAttribsARBProxy) glx.GetProcAddressARB(cast(^u8) proc_name); 

	if (IsExtensionSupported(&gl_extensions, "GLX_ARB_create_context") || CreateContextAttribsARBProc != nil) {	
	    when ODIN_DEBUG { 	
		    modern_context_attributes := []i32 {
		       	glx.CONTEXT_MAJOR_VERSION_ARB, mx_renderer.GL_MAJOR_VERSION,
		        glx.CONTEXT_MINOR_VERSION_ARB, mx_renderer.GL_MINOR_VERSION,
		        glx.CONTEXT_FLAGS_ARB, glx.CONTEXT_DEBUG_BIT_ARB | glx.CONTEXT_FORWARD_COMPATIBLE_BIT_ARB,
		        glx.CONTEXT_PROFILE_MASK_ARB, glx.CONTEXT_CORE_PROFILE_BIT_ARB,
		        None,
		    };
	    } else {
	        modern_context_attributes := []i32 {
		       	glx.CONTEXT_MAJOR_VERSION_ARB, mx_renderer.GL_MAJOR_VERSION,
		        glx.CONTEXT_MINOR_VERSION_ARB, mx_renderer.GL_MINOR_VERSION,
		        glx.CONTEXT_FLAGS_ARB, glx.CONTEXT_FORWARD_COMPATIBLE_BIT_ARB,
		        glx.CONTEXT_PROFILE_MASK_ARB, glx.CONTEXT_CORE_PROFILE_BIT_ARB, 
		        None,
			};	
	    }

	    temp_context := CreateContextAttribsARBProc(display, config, gl_context, true, raw_data(modern_context_attributes));

	    if temp_context == nil do return nil, false; 

	    // Destroy old context and overwrite the variable. 
	    glx.DestroyContext(cast(^glx._XDisplay) display, gl_context);
	    gl_context = temp_context;

    	gl.load_up_to(mx_renderer.GL_MAJOR_VERSION, mx_renderer.GL_MINOR_VERSION, proc(p: rawptr, name: cstring) { 
			(cast(^rawptr)p)^ = cast(rawptr) glx.GetProcAddress(cast(^u8) name); 
		});
	}

	x11.Sync(display);

	glx.MakeCurrent(cast(^glx._XDisplay) display, cast(u64) window, gl_context);

	GetOpenGLInfo();

	/*
	if IsExtensionSupported(&gl_extensions, "GLX_EXT_swap_control") {
		// You can only write to the state and then in the loop activate v-sync.
		proc_name : cstring = "glXSwapIntervalEXT";
		SwapIntervalEXT := cast(SwapIntervalEXTProxy) glx.GetProcAddressARB(cast(^u8) proc_name);

		assert(SwapIntervalEXT != nil, fmt.tprintf("Failed to get procedure: %s\n", proc_name));
		// V-Sync enabled == 1; disabled == 0;
		//SwapIntervalEXT(cast(^glx._XDisplay) display, window, 1);
	}
	*/

	return gl_context, true;
}


GetOpenGLInfo :: proc() {
	using gl;

	vendor := string(GetString(VENDOR));
	renderer := string(GetString(RENDERER));
	version := string(GetString(VERSION));

	fmt.println(vendor, "::", renderer, "::", version);
}


CreateContextAttribsARBProxy :: proc(display: ^x11.Display, config: glx.GLXFBConfig, gl_context:  glx.GLXContext, direct: bool, attributes: ^i32) -> glx.GLXContext;
SwapIntervalEXTProxy :: proc(dpy: ^glx._XDisplay, drawable: glx.Drawable, interval: int);


GetMonitorInfo :: proc(display: ^x11.Display, window: x11.Window) -> (i32, i32, i32) {
	using xrandr;

	width, height, refresh : i32 = 0, 0, 0;

	monitor_count : i32 = 0;
	monitors := GetMonitors(cast(^_XDisplay) display, cast(u64) window, 1, &monitor_count);
	defer FreeMonitors(monitors);

	assert(monitor_count != 0, "Monitor count is 0.");

	for idx in 0..=monitor_count-1 {
		monitor_info_ := mem.ptr_offset(monitors, idx);
		if monitor_info_.primary > 0 {
			width = monitor_info_.width;
			height = monitor_info_.height;
		}
	}

	info := GetScreenInfo(cast(^_XDisplay) display, cast(u64) window);
	defer FreeScreenConfigInfo(info);
	
	refresh = cast(i32) ConfigCurrentRate(info);

	return width, height, refresh;
}


IsExtensionSupported :: proc(gl_extensions: ^string, extension: string) -> bool {
	for ext in strings.split_iterator(gl_extensions, " ") {
		if ext == extension do return true; 
	}

	return false; 
}

GetPointerCoordinates :: proc(display: ^x11.Display, window: x11.Window) -> (i32, i32) {
	using x11;

	root_window : x11.Window; 
	child_window : x11.Window;
	root_x, root_y : i32 = 0, 0;
	win_x, win_y : i32 = 0, 0;
	mask := KeyMask.ShiftMask;

	result := QueryPointer(display, window, &root_window, &child_window, &root_x, &root_y, &win_x, &win_y, &mask);
	
	// Coordinates are relative to the window top left corner, meaning they can be negative.

	return max(0, win_x), max(0, win_y);
}