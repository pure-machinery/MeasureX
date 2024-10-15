package mx_ui


import "../mx_renderer";
import "../mx_chain";
import "../mx_input";

import "core:fmt";
import "core:reflect";
import "core:math/rand";
import "core:math/bits";
import "core:mem";
import "core:hash";
import "base:runtime";
import "core:math";
import "core:strings"

import "../../profiler";

UI : ui_context = { 
	hot      = -1,
	active   = -1,
	focused  = -1, 
	last_hot = -1,

	delta_time = 0.0,
	hover_time = 0.0,

	mouse_x = -1.0,
	mouse_y = -1.0,

	screen_x = 0.0,
	screen_y = 0.0,

	left_press  = false,

	text_delete_timer = 0.0,
	text_delete_threshold = 0.25,

	text_input_stall_timer = 0.0,
	text_input_stall_threshold = 0.25,
};

DEFAULT_STYLE_COUNT :: 32

// The style should go per widget perhaps:
// Eg we have button style: 
// 

default_style := ui_style {
		background_color = [4]f32 { 0.1, 0.1, 0.1, 1.0 },
		background_color_hover = [4]f32 { 0.239, 0.239, 0.239, 1.0 },
		background_color_press = [4]f32 { 0.3, 0.3, 0.3, 1.0 },

		border_thickness = 1.0,
		border_color = [4]f32 { 0.8, 0.8, 0.8, 1.0 },
		border_color_press = [4]f32 { 0.2, 0.8, 0.8, 1.0 },
		border_color_hover = [4]f32 { 0.1, 0.8, 0.8, 1.0 },

		text_color_default = [4]f32 { 0.8, 0.8, 0.8, 1.0 },
		text_color_hover = [4]f32 { 0.1, 0.8, 0.8, 1.0 },
		text_size_default = 20.0,

		default_padding = 5.0, 
};

ui_descriptor :: struct {
	mouse_x: f32,
	mouse_y: f32,
	screen_x: f32,
	screen_y: f32,
}


ui_axis :: enum {
	X_AXIS = 0,
	Y_AXIS = 1,
}



// NOTE(G): Offset represents how much pixels the next widget on the given axis should be.
/*
ui_layout :: struct {
	axis: ui_axis,
	offset: f32,
}
*/

UiGetDescriptor :: proc() -> ui_descriptor
{
	desc := ui_descriptor {};
	desc.mouse_x = UI.mouse_x;
	desc.mouse_y = UI.mouse_y;
	desc.screen_x = UI.screen_x;
	desc.screen_y = UI.screen_y;

	return desc;
}

ui_state :: enum 
{
	IDLE = 0x0,
	HOVER = 0x1,
	PRESSED = 0x2,
	DRAGGED = 0x4,
	CLICK = 0x8,
}

@(private="file")
ui_id :: int;

ui_context :: struct
{
	hot:    ui_id,
	active: ui_id,
	focused: ui_id,

	last_hot: ui_id,
	last_focused: ui_id,

	delta_time: f32,
	hover_time: f32, 
	frame_index: uint,

	mouse_x, mouse_y: f32,
	mouse_scroll: f32, 

	last_mouse_x, last_mouse_y: f32,
	screen_x, screen_y: f32,

	left_press: bool, 
	// Do we need all of this?
	ctx: ^mx_renderer.graphics_context,
	input: ^mx_input.input_state,

	// We need a hashmap here so we can just overwrite the specific data of widgets?
	internal_count : u64, 

	string_data: []u8, 
	string_data_offset: int,

	widgets: [dynamic]ui_widget,
	last_widgets: [dynamic]ui_widget, 

	styles : [dynamic]ui_style,
	active_style: int,

	screen: ^ui_widget,
	parent: ^ui_widget,

	// TODO(G): See how this can go outside the ui_context?
	input_buffer: gap_buffer,

	text_delete_timer: f32,
	text_delete_threshold: f32, 

	text_input_stall_timer: f32,
	text_input_stall_threshold: f32,

	key_skip_next_char_duration: f32,
	key_skip_next_char: bool,

	key_skip_prev_char_duration: f32,
	key_skip_prev_char: bool,

	key_delete_prev_char_duration: f32,
	key_delete_prev_char: bool,


}

ui_widget_response :: struct {
	widget: ^ui_widget,

	hovered: bool,
	single_clicked: bool,
	double_clicked: bool,
	right_clicked: bool,
	pressed: bool,
	released: bool,
	dragged: bool,
	scroll: f32,
	focused: bool,
	
	active: bool,
}


_ui_widget_flags :: enum u16 {
	DRAW_INTERACTIVE,
	DRAW_CLIPPED,
	DRAW_BACKGROUND,
	DRAW_TEXT,
	DRAW_BORDER,
	DRAW_HOT_ANIMATION,
	DRAW_ACTIVE_ANIMATION,
	DRAW_DISABLED,
	DRAW_FOCUSED,
}

ui_widget_flags :: bit_set [_ui_widget_flags];


ui_widget_size_kind :: enum u16 {
	SIZE_NONE,
	SIZE_BY_PIXELS,
	SIZE_BY_TEXT,
	SIZE_BY_SCALE,
	// TODO(G): Find a way to avoid "SIZE_BY_EXPAND".
	SIZE_BY_EXPAND,
	SIZE_BY_CHILDREN,
}


ui_widget_size_config :: struct {
	kind: ui_widget_size_kind,
	value: f32,
}

// TODO(G): Perhaps compact this struct?
ui_widget :: struct #align(32) {
	// Specifies the first / last widget in the hierarchy below (one depth below).
	first_child: ^ui_widget,
	last_child: ^ui_widget,
	// Specifies the next/previous widgets in the same depth.
	next_sibling: ^ui_widget,
	prev_sibling: ^ui_widget,
	// Parent widget.
	parent: ^ui_widget,
	
	// Generation info.
	unique_id: ui_id, 
	frame_added: uint,

	// Per-frame info:
	// flags: ui_widget_flags,
	text: string,
	style: int, 

	// Calculated every frame:
	size: [2]ui_widget_size_config,

	// Can we expand the layout? 
	layout:     ui_axis,
	override_layout: bool, 

	flags: ui_widget_flags,
	rect:       ui_rect,
	clipping_rect: ui_rect,
	
	computed_size: [2]f32,
	at:            [2]f32,

	offset:        [2]f32,
	// Persists across frames. 
	hover_time: f32,
	press_time: f32, 
	time_since_last_interaction: f32,
}

ui_style :: struct 
{
	background_color: [4]f32,
	background_color_hover: [4]f32,
	background_color_press: [4]f32, 

	border_thickness: f32, 
	border_color: [4]f32,
	border_color_press: [4]f32,
	border_color_hover: [4]f32,

	// Text can be global. 
	text_color_default: [4]f32,
	text_color_hover: [4]f32,
	text_size_default: f32,

	default_padding: f32, 
	default_radius: [4]f32,
}

ui_rect :: mx_renderer.rectangle;


UiGenerateID :: proc(text: string, location := #caller_location) -> ui_id {
	//return cast(int) hash.murmur64a(transmute([]u8) text);
	return cast(int) hash.fnv64a(transmute([]u8) text);
}


UiGetWidgetResponse :: proc(widget: ^ui_widget, location := #caller_location) -> ui_widget_response {
	assert(widget.flags & { .DRAW_INTERACTIVE } != {}, fmt.tprintf("Widget (%s) has no interaction flag set. @ %s\n", widget.text, location));

	result := ui_widget_response {};

	// TODO(G): Intersect it with the clipping rect.
	// if it's in the clipping rect and in the casual rect.
	is_inside := UiContainsMousePosition(widget.rect);

	if (UI.active == 0 || UI.active == widget.unique_id) && is_inside { 
		result.hovered = true;
		UI.hot = widget.unique_id;

		widget.hover_time += UI.delta_time;
	} else {
		widget.hover_time = max(0, widget.hover_time - UI.delta_time);
	}
	// Might be good for dragging widgets.z
	//is_near := mx_input.IsInCursorProximity(UI.last_mouse_x, UI.last_mouse_y, UI.mouse_x, UI.mouse_y)

	if UI.active == 0 && result.hovered && UI.left_press {
		UI.active = widget.unique_id;
		result.active = true; 
	}

	if UI.active == widget.unique_id {
		result.pressed = true; 
		widget.press_time += UI.delta_time;		
	} else {
		widget.press_time = max(0, widget.press_time - UI.delta_time);
	}
	// TODO(G): Implement dragging.

	if result.hovered && widget.unique_id == UI.active && UI.left_press == false {
		result.single_clicked = true;
		
		fmt.println("Focused: ", widget.unique_id, widget.text);
		UI.focused = UI.active;
	}

	if !result.hovered {
		widget.time_since_last_interaction += UI.delta_time;
	} else {
		widget.time_since_last_interaction = max(0, widget.time_since_last_interaction - UI.delta_time);
	}

	return result;
}


UiFindWidgetByHash :: proc(hash: int, last_frame: bool) -> ^ui_widget {
	which := UI.widgets;

	if last_frame {
		which = UI.last_widgets;
	}

 	for _, i in UI.last_widgets {
		w := &UI.last_widgets[i];
		if hash == w.unique_id do return w;
	}

	return nil;
}

UiMakeWidget :: proc(parent: ^ui_widget, flags: ui_widget_flags, size_x, size_y: ui_widget_size_config, layout: ui_axis, text: string) -> ^ui_widget {
	display := text; 
	hash := fmt.tprintf("ui_node_%d", UI.internal_count);

	if res, ok := strings.split(text, "##", context.temp_allocator); ok == .None && len(res) == 2 {
		display = res[0];
		hash = res[1];
	}

	widget := ui_widget {
		flags = flags,
		size = { size_x, size_y },
		unique_id = UiGenerateID(hash),
		text = display,
		parent = parent,
		frame_added = UI.frame_index,
		layout = layout,
		style = UI.active_style,
	};

	if found := UiFindWidgetByHash(widget.unique_id, true); found != nil {
		// The rect is saved because of the interaction events. Since we calculate the size in the end of the frame.
		widget.text = display;
		widget.rect = found.rect;
		widget.hover_time = found.hover_time;
		widget.press_time = found.press_time;
		widget.time_since_last_interaction = found.time_since_last_interaction;
		// Test:
	}

	result : ^ui_widget = nil; 

	append(&UI.widgets, widget);
	result = &UI.widgets[UI.internal_count];
	
	if parent.first_child == nil {
		parent.first_child = result; 
	} else {
		parent.last_child.next_sibling = result;
		result.prev_sibling = parent.last_child;
	}

	parent.last_child = result;

	UI.internal_count += 1;

	return result;
}

UiDrawWidget :: proc(widget: ^ui_widget) {
	if widget.flags == {} do return; 

	response := ui_widget_response {};
	color := [4]f32{};
	border_color := [4]f32{};
	border_thickness : f32 = 0.0;

	style := UI.styles[widget.style];

	if widget.flags & { .DRAW_INTERACTIVE } != {} { 
		response = UiGetWidgetResponse(widget);
		// TEMP:
		color = { 0.125, 0.125, 0.125, 1.0 };
		border_color := [4]f32 { 0.5, 1.0, 0.0, 1.0 };
		border_thickness : f32 = 1.0;
	} 

	if widget.flags & { .DRAW_BACKGROUND } != {} do color = style.background_color; 

	if widget.flags & { .DRAW_BORDER } != {} {
		border_color = style.border_color;
		border_thickness = style.border_thickness;

		if response.hovered do border_color = style.border_color_hover;
		if response.pressed do border_color = style.border_color_press;
		if response.active do border_color = { 0.25, 0.1, 0.7, 1.0 };
	}

	mx_renderer.PushRectangle(UI.ctx, widget.rect, color, {}, border_color, border_thickness);
	
	when ODIN_DEBUG do mx_renderer.PushRectangleBorder(UI.ctx, widget.rect, { 1.0, 0.0, 0.0, 1.0 }, 1.0);

	// This needs to go after the background drawing!
	if widget.flags & { .DRAW_TEXT } != {} {
		color := style.text_color_default;

		if response.hovered do color = style.text_color_hover;

		//x, y := UiRectGetCenter(widget.rect);
		attribs := mx_renderer.string_attributes {
			text = widget.text,
			justify = .MIDDLE,
			font_size = style.text_size_default, 
		}

		mx_renderer.PushString(UI.ctx, widget.rect, color, attribs);
	}

}


UiRectNewCenter :: proc(x,y: f32, width, height: f32) -> ui_rect
{
	half_w := width  * 0.5;
	half_h := height * 0.5;

	rect : ui_rect = {
		min_x = x - half_w,
		min_y = y - half_h,
		max_x = x + half_w,
		max_y = y + half_h,
	};

	return rect; 
}

UiRectGetCenter :: proc(rect: ui_rect) -> (f32, f32)
{
	x := (rect.max_x - rect.min_x) * 0.5 + rect.min_x;
	y := (rect.max_y - rect.min_y) * 0.5 + rect.min_y;

	return x, y;
}

UiRectMinMax :: proc(min_x, min_y, max_x, max_y : f32) -> ui_rect
{
	rect : ui_rect = {
		min_x = min_x,
		min_y = min_y,
		max_x = max_x,
		max_y = max_y,
	};

	return rect;
}

UiRectGetDimensions :: proc(rect: ui_rect) -> (f32, f32)
{
	width := rect.max_x - rect.min_x;
	heigth := rect.max_y - rect.min_y;

	return width, heigth;
}

UiRectScale :: proc(rect: ^ui_rect, factor: f32) 
{	

	width, height := UiRectGetDimensions(rect^);

	half_scale := abs(factor) * 0.5;

	half_width := width * half_scale;
	half_height := height * half_scale;

	x, y := UiRectGetCenter(rect^);

	rect.max_x = x + half_width;
	rect.min_x = x - half_width;
	rect.max_y = y + half_height;
	rect.min_y = y - half_height;	
}


UiSetStyle :: proc(style: ui_style) {
	append(&UI.styles, style);
	UI.active_style = len(UI.styles) - 1;
}

UiResetStyle :: proc() {
	UI.active_style = 0;
}



UiInitialize :: proc(ctx: ^mx_renderer.graphics_context, input: ^mx_input.input_state, total_widgets := 512) {
	// TODO(G): Perhaps make these slices? 
	UI.widgets = make_dynamic_array_len_cap([dynamic]ui_widget, 0, total_widgets);
	UI.last_widgets = make_dynamic_array_len_cap([dynamic]ui_widget, 0, total_widgets);
	UI.styles = make_dynamic_array_len_cap([dynamic]ui_style, 0, DEFAULT_STYLE_COUNT);
	UI.input_buffer = InitGapBuffer(10);

	UI.ctx = ctx;
	UI.input = input;
	
	fmt.println("Size of ui_widget struct: ", size_of(ui_widget), align_of(ui_widget));
}

UiBegin :: proc(mouse_x, mouse_y : f64, scroll: f32,  screen_width: i32, screen_height: i32, left_press: bool, dt: f32, frame: uint)
{
	UI.left_press  = left_press;

	UI.mouse_x = cast(f32) mouse_x; 
	UI.mouse_y = cast(f32) mouse_y; 
	UI.mouse_scroll = scroll;

	UI.delta_time = dt; 
	UI.frame_index = frame;

	UI.hot = 0;
	UI.internal_count = 0;

	UI.screen_x = cast(f32) screen_width;
	UI.screen_y = cast(f32) screen_height;
	
	screen_widget := ui_widget {};
	screen_widget.rect = UiRectMinMax(0, 0, UI.screen_x, UI.screen_y);
	screen_widget.computed_size = { UI.screen_x, UI.screen_y };
	screen_widget.text = "screen_widget";
	screen_widget.unique_id = UiGenerateID(screen_widget.text);
	screen_widget.frame_added = UI.frame_index;
	screen_widget.layout = .Y_AXIS;
	
	append(&UI.widgets, screen_widget);
	append(&UI.styles, default_style);

	UI.parent = &UI.widgets[UI.internal_count];
	UI.screen = UI.parent;
	UI.internal_count += 1;
	/*
	if mx_input.KeyJustReleased(UI.input, .KEY_TAB) && UI.internal_count > 0 {
		// If no focused search for first active widget.
		// previous <- current -> next ...
		
		if UI.focused == -1 {
			// Move this to top level UI context ?? 
			stack := make_dynamic_array_len_cap([dynamic]^ui_widget, 0, cap(UI.widgets), context.temp_allocator);
			defer delete(stack);

			append(&stack, UI.screen);
			for node, ok := pop_safe(&stack); node != nil && ok; node, ok = pop_safe(&stack) {
				fmt.println(node.text);
				if node.flags & { .DRAW_INTERACTIVE } != {} {
					//UI.focused = node.unique_id;
					fmt.println("Focused", UI.focused, node.text);
					//break; 
				}

				for child := node.last_child; child != nil; child = child.prev_sibling do append(&stack, child);
			}
		}
	}
	*/
}


UiEnd :: proc() 
{
	// If there is no left press set active to 0. - else 
	// if there is left press this frame and active is 0 
	if UI.left_press == false do UI.active = 0;
	else if UI.active == 0 do UI.active = -1;

	UI.last_hot = UI.hot;

	UI.last_mouse_x = UI.mouse_x;
	UI.last_mouse_y = UI.mouse_y;


	// Will reallocate only if current capacity can't handle the length.
	resize(&UI.last_widgets, len(UI.widgets));
	copy_slice(UI.last_widgets[:], UI.widgets[:]); 

	clear(&UI.widgets);	
	clear(&UI.styles);
}


@(private="file")
UiContainsMousePosition :: proc(rect: ui_rect) -> bool 
{	
	inside_x := (rect.min_x < UI.mouse_x && rect.max_x > UI.mouse_x);
	inside_y := (rect.min_y < UI.mouse_y && rect.max_y > UI.mouse_y);

	return inside_x && inside_y;
}


AnimateValue :: proc(value : f32) -> f32 {
	return value == 1 ? 1 : 1 - math.pow(2, -10 * value);
}

UiCalculateWidgetPosition :: proc(widget: ^ui_widget, axis: ui_axis) {
	if widget.parent == nil do return; 

	parent := widget.parent;

	if !widget.override_layout {
		idx := cast(int) parent.layout;

		pos := [2]f32 { parent.rect.min_x, parent.rect.min_y };

		pos[idx] += parent.at[idx];

		parent.at[idx] += widget.computed_size[idx];

		widget.rect = { 
			pos.x, 
			pos.y,
			pos.x + widget.computed_size.x, 
			pos.y + widget.computed_size.y, 
		}; 

	} else {
		// Minimal values should be provided manually by the user.
		widget.rect.max_x = widget.rect.min_x + widget.computed_size.x;
		widget.rect.max_y = widget.rect.min_y + widget.computed_size.y;
	}

}


Debug :: proc(widget, parent: ^ui_widget) {
	fmt.printf("%-20s %-20d %-5f %-5f %-5f %-5f %-5f %-5f %-20s %-5f %-5f %-5f %-5f %-20d\n",
		parent.text, parent.unique_id, parent.at.x, parent.at.y,
		parent.rect.min_x, parent.rect.min_y, parent.rect.max_x, parent.rect.max_y, 
		widget.text, 
		widget.rect.min_x, widget.rect.min_y, widget.rect.max_x, widget.rect.max_y,
		widget.unique_id,
	);	
}

UiCalculateIndependentSize :: proc(axis: ui_axis) {
	for _, i in UI.widgets {
		widget := &UI.widgets[i];
		result := &widget.computed_size[cast(int) axis];

		#partial switch size := widget.size[axis]; size.kind {
			case .SIZE_BY_PIXELS:
				result^ = size.value;
			case .SIZE_BY_TEXT: 
				style := UI.styles[UI.active_style];
				switch axis {
					case .X_AXIS:
						result^ = size.value * mx_renderer.GetTextWidth(UI.ctx, widget.text, style.text_size_default) + 2.0 * style.default_padding;
					case .Y_AXIS:
						result^ = size.value * mx_renderer.GetTextHeight(UI.ctx, widget.text, style.text_size_default) + 2.0 * style.default_padding;
				}
		} 
	}
}

UiCalculateUpwardDependentSize :: proc(widget: ^ui_widget, axis: ui_axis) {
	if widget.parent == nil do return; 

	parent_size := widget.parent.computed_size[cast(int) axis];
	result := &widget.computed_size[cast(int) axis];

	#partial switch size := widget.size[cast(int) axis]; size.kind {
		case .SIZE_BY_SCALE:
			result^ = size.value * parent_size;
	} 	
}

UiCalculateDownwardDependentSize :: proc(widget: ^ui_widget, axis: ui_axis) {
	result := &widget.computed_size[cast(int) axis];

	#partial switch size := widget.size[cast(int) axis]; size.kind {
		case .SIZE_BY_CHILDREN:
			for child := widget.first_child; child != nil; child = child.next_sibling {
				result^ += child.computed_size[cast(int) axis];
			}		
	}	
}

UiCalculateSiblingDependentSize :: proc(widget: ^ui_widget, axis: ui_axis) {
	if widget.parent == nil do return;

	result := &widget.computed_size[cast(int) axis];
	parent_size := widget.parent.computed_size[cast(int) axis];
	
	parent := widget.parent; 
	// Can this be replaced with the ?
	#partial switch size := widget.size[cast(int) axis]; size.kind {	
		case .SIZE_BY_EXPAND:
			assert(parent.size[cast(int) axis].kind != .SIZE_BY_CHILDREN);

			occupied : f32 = 0.0;

			for node := parent.first_child; node != nil; node = node.next_sibling {
				occupied += node.computed_size[cast(int) axis];
			}

			result^ = parent_size - occupied;
	}
}

PrintResultWidget :: proc(widget: ^ui_widget, procedure: string) {
	if strings.compare(widget.text, "result_layout") == 0 {
		fmt.println(UI.frame_index, widget.rect, widget.computed_size, widget.at, widget.unique_id, procedure);
	}
}

UiLayoutPreorder :: proc(widget: ^ui_widget, axis: ui_axis, _calculate: proc(^ui_widget, ui_axis)) {
	if widget == nil do return; 

	_calculate(widget, axis);

	for sib := widget.first_child; sib != nil; sib = sib.next_sibling {
			UiLayoutPreorder(sib, axis, _calculate);
	}
}

UiLayoutPostorder :: proc(widget: ^ui_widget, axis: ui_axis, _calculate: proc(^ui_widget, ui_axis)) {
	if widget == nil do return;

	for sib := widget.first_child; sib != nil; sib = sib.next_sibling {
		UiLayoutPostorder(sib, axis, _calculate);
	}

	_calculate(widget, axis);
}

UiLayoutInorder :: proc(widget: ^ui_widget, axis: ui_axis, _calculate: proc(^ui_widget, ui_axis)) {
	if widget == nil do return; 

	for sib := widget.first_child; sib != nil; sib = sib.next_sibling {
		UiLayoutInorder(sib, axis, _calculate);
	}

	_calculate(widget, axis);
}

UiMakeLayout :: proc() {
	// Independent nodes.
	UiCalculateIndependentSize(.X_AXIS);
	UiCalculateIndependentSize(.Y_AXIS);
	// Downwards dependent nodes.
	UiLayoutPreorder(UI.screen, .X_AXIS, UiCalculateUpwardDependentSize);
	UiLayoutPreorder(UI.screen, .Y_AXIS, UiCalculateUpwardDependentSize);
	// Upwards dependent nodes.
	UiLayoutPostorder(UI.screen, .X_AXIS, UiCalculateDownwardDependentSize);
	UiLayoutPostorder(UI.screen, .Y_AXIS, UiCalculateDownwardDependentSize);
	// Sibling dependent nodes.
	UiLayoutPreorder(UI.screen, .X_AXIS, UiCalculateSiblingDependentSize);
	UiLayoutPreorder(UI.screen, .Y_AXIS, UiCalculateSiblingDependentSize);

	// We only need to calculate this once - and we don't need an axis.
	UiLayoutPreorder(UI.screen, {}, UiCalculateWidgetPosition);
}

UiFlushWidgets :: proc() {	
	stack := make_dynamic_array_len_cap([dynamic]^ui_widget, 0, cap(UI.widgets), context.temp_allocator);
	defer delete(stack);

	append(&stack, UI.screen);
	for node, ok := pop_safe(&stack); node != nil && ok; node, ok = pop_safe(&stack) {
		for child := node.last_child; child != nil; child = child.prev_sibling {
			append(&stack, child);
		}
	
		UiDrawWidget(node);
	}
}