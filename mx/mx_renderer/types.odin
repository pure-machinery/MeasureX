package mx_renderer

// Instance data.
vertex :: struct #packed
{
	min: [2]f32,
	max: [2]f32,
	min_uv: [2]f32,
	max_uv: [2]f32,
	color: [4]f32,
	border_color: [4]f32,
	thickness: f32,
	clip_id: int,
}

rectangle :: struct {
	min_x: f32,
	min_y: f32,
	max_x: f32,
	max_y: f32,
}

ICON_CLOSE        :: 0xe800
ICON_FILE_PDF     :: 0xe801
ICON_FULLSCREEN   :: 0xe802
ICON_LEFT         :: 0xe803
ICON_RIGHT        :: 0xe804