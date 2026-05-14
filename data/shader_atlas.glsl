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
pbr basic.vs pbr.fs
skybox_gbuffer_pbr basic.vs skybox_gbuffer_pbr.fs
deferred_ambient_directional_pbr quad.vs deferred_ambient_directional_pbr.fs
light_volume_pbr basic.vs light_volume_pbr.fs
ssao quad.vs ssao.fs
tonemapper quad.vs tonemapper.fs


\gamma_functions

vec3 gammaToLinear(vec3 v) {
	return pow(v, vec3(2.2));
}

vec3 linearToGamma(vec3 v) {
	return pow(v, vec3(1.0/2.2));
}


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
#include "gamma_functions"

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
	tex_color.rgb = gammaToLinear(tex_color.rgb);
	vec4 gamma_color = u_color;
	gamma_color.rgb = gammaToLinear(u_color.rgb);
    vec4 final_color = gamma_color * tex_color;

    if(final_color.a < u_alpha_cutoff)
        discard;

    vec3 N = normalize(v_normal);
	vec3 normal_pixel = texture(u_normal_map, v_uv).xyz; 
	gbuffer_normal = vec4(N * 0.5 + 0.5, 1.0); 
	vec3 map_normal = texture(u_normal_map, v_uv).xyz * 2.0 - 1.0; 
	N = perturbNormal(N, v_world_position, v_uv, map_normal);

	final_color.rgb = linearToGamma(final_color.rgb);
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
	normal = normalize(normal * 2.0 - 1.0);
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

\pbr_functions

#define PI 3.14159265359

float DistributionGGX(vec3 N, vec3 H, float roughness) {
    float a2 = pow(roughness, 4.0);
    float NdotH = max(dot(N, H), 0.0);
    float denom = (NdotH * NdotH * (a2 - 1.0) + 1.0);
	float divisor = max(PI * denom * denom, 0.0001);
    return a2 / divisor;
}

float GeometrySchlickGGX(float NdotV, float roughness) {
    float k = pow(roughness, 2.0) / 2.0;
	float divisor = max(NdotV * (1.0 - k) + k, 0.0001);
    return NdotV / divisor;
}

float GeometrySmith(vec3 N, vec3 V, vec3 L, float roughness) {
    return GeometrySchlickGGX(max(dot(N, V), 0.0), roughness) * GeometrySchlickGGX(max(dot(N, L), 0.0), roughness);
}

vec3 fresnelSchlick(float cosTheta, vec3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

\pbr.fs
#version 330 core
#include "perturbNormal"
#include "pbr_functions"
#include "gamma_functions"

#define MAX_LIGHTS 8

in vec3 v_world_position;
in vec3 v_normal;
in vec2 v_uv;

uniform vec4 u_color;
uniform sampler2D u_texture;
uniform sampler2D u_normal_map;
uniform sampler2D u_metallic_roughness;

uniform vec3 u_camera_position;
uniform vec3 u_ambient_light;
uniform float u_alpha_cutoff;

uniform int u_num_lights;
uniform vec3 u_light_position[MAX_LIGHTS];
uniform vec3 u_light_color[MAX_LIGHTS];
uniform float u_light_intensity[MAX_LIGHTS];
uniform int u_light_type[MAX_LIGHTS]; // 0: no_light | 1: point | 2: spot | 3: directional
uniform vec3 u_light_direction[MAX_LIGHTS];
uniform vec2 cones[MAX_LIGHTS];

uniform sampler2D u_spot_shadow_map;
uniform sampler2D u_directional_shadow_map;
uniform mat4 u_spot_light_viewprojection;
uniform mat4 u_directional_light_viewprojection;
uniform float u_shadow_bias;

out vec4 FragColor;

void main() 
{
	vec3 map_normal = texture(u_normal_map, v_uv).xyz * 2.0 - 1.0;
	vec3 N = perturbNormal(normalize(v_normal), v_world_position, v_uv, map_normal);
	vec3 V = normalize(u_camera_position - v_world_position);
	float NdotV = max(dot(N, V), 0.0);
	
	// color del material
	vec4 tex_color = texture(u_texture, v_uv);
	tex_color.rgb = gammaToLinear(tex_color.rgb);
    if((u_color.a * tex_color.a) < u_alpha_cutoff) discard;

    vec3 albedo = tex_color.rgb * gammaToLinear(u_color.rgb);
    vec3 orm = texture(u_metallic_roughness, v_uv).rgb;
    float ao = orm.r;
    float roughness = orm.g;
    float metallic = orm.b;

	vec3 F0 = mix(vec3(0.04), albedo, metallic);
    vec3 Lo = vec3(0.0);

	for(int i=0;i< u_num_lights;i++){
		vec3 L;
		float attenuation = 0.0;
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

        vec3 H = normalize(V + L);
        float NdotL = max(dot(N, L), 0.0);
        
        float Dist = DistributionGGX(N, H, roughness);
        float G = GeometrySmith(N, V, L, roughness);      
        vec3 F = fresnelSchlick(max(dot(H, V), 0.0), F0);
        
        vec3 numerator = Dist * G * F;
        float denominator = 4.0 * NdotV * NdotL + 0.0001;
        vec3 specular = numerator / denominator;

        vec3 kD = (vec3(1.0) - F) * (1.0 - metallic);

        Lo += (kD * albedo / PI + specular) * gammaToLinear(u_light_color[i]) * attenuation * NdotL * (1.0 - shadow);
	}
	vec3 ambient = gammaToLinear(u_ambient_light) * albedo * ao;
    
    vec3 color = ambient + Lo;
	color = linearToGamma(color);
    FragColor = vec4(color, 0.0);
}

//JORDIANDREU

\skybox_gbuffer_pbr.fs

#version 330 core
 #include "gamma_functions"
in vec3 v_world_position;

uniform samplerCube u_texture;
uniform vec3 u_camera_position;

layout(location = 0) out vec4 gbuffer_albedo;
layout(location = 1) out vec4 gbuffer_normal;
layout(location = 2) out vec4 gbuffer_orm;

void main()
{
	vec3 E = v_world_position - u_camera_position;
	vec4 color = texture( u_texture, E );
	gbuffer_normal = vec4(1,1,1,1);
	gbuffer_albedo = color;
	gbuffer_orm = vec4(1.0, 1.0, 0.0, 1.0);
}

\deferred_ambient_directional_pbr.fs
#version 330 core
#include "pbr_functions"
#include "gamma_functions"

in vec2 v_uv;

uniform sampler2D u_gbuffer_color;
uniform sampler2D u_gbuffer_normal;
uniform sampler2D u_gbuffer_depth;
uniform sampler2D u_gbuffer_orm;

uniform vec3 u_ambient_light;
uniform mat4 u_inverse_viewprojection;
uniform vec3 u_camera_position;

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
	vec4 base_color = texture(u_gbuffer_color, v_uv);
	base_color.rgb = gammaToLinear(base_color.rgb);

	if(base_color.a < u_alpha_cutoff)
		discard;
	
	vec3 N = texture(u_gbuffer_normal, v_uv).xyz * 2.0 - 1.0;
	N = normalize(N);
	vec3 orm = texture(u_gbuffer_orm, v_uv).rgb;
    float ao = orm.r;
    float roughness = orm.g;
    float metallic = orm.b;

	vec4 clipSpacePosition = vec4(v_uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 worldPos = u_inverse_viewprojection * clipSpacePosition;
	vec3 v_world_position = worldPos.xyz / worldPos.w;
	vec3 V = normalize(u_camera_position - v_world_position);
	vec3 L = normalize(u_light_direction);
    vec3 H = normalize(V + L);
	vec3 F0 = mix(vec3(0.04), base_color.rgb, metallic);

	// SHADOWS
	float shadow = 0.0;
	vec4 light_space_pos = u_directional_light_viewprojection * vec4(v_world_position, 1.0);

	vec3 proj_coords = light_space_pos.xyz / light_space_pos.w;
	proj_coords = proj_coords * 0.5 + 0.5;

	float closest_depth = texture(u_directional_shadow_map, proj_coords.xy).r;

	float current_depth = proj_coords.z - u_shadow_bias;

	shadow = current_depth > closest_depth ? 1.0 : 0.0;
		
	float NdotL = max(dot(N, L), 0.0);
    float NdotV = max(dot(N, V), 0.0);

    float Dist = DistributionGGX(N, H, roughness);
    float G = GeometrySmith(N, V, L, roughness);
    vec3 F = fresnelSchlick(max(dot(H, V), 0.0), F0);

    vec3 spec_num = Dist * G * F;
    float spec_den = 4.0 * NdotV * NdotL + 0.0001;
    vec3 specular = spec_num / spec_den;

    vec3 kD = (vec3(1.0) - F) * (1.0 - metallic);
    
    vec3 diffuse = (kD * base_color.rgb / PI);
    vec3 direct = (diffuse + specular) * gammaToLinear(u_light_color) * u_light_intensity * NdotL * (1.0 - shadow);
    vec3 ambient = base_color.rgb * gammaToLinear(u_ambient_light) * ao;

    vec3 final_color = ambient + direct;
	final_color = linearToGamma(final_color);

    FragColor = vec4(final_color, base_color.a);
    if(depth >= 1.0) FragColor = base_color;
}

\light_volume_pbr.fs
#version 330 core
#include "pbr_functions"
#include "gamma_functions"

uniform sampler2D u_gbuffer_color;
uniform sampler2D u_gbuffer_normal;
uniform sampler2D u_gbuffer_depth;
uniform sampler2D u_gbuffer_orm;

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
uniform float u_max_distance;

out vec4 FragColor;

void main() 
{	
	vec2 uv = gl_FragCoord.xy / u_resolution;
	float depth = texture(u_gbuffer_depth, uv).r;

    if (depth >= 1.0) discard;

	// G-Buffer
	vec3 base_color = texture(u_gbuffer_color, uv).rgb;
	base_color = gammaToLinear(base_color);
	vec3 N = normalize(texture(u_gbuffer_normal, uv).xyz * 2.0 - 1.0);
    vec3 orm = texture(u_gbuffer_orm, uv).rgb;
    float roughness = orm.g;
    float metallic = orm.b;

	// posiciones
	vec4 screen_pos = vec4(uv.x * 2.0 - 1.0, uv.y * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
	vec4 proj_world_pos = u_inverse_viewprojection * screen_pos;
	vec3 pixel_world_pos = proj_world_pos.xyz / proj_world_pos.w;

	// luz
	vec3 V = normalize(u_camera_position - pixel_world_pos);
	float distance = length(u_light_position - pixel_world_pos);

	if (distance > u_max_distance) discard;

    vec3 L = normalize(u_light_position - pixel_world_pos);
	vec3 H = normalize(V + L);
	vec3 F0 = mix(vec3(0.04), base_color, metallic);

	float attenuation = u_light_intensity / max(distance * distance, 0.0001);

	// SPOT
    if (u_light_type == 2) { 
		vec3 D = normalize(u_light_direction);
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

    float NdotL = max(dot(N, L), 0.0);
    float NdotV = max(dot(N, V), 0.0);

    float Dist = DistributionGGX(N, H, roughness);
    float G = GeometrySmith(N, V, L, roughness);
    vec3 F = fresnelSchlick(max(dot(H, V), 0.0), F0);

    vec3 spec_num = Dist * G * F;
    float spec_den = 4.0 * NdotV * NdotL + 0.0001;
    vec3 specular = spec_num / spec_den;

    vec3 kD = (vec3(1.0) - F) * (1.0 - metallic);
    
    vec3 diffuse = (kD * base_color / PI);
    vec3 result = (diffuse + specular) * gammaToLinear(u_light_color) * attenuation * NdotL;

	result = linearToGamma(result);
    FragColor = vec4(result, 1.0);
}

\ssao.fs
#version 330 core

in vec2 v_uv;

out vec4 FragColor;

uniform vec3 u_sample_pos[64];

uniform int u_sample_count;
uniform float u_sample_radius;

uniform mat4 u_p_mat;
uniform mat4 u_inv_p_mat;
uniform mat4 u_v_mat;

uniform vec2 u_res_inv;

uniform sampler2D u_depth_tex;
uniform sampler2D u_normal_tex;
void main()
{
    vec2 uv = v_uv + 0.5 * u_res_inv;

    float depth = texture(u_depth_tex, uv).r;

    if(depth >= 1.0)
    {
        FragColor = vec4(1.0);
        return;
    }

    vec4 clip_coords = vec4(uv, depth, 1.0);
    clip_coords.xyz = clip_coords.xyz * 2.0 - 1.0;

    vec4 view_sample_origin = u_inv_p_mat * clip_coords;
    view_sample_origin /= view_sample_origin.w;

    float ao_term = 0.0;

    for(int i = 0; i < u_sample_count; i++)
    {
        vec3 view_sample = u_sample_pos[i];

        view_sample *= u_sample_radius;

        view_sample += view_sample_origin.xyz;

        vec4 proj_sample = u_p_mat * vec4(view_sample, 1.0);

        proj_sample /= proj_sample.w;

        vec2 sample_uv = proj_sample.xy * 0.5 + 0.5;

        float sample_depth = texture(u_depth_tex, sample_uv).r;

        float sample_depth_proj = proj_sample.z * 0.5 + 0.5;

        if(sample_depth >= sample_depth_proj)
            ao_term += 1.0;
    }

    ao_term /= float(u_sample_count);
    FragColor = vec4(vec3(ao_term), 1.0);
}

\tonemapper.fs
#version 330 core

#include "pbr_functions"

in vec2 v_uv;

uniform float u_scale;
uniform float u_average_lum;
uniform float u_lumwhite2;
uniform float u_igamma;
uniform sampler2D u_texture;

out vec4 FragColor;

void main(){
	vec4 color = texture2D( u_texture, v_uv );
	vec3 rgb = color.xyz;

	float lum = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
	float L = (u_scale / u_average_lum);
	float Ld = (L*(1.0 + L / u_lumwhite2)) / (1.0 + L);

	rgb = (rgb / lum) * Ld;
	rgb = max(rgb, vec3(0.001));
	rgb = pow(rgb, vec3(u_igamma));
	FragColor = vec4(rgb, color.a);
}