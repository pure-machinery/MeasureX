package mx_ui


import "core:fmt"
import "core:math"
import "core:strings"
import "core:strconv"
import "base:intrinsics"
import "core:reflect"

import "../mx_renderer"
import "../mx_input"

UiLayout :: proc(parent: ^ui_widget, kind: [2]ui_widget_size_kind, size: [2]f32, layout: ui_axis) -> ^ui_widget {
	result := UiMakeWidget(
		parent,
		{ .DRAW_BACKGROUND },
		ui_widget_size_config { kind.x, size.x },
		ui_widget_size_config { kind.y, size.y },
		layout,
		{},
	);	

	return result;
}

UiSeparator :: proc(parent: ^ui_widget, value: f32) {
	x_size := ui_widget_size_config {};
	y_size := ui_widget_size_config {};

	#partial switch parent.layout {
		case .X_AXIS: 
			x_size = ui_widget_size_config { .SIZE_BY_PIXELS, value };
			y_size = ui_widget_size_config { .SIZE_BY_SCALE, 1.0 };
		case .Y_AXIS:
			x_size = ui_widget_size_config { .SIZE_BY_SCALE, 1.0 };
			y_size = ui_widget_size_config { .SIZE_BY_PIXELS, value };
	}

	UiMakeWidget(
		parent,
		{ .DRAW_BACKGROUND }, 
		x_size,
		y_size,
		{}, 
		{},
	);
}

UiButton :: proc(parent: ^ui_widget, text: string) -> ^ui_widget {
	result := UiMakeWidget(
		parent,
		{ .DRAW_TEXT, .DRAW_BACKGROUND, .DRAW_INTERACTIVE }, 
		ui_widget_size_config {	.SIZE_BY_TEXT, 1.0 },
		ui_widget_size_config { .SIZE_BY_SCALE, 1.0 },
		{},
		text,
	);

	return result;
}

UiLabel :: proc(parent: ^ui_widget, text: string) -> ^ui_widget {
	result := UiMakeWidget(
		parent,
		{ .DRAW_BACKGROUND, .DRAW_TEXT, }, 
		ui_widget_size_config {	.SIZE_BY_TEXT, 1.0 },
		ui_widget_size_config { .SIZE_BY_SCALE, 1.0 },
		{},
		text);

	return result;	
}

UiLabelScaled :: proc(parent: ^ui_widget, scale: f32, text: string) -> ^ui_widget {
	result := UiMakeWidget(
		parent,
		{ .DRAW_BACKGROUND, .DRAW_TEXT }, 
		ui_widget_size_config {	.SIZE_BY_SCALE, scale },
		ui_widget_size_config { .SIZE_BY_SCALE, 1.0 },
		{},
		text);	

	return result;
}

// TODO(G): Figure out how to implement this. Add a input buffer to the UI context.
UiTextEdit :: proc(parent: ^ui_widget, text: string) -> ui_widget_response {
	widget := UiMakeWidget(
		parent,
		{ .DRAW_BACKGROUND, .DRAW_INTERACTIVE, .DRAW_TEXT }, 
		ui_widget_size_config {	.SIZE_BY_TEXT, 1.0 },
		ui_widget_size_config { .SIZE_BY_SCALE, 1.0 },
		{},
		text);

	response := UiGetWidgetResponse(widget);

	return response;
}

UiTextEditScaled :: proc(parent: ^ui_widget, scale: f32, text: string) -> ^ui_widget {
	widget := UiMakeWidget(
		parent,
		{ .DRAW_BACKGROUND, .DRAW_INTERACTIVE, .DRAW_FOCUSED, .DRAW_TEXT }, 
		ui_widget_size_config {	.SIZE_BY_SCALE, scale },
		ui_widget_size_config { .SIZE_BY_SCALE, 1.0 },
		.X_AXIS,
		text);

	response := UiGetWidgetResponse(widget);
	
	if response.single_clicked {
		ResetGapBuffer(&UI.input_buffer);
		AppendString(&UI.input_buffer, widget.text);
		//fmt.println ("Gap buffer reset on: ", widget.text, string(UI.input_buffer.base[:]))
	}

	// This is the editing mode of the text!
	// UI.focused could be a pointer though.
	if response.focused {
		if last_widget := UiFindWidgetByHash(UI.last_focused, true); last_widget != nil {
			//fmt.println ("Editing: ", widget.unique_id, widget.text, "last", last_widget.text)	
	}
		// Cursor moving.
		if typed, elapsed := mx_input.KeysAreDownAny(UI.input, { .KEY_RIGHT }); typed != .KEY_UNKNOWN {
			threshold := UI.key_skip_char_duration == 0 || UI.key_skip_char_duration > UI.text_input_stall_threshold;
			if threshold { 
				GapMove(&UI.input_buffer, UI.input_buffer.gap_start + 1);
			}
		}

		if typed, elapsed := mx_input.KeysAreDownAny(UI.input, { .KEY_LEFT }); typed != .KEY_UNKNOWN {
			threshold := UI.key_skip_char_duration == 0 || UI.key_skip_char_duration > UI.text_input_stall_threshold;
			if threshold { 
				GapMove(&UI.input_buffer, UI.input_buffer.gap_start - 1);
			}
		}

		// Typing & deleting characters.
		keys := []mx_input.mx_key { .KEY_DASH, .KEY_PERIOD, .KEY_0, .KEY_1, .KEY_2, .KEY_3, .KEY_4, .KEY_5, .KEY_6, .KEY_7, .KEY_8, .KEY_9 }
		if typed, elapsed := mx_input.KeysAreDownAny(UI.input, keys); typed != .KEY_UNKNOWN {

			if elapsed == 0 || elapsed > UI.text_input_stall_threshold {
				InsertCharacter(&UI.input_buffer, cast(u8) typed);
			}
		}
		
		delete_keys := []mx_input.mx_key { .KEY_BACKSPACE }
		if typed, elapsed := mx_input.KeysAreDownAny(UI.input, delete_keys); typed != .KEY_UNKNOWN {
			if elapsed == 0 || u32(elapsed / UI.text_delete_threshold) == 1 {
					RemoveCharacter(&UI.input_buffer);
			}
		}

		widget.text = ExtractString(&UI.input_buffer);
	}
	

	return widget;	
}



UiSliderEnumScaled :: proc(parent: ^ui_widget, scale: f32, value: ^$T) -> ^ui_widget where intrinsics.type_is_enum(T) {
	layout := UiLayout(parent, { .SIZE_BY_SCALE, .SIZE_BY_SCALE }, { scale, 1.0 }, .X_AXIS);
	layout.flags += { .DRAW_BORDER };

	_min := cast(i32) min(T);
	_max := cast(i32) max(T);

	left_arrow  := UiButton(layout, fmt.tprintf("%c", rune(mx_renderer.ICON_LEFT)));
	UiSeparator(layout, 4.0);
	result 		:= UiLabel(layout, reflect.enum_string(value^));
	result.size = { { .SIZE_BY_EXPAND, 1.0 } , { .SIZE_BY_SCALE, 1.0 } }  

	UiSeparator(layout, 4.0);
	right_arrow := UiButton(layout, fmt.tprintf("%c", rune(mx_renderer.ICON_RIGHT)));
/*
	left_arrow := UiMakeWidget(
		layout,
		{ .DRAW_TEXT, .DRAW_BACKGROUND, .DRAW_INTERACTIVE }, 
		ui_widget_size_config {	.SIZE_BY_SCALE, 1.0 },
		ui_widget_size_config { .SIZE_BY_TEXT, 1.0 },
		{},
		fmt.tprintf("%c", rune(mx_renderer.ICON_LEFT)));

	inner_layout := UiLayout(layout, { .SIZE_BY_SCALE, .SIZE_BY_SCALE }, { 0.8, 1.0 }, .X_AXIS);
	inner_layout.flags += { .DRAW_INTERACTIVE, .DRAW_CLIPPED };
	inner_layout.clipping_rect = inner_layout.rect;
/*
	clip_layout := UiLayout(inner_layout, { .SIZE_BY_CHILDREN, .SIZE_BY_SCALE } , { 1.0, 1.0 }, .X_AXIS );
	clip_layout.clipping_rect = clip_layout.rect;
	clip_layout.override_layout = true; 
	clip_layout.rect.min_x = inner_layout.rect.min_x;
	clip_layout.rect.min_y = inner_layout.rect.min_y;

	_min := cast(i32) min(T);
	_max := cast(i32) max(T);

	for idx := _min; idx < _max; idx += 1 {
		UiMakeWidget(
			clip_layout,
			{ .DRAW_TEXT, .DRAW_BACKGROUND }, 
			ui_widget_size_config {	.SIZE_BY_TEXT, 1.0 },
			ui_widget_size_config { .SIZE_BY_SCALE, 1.0 },
			{},
			reflect.enum_string(T(idx)));
	}
*/
	right_arrow := UiMakeWidget(
		layout,
		{ .DRAW_TEXT, .DRAW_BACKGROUND, .DRAW_INTERACTIVE }, 
		ui_widget_size_config {	.SIZE_BY_SCALE, 0.1 },
		ui_widget_size_config { .SIZE_BY_SCALE, 1.0 },
		{},
		fmt.tprintf("%c", rune(mx_renderer.ICON_RIGHT)));
*/

	{
		disabled_style := default_style;
		disabled_style.text_color_default = { 0.25, 0.25, 0.25, 1.0 };

		UiSetStyle(disabled_style);
		defer UiResetStyle();

		//prev.style = UI.active_style;
		//next.style = UI.active_style;
	}

	//result_width, _ := UiRectGetDimensions(inner_layout.rect);
	input_scale := cast(f32) value^ / cast(f32) (_max - _min);

	// TOOD(G): Add a slider

	// This is scroll stuff.
	/*
	if response := UiGetWidgetResponse(inner_layout); response.pressed {
		mouse_pos := math.clamp((UI.mouse_x - clip_layout.rect.min_x), 0, result_width);
		mouse_scale := cast(i32) math.floor( cast(f32) _max * mouse_pos / result_width);
		

		value^ = cast(T) math.clamp(mouse_scale, _min, _max);		
	}
	*/

	if response := UiGetWidgetResponse(left_arrow); response.single_clicked {
		value^ = cast(T) max((cast(i32) value^ - 1), 0); 
	}

	if response := UiGetWidgetResponse(right_arrow); response.single_clicked {
		value^ = cast(T) min((cast(i32) value^ + 1), _max); 
	}	
	
	return layout;
}


UiCheckbox :: proc(parent: ^ui_widget, value: ^bool) -> ^ui_widget {
	outer := UiMakeWidget(
		parent,
		{ .DRAW_INTERACTIVE, .DRAW_BACKGROUND, .DRAW_BORDER }, 
		ui_widget_size_config {	.SIZE_BY_PIXELS, 30.0 },
		ui_widget_size_config { .SIZE_BY_SCALE, 1.0 },
		.X_AXIS,
		{});

	// how do we implement this?
	if value^ {
		UiMakeWidget(
			outer,
			{ .DRAW_INTERACTIVE, .DRAW_BACKGROUND, .DRAW_BORDER }, 
			ui_widget_size_config {	.SIZE_BY_SCALE, 0.7 },
			ui_widget_size_config { .SIZE_BY_SCALE, 0.7 },
			.X_AXIS,
			{});
	}

	if response := UiGetWidgetResponse(outer); response.single_clicked {
		value^ = !(value^);
	}

	return outer;
}


UiRadioButton :: proc(parent: ^ui_widget, label: string, options: []any, active: ^int) -> ^ui_widget {
	layout := UiLayout(parent, { .SIZE_BY_CHILDREN, .SIZE_BY_SCALE }, { 1.0, 1.0 }, .X_AXIS);

	UiLabel(layout, label);
	UiSeparator(layout, 6.0);

	for i, idx in options {
		child := UiButton(layout, fmt.tprintf("%s", i));

		if response := UiGetWidgetResponse(child); response.single_clicked {
			active^ = idx;
		}

		if idx == active^ {
			child.flags += { .DRAW_BORDER };
		}

	}
	
	return layout;
}


// Vertical
// Slider needs to be mutual <-> between the needed widget and itself.
UiScrollArea :: proc(parent: ^ui_widget) -> ^ui_widget {
	scrollbar_size : f32 = 16.0;

	layout := UiMakeWidget(
		parent,
		{ .DRAW_BACKGROUND }, 
		ui_widget_size_config {	.SIZE_BY_SCALE, 1.0 },
		ui_widget_size_config { .SIZE_BY_EXPAND, 1.0 },
		.X_AXIS,
		{});

	width, height := UiRectGetDimensions(layout.rect);

	// Check for mouse scroll wheel.
	
	container := UiMakeWidget(
		parent,
		{ .DRAW_INTERACTIVE, .DRAW_BACKGROUND, .DRAW_CLIPPED }, 
		ui_widget_size_config {	.SIZE_BY_PIXELS, width - scrollbar_size },
		ui_widget_size_config { .SIZE_BY_SCALE, 1.0 },
		.Y_AXIS,
	{});

	scroller := UiMakeWidget(
		parent,
		{ .DRAW_INTERACTIVE, .DRAW_BACKGROUND }, 
		ui_widget_size_config {	.SIZE_BY_PIXELS, scrollbar_size },
		ui_widget_size_config { .SIZE_BY_SCALE, 1.0 },
		.Y_AXIS,
		{});


	return container;
}