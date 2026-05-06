//example of some shaders compiled
flat basic.vs flat.fs
texture basic.vs texture.fs
skybox basic.vs skybox.fs
depth quad.vs depth.fs
multi basic.vs multi.fs
plain basic.vs plain.fs
//mio
phong basic.vs phong.fs
gbuffer_fill basic.vs gbuffer_fill.fs
deferred_light quad.vs deferred_light.fs
skybox_gbuffer basic.vs skybox_gbuffer.fs
deferred_ambient_directional quad.vs deferred_ambient_directional.fs
light_volume basic.vs light_volume.fs


\perturbNormal

// From https://github.com/glslify/glsl-perturb-normal/blob/master/cotangent-frame.glsl
mat3 cotangent_frame(vec3 N, vec3 p, vec2 uv)
{
	// get edge vectors of the pixel triangle
	vec3 dp1 = dFdx(p);
	vec3 dp2 = dFdy(p);
	vec2 duv1 = dFdx(uv);
	vec2 duv2 = dFdy(uv);

	// solve the linear system
	vec3 dp2perp = cross(dp2, N);
	vec3 dp1perp = cross(N, dp1);
	vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
	vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;

	// construct a scale-invariant frame 
	float invmax = inversesqrt(max(dot(T, T), dot(B, B)));
	return mat3(T * invmax, B * invmax, N);
}

// assume N, the interpolated vertex normal and 
// WP the world position
vec3 perturbNormal(vec3 N, vec3 WP, vec2 uv, vec3 normal_pixel)
{
	mat3 TBN = cotangent_frame(N, WP, uv);
	return normalize(TBN * normal_pixel);
}

\basic.vs

#version 330 core

in vec3 a_vertex;
in vec3 a_normal;
in vec2 a_coord;
in vec4 a_color;

uniform vec3 u_camera_position;

uniform mat4 u_model;
uniform mat4 u_viewprojection;

//this will store the color for the pixel shader
out vec3 v_position;
out vec3 v_world_position;
out vec3 v_normal;
out vec2 v_uv;
out vec4 v_color;

uniform float u_time;

void main()
{	
	//calcule the normal in camera space (the NormalMatrix is like ViewMatrix but without traslation)
	v_normal = (u_model * vec4( a_normal, 0.0) ).xyz;
	
	//calcule the vertex in object space
	v_position = a_vertex;
	v_world_position = (u_model * vec4( v_position, 1.0) ).xyz;
	
	//store the color in the varying var to use it from the pixel shader
	v_color = a_color;

	//store the texture coordinates
	v_uv = a_coord;

	//calcule the position of the vertex using the matrices
	gl_Position = u_viewprojection * vec4( v_world_position, 1.0 );
}

\quad.vs

#version 330 core

in vec3 a_vertex;
in vec2 a_coord;
out vec2 v_uv;

void main()
{	
	v_uv = a_coord;
	gl_Position = vec4( a_vertex, 1.0 );
}


\flat.fs

#version 330 core

uniform vec4 u_color;

out vec4 FragColor;

void main()
{
	FragColor = u_color;
}


\texture.fs

#version 330 core

in vec3 v_position;
in vec3 v_world_position;
in vec3 v_normal;
in vec2 v_uv;
in vec4 v_color;

uniform vec4 u_color;
uniform sampler2D u_texture;
uniform float u_time;
uniform float u_alpha_cutoff;

out vec4 FragColor;

void main()
{
	vec2 uv = v_uv;
	vec4 color = u_color;
	color *= texture( u_texture, v_uv );

	if(color.a < u_alpha_cutoff)
		discard;

	FragColor = color;
}


\skybox.fs

#version 330 core

in vec3 v_position;
in vec3 v_world_position;

uniform samplerCube u_texture;
uniform vec3 u_camera_position;
out vec4 FragColor;

void main()
{
	vec3 E = v_world_position - u_camera_position;
	vec4 color = texture( u_texture, E );
	FragColor = color;
}


\multi.fs

#version 330 core

in vec3 v_position;
in vec3 v_world_position;
in vec3 v_normal;
in vec2 v_uv;

uniform vec4 u_color;
uniform sampler2D u_texture;
uniform float u_time;
uniform float u_alpha_cutoff;

layout(location = 0) out vec4 FragColor;
layout(location = 1) out vec4 NormalColor;

void main()
{
	vec2 uv = v_uv;
	vec4 color = u_color;
	color *= texture( u_texture, uv );

	if(color.a < u_alpha_cutoff)
		discard;

	vec3 N = normalize(v_normal);

	FragColor = color;
	NormalColor = vec4(N,1.0);
}


\depth.fs

#version 330 core

uniform vec2 u_camera_nearfar;
uniform sampler2D u_texture; //depth map
in vec2 v_uv;
out vec4 FragColor;

void main()
{
	float n = u_camera_nearfar.x;
	float f = u_camera_nearfar.y;
	float z = texture(u_texture,v_uv).x;
	if( n == 0.0 && f == 1.0 )
		FragColor = vec4(z);
	else
		FragColor = vec4( n * (z + 1.0) / (f + n - z * (f - n)) );
}


\instanced.vs

#version 330 core

in vec3 a_vertex;
in vec3 a_normal;
in vec2 a_coord;

in mat4 u_model;

uniform vec3 u_camera_pos;

uniform mat4 u_viewprojection;

//this will store the color for the pixel shader
out vec3 v_position;
out vec3 v_world_position;
out vec3 v_normal;
out vec2 v_uv;

void main()
{	
	//calcule the normal in camera space (the NormalMatrix is like ViewMatrix but without traslation)
	v_normal = (u_model * vec4( a_normal, 0.0) ).xyz;
	
	//calcule the vertex in object space
	v_position = a_vertex;
	v_world_position = (u_model * vec4( a_vertex, 1.0) ).xyz;
	
	//store the texture coordinates
	v_uv = a_coord;

	//calcule the position of the vertex using the matrices
	gl_Position = u_viewprojection * vec4( v_world_position, 1.0 );
}

//mio
\phong.fs
#version 330 core
#include "perturbNormal"

#define MAX_LIGHTS 8

in vec3 v_world_position;
in vec3 v_normal;
in vec2 v_uv;

uniform vec4 u_color;
uniform sampler2D u_texture;

uniform vec3 u_camera_position;

uniform int u_num_lights;

uniform vec3 u_light_position[MAX_LIGHTS];
uniform vec3 u_light_color[MAX_LIGHTS];
uniform float u_light_intensity[MAX_LIGHTS];

uniform vec3 u_ambient_light;
uniform float u_shininess;
uniform float u_alpha_cutoff;
uniform float u_shadow_bias;

uniform int u_light_type[MAX_LIGHTS]; // 0: no_light | 1: point | 2: spot | 3: directional
uniform vec3 u_light_direction[MAX_LIGHTS];

uniform vec2 cones[MAX_LIGHTS];

uniform sampler2D u_normal_map;

uniform sampler2D u_spot_shadow_map;
uniform sampler2D u_directional_shadow_map;
uniform mat4 u_spot_light_viewprojection;
uniform mat4 u_directional_light_viewprojection;

out vec4 FragColor;

void main() 
{
	vec3 map_normal = texture(u_normal_map, v_uv).xyz * 2.0 - 1.0;
	vec3 N = perturbNormal(normalize(v_normal), v_world_position, v_uv, map_normal);
	vec3 V = normalize(u_camera_position - v_world_position);
	
	// color del material
	vec4 base_color = u_color * texture(u_texture, v_uv);
	vec3 ambient = base_color.rgb * u_ambient_light; //ka * Ia
	vec3 diffuse = vec3(0.0);
	vec3 specular = vec3(0.0);

	if(base_color.a < u_alpha_cutoff)
		discard;

	for(int i=0;i< u_num_lights;i++){
		vec3 L;
		float attenuation;
		vec3 D = normalize(u_light_direction[i]);

		// POINT LIGHT
		if (u_light_type[i] == 1) { 
			float distance = length(u_light_position[i] - v_world_position);
			attenuation = u_light_intensity[i] / (distance * distance);
			L = normalize(u_light_position[i] - v_world_position);
		}

		// SPOTLIGHT LIGHT
		else if (u_light_type[i] == 2) {
			float distance = length(u_light_position[i] - v_world_position);
			attenuation = u_light_intensity[i] / (distance * distance);
			L = normalize(u_light_position[i] - v_world_position);
			
			if (dot(L, D) >= cones[i].y) {
				attenuation *= (dot(L,D) - cones[i].y) / (cones[i].x - cones[i].y);
			} else {
				attenuation *= 0.0;
			}
		}

		// DIRECTIONAL LIGHT
		else if (u_light_type[i] == 3) { // DIRECTIONAL
			attenuation = u_light_intensity[i];
			L = D;
		}

		// SHADOWS
		float shadow = 0.0;
		if (u_light_type[i] == 3) {
			vec4 light_space_pos = u_directional_light_viewprojection * vec4(v_world_position, 1.0);

			vec3 proj_coords = light_space_pos.xyz / light_space_pos.w;
			proj_coords = proj_coords * 0.5 + 0.5;

			float closest_depth = texture(u_directional_shadow_map, proj_coords.xy).r;

			float current_depth = proj_coords.z - u_shadow_bias;

			shadow = current_depth > closest_depth ? 1.0 : 0.0;
		}
		else if (u_light_type[i] == 2) {
			vec4 light_space_pos = u_spot_light_viewprojection * vec4(v_world_position, 1.0);

			vec3 proj_coords = light_space_pos.xyz / light_space_pos.w;
			proj_coords = proj_coords * 0.5 + 0.5;

			float closest_depth = texture(u_spot_shadow_map, proj_coords.xy).r;

			float current_depth = proj_coords.z - u_shadow_bias;

			shadow = current_depth > closest_depth ? 1.0 : 0.0;
		}
		else if (u_light_type[i] == 1) {
			shadow = 0.0;
		}
			
		vec3 R = reflect(-L, N);
		float light_factor = 1.0 - shadow;
		diffuse += base_color.rgb * max(dot(N, L), 0.0) * attenuation * u_light_color[i] * light_factor; //kd * (Lj * N) * Li^dir
		specular += base_color.rgb * pow(max(dot(R, V), 0.0), u_shininess) * attenuation * u_light_color[i] * light_factor; //ks * (Rj * V)^a Li^dir(Lj)
	}
	vec3 final_color = ambient + diffuse + specular;
	FragColor = vec4(final_color, base_color.a);
}

\plain.fs

#version 330 core

out vec4 FragColor;

in vec2 v_uv;
uniform sampler2D u_texture;
uniform float u_alpha_cutoff;

void main()
{
	if(texture(u_texture, v_uv).a < u_alpha_cutoff)
		discard;
	FragColor = vec4(0.0, 0.0, 0.0, 1.0);
}

\gbuffer_fill.fs

#version 330 core
#include "perturbNormal"

in vec3 v_position;
in vec3 v_world_position;
in vec3 v_normal;
in vec2 v_uv;

uniform vec4 u_color;
uniform sampler2D u_texture;
uniform sampler2D u_normal_map;
uniform float u_alpha_cutoff;
uniform sampler2D u_metallic;

layout(location = 0) out vec4 gbuffer_albedo;
layout(location = 1) out vec4 gbuffer_normal;
layout(location = 2) out vec4 gbuffer_metallic;

void main() {

    vec4 tex_color = texture(u_texture, v_uv);
    vec4 final_color = u_color * tex_color;

    if(final_color.a < u_alpha_cutoff)
        discard;

    vec3 N = normalize(v_normal);
	vec3 normal_pixel = texture(u_normal_map, v_uv).xyz; 
	gbuffer_normal = vec4(N * 0.5 + 0.5, 1.0); 
	vec3 map_normal = texture(u_normal_map, v_uv).xyz * 2.0 - 1.0; 
	N = perturbNormal(N, v_world_position, v_uv, map_normal);


    gbuffer_albedo = vec4(final_color.rgb, 1.0);
	gbuffer_metallic = vec4(texture(u_metallic, v_uv).xyz, 1.0);
    gbuffer_normal = vec4(N * 0.5 + 0.5, 1.0); //Convert to space in [0,1]
}

\deferred_light.fs
#version 330 core

#define MAX_LIGHTS 8

in vec2 v_uv;

uniform sampler2D u_gbuffer_color;
uniform sampler2D u_gbuffer_normal;
uniform sampler2D u_gbuffer_depth;

uniform mat4 u_inverse_viewprojection;
uniform vec3 u_camera_position;

uniform int u_num_lights;

uniform vec3 u_light_position[MAX_LIGHTS];
uniform vec3 u_light_color[MAX_LIGHTS];
uniform float u_light_intensity[MAX_LIGHTS];

uniform vec3 u_ambient_light;
uniform float u_shininess;
uniform float u_alpha_cutoff;
uniform float u_shadow_bias;

uniform int u_light_type[MAX_LIGHTS]; // 0: no_light | 1: point | 2: spot | 3: directional
uniform vec3 u_light_direction[MAX_LIGHTS];

uniform vec2 cones[MAX_LIGHTS];

uniform sampler2D u_normal_map;

uniform sampler2D u_spot_shadow_map;
uniform sampler2D u_directional_shadow_map;
uniform mat4 u_spot_light_viewprojection;
uniform mat4 u_directional_light_viewprojection;

out vec4 FragColor;

void main() 
{
	float depth = texture(u_gbuffer_depth, v_uv).r;
	vec3 N = texture(u_gbuffer_normal, v_uv).xyz * 2.0 - 1.0;
	N = normalize(N);
	vec4 clipSpacePosition = vec4(v_uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 worldPos = u_inverse_viewprojection * clipSpacePosition;
	vec3 v_world_position = worldPos.xyz / worldPos.w;
	vec3 V = normalize(u_camera_position - v_world_position);
	
	// color del material
	vec4 base_color = texture(u_gbuffer_color, v_uv);
	vec3 ambient = base_color.rgb * u_ambient_light; //ka * Ia
	vec3 diffuse = vec3(0.0);
	vec3 specular = vec3(0.0);

	if(base_color.a < u_alpha_cutoff)
		discard;

	for(int i=0;i< u_num_lights;i++){
		vec3 L;
		float attenuation;
		vec3 D = normalize(u_light_direction[i]);

		// POINT LIGHT
		if (u_light_type[i] == 1) { 
			float distance = length(u_light_position[i] - v_world_position);
			attenuation = u_light_intensity[i] / (distance * distance);
			L = normalize(u_light_position[i] - v_world_position);
		}

		// SPOTLIGHT LIGHT
		else if (u_light_type[i] == 2) {
			float distance = length(u_light_position[i] - v_world_position);
			attenuation = u_light_intensity[i] / (distance * distance);
			L = normalize(u_light_position[i] - v_world_position);
			
			if (dot(L, D) >= cones[i].y) {
				attenuation *= (dot(L,D) - cones[i].y) / (cones[i].x - cones[i].y);
			} else {
				attenuation *= 0.0;
			}
		}

		// DIRECTIONAL LIGHT
		else if (u_light_type[i] == 3) { // DIRECTIONAL
			attenuation = u_light_intensity[i];
			L = D;
		}

		// SHADOWS
		float shadow = 0.0;
		if (u_light_type[i] == 3) {
			vec4 light_space_pos = u_directional_light_viewprojection * vec4(v_world_position, 1.0);

			vec3 proj_coords = light_space_pos.xyz / light_space_pos.w;
			proj_coords = proj_coords * 0.5 + 0.5;

			float closest_depth = texture(u_directional_shadow_map, proj_coords.xy).r;

			float current_depth = proj_coords.z - u_shadow_bias;

			shadow = current_depth > closest_depth ? 1.0 : 0.0;
		}
		else if (u_light_type[i] == 2) {
			vec4 light_space_pos = u_spot_light_viewprojection * vec4(v_world_position, 1.0);

			vec3 proj_coords = light_space_pos.xyz / light_space_pos.w;
			proj_coords = proj_coords * 0.5 + 0.5;

			float closest_depth = texture(u_spot_shadow_map, proj_coords.xy).r;

			float current_depth = proj_coords.z - u_shadow_bias;

			shadow = current_depth > closest_depth ? 1.0 : 0.0;
		}
		else if (u_light_type[i] == 1) {
			shadow = 0.0;
		}
			
		vec3 R = reflect(-L, N);
		float light_factor = 1.0 - shadow;
		diffuse += base_color.rgb * max(dot(N, L), 0.0) * attenuation * u_light_color[i] * light_factor; //kd * (Lj * N) * Li^dir
		specular += base_color.rgb * pow(max(dot(R, V), 0.0), u_shininess) * attenuation * u_light_color[i] * light_factor; //ks * (Rj * V)^a Li^dir(Lj)
	}
	vec3 final_color = ambient + diffuse + specular;
	FragColor = vec4(final_color, base_color.a);
	if (depth >=1) FragColor = FragColor*4;
}

\skybox_gbuffer.fs

#version 330 core

in vec3 v_position;
in vec3 v_world_position;

uniform samplerCube u_texture;
uniform vec3 u_camera_position;
out vec4 FragColor;

layout(location = 0) out vec4 gbuffer_albedo;
layout(location = 1) out vec4 gbuffer_normal;

void main()
{
	vec3 E = v_world_position - u_camera_position;
	vec4 color = texture( u_texture, E );
	gbuffer_normal = vec4(1,1,1,1);
	gbuffer_albedo = color;
}

\deferred_ambient_directional.fs
#version 330 core

in vec2 v_uv;

uniform sampler2D u_gbuffer_color;
uniform sampler2D u_gbuffer_normal;
uniform sampler2D u_gbuffer_depth;

uniform vec3 u_ambient_light;
uniform mat4 u_inverse_viewprojection;
uniform vec3 u_camera_position;

uniform float u_shininess;
uniform float u_alpha_cutoff;
uniform float u_shadow_bias;

uniform sampler2D u_directional_shadow_map;
uniform mat4 u_directional_light_viewprojection;

uniform vec3 u_light_color;
uniform float u_light_intensity;

uniform vec3 u_light_direction;

out vec4 FragColor;

void main() 
{
	float depth = texture(u_gbuffer_depth, v_uv).r;
	vec3 N = texture(u_gbuffer_normal, v_uv).xyz * 2.0 - 1.0;
	N = normalize(N);
	vec4 clipSpacePosition = vec4(v_uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 worldPos = u_inverse_viewprojection * clipSpacePosition;
	vec3 v_world_position = worldPos.xyz / worldPos.w;
	vec3 V = normalize(u_camera_position - v_world_position);
	
	// color del material
	vec4 base_color = texture(u_gbuffer_color, v_uv);
	vec3 ambient = base_color.rgb * u_ambient_light; //ka * Ia
	vec3 diffuse = vec3(0.0);
	vec3 specular = vec3(0.0);

	if(base_color.a < u_alpha_cutoff)
		discard;

	vec3 L;
	float attenuation;
	vec3 D = normalize(u_light_direction);

	attenuation = u_light_intensity;
	L = D;

	// SHADOWS
	float shadow = 0.0;
	vec4 light_space_pos = u_directional_light_viewprojection * vec4(v_world_position, 1.0);

	vec3 proj_coords = light_space_pos.xyz / light_space_pos.w;
	proj_coords = proj_coords * 0.5 + 0.5;

	float closest_depth = texture(u_directional_shadow_map, proj_coords.xy).r;

	float current_depth = proj_coords.z - u_shadow_bias;

	shadow = current_depth > closest_depth ? 1.0 : 0.0;
		
	vec3 R = reflect(-L, N);
	float light_factor = 1.0 - shadow;
	diffuse += base_color.rgb * max(dot(N, L), 0.0) * attenuation * u_light_color * light_factor; //kd * (Lj * N) * Li^dir
	specular += base_color.rgb * pow(max(dot(R, V), 0.0), u_shininess) * attenuation * u_light_color * light_factor; //ks * (Rj * V)^a Li^dir(Lj)

	vec3 final_color = ambient + diffuse + specular;
	FragColor = vec4(final_color, base_color.a);
	if(depth>=1) FragColor = base_color;
}

\light_volume.fs
#version 330 core

uniform sampler2D u_gbuffer_color;
uniform sampler2D u_gbuffer_normal;
uniform sampler2D u_gbuffer_depth;

uniform mat4 u_inverse_viewprojection;
uniform vec3 u_camera_position;
uniform vec2 u_resolution;

uniform vec3 u_light_position;
uniform vec3 u_light_color;
uniform float u_light_intensity;

uniform int u_light_type; // 1 point, 2 spot
uniform vec3 u_light_direction;
uniform vec2 u_cone;

uniform sampler2D u_shadow_map;
uniform mat4 u_light_viewprojection;

uniform float u_shadow_bias;
uniform float u_shininess;
uniform float u_max_distance;

out vec4 FragColor;

void main() 
{	
	vec2 uv = gl_FragCoord.xy / u_resolution;

	// G-Buffer
	vec3 base_color = texture(u_gbuffer_color, uv).rgb;
	vec3 normal = texture(u_gbuffer_normal, uv).xyz;
	normal = normalize(normal * 2.0 - 1.0); // Asumiendo que guardaste la normal en [0, 1]
	float depth = texture(u_gbuffer_depth, uv).r;

	// posiciones
	vec4 screen_pos = vec4(uv.x * 2.0 - 1.0, uv.y * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
	vec4 proj_world_pos = u_inverse_viewprojection * screen_pos;
	vec3 pixel_world_pos = proj_world_pos.xyz / proj_world_pos.w;

	// luz
	vec3 V = normalize(u_camera_position - pixel_world_pos);
	float distance = length(u_light_position - pixel_world_pos);

	if (distance > u_max_distance) discard;

    vec3 L = normalize(u_light_position - pixel_world_pos);
    vec3 D = normalize(u_light_direction);

	float attenuation = u_light_intensity / (distance * distance);

	// SPOT
    if (u_light_type == 2) { 

        float cos_angle = dot(normalize(L), D);

		if (cos_angle < u_cone.y)
			discard;

		attenuation *= clamp((cos_angle - u_cone.y) / (u_cone.x - u_cone.y), 0.0, 1.0);

        vec4 light_space_pos = u_light_viewprojection * vec4(pixel_world_pos, 1.0);
        vec3 proj_coords = light_space_pos.xyz / light_space_pos.w;
        proj_coords = proj_coords * 0.5 + 0.5;

        if (proj_coords.x >= 0.0 && proj_coords.x <= 1.0 &&
            proj_coords.y >= 0.0 && proj_coords.y <= 1.0) 
        {
            float closest_depth = texture(u_shadow_map, proj_coords.xy).r;
            float current_depth  = proj_coords.z - u_shadow_bias;
            if (current_depth > closest_depth) attenuation = 0.0;
        }
    }

    vec3 diffuse = base_color * max(dot(normal, L), 0.0) * attenuation * u_light_color;
    vec3 R = reflect(-L, normal);
    vec3 specular = base_color * pow(max(dot(R, V), 0.0), u_shininess) * attenuation * u_light_color;

    FragColor = vec4(diffuse + specular, 1.0);
}