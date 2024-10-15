package mx_core


import "../mx_input"
import "../mx_renderer"
import "../mx_parser"
import "../mx_chain"
import "../mx_ui"

import "../../profiler"

import "core:math"
import "core:math/rand"
import "core:fmt"
import "base:runtime"
import "core:reflect"
import "core:strconv"
import "core:mem"
import "core:time"
import "core:os"
import "core:slice"
import "core:strings"

added := false;

state_data :: struct {
	is_initialised: bool, 
	chain: mx_chain.dimension_chain,
	selected_node: ^mx_chain.dimension_node,

	// Monitor refresh rate.
	refresh_rate: f64,
	desired_dt: f64,
	dt: f64,
	elapsed: f64,
	frame: uint,

	signal: window_signal,

	log_file: os.Handle,

	move_timer: timer,
}

timer :: struct {
	elapsed: f64,
	seconds: f64, 
}

RunApplication :: proc(input: ^mx_input.input_state, ctx: ^mx_renderer.graphics_context, state: ^state_data) {
	using mx_input;
	using mx_renderer;

	if !state.is_initialised {
		mx_ui.UiInitialize(ctx, input);
		profiler.InitProfiler(64);

		if temp_chain, ok := mx_chain.InitializeChain(); ok {
			state.chain = temp_chain;
			state.selected_node = mx_chain.ChainInsertNode(&state.chain, nil);
			state.is_initialised = ok;
			state.move_timer = timer { 0.0, 0.05 };

			//CreateLogFile(state);
		} else {
			state.signal.should_close = true;
			return; 
		}
	}

	//profiler.BeginRecordEntry(#procedure);
	//defer profiler.EndRecordEntry();

	mx_ui.UiBegin(cast(f64) input.mouse_x, cast(f64) input.mouse_y, input.scroll, ctx.screen_width, ctx.screen_height, input.left_press, cast(f32) state.dt, state.frame);
	defer mx_ui.UiEnd();

	if KeyJustReleased(input, mx_key.KEY_Q) { 
		state.signal.should_close = true;
		os.close(state.log_file);
		return;
	}
	
	if KeyJustReleased(input, mx_key.KEY_DELETE) {
		state.selected_node = mx_chain.ChainFreeNode(&state.chain, state.selected_node);
	}

	if is, _ := KeyIsDown(input, mx_key.KEY_LSHIFT); is && KeyJustReleased(input, mx_key.KEY_A) {
		state.selected_node = mx_chain.ChainInsertNode(&state.chain, state.selected_node);
		added = true;
		fmt.println("ADDED:")
	}

	//if state.selected_node != nil do EditDimension(state, input);
	/*
	{
		using mx_ui;
     	sty := default_style;
     	sty.background_color_hover = { 1.0, 0.0, 0.0, 1.0 };
     	sty.text_size_default = 20.0;
     	UiSetStyle(sty);

		temp_layout := UiLayout(UI.screen, { .SIZE_BY_SCALE, .SIZE_BY_SCALE } , { 1.0, 0.500 }, .X_AXIS);

		for idx := 0; idx < 3; idx += 1 {
			//sty.text_size_default = cast(f32) (idx + 1) * 10.0;
			//UiSetStyle(sty);

			//UiButton(temp_layout, "Placeholder");
			//UiLabel(temp_layout, "Labelholder");
		} 
			UiLabel(temp_layout, "Labelholder");
			UiButton(temp_layout, "Hello");
			UiButton(temp_layout, "Placeholder");
			UiLabel(temp_layout, "Labelholder");
		/*
		new_layout := UiLayout(UI.screen, { .SIZE_BY_SCALE, .SIZE_BY_SCALE }, { 1.0, 0.500 }, .CENTER);

		sty.background_color = { 0.5, 1.0, 0.125, 0.5 };
		sty.default_radius = 8.0 ;
		sty.text_size_default = 40.0;
		UiSetStyle(sty);

		UiButton(new_layout, "Goodnight!");
		*/
	}
	*/
	//PrintTable();

	UiHeaderBar(input, &state.signal, &state.chain, state.dt, state.desired_dt);
	UiToleranceWidget(&state.chain, state.selected_node, state.elapsed);

	mx_ui.UiMakeLayout();
	mx_ui.UiFlushWidgets();

	ClearBackgroundColor(0.25, 0.25, 0.25, 1.0);
	DrawUI(ctx, .RECTANGLE);

	//if added do assert(0 == 1);
}

window_signal :: struct {
	should_close: bool,
	should_resize: bool,
	should_fullscreen: bool,
	fullscreen: bool,
	// Window positions.
	should_move: bool,
	window_x, window_y: i32, 
	width, height: i32, 

	absolute_x, absolute_y: i32,
	// Screen id.
	screen: i32, 
}

UiHeaderBar :: proc(input: ^mx_input.input_state, signal: ^window_signal, chain: ^mx_chain.dimension_chain, dt: f64, desired_dt: f64) {
	using mx_ui; 
	using time;

	title_bar := UiLayout(UI.screen, { .SIZE_BY_SCALE, .SIZE_BY_PIXELS } , { 1.0, 36.0 }, .X_AXIS);
	title_bar.text = "title_bar";

	UiSeparator(title_bar, 2.0);

	export := UiButton(title_bar, fmt.tprintf("%c##export_pdf", rune(mx_renderer.ICON_FILE_PDF)));
	
	if response := UiGetWidgetResponse(export); response.single_clicked {
		// Perhaps create a text input widget for the file path?
		now := time.now();
		hour, min, sec := time.clock_from_time(now);
		year, month, day := time.date(now);

		file := fmt.tprintf("%d:%d:%d-%d-%d-%d.pdf", hour, min, sec, day, month, year);
		
		fmt.println(file);

		//ExportToPDF(file, chain);
		// Do the exporting.
	}

	UiSeparator(title_bar, 2.0);

	radio_button := UiRadioButton(title_bar, "ISO2862:", { "F", "M", "C", "V" }, cast(^int) &chain.designation);

	expander := UiLayout(title_bar, { .SIZE_BY_EXPAND, .SIZE_BY_SCALE }, { 0.0, 1.0 }, {});

	//UiLabel(title_bar, fmt.tprintf("%.6f %.6f ", dt, desired_dt));
	
	UiSeparator(title_bar, 2.0);

	fullscreen := UiButton(title_bar, fmt.tprintf("%c##fullscreen", rune(mx_renderer.ICON_FULLSCREEN)));
	
	UiSeparator(title_bar, 2.0);

	close_button := UiButton(title_bar, fmt.tprintf("%c##close", rune(mx_renderer.ICON_CLOSE)));

	UiSeparator(title_bar, 2.0);

	if response := UiGetWidgetResponse(close_button); response.single_clicked {
		signal.should_close = true; 
	}

	if response := UiGetWidgetResponse(fullscreen); response.single_clicked {
		signal.should_fullscreen = !signal.should_fullscreen;
	}
	/*

	if response := UiGetWidgetResponse(save); true {
		// TODO(G): Save as a binary file.
	}
	
	*/
}

UiToleranceWidget :: proc(chain: ^mx_chain.dimension_chain, selected: ^mx_chain.dimension_node, elapsed: f64) 
{
	using mx_ui;
	using mx_chain;

	panel := UiLayout(UI.screen, { .SIZE_BY_SCALE, .SIZE_BY_PIXELS }, { 1.0, 30.0 } , .X_AXIS);
	
	// UiLayoutScaled(1 / 6.0);
	list_scale : f32 = 1 / 6.0; 
	UiLabelScaled(panel, list_scale, "Standard");
	UiLabelScaled(panel, list_scale, "Nominal");
	UiLabelScaled(panel, list_scale, "Field");
	UiLabelScaled(panel, list_scale, "Grade");
	UiLabelScaled(panel, list_scale, "Lower");
	UiLabelScaled(panel, list_scale, "Upper");
	
	//UiSeparator(UI.screen, 8.0);
	
	{ 
		// Clipping list.
		//scroller_layout := UiLayout(UI.screen, { .SIZE_BY_SCALE, .SIZE_BY_EXPAND }, { 1.0, 1.0 }, .X_AXIS);

		//list_x, list_y := UiRectGetDimensions(scroller_layout.rect);

		list := UiLayout(UI.screen, { .SIZE_BY_SCALE, .SIZE_BY_EXPAND }, { 1.0, 1.0 }, .Y_AXIS);

		for node := chain.head; node != nil; node = node.next {
			spanner := UiLayout(list, { .SIZE_BY_SCALE, .SIZE_BY_PIXELS }, { 1.0, 30.0 } , .X_AXIS);

			state_slider := UiSliderEnumScaled(spanner, list_scale, &node.state);
			nominal_input := UiTextEditScaled(spanner, list_scale, fmt.tprintf("%f##nominal_%x", node.nominal_value, node));

			if node.state == .ISO286 {
				field_slider := UiSliderEnumScaled(spanner, list_scale, &node.field);
				grade_slider := UiSliderEnumScaled(spanner, list_scale, &node.grade);
			} else {
				UiLayout(spanner, { .SIZE_BY_EXPAND, .SIZE_BY_SCALE}, { 1.0, 1.0 }, {});
			}

			lower_input := UiTextEditScaled(spanner, list_scale, fmt.tprintf("%.3f##lower_%x", node.lower_tolerance, node));
			upper_input := UiTextEditScaled(spanner, list_scale, fmt.tprintf("%.3f##upper_%x", node.upper_tolerance, node));


			node.nominal_value = strconv.atof(nominal_input.text);
			// TODO: Change widget style setting. Eg. that i can set per widget.
			switch node.state {
				case .ISO286:
					// TODO(G): Implement table for this standard.
				case .ISO2862:
					lower, upper := mx_chain.FetchToleranceRangeISO2862(node.nominal_value, chain.designation);
					node.lower_tolerance = lower;
					node.upper_tolerance = upper;

					//style.text_color_default = [4]f32 { 0.639, 0.639, 0.639, 1.0 };
				case .None:
					node.lower_tolerance = strconv.atof(lower_input.text);
					node.upper_tolerance = strconv.atof(upper_input.text);

					if node.upper_tolerance < node.lower_tolerance {
						//red := 1.0 * cast(f32) abs(math.sin(2.0 * elapsed));
						//style.text_color_default = [4]f32 { red, 0.0, 0.0, 1.0 };
					}
			}

			UiSeparator(list, 5.0);
		}
	
		UiSeparator(UI.screen, 6.0);

	}
	

	
	{
		style := mx_ui.default_style;
		style.text_size_default = 28.0;
		style.background_color = { 0.2, 0.2, 0.2, 1.0 };
		style.default_radius = { 8.0, 8.0, 8.0, 8.0 };
		style.border_thickness = 3.0;
		style.border_color = {0.5, 0.125, 1.0, 1.0 };

		end_dim := mx_chain.CalculateEndDimension(chain^);
		
		result_layout := UiLayout(UI.screen, { .SIZE_BY_SCALE, .SIZE_BY_PIXELS }, { 1.0, 60.0 } , .X_AXIS);
		//result_layout.draw_flags += { .DRAW_BORDER };

		UiSetStyle(style);
		defer UiResetStyle();		
		
		lhs_layout := UiLayout(result_layout, { .SIZE_BY_SCALE, .SIZE_BY_SCALE}, { 0.5, 1.0 }, .X_AXIS);
		rhs_layout := UiLayout(result_layout, { .SIZE_BY_SCALE, .SIZE_BY_SCALE}, { 0.5, 1.0 }, .Y_AXIS);
		u_parent :=	UiLayout(rhs_layout, { .SIZE_BY_SCALE, .SIZE_BY_SCALE}, { 1.0, 0.5 }, .X_AXIS);
		l_parent := UiLayout(rhs_layout, { .SIZE_BY_SCALE, .SIZE_BY_SCALE}, { 1.0, 0.5 }, .X_AXIS);

		n := UiLabelScaled(lhs_layout, 1.0, fmt.tprintf("%f##end_nominal",end_dim.nominal_value));
		l := UiLabelScaled(l_parent, 1.0, fmt.tprintf("%f##end_lower",end_dim.lower_tolerance));
		u := UiLabelScaled(u_parent, 1.0, fmt.tprintf("%f##end_upper",end_dim.upper_tolerance));
	}
	
}


PrintTable :: proc() {
	using mx_ui; 

	stack := make_dynamic_array_len_cap([dynamic]^ui_widget, 0, cap(UI.widgets), context.temp_allocator);
	defer delete(stack);

	append(&stack, UI.screen);

	depth := 0; 
	last_parent := UI.screen;

	level := 0;
	for node, ok := pop_safe(&stack); node != nil && ok; node, ok = pop_safe(&stack) {
		fmt.println(node.text);

		for child := node.first_child; child != nil; child = child.next_sibling {
			fmt.print("\t");
			fmt.println("-> ", child.text);
			append(&stack, child);
		}
	}	
}


CreateLogFile :: proc(state: ^state_data) {
	if file, ok := os.open("performance.txt", os.O_CREATE | os.O_WRONLY | os.O_TRUNC, os.S_IRWXU); ok == os.ERROR_NONE {
		state.log_file = file;
	}
}


// TODO(G): Add basic PDF parsing.
ExportToPDF :: proc(filename: string, chain: ^mx_chain.dimension_chain) -> bool {
	using strings;
	using mx_parser;


	fd, err := os.open(filename, os.O_CREATE | os.O_WRONLY | os.O_TRUNC, os.S_IRWXU);
	defer os.close(fd);

 	if err != os.ERROR_NONE {
 		when ODIN_DEBUG do fmt.println("Failed to open file: ", err);
 		return false;
 	}; 

 	fmt.println(os.fstat(fd, context.temp_allocator));

 	//ctx := InitPDF(2, 0, context.temp_allocator);
 	//AddObject(&ctx, .DICTIONARY, {}, )


 	builder : Builder = ---; 
	builder_init_len_cap(&builder, 0, mem.Kilobyte, context.temp_allocator);
 	defer builder_destroy(&builder);

 	// Write header indicating which version to use.
 	write_string(&builder, "%PDF−2.0\n");

 	obj_1 := fmt.tprintf("%10d", builder_len(builder));
 	write_string(&builder, "1 0 obj <</Type /Catalog /Pages 2 0 R>> endobj\n");
 	// Signifying single page with object id 3.
 	obj_2 := fmt.tprintf("%10d", builder_len(builder));
 	write_string(&builder, "2 0 obj <</Type /Pages /Kids [3 0 R] /Count 1>> endobj\n");
 	// Page object?
  	obj_3 := fmt.tprintf("%10d", builder_len(builder));
 	write_string(&builder, "3 0 obj<</Font <</F1 5 0 R>>>> endobj\n");
 	
 	obj_4 := fmt.tprintf("%10d", builder_len(builder));
 	write_string(&builder, "4 0 obj<</Type /Font /Subtype /Type1 /BaseFont /Helvetica>> endobj\n");

 	obj_5 := fmt.tprintf("%10d", builder_len(builder));
 	write_string(&builder, "5 0 obj<</Type /Page /Parent 2 0 R /Resources 3 0 R /MediaBox [0 0 500 800] /Contents 6 0 R>>\n");

 	{
	 	temp : Builder = ---; 
		builder_init_len_cap(&temp, 0, mem.Kilobyte, context.temp_allocator);
 		defer builder_destroy(&temp);

	 	idx := 0; 
	 	write_string(&temp, "BT\n/F1 24 Tf\n");
	 	defer write_string(&temp, "ET\n");

	 	// Position in the file.
	 	x, y := 10, 10;
	 	for node := chain.head; node != nil; node = node.next {
	 		write_string(&temp, fmt.tprintf("%d %d Td\n", x, y));
	 		write_string(&temp, fmt.tprintf("(x%d = %.3f ( %.3f, %.3f ))Tj\n", idx, node.nominal_value, node.upper_tolerance, node.lower_tolerance));

	 		idx += 1;
	 		y += 50;
	 	}
 	}

 	write_string(&builder, "6 0")

 	// Write xref!
 	xref_start := builder_len(builder);
 	write_string(&builder, "xref\n");
 	write_string(&builder, "0 4\n");
 	write_string(&builder, "0000000000 65535 f\n\r");
 	write_string(&builder, fmt.tprintf("%s 00000 n\n\r", obj_1));
 	write_string(&builder, fmt.tprintf("%s 00000 n\n\r", obj_2));
 	write_string(&builder, fmt.tprintf("%s 00000 n\n\r", obj_3));
 	write_string(&builder, "trailer <</Size 4/Root 1 0 R>>\n");
 	write_string(&builder, "startxref\n");
 	write_int(&builder, xref_start);

 	fmt.println("objects at: ", obj_1, obj_2, obj_3);

 	write_string(&builder, "\n%%EOF");

 	os.write_string(fd, to_string(builder));

	return true;
}