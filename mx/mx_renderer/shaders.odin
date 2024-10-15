package mx_renderer;

GL_MAJOR_VERSION :: 3
GL_MINOR_VERSION :: 3

UI_VERTEX_SHADER :: `
#version 330 core

layout (location = 0) in vec2 min;
layout (location = 1) in vec2 max;
layout (location = 2) in vec2 min_uv;
layout (location = 3) in vec2 max_uv;
layout (location = 4) in vec4 color;
layout (location = 5) in vec4 border_color;
layout (location = 6) in vec4 radius;
layout (location = 7) in float thickness;
layout (location = 8) in int clipid;

out vec4 out_color;
out vec2 out_uv;
out vec2 rect_center; 
out vec2 rect_half_size;
out vec4 bcolor;
out float out_thickness; 

uniform vec2 resolution;

vec2 GetNormalizedCoordinates(vec2 pos) 
{
    float x = pos.x / resolution.x * 2.0 - 1.0;
    float y = 1.0 - pos.y / resolution.y * 2.0;

    return vec2(x, y);
} 

void main()
{
    vec2 vertices[4] = vec2[4] ( vec2(-1,-1), vec2(-1, 1), vec2(1, 1), vec2(1, -1) );  

    vec2 dst_half_size = (max - min) * 0.5;
    vec2 dst_center = min + dst_half_size;
    vec2 dst_pos = dst_center + vertices[gl_VertexID % 4] * dst_half_size;

    vec2 src_half_size = (max_uv - min_uv) * 0.5;
    vec2 src_center = min_uv + src_half_size;
    vec2 src_pos = src_center + vertices[gl_VertexID % 4] * src_half_size;

    gl_Position = vec4(GetNormalizedCoordinates(dst_pos), 0.0, 1.0);

    out_color = color;
    out_uv = src_pos;
    bcolor = border_color;
    out_thickness = thickness;
    rect_center = dst_center;
    rect_half_size = dst_half_size;
}
`;

UI_FRAGMENT_SHADER :: `
#version 330 core

in vec4 out_color;
in vec2 out_uv;
in vec2 rect_center; 
in vec2 rect_half_size;
in vec4 bcolor;
in float out_thickness;

in vec4 gl_FragCoord;

out vec4 FragColor;

uniform vec2 resolution;
uniform sampler2D text;

/*
layout(binding = 1, std140) buffer clipping
{
    float min_x;
    float min_y;
    float max_x;
    float max_y;
};
*/

/*
float sdf_rounded_box(vec2 sample_pos, vec2 rect_center, vec2 rect_half_size, float radius)
{
    vec2 d2 = (abs(rect_center - sample_pos) - rect_half_size + vec2(radius, radius));
    
    return min(max(d2.x, d2.y), 0.0) + length(max(d2, 0.0)) - radius;
}
*/


float sdf_box(vec2 sample_pos, vec2 rect_center, vec2 rect_half_size)
{
    vec2 d2 = abs(rect_center - sample_pos) - rect_half_size;
    
    return min(max(d2.x, d2.y), 0.0) + length(max(d2, 0.0));
}

// TODO(G): The border pixels are not consistent always depending on how much the widget is expanded.
void main()
{	
    float softness = 0.005;

    float dist = sdf_box(vec2(gl_FragCoord.x, resolution.y - gl_FragCoord.y), rect_center, rect_half_size);
    float sdf_factor = 1.0 - smoothstep(0.0, softness, dist);
    
    vec4 color = out_color;
    
    if (dist > -out_thickness && dist < 0.0 ) {
        color = bcolor;
    }

    FragColor = vec4(1.0, 1.0, 1.0, texture(text, out_uv).r) * color;
}
`;