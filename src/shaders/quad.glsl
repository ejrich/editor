#version 450

#if _VERT

struct Vertex {
    vec3 position;
    vec2 bottom_left_texture_coord_mask;
    vec2 top_right_texture_coord_mask;
};

Vertex positions[6] = Vertex[](
    Vertex(vec3(-0.5, -0.5, 0.0), vec2(1.0, 1.0), vec2(0.0, 0.0)),
    Vertex(vec3( 0.5, -0.5, 0.0), vec2(0.0, 1.0), vec2(1.0, 0.0)),
    Vertex(vec3( 0.5,  0.5, 0.0), vec2(0.0, 0.0), vec2(1.0, 1.0)),
    Vertex(vec3( 0.5,  0.5, 0.0), vec2(0.0, 0.0), vec2(1.0, 1.0)),
    Vertex(vec3(-0.5,  0.5, 0.0), vec2(1.0, 0.0), vec2(0.0, 1.0)),
    Vertex(vec3(-0.5, -0.5, 0.0), vec2(1.0, 1.0), vec2(0.0, 0.0))
);

layout(location = 0) out vec4 frag_color;
layout(location = 1) out vec2 frag_tex_coord;
layout(location = 2) out uint frag_single_channel;

struct QuadInstanceData {
    vec4 color;
    vec3 position;
    uint single_channel;
    float width;
    float height;
    vec2 bottom_left_texture_coord;
    vec2 top_right_texture_coord;
};

layout(set = 0, binding = 0) readonly buffer QuadData {
    QuadInstanceData instances[];
} quads;

void main() {
    QuadInstanceData quad_data = quads.instances[gl_InstanceIndex];

    mat3 scale = mat3(vec3(quad_data.width, 0.0, 0.0), vec3(0.0, quad_data.height, 0.0), vec3(0.0, 0.0, 1.0));

    Vertex vertex = positions[gl_VertexIndex];
    quad_data.position.y *= -1;
    gl_Position = vec4(vertex.position * scale + quad_data.position, 1.0);

    frag_color = quad_data.color;
    frag_single_channel = quad_data.single_channel;
    frag_tex_coord =
        vertex.bottom_left_texture_coord_mask * quad_data.bottom_left_texture_coord +
        vertex.top_right_texture_coord_mask * quad_data.top_right_texture_coord;
}

#elif _FRAG

layout(set = 1, binding = 1) uniform sampler2D tex_sampler;

layout(location = 0) in vec4 frag_color;
layout(location = 1) in vec2 frag_tex_coord;
layout(location = 2) flat in uint frag_single_channel;

layout(location = 0) out vec4 out_color;

void main() {
    vec4 texture = texture(tex_sampler, frag_tex_coord);
    if (frag_single_channel == 1) {
        if (texture.r == 0.0)
            discard;

        out_color = vec4(frag_color.xyz, frag_color.w * texture.r);
    }
    else {
        out_color = frag_color * texture;
    }
}

#endif
