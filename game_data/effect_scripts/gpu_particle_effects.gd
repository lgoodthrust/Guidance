class_name gpu_particle_effects

extends RefCounted

func explotion_01() -> GPUParticles3D:
	var c = Curve.new()
	c.bake_resolution = 32
	c.add_point(Vector2(0,1), 0, -1)
	c.add_point(Vector2(1,0), -1, 0)
	
	var ct = CurveTexture.new()
	ct.width = 32
	ct.curve = c
	
	var ppm = ParticleProcessMaterial.new()
	ppm.inherit_velocity_ratio = 0.01
	ppm.initial_velocity_min = 25.0
	ppm.initial_velocity_max = 50.0
	ppm.spread = 180.0
	ppm.gravity = Vector3.ZERO
	ppm.scale_min = 0.5
	ppm.scale_max = 1.0
	ppm.scale_curve = ct
	
	var sm = StandardMaterial3D.new()
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	sm.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	sm.disable_ambient_light = true
	sm.emission_enabled = true
	sm.emission = Color8(255,255,255,255)
	
	var bm = BoxMesh.new()
	bm.size = Vector3(0.5,0.5,0.5)
	bm.material = sm
	
	var gpup = GPUParticles3D.new()
	gpup.amount = 150
	gpup.one_shot = true
	gpup.lifetime = 0.75
	gpup.explosiveness = 1.0
	gpup.fixed_fps = 15
	gpup.process_material = ppm
	gpup.draw_pass_1 = bm
	
	return gpup


func smoke_01() -> GPUParticles3D:
	var color = Color8(25, 25, 25, 255)
	
	var bmm = StandardMaterial3D.new()
	bmm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	bmm.albedo_color = color
	bmm.emission_enabled = true
	bmm.emission = color
	bmm.emission_energy_multiplier = 1.0
	
	var bm = BoxMesh.new()
	bm.size = Vector3(0.2, 0.2, 0.2)
	bm.material = bmm
	
	var ppm = ParticleProcessMaterial.new()
	ppm.gravity = Vector3.UP * 0.25
	ppm.inherit_velocity_ratio = 0.0
	
	var gpup = GPUParticles3D.new()
	gpup.amount = 500
	gpup.one_shot = false
	gpup.fixed_fps = 45
	gpup.explosiveness = 0.0
	gpup.lifetime = 3.0
	gpup.process_material = ppm
	gpup.draw_passes = 1
	gpup.draw_pass_1 = bm
	
	return gpup
