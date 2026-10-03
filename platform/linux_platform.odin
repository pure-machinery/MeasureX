package platform


import xlib   "vendor:x11/xlib";
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
XA_ATOM :: xlib.Atom(4)
XA_CARDINAL :: xlib.Atom(6)


main :: proc() {
	mem.scratch_allocator_init(&scratch, 8 * mem.Megabyte, context.allocator);
	context.temp_allocator = mem.scratch_allocator(&scratch);
	defer mem.scratch_allocator_destroy(&scratch);


	display := xlib.OpenDisplay(nil);
	defer xlib.CloseDisplay(display);

	if display == nil {
		// TODO(G): Logging.
		return;
	};	

	default_screen := xlib.DefaultScreen(display);
	root_window := xlib.DefaultRootWindow(display);

	screen_height := xlib.DisplayHeight(display, default_screen);
	screen_width := xlib.DisplayWidth(display, default_screen);

	// Other attributes are set by default to proper values.
	// No need for DEPTH and STENCIL buffers.
	attribute_list := []i32 {
		glx.RED_SIZE, 8,
		glx.GREEN_SIZE, 8,
		glx.BLUE_SIZE, 8,
		glx.ALPHA_SIZE, 8,
		glx.BUFFER_SIZE, 32,
		glx.DOUBLEBUFFER, 1,
		xlib.None,
	}; 

	config_count : i32 = 0;
	fb_configs := glx.ChooseFBConfig(cast(^glx._XDisplay) display, default_screen, raw_data(attribute_list), &config_count);
	defer xlib.Free(fb_configs);

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
		defer xlib.Free(info);

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

	visual_info := cast(^xlib.XVisualInfo) glx.GetVisualFromFBConfig(cast(^glx._XDisplay) display, config);
	defer xlib.Free(visual_info);

	when ODIN_DEBUG do fmt.println("Visual info picked:", visual_info);

	if visual_info == nil do return;
	
	window_attributes : xlib.XSetWindowAttributes = {};
	window_attributes.border_pixel = 0;
	// Setting a CWBackPixmap mask for this flickers the window....
	window_attributes.background_pixel = 0;
	window_attributes.colormap = xlib.CreateColormap(display, root_window, visual_info.visual, xlib.ColormapAlloc.AllocNone);
    window_attributes.bit_gravity = xlib.Gravity.NorthWestGravity;
	window_attributes.event_mask = xlib.EventMask { 
		.ButtonPress,
		.ButtonRelease,
		.KeyPress, 
		.KeyRelease,
		.PointerMotion,
		.StructureNotify, 
		.SubstructureNotify,
		.PropertyChange, };

	window := xlib.CreateWindow(
		display, 
		root_window, 
		screen_width >> 1, 
		screen_height >> 1, 
		DEFAULT_WIDTH,
		DEFAULT_HEIGHT,
		0,
		visual_info.depth,
		xlib.WindowClass.InputOutput, // CopyFromParent,
		visual_info.visual, 
		xlib.WindowAttributeMask { .CWColormap, .CWEventMask}, 
		&window_attributes);

	defer xlib.DestroyWindow(display, window);

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
	close_window_atom := xlib.InternAtom(display, "WM_DELETE_WINDOW", false);
	// clipboard_atom := InternAtom(display , "CLIPBOARD", False);
	// target_atom := InternAtom(display , "TARGETS", False);
	// utf8_string_atom := InternAtom(display, "UTF8_STRING", False);

	window_hints_atom := xlib.InternAtom(display, "WM_SIZE_HINTS", false);
	hints := xlib.XSizeHints {
		flags = xlib.SizeHints { .PMinSize },
		min_width = 640, 
		min_height = 640,
	};

	xlib.SetWMProtocols(display, window, &close_window_atom, 1);
	xlib.SetWMNormalHints(display, window, &hints);

	xlib.ClearWindow(display, window);
	xlib.MapWindow(display, window);
	xlib.Flush(display);

	renderer := mx_renderer.InitGraphicsContext(DEFAULT_WIDTH, DEFAULT_HEIGHT);
	state := mx_core.state_data {};
	input := mx_input.input_state {};

	image_data := #load("assets/asset.png");
	glyph_data := #load("assets/asset");

	if font_image, font_map, max_height, success := mx_parser.ParseTTF(image_data, glyph_data); success {
		fmt.println("Size of font_map: ", len(font_map))
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

		for xlib.EventsQueued(display, .QueuedAfterReading) != 0 {
			event := xlib.XEvent {};
			xlib.NextEvent(display, &event);

			#partial switch event.type {
				case xlib.EventType.MotionNotify:
					motion : xlib.XMotionEvent = event.xmotion;
					input.mouse_x = motion.x;
					input.mouse_y = motion.y;

					signal.absolute_x = motion.x_root;
					signal.absolute_y = motion.y_root;
				case xlib.EventType.ButtonPress:
					pressed_button : xlib.XButtonEvent = event.xbutton;
					
					// What about right click?
					if      pressed_button.button == xlib.MouseButton.Button1 && (pressed_button.state & xlib.InputMask { .Button1Mask } == {}) do input.left_press = true;
					else if pressed_button.button == xlib.MouseButton.Button3 && (pressed_button.state & xlib.InputMask { .Button3Mask } == {}) do input.right_press = true; 
					else if pressed_button.button == xlib.MouseButton.Button4 && (pressed_button.state & xlib.InputMask { .Button4Mask } == {}) do input.scroll = 1.0; 
				case xlib.EventType.ButtonRelease:
					released_button : xlib.XButtonEvent = event.xbutton;

					if      released_button.button == xlib.MouseButton.Button1 && (released_button.state & xlib.InputMask { .Button1Mask } != {}) do input.left_press = false;
					else if released_button.button == xlib.MouseButton.Button3 && (released_button.state & xlib.InputMask { .Button3Mask } != {}) do input.right_press = false; 
					else if released_button.button == xlib.MouseButton.Button5 && (released_button.state & xlib.InputMask { .Button5Mask } != {}) do input.scroll = -1.0; 
				case xlib.EventType.KeyPress:
					pressed_key : xlib.XKeyEvent = event.xkey;

					key := TranslateKey(xlib.KeycodeToKeysym(display, cast(u8) pressed_key.keycode, 0));
					mx_input.UpdateInputState(&input, key, .PRESSED);
				case xlib.EventType.KeyRelease:
					released_key : xlib.XKeyEvent = event.xkey;

					if xlib.EventsQueued(display, .QueuedAfterReading) != 0 {
						next_event := xlib.XEvent {};
						xlib.PeekEvent(display, &next_event)

						is_keypress := next_event.type == xlib.EventType.KeyPress;
						same_time := next_event.xkey.time == released_key.time;
						same_code := next_event.xkey.keycode == released_key.keycode;

						if is_keypress && same_time && same_code do break;
					}
					
					key := TranslateKey(xlib.KeycodeToKeysym(display, cast(u8) released_key.keycode, 0));
					mx_input.UpdateInputState(&input, key, mx_input.key_state.RELEASED);

					if key == mx_input.mx_key.KEY_F12 {
						signal.should_fullscreen = !signal.should_fullscreen;
					}
				case xlib.EventType.ConfigureNotify:
					config_event := event.xconfigure;

					root_window := xlib.Window {};
					child_window := xlib.Window {};
					root_x : i32 = 0;
					root_y : i32 = 0;

					mouse_x : i32 = 0;
					mouse_y : i32 = 0;

					mask := xlib.KeyMask {};

					result := xlib.QueryPointer(
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
				case xlib.EventType.ClientMessage:
					client_event := event.xclient;

					if (client_event.data.l[0] == cast(int) close_window_atom) {
						signal.should_close = true;
						break;
					}
			}

			//continue;
		} 

		attrib := xlib.XWindowAttributes {};
		
		xlib.GetWindowAttributes(display, window, &attrib);
		

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
			//time.accurate_sleep(diff);
		}
	}
}

TranslateKey :: proc(keycode: xlib.KeySym) -> mx_input.mx_key {
	#partial switch(keycode) {
		case .XK_A, .XK_a: return mx_input.mx_key.KEY_A;
		case .XK_B, .XK_b: return mx_input.mx_key.KEY_B;
		case .XK_C, .XK_c: return mx_input.mx_key.KEY_C;
		case .XK_D, .XK_d: return mx_input.mx_key.KEY_D;
		case .XK_E, .XK_e: return mx_input.mx_key.KEY_E;
		case .XK_F, .XK_f: return mx_input.mx_key.KEY_F;
		case .XK_G, .XK_g: return mx_input.mx_key.KEY_G;
		case .XK_H, .XK_h: return mx_input.mx_key.KEY_H;
		case .XK_I, .XK_i: return mx_input.mx_key.KEY_I;
		case .XK_J, .XK_j: return mx_input.mx_key.KEY_J;
		case .XK_K, .XK_k: return mx_input.mx_key.KEY_K;
		case .XK_L, .XK_l: return mx_input.mx_key.KEY_L; 
		case .XK_M, .XK_m: return mx_input.mx_key.KEY_M;
		case .XK_N, .XK_n: return mx_input.mx_key.KEY_N;
		case .XK_O, .XK_o: return mx_input.mx_key.KEY_O;
		case .XK_P, .XK_p: return mx_input.mx_key.KEY_P;
		case .XK_Q, .XK_q: return mx_input.mx_key.KEY_Q;
		case .XK_R, .XK_r: return mx_input.mx_key.KEY_R;
		case .XK_S, .XK_s: return mx_input.mx_key.KEY_S;
		case .XK_T, .XK_t: return mx_input.mx_key.KEY_T;
		case .XK_U, .XK_u: return mx_input.mx_key.KEY_U;
		case .XK_V, .XK_v: return mx_input.mx_key.KEY_V;
		case .XK_W, .XK_w: return mx_input.mx_key.KEY_W;
		case .XK_X, .XK_x: return mx_input.mx_key.KEY_X;
		case .XK_Y, .XK_y: return mx_input.mx_key.KEY_Y;
		case .XK_Z, .XK_z: return mx_input.mx_key.KEY_Z;

	 	case .XK_period:   return mx_input.mx_key.KEY_PERIOD;
		case .XK_0:        return mx_input.mx_key.KEY_0;
		case .XK_1:        return mx_input.mx_key.KEY_1;
		case .XK_2:        return mx_input.mx_key.KEY_2;
		case .XK_3:        return mx_input.mx_key.KEY_3;
		case .XK_4:        return mx_input.mx_key.KEY_4;
		case .XK_5:        return mx_input.mx_key.KEY_5;
		case .XK_6:        return mx_input.mx_key.KEY_6;
		case .XK_7:        return mx_input.mx_key.KEY_7;
		case .XK_8:        return mx_input.mx_key.KEY_8;
		case .XK_9:        return mx_input.mx_key.KEY_9;

		case .XK_F1:       return mx_input.mx_key.KEY_F1;
		case .XK_F2:       return mx_input.mx_key.KEY_F2;
		case .XK_F3:       return mx_input.mx_key.KEY_F3;
		case .XK_F4:       return mx_input.mx_key.KEY_F4;
		case .XK_F5:       return mx_input.mx_key.KEY_F5;
		case .XK_F6:       return mx_input.mx_key.KEY_F6;
		case .XK_F7:       return mx_input.mx_key.KEY_F7;
		case .XK_F8:       return mx_input.mx_key.KEY_F8;
		case .XK_F9:       return mx_input.mx_key.KEY_F9;
		case .XK_F10:      return mx_input.mx_key.KEY_F10;
		case .XK_F11:      return mx_input.mx_key.KEY_F11;
		case .XK_F12:      return mx_input.mx_key.KEY_F12;


		case .XK_Tab:       return mx_input.mx_key.KEY_TAB;
		case .XK_Shift_L:   return mx_input.mx_key.KEY_LSHIFT;
		case .XK_Control_L: return mx_input.mx_key.KEY_LCTRL;
		case .XK_Escape:    return mx_input.mx_key.KEY_ESC;
		case .XK_Delete:    return mx_input.mx_key.KEY_DELETE;
		case .XK_BackSpace: return mx_input.mx_key.KEY_BACKSPACE;
		case .XK_minus:     return mx_input.mx_key.KEY_DASH;
		case .XK_Left:      return mx_input.mx_key.KEY_LEFT;
		case .XK_Right:     return mx_input.mx_key.KEY_RIGHT;
		case .XK_space:     return mx_input.mx_key.KEY_SPACE;

		case: return mx_input.mx_key.KEY_UNKNOWN;
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
	dir, err := os.get_working_directory(context.temp_allocator);
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

	os_err := os.set_working_directory(write_to);
	defer os.set_working_directory(dir);

	if os_err != os.ERROR_NONE do return;

	desktop_entry_name := strings.concatenate({title, ".desktop"}, context.temp_allocator);

	if os.exists(desktop_entry_name) do return; 

	desktop_fd, desktop_err := os.open(desktop_entry_name, { .Create, .Write, .Trunc }, { .Read_User, .Write_User });
	defer os.close(desktop_fd);

 	if desktop_err != os.ERROR_NONE {
 		fmt.println("Failed to open file: ", desktop_err);
 		return;
 	}; 

 	os.write_string(desktop_fd, fmt.tprintf(DESKTOP_ENTRY_FILE, title, path_to_binary));
}

SetWindowName :: proc(display: ^xlib.Display, window: xlib.Window, title: string) {
	name := xlib.InternAtom(display, "_NET_WM_NAME", false);
	icon_name := xlib.InternAtom(display, "_NET_WM_ICON_NAME", false);
	utf_string := xlib.InternAtom(display, "UTF8_STRING", false);

	xlib.ChangeProperty(display, window, name, utf_string, 8, PropModeReplace, raw_data(title), cast(i32) len(title));
	xlib.ChangeProperty(display, window, icon_name, utf_string, 8, PropModeReplace, raw_data(title), cast(i32) len(title));

	res_class, err_1 := strings.clone_to_cstring(title, context.temp_allocator);
	res_name, err_2 := strings.clone_to_cstring(strings.to_lower(title, context.temp_allocator));


	hint := xlib.XClassHint { res_class, res_name };

	res_, err_ := strings.clone_to_cstring(strings.to_lower(title, context.temp_allocator))

	xlib.SetClassHint(display, window, &hint);
}

SetOtherProperties :: proc(display: ^xlib.Display, window: xlib.Window) {
	window_type := xlib.InternAtom(display, "_NET_WM_WINDOW_TYPE", false);
	normal_type := xlib.InternAtom(display, "_NET_WM_WINDOW_TYPE_NORMAL", false);
	atom_ := xlib.InternAtom(display, "ATOM", false);
	
	allowed_actions := xlib.InternAtom(display, "_NET_WM_ALLOWED_ACTIONS", false);
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

	allowed_atoms := make([]xlib.Atom, len(requested_actions));
	defer delete(allowed_atoms);

	xlib.InternAtoms(display, raw_data(requested_actions), cast(i32) len(requested_actions), false, &allowed_atoms[0]);

	xlib.ChangeProperty(display, window, allowed_actions, allowed_actions, 32, PropModeReplace, cast(^u8) raw_data(allowed_atoms) , cast(i32) len(requested_actions));
	xlib.ChangeProperty(display, window, window_type, atom_, 32, PropModeReplace, cast(^u8) &normal_type, 1);
}


SetWindowType :: proc(display: ^xlib.Display, window: xlib.Window) {
	window_type_atom := xlib.InternAtom(display, "_NET_WM_WINDOW_TYPE", false);
	splash_type := xlib.InternAtom(display, 	"_NET_WM_WINDOW_TYPE_NORMAL", false);

	xlib.ChangeProperty(display, window, window_type_atom, XA_ATOM, 32, PropModeReplace, cast(^u8) &splash_type, 1);
}

SetWindowFrameExtents :: proc(display: ^xlib.Display, window: xlib.Window, size: f32) {
	frame_atom := xlib.InternAtom(display, "_NET_FRAME_EXTENTS", false);
	frames := [4]f32 { size, size, size, size };

	xlib.ChangeProperty(display, window, frame_atom, XA_CARDINAL, 32, PropModeReplace, cast(^u8) &frames[0], 4);
}

MakeBorderless :: proc(display: ^xlib.Display, window: xlib.Window) {
	MotifWMHints :: struct {
	    flags: mwm_flags,
	    functions : mwm_functions,
	    decorations: u64,
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

	mwmHintsProperty := xlib.InternAtom(display, "_MOTIF_WM_HINTS", true);
	window_hints := MotifWMHints {
		flags = .DECORATIONS | .FUNCTIONS,
		decorations = 0,
		functions = .ALL,
	};

	fmt.println(window_hints, size_of(window_hints));

	xlib.ChangeProperty(display, window, mwmHintsProperty, mwmHintsProperty, 8, PropModeReplace, cast(^u8) &window_hints, 5);
}

ToggleFullscreen :: proc(display: ^xlib.Display, window: xlib.Window, is_fullscreen: ^bool)
{	
	event := xlib.XEvent {};
	state_atom := xlib.InternAtom(display, "_NET_WM_STATE", false);
	fullscreen_atom := xlib.InternAtom(display, "_NET_WM_STATE_FULLSCREEN", false);

	PropertyAction :: enum {
		REMOVE = 0x0,
		SET_OR_ADD = 0x1,
		TOGGLE = 0x2,
	};

	action : i64 = ---; 

	if is_fullscreen^ {
		action = i64(PropertyAction.REMOVE);
		is_fullscreen^ = false;
		xlib.UngrabPointer(display, xlib.CurrentTime);
	} else {
		action = i64(PropertyAction.SET_OR_ADD);
		is_fullscreen^ = true; 
		xlib.GrabPointer(display, window, true, xlib.EventMask {}, xlib.GrabMode.GrabModeAsync, xlib.GrabMode.GrabModeAsync, window, xlib.None, xlib.CurrentTime);
	}

	event.xclient.type = xlib.EventType.ClientMessage;
	event.xclient.serial = 0;
	event.xclient.send_event = true;
	event.xclient.window = window;
	event.xclient.message_type = state_atom;
	event.xclient.format = 32;
	event.xclient.data.l[ 0 ] = cast(int) action;
	event.xclient.data.l[ 1 ] = cast(int) fullscreen_atom;
	event.xclient.data.l[ 2 ] = 0;
	event.xclient.data.l[ 3 ] = 0;

	xlib.SendEvent(display, xlib.DefaultRootWindow(display), false, xlib.EventMask { .SubstructureRedirect, .SubstructureNotify }, &event);
	xlib.Sync(display, true);
}
/*
// Is there an event we can listen to?
CurrentAttachedScreens :: proc(display: ^xlib.XDisplay) -> [16]int {
	for screen_idx : i32 = 0; screen_idx < ScreenCount(display); screen_idx += 1 {
		screen_ptr := ScreenOfXDisplay(display, screen_idx);

		screen_height := XDisplayHeight(display, screen_idx);
		screen_width := XDisplayWidth(display, screen_idx);

		// xrandr ! If you want to get the names / vendor information.
	}

	return [16]int {};
}
*/

CopyToClipboard :: proc(display: ^xlib.Display, window: xlib.Window, data: []u8) {
	// TODO(G)
}


InitOpenGL :: proc(display: ^xlib.Display, window: xlib.Window, screen: i32, config: glx.GLXFBConfig) -> (glx.GLXContext, bool)
{
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
		        xlib.None,
		    };
	    } else {
	        modern_context_attributes := []i32 {
		       	glx.CONTEXT_MAJOR_VERSION_ARB, mx_renderer.GL_MAJOR_VERSION,
		        glx.CONTEXT_MINOR_VERSION_ARB, mx_renderer.GL_MINOR_VERSION,
		        glx.CONTEXT_FLAGS_ARB, glx.CONTEXT_FORWARD_COMPATIBLE_BIT_ARB,
		        glx.CONTEXT_PROFILE_MASK_ARB, glx.CONTEXT_CORE_PROFILE_BIT_ARB, 
		        xlib.None,
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

	xlib.Sync(display, true);

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
	vendor := string(gl.GetString(gl.VENDOR));
	renderer := string(gl.GetString(gl.RENDERER));
	version := string(gl.GetString(gl.VERSION));

	fmt.println(vendor, "::", renderer, "::", version);
}


CreateContextAttribsARBProxy :: proc(display: ^xlib.Display, config: glx.GLXFBConfig, gl_context:  glx.GLXContext, direct: bool, attributes: ^i32) -> glx.GLXContext;
SwapIntervalEXTProxy :: proc(dpy: ^glx._XDisplay, drawable: glx.Drawable, interval: int);


GetMonitorInfo :: proc(display: ^xlib.Display, window: xlib.Window) -> (i32, i32, i32) {
	width, height, refresh : i32 = 0, 0, 0;

	monitor_count : i32 = 0;
	monitors := xrandr.GetMonitors(cast(^xrandr._XDisplay) display, cast(u64) window, 1, &monitor_count);
	defer xrandr.FreeMonitors(monitors);

	assert(monitor_count != 0, "Monitor count is 0.");

	for idx in 0..=monitor_count-1 {
		monitor_info_ := mem.ptr_offset(monitors, idx);
		if monitor_info_.primary > 0 {
			width = monitor_info_.width;
			height = monitor_info_.height;
		}
	}

	info := xrandr.GetScreenInfo(cast(^xrandr._XDisplay) display, cast(u64) window);
	defer xrandr.FreeScreenConfigInfo(info);
	
	refresh = cast(i32) xrandr.ConfigCurrentRate(info);

	return width, height, refresh;
}


IsExtensionSupported :: proc(gl_extensions: ^string, extension: string) -> bool {
	for ext in strings.split_iterator(gl_extensions, " ") {
		if ext == extension do return true; 
	}

	return false; 
}

GetPointerCoordinates :: proc(display: ^xlib.Display, window: xlib.Window) -> (i32, i32) {
	root_window : xlib.Window; 
	child_window : xlib.Window;
	root_x, root_y : i32 = 0, 0;
	win_x, win_y : i32 = 0, 0;
	mask := xlib.KeyMask.ShiftMask;

	result := xlib.QueryPointer(display, window, &root_window, &child_window, &root_x, &root_y, &win_x, &win_y, &mask);
	
	// Coordinates are relative to the window top left corner, meaning they can be negative.

	return max(0, win_x), max(0, win_y);
}