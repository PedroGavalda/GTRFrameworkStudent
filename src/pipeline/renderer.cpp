#include "renderer.h"

#include <algorithm> //sort

#include "camera.h"
#include "../gfx/gfx.h"
#include "../gfx/shader.h"
#include "../gfx/mesh.h"
#include "../gfx/texture.h"
#include "../gfx/fbo.h"
#include "../pipeline/prefab.h"
#include "../pipeline/material.h"
#include "../pipeline/animation.h"
#include "../utils/utils.h"
#include "../extra/hdre.h"
#include "../core/ui.h"

using namespace SCN;

//some globals
GFX::Mesh sphere;

Renderer::Renderer(const char* shader_atlas_filename)
{
	render_wireframe = false;
	render_boundaries = false;
	scene = nullptr;
	skybox_cubemap = nullptr;


	if (!GFX::Shader::LoadAtlas(shader_atlas_filename))
		exit(1);
	GFX::checkGLErrors();

	sphere.createSphere(1.0f);
	sphere.uploadToVRAM();
	gbuffer_fbo.create(1920, 1200, 2, GL_RGBA, GL_UNSIGNED_BYTE, true);
}

void Renderer::setupScene()
{
	if (scene->skybox_filename.size())
		skybox_cubemap = GFX::Texture::Get(std::string(scene->base_folder + "/" + scene->skybox_filename).c_str());
	else
		skybox_cubemap = nullptr;
}

std::vector<sRenderable> render_list;

std::vector<LightEntity*> light_list;

void parseNode(Node* node) {
	if (!node) {
		return; //not analyze empty nodes
	}

	render_list.push_back({
		.mesh = node->mesh,
		.material = node->material,
		.model = node->getGlobalMatrix()
		});

	for (Node* child : node->children) {
		parseNode(child);
	}
}


void Renderer::parseSceneEntities(SCN::Scene* scene, Camera* cam) {
	// HERE =====================
	// TODO: GENERATE RENDERABLES
	// ==========================
	render_list.clear();
	light_list.clear();

	for (int i = 0; i < scene->entities.size(); i++) {
		BaseEntity* entity = scene->entities[i];

		if (!entity->visible) {
			continue;
		}

		// PREFABS
		if (entity->getType() == eEntityType::PREFAB) {
			//
			PrefabEntity* e = (PrefabEntity*)entity;

			parseNode(&(e->root));

		}

		// LIGHTS
		if (entity->getType() == eEntityType::LIGHT) {
			LightEntity* light = (LightEntity*)entity;
			light_list.push_back(light);
		}
	}

}

void Renderer::generateShadowMap(std::vector<sRenderable*> opaque) {
	for (int i = 0; i < light_list.size(); i++) {

		shadow_fbos[i]->bind();

		glEnable(GL_CULL_FACE);
		if (use_front_face_culling)
			glCullFace(GL_FRONT);
		else
			glCullFace(GL_BACK);

		glColorMask(false, false, false, false);

		glClear(GL_DEPTH_BUFFER_BIT);

		// Camera Setups
		LightEntity* light = light_list[i];

		mat4 light_model = light->root.getGlobalMatrix();
		vec3 light_pos = light_model.getTranslation();
		vec3 light_dir = normalize(light_model.frontVector());
		light_cameras[i]->lookAt(light_pos, light_dir * vec3(0.0f, 0.0f, -1.0f), vec3(0.0f, 1.0f, 0.0f));

		//DIRECTIONAL LIGHT
		if (light->light_type == DIRECTIONAL) {
			float half_size = light->area / 2.0f;
			light_cameras[i]->setOrthographic(-half_size, half_size, -half_size, half_size, light->near_distance, light->max_distance);
		}

		//SPOTLIGHT
		else if (light->light_type == SPOT) {
			//codigo del sushant que se tiene que cambiar
			float fov = (light->cone_info.y * 2.0f);
			light_cameras[i]->setPerspective(fov, 1.0f, light->near_distance, light->max_distance);
		}
		else {
			goto point;
		}

		//mat4 light_vps = light_cameras[i]->viewprojection_matrix;

		for (const auto& r : opaque) {
			renderPlain(light_cameras[i].get(), r->model, r->mesh, r->material);
		}

	point:
		glColorMask(true, true, true, true);

		glCullFace(GL_BACK);
		glDisable(GL_CULL_FACE);

		shadow_fbos[i]->unbind();
	}
}

void Renderer::renderPlain(Camera* camera, const Matrix44 model, GFX::Mesh* mesh, SCN::Material* material) {
	//in case there is nothing to do
	if (!mesh || !mesh->getNumVertices() || !material)
		return;
	assert(glGetError() == GL_NO_ERROR);

	//define locals to simplify coding
	GFX::Shader* shader = NULL;

	glEnable(GL_DEPTH_TEST);

	//chose a shader
	shader = GFX::Shader::Get("plain");

	assert(glGetError() == GL_NO_ERROR);

	//no shader? then nothing to render
	if (!shader)
		return;
	shader->enable();

	//upload uniforms
	shader->setUniform("u_model", model);

	// Upload camera uniforms
	shader->setUniform("u_viewprojection", camera->viewprojection_matrix);
	shader->setUniform("u_camera_position", camera->eye);

	// Upload time, for cool shader effects
	float t = getTime();
	shader->setUniform("u_time", t);

	// Render just the verticies as a wireframe
	if (render_wireframe)
		glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);

	material->bind(shader);
	//do the draw call that renders the mesh into the screen
	mesh->render(GL_TRIANGLES);

	//disable shader
	shader->disable();

	//set the render state as it was before to avoid problems with future renders
	glDisable(GL_BLEND);
	glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
}

void Renderer::renderScene(SCN::Scene* scene, Camera* camera)
{

	this->scene = scene;
	setupScene();

	parseSceneEntities(scene, camera);
	if (num_lights < light_list.size()) {
		for (int i = num_lights; i < light_list.size(); i++) {
			shadow_fbos.push_back(std::make_unique<GFX::FBO>());
			light_cameras.push_back(std::make_unique<Camera>());
			shadow_fbos[i]->setDepthOnly(1024, 1024);
			num_lights++;
		}
	}

	//set the clear color (the background color)
	glClearColor(scene->background_color.x, scene->background_color.y, scene->background_color.z, 1.0);

	std::vector<sRenderable*> opaque;
	std::vector<sRenderable*> transparent;
	for (auto& r : render_list) {
		if (!r.material) continue;
		if (r.material->alpha_mode == BLEND)
			transparent.push_back(&r);
		else
			opaque.push_back(&r);
	}

	std::sort(opaque.begin(), opaque.end(), [&](sRenderable* a, sRenderable* b) {
		float da = (a->model.getTranslation() - camera->eye).length();
		float db = (b->model.getTranslation() - camera->eye).length();
		return da < db;}
	);
	std::sort(transparent.begin(), transparent.end(), [&](sRenderable* a, sRenderable* b) {
		float da = (a->model.getTranslation() - camera->eye).length();
		float db = (b->model.getTranslation() - camera->eye).length();
		return da > db;}
	);
	updateLights();

	// Clear the color and the depth buffer
	gbuffer_fbo.bind();
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	for (auto* r : opaque) {
		if (is_in_frustum(r, camera)) {
			renderMeshWithMaterial(r->model, r->mesh, r->material, "gbuffer_fill");
		}
	}
	gbuffer_fbo.unbind();
	GFX::checkGLErrors();
	Camera* player_cam = camera;


	generateShadowMap(opaque);
	player_cam->enable();

	glDisable(GL_DEPTH_TEST);
	glDisable(GL_BLEND);
	GFX::Mesh* quad = GFX::Mesh::getQuad();
	GFX::Shader* light_pass_shader;
	light_pass_shader = GFX::Shader::Get("deferred_light");
	light_pass_shader->enable();
	sendLightUniforms(light_pass_shader);
	Matrix44 inverse_matrix = camera->viewprojection_matrix;
	inverse_matrix.inverse();
	light_pass_shader->setUniform("u_inverse_viewprojection", inverse_matrix);
	light_pass_shader->setUniform("u_camera_position", camera->eye);
	light_pass_shader->setTexture("u_gbuffer_color", gbuffer_fbo.color_textures[0], 0);
	light_pass_shader->setTexture("u_gbuffer_normal", gbuffer_fbo.color_textures[1], 1);
	light_pass_shader->setTexture("u_gbuffer_depth", gbuffer_fbo.depth_texture, 2);
	quad->render(GL_TRIANGLES);

	light_pass_shader->disable();
	glEnable(GL_DEPTH_TEST);

	//render skybox
	if (skybox_cubemap)
		renderSkybox(skybox_cubemap);

	//HERE =====================
	//TODO: RENDER RENDERABLES
	//==========================

	for (auto* r : opaque) {
		if (is_in_frustum(r, camera)) {
			renderMeshWithMaterial(r->model, r->mesh, r->material, "phong");
		}
	}
	for (auto* r : transparent) {
		if (is_in_frustum(r, camera)) {
			renderMeshWithMaterial(r->model, r->mesh, r->material, "phong");
		}
	}

}


bool Renderer::is_in_frustum(sRenderable* r, Camera* camera) {
	if (!r || !camera)
		return false;
	vec3 aabb_min = r->mesh->aabb_min;
	vec3 aabb_max = r->mesh->aabb_max;
	vec3 aabb_coordinates[8];
	int counter_outs = 0;
	for (int i = 0;i < 8;i++) {
		aabb_coordinates[i] = aabb_min;
		if (i >= 4) aabb_coordinates[i].x = aabb_max.x;
		if (i % 4 == 2 || i % 4 == 3) aabb_coordinates[i].y = aabb_max.y;
		if (i % 2 == 1) aabb_coordinates[i].z = aabb_max.z;
		aabb_coordinates[i] = r->model * aabb_coordinates[i];
	}
	for (int i = 0;i < 6;i++) {
		for (int j = 0;j < 8;j++) {
			if (camera->frustum[i][0] * aabb_coordinates[j].x + camera->frustum[i][1] * aabb_coordinates[j].y + camera->frustum[i][2] * aabb_coordinates[j].z + camera->frustum[i][3] >= 0) {
				break;
			}
			if (j == 7) return false;
		}
	}
	return true;
}

void Renderer::renderSkybox(GFX::Texture* cubemap)
{
	Camera* camera = Camera::current;

	// Apply skybox necesarry config:
	// No blending, no dpeth test, we are always rendering the skybox
	// Set the culling aproppiately, since we just want the back faces
	glDisable(GL_BLEND);
	glDisable(GL_DEPTH_TEST);
	glDisable(GL_CULL_FACE);

	if (render_wireframe)
		glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);

	GFX::Shader* shader = GFX::Shader::Get("skybox");
	if (!shader)
		return;
	shader->enable();

	// Center the skybox at the camera, with a big sphere
	Matrix44 m;
	m.setTranslation(camera->eye.x, camera->eye.y, camera->eye.z);
	m.scale(10, 10, 10);
	shader->setUniform("u_model", m);

	// Upload camera uniforms
	shader->setUniform("u_viewprojection", camera->viewprojection_matrix);
	shader->setUniform("u_camera_position", camera->eye);

	shader->setUniform("u_texture", cubemap, 0);

	sphere.render(GL_TRIANGLES);

	shader->disable();

	// Return opengl state to default
	glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
	glEnable(GL_DEPTH_TEST);
}


std::vector<vec3> positions;
std::vector<vec3> colors;
std::vector<float> intensities;
std::vector<int> types;
std::vector<vec3> directions;
std::vector<vec2> cones;

void Renderer::updateLights() {
	positions.clear();
	colors.clear();
	intensities.clear();
	types.clear();
	directions.clear();
	cones.clear();

	for (LightEntity* l : light_list) {
		positions.push_back(l->root.getGlobalMatrix().getTranslation());
		colors.push_back(l->color);
		intensities.push_back(l->intensity);

		types.push_back(l->light_type);

		vec3 dir = l->root.getGlobalMatrix().frontVector();
		directions.push_back(dir);

		float alpha_min = l->cone_info.x * DEG2RAD;
		float alpha_max = l->cone_info.y * DEG2RAD;
		cones.push_back(vec2(cos(alpha_min), cos(alpha_max)));
	}
	for (int i = 0; i < light_list.size(); i++) {
		LightEntity* light = light_list[i];

		mat4 light_model = light->root.getGlobalMatrix();
		vec3 light_pos = light_model.getTranslation();

		light_cameras[i]->lookAt(
			light_pos,
			light_pos + light_model.frontVector(),
			vec3(0.0f, 1.0f, 0.0f)
		);

		if (light->light_type == SPOT) {
			float fov = light->cone_info.y * 2.0f;
			light_cameras[i]->setPerspective(fov, 1.0f, 0.1f, 100.0f);
		}
	}
}

// Renders a mesh given its transform and material
void Renderer::renderMeshWithMaterial(const Matrix44 model, GFX::Mesh* mesh, SCN::Material* material, const char* type_shader)
{
	//in case there is nothing to do
	if (!mesh || !mesh->getNumVertices() || !material)
		return;
	assert(glGetError() == GL_NO_ERROR);

	//define locals to simplify coding
	GFX::Shader* shader = NULL;
	Camera* camera = Camera::current;

	glEnable(GL_DEPTH_TEST);

	//chose a shader
	shader = GFX::Shader::Get(type_shader);

	assert(glGetError() == GL_NO_ERROR);

	//no shader? then nothing to render
	if (!shader)
		return;
	shader->enable();

	int num_lights = light_list.size();
	shader->setUniform("u_num_lights", num_lights);


	if (num_lights > 0) {
		shader->setUniform3Array("u_light_position", &positions[0].x, num_lights);
		shader->setUniform3Array("u_light_color", &colors[0].x, num_lights);
		shader->setUniform1Array("u_light_intensity", intensities.data(), num_lights);
		shader->setUniform1Array("u_light_type", types.data(), num_lights);
		shader->setUniform3Array("u_light_direction", &directions[0].x, num_lights);
		shader->setUniform2Array("cones", &cones[0].x, num_lights);
	}

	shader->setUniform("u_ambient_light", scene->ambient_light);
	shader->setUniform("u_shadow_bias", shadow_bias);

	int spot_index = -1;
	int dir_index = -1;

	for (int i = 0; i < light_list.size(); i++) {
		if (light_list[i]->light_type == SPOT && spot_index == -1)
			spot_index = i;
		else if (light_list[i]->light_type == DIRECTIONAL && dir_index == -1)
			dir_index = i;
	}

	if (spot_index != -1 && spot_index < light_cameras.size())
		shader->setUniform("u_spot_light_viewprojection", light_cameras[spot_index]->viewprojection_matrix);

	if (dir_index != -1 && dir_index < light_cameras.size())
		shader->setUniform("u_directional_light_viewprojection", light_cameras[dir_index]->viewprojection_matrix);

	material->bind(shader);

	//upload uniforms
	shader->setUniform("u_model", model);

	// Upload camera uniforms
	shader->setUniform("u_viewprojection", camera->viewprojection_matrix);
	shader->setUniform("u_camera_position", camera->eye);

	// Upload time, for cool shader effects
	float t = getTime();
	shader->setUniform("u_time", t);

	if (spot_index != -1 && spot_index < shadow_fbos.size())
		shader->setUniform("u_spot_shadow_map", shadow_fbos[spot_index]->depth_texture, 3);

	if (dir_index != -1 && dir_index < shadow_fbos.size())
		shader->setUniform("u_directional_shadow_map", shadow_fbos[dir_index]->depth_texture, 4);

	// Render just the verticies as a wireframe
	if (render_wireframe)
		glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);

	//do the draw call that renders the mesh into the screen
	mesh->render(GL_TRIANGLES);

	//disable shader
	shader->disable();

	//set the render state as it was before to avoid problems with future renders
	glDisable(GL_BLEND);
	glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
}

#ifndef SKIP_IMGUI

void Renderer::showUI()
{

	ImGui::Checkbox("Wireframe", &render_wireframe);
	ImGui::Checkbox("Boundaries", &render_boundaries);

	//add here your stuff
	ImGui::SliderFloat("Shininess", &global_shininess, 1.0f, 100.0f);
	ImGui::SliderFloat("Shadow Bias", &shadow_bias, 0.0001f, 0.01f, "%.4f", ImGuiSliderFlags_Logarithmic);
	ImGui::Checkbox("Forward Face Culling", &use_front_face_culling);
}

void Renderer::sendLightUniforms(GFX::Shader* shader) {
	int num_lights = light_list.size();
	shader->setUniform("u_num_lights", num_lights);

	if (num_lights > 0) {
		shader->setUniform3Array("u_light_position", &positions[0].x, num_lights);
		shader->setUniform3Array("u_light_color", &colors[0].x, num_lights);
		shader->setUniform1Array("u_light_intensity", intensities.data(), num_lights);
		shader->setUniform1Array("u_light_type", types.data(), num_lights);
		shader->setUniform3Array("u_light_direction", &directions[0].x, num_lights);
		shader->setUniform2Array("cones", &cones[0].x, num_lights);
	}

	shader->setUniform("u_ambient_light", scene->ambient_light);
	shader->setUniform("u_shadow_bias", shadow_bias);

	int spot_index = -1;
	int dir_index = -1;
	for (int i = 0; i < light_list.size(); i++) {
		if (light_list[i]->light_type == SPOT && spot_index == -1) spot_index = i;
		else if (light_list[i]->light_type == DIRECTIONAL && dir_index == -1) dir_index = i;
	}

	if (spot_index != -1 && spot_index < light_cameras.size()) {
		shader->setUniform("u_spot_light_viewprojection", light_cameras[spot_index]->viewprojection_matrix);
		shader->setUniform("u_spot_shadow_map", shadow_fbos[spot_index]->depth_texture, 3);
	}

	if (dir_index != -1 && dir_index < light_cameras.size()) {
		shader->setUniform("u_directional_light_viewprojection", light_cameras[dir_index]->viewprojection_matrix);
		shader->setUniform("u_directional_shadow_map", shadow_fbos[dir_index]->depth_texture, 4);
	}
}

#else
void Renderer::showUI() {}
#endif