extends Node

#References
#Camera currently controlled by the FX system
#Camera attached to player
var _player_camera: Camera2D = null;
#Active camera, player or cinematic
var _active_camera: Camera2D = null;
#Cinematic camera and director are per-world
var _cinematic_camera: Camera2D = null;
var _camera_director: CameraDirector = null;
#Optional vignette material reference
var _vignette_material: ShaderMaterial = null

#Camera Shake
var _shake_time: float = 0.0
var _shake_duration: float = 0.0
var _shake_strength: float = 0.0
var _shake_base_offset: Vector2 = Vector2.ZERO



#region Public API
#Register the current camera (call this in Camera._ready())
func set_player_camera(camera: Camera2D) -> void:
	_player_camera = camera;
	#If no active camera yet, default to player camera
	if _active_camera == null:
		set_active_camera(camera);

func get_player_camera() -> Camera2D:
	return _player_camera;
	
func set_active_camera(camera: Camera2D) -> void:
	_active_camera = camera;
	if _active_camera != null:
		_shake_base_offset = _active_camera.offset;
	
func get_active_camera() -> Camera2D:
	return _active_camera;
	
func set_camera_director(d: CameraDirector) -> void:
	_camera_director = d;
	
func get_camera_director() -> CameraDirector:
	return _camera_director;
	
#Called from WorldScene when it creates/owns cinematic camera
func set_cinematic_camera(camera: Camera2D) -> void:
	_cinematic_camera = camera;
	
#Focus and hold position
func play_focus_world_position_and_hold(
	world_pos: Vector2,
	pan_duration: float = 0.8,
	hold_duration: float = 2.0,
) -> void:
	if _camera_director == null or _player_camera == null:
		return;
	if not _camera_director.has_method("pan_to_world_position_and_hold"):
		return;
	#Safety checks passed, deal with camera pan
	_camera_director.call("pan_to_world_position_and_hold", world_pos, pan_duration, hold_duration);
	
#High level api used by UIRouter/Quests/Cutscenes
func play_focus_world_position(
	world_pos: Vector2,
	pan_duration: float = 0.6,
	hold_duration: float = 1.0,
	return_duration: float = 0.6
) -> void:
	#No camera director exists
	if _camera_director == null or _player_camera == null:
		return;
	#Pan to world position method doesn't exist
	if not _camera_director.has_method("pan_to_world_position"):
		return;
		
	#Safety checks passed
	_camera_director.call("pan_to_world_position", world_pos, pan_duration, hold_duration, return_duration);
	
#Plays the full building upgrade cinematic 
#Call with await--resolves when camera has fully returned
func play_building_upgrade_cinematic(quest_id: String) -> void:
	#Resolve quest - building
	if not UIRouter.QUEST_REPAIR_BUILDING_MAP.has(quest_id):
		return;
	#Found the correct building, continue
	var building_id: String = String(UIRouter.QUEST_REPAIR_BUILDING_MAP[quest_id]);
	
	#Find the building in the actual scene tree
	var target_building: BuildingRoot = null;
	for building in get_tree().get_nodes_in_group("buildings"):
		if building is BuildingRoot and (building as BuildingRoot).building_id == building_id:
			target_building = building as BuildingRoot;
			break;
	#No building was found
	if target_building == null:
		push_warning("No target_building was found.")
		return;
		
	if _camera_director == null:
		return;
		
	#Pan to building and hold
	var building_pos: Vector2 = target_building.get_focus_world_position();
	play_focus_world_position_and_hold(building_pos, 0.8, 0.3);
	
	#Wait for camera to arrive at the building
	await _camera_director.focus_reached;
	
	#Trigger the upgrade transition
	target_building.play_upgrade_to_stage(1);
	
	#Wait for transition and a brief pause
	await get_tree().create_timer(target_building.stage_transition_duration + 0.5).timeout;
	
	#Play the release hold with return tween
	await _camera_director.release_hold_with_return();

#Register vignette material (call this from wherever you create the overlay)
func set_vignette_material(mat: ShaderMaterial) -> void:
	_vignette_material = mat;

#Trigger a camera shake
func shake_camera(strength: float, duration: float) -> void:
	#Need to add to Options menu--use calm visual mode for now
	if Settings.reduce_screen_shake:
		return;
	
	if _active_camera == null:
		return;
	
	#Set shake parameters
	_shake_strength = strength;
	_shake_duration = duration;
	_shake_time = duration;
	_shake_base_offset = _active_camera.offset;

#Trigger a damage flash using vignette
func damage_flash(intensity: float = 0.6, duration: float = 0.2) -> void:
	
	if _vignette_material == null:
		return
	
	#Only show if calm visual mode isn't enabled
	if Settings.calm_visual_mode:
		return;
	
	#Get baseline vignette style so it can revert back after damage
	var base_colour = Color(0,0,0);
	var base_opacity: float = 0.3;
	
	var hit_colour = Color(0.6, 0.0, 0.0);
	var hit_opacity = intensity;
	
	#Start from the hit flash state
	_vignette_material.set_shader_parameter("vignette_rgb", hit_colour);
	_vignette_material.set_shader_parameter("vignette_opacity", hit_opacity);
	
	var tween := create_tween();
	
	#Tween a 0+1 progress value and lerp both colours and opacity
	tween.tween_method(
		func(t: float) -> void:
			#t = 0 fully hit, t = 1 fully base
			var colour = hit_colour.lerp(base_colour, t);
			var opacity = lerp(hit_opacity, base_opacity, t);
			_vignette_material.set_shader_parameter("vignette_rgb", colour);
			_vignette_material.set_shader_parameter("vignette_opacity", opacity),
		0.0, 1.0, duration
	)
#endregion

#region Internal helpers
func _process(delta: float) -> void:
	_update_shake(delta);

func _update_shake(delta: float) -> void:
	if _active_camera == null:
		return;
	
	if _shake_time <= 0.0:
		#Reset to base offset
		_active_camera.offset = _shake_base_offset;
		return;
	
	_shake_time -= delta;
	
	var progress: float = _shake_time / _shake_duration;
	var current_strength: float = _shake_strength * progress;
	
	var offset: Vector2 = Vector2(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)
	) * current_strength
	
	_active_camera.offset = _shake_base_offset + offset;


#endregion
