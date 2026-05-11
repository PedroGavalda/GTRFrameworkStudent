#pragma once
#include "scene.h"
#include "prefab.h"

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

#include "light.h"

//forward declarations
class Camera;
class Skeleton;
namespace GFX {
	class Shader;
	class Mesh;
	class FBO;
}


namespace SCN {

	class Prefab;
	class Material;
	struct sRenderable {
		GFX::Mesh* mesh = nullptr; //the thing we want to render
		Material* material = nullptr;
		Matrix44 model; //where we want to render it 

	};

	// This class is in charge of rendering anything in our system.
	// Separating the render from anything else makes the code cleaner
	class Renderer
	{
	public:
		std::vector<std::unique_ptr<GFX::FBO>> shadow_fbos;
		std::vector<std::unique_ptr<Camera>> light_cameras;
		int num_lights = 0;
		bool render_wireframe;
		bool render_boundaries;

		GFX::Texture* skybox_cubemap;
		GFX::FBO gbuffer_fbo;
		GFX::FBO illumination_fbo;
		SCN::Scene* scene;
		GFX::FBO lighting_FBO;
		GFX::FBO ssao_fbo;

		//updated every frame
		Renderer(const char* shaders_atlas_filename );

		//just to be sure we have everything ready for the rendering
		void setupScene();

		//add here your functions
		//...

		void parseSceneEntities(SCN::Scene* scene, Camera* camera);

		//renders several elements of the scene
		void renderScene(SCN::Scene* scene, Camera* camera);

		//render the skybox
		void renderSkybox(GFX::Texture* cubemap);

		//to render one mesh given its material and transformation matrix
		void renderMeshWithMaterial(const Matrix44 model, GFX::Mesh* mesh, SCN::Material* material, const char* type_shader);

		void showUI();

		bool is_in_frustum(sRenderable* r, Camera* camera);

		void updateLights();

		void generateShadowMap(std::vector<sRenderable*> opaque);

		void renderPlain(Camera* camera, const Matrix44 model, GFX::Mesh* mesh, SCN::Material* material);

		float shadow_bias = 0.0001f;
		bool use_front_face_culling = true;

		void sendLightUniforms(GFX::Shader* shader);

		void renderAmbientAndDirectional(Camera* camera);
		void renderLightVolume(const Matrix44& model, LightEntity* light, Camera* camera, float max_dist);
		bool use_deferred = true;

		void renderSSAO(Camera* camera);
		int ssao_sample_count = 32;
		float ssao_radius = 0.01f;
		std::vector<vec3> ssao_samples;
	};

};