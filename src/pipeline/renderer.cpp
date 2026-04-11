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

void Renderer::renderScene(SCN::Scene* scene, Camera* camera)
{
	this->scene = scene;
	setupScene();

	parseSceneEntities(scene, camera);

	//set the clear color (the background color)
	glClearColor(scene->background_color.x, scene->background_color.y, scene->background_color.z, 1.0);

	// Clear the color and the depth buffer
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	GFX::checkGLErrors();

	//render skybox
	if (skybox_cubemap)
		renderSkybox(skybox_cubemap);

	// HERE =====================
	// TODO: RENDER RENDERABLES
	// ==========================
	std::vector<sRenderable*> opaque;
	std::vector<sRenderable*> transparent;
	for (auto& r : render_list){
		if (!r.material) continue;
		if (r.material->alpha_mode == BLEND)
			transparent.push_back(&r);
		else
			opaque.push_back(&r);
	}
	std::sort(opaque.begin(), opaque.end(), [&](sRenderable* a, sRenderable* b){
		float da = (a->model.getTranslation() - camera->eye).length();
		float db = (b->model.getTranslation() - camera->eye).length();
		return da < db;}
	);
	std::sort(transparent.begin(), transparent.end(), [&](sRenderable* a, sRenderable* b) {
		float da = (a->model.getTranslation() - camera->eye).length();
		float db = (b->model.getTranslation() - camera->eye).length();
		return da > db;}
	);
	for (auto* r : opaque) {
		if (is_in_frustum(r, camera)) {
			renderMeshWithMaterial(r->model, r->mesh, r->material);
		}
	}
	for (auto* r : transparent) {
		if (is_in_frustum(r, camera)) {
			renderMeshWithMaterial(r->model, r->mesh, r->material);
		}
	}

}

bool Renderer::is_in_frustum(sRenderable* r, Camera* camera) {
	if (!r || !camera)
		return false;
	vec3 aabb_min_world = r->model*r->mesh->aabb_min;
	vec3 aabb_max_world = r->model * r->mesh->aabb_max;
	vec3 aabb_coordinates[8];
	int counter_outs = 0;
	for (int i = 0;i < 8;i++) {
		aabb_coordinates[i] = aabb_min_world;
		if (i>=4) aabb_coordinates[i].x = aabb_max_world.x;
		if (i % 4 == 2 || i % 4 == 3) aabb_coordinates[i].y = aabb_max_world.y;
		if (i % 2 == 1) aabb_coordinates[i].z = aabb_max_world.z;
	}
	for (int i = 0;i < 6;i++) {
		for (int j = 0;j < 8;j++) {
			if (camera->frustum[i][0] * aabb_coordinates[j].x + camera->frustum[i][1] * aabb_coordinates[j].y + camera->frustum[i][2] * aabb_coordinates[j].z + camera->frustum[i][3] > 0) {
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

// Renders a mesh given its transform and material
void Renderer::renderMeshWithMaterial(const Matrix44 model, GFX::Mesh* mesh, SCN::Material* material)
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
	shader = GFX::Shader::Get("phong");

	assert(glGetError() == GL_NO_ERROR);

	//no shader? then nothing to render
	if (!shader)
		return;
	shader->enable();

	LightEntity* light = light_list.empty() ? nullptr : light_list[0];
	if (light) {
		shader->setUniform("u_light_position", light->root.getGlobalMatrix().getTranslation());
		shader->setUniform("u_light_color", light->color);
		shader->setUniform("u_light_intensity", light->intensity);
	}

	shader->setUniform("u_ambient_light", scene->ambient_light);

	material->bind(shader);

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
	//...
}

#else
void Renderer::showUI() {}
#endif