extends Node
class_name CameraDirector;

#Signals so cutscene things don't start until the signal fires
signal focus_reached(world_pos: Vector2)
signal focus_finished(world_pos: Vector2) #optional, after hold+return

@export_group("Default Timing")
@export var default_pan_duration: float = 0.8;
@export var default_hold_duration: float = 0.6;
@export var default_return_duration: float = 0.8;
@export var item_get_zoom_scale: float = 1.25;
@export var item_get_zoom_duration: float = 0.25;
@export var item_get_offset_y: float = -32.0;

@onready var cinematic_camera: Camera2D = $CinematicCamera;
const LOCK_SOURCE: String = "cinematic_camera";
#Camera states
enum CameraState {PLAYER, CINEMATIC};
var _state: CameraState = CameraState.PLAYER;
var _tween: Tween = null;
#Item zoom tween stuffs
var _item_get_zoom_tween: Tween = null;
var _item_get_saved_zoom: Vector2 = Vector2.ONE;
var _item_get_saved_offset: Vector2 = Vector2.ZERO;
#Smooth follow target
var _follow_target: Node2D = null;
var _follow_lerp_speed: float = 5.0;


func _ready() -> void:
	_state = CameraState.PLAYER;
	VisualFX.set_camera_director(self);
	VisualFX.set_cinematic_camera(cinematic_camera);
	
func _process(delta: float) -> void:
	if _follow_target == null:
		return;
	if _state != CameraState.CINEMATIC:
		return;
	if not is_instance_valid(_follow_target):
		_follow_target = null;
		return;
	#Safety checks passed
	var target_pos = _clamp_to_limits(_follow_target.global_position, cinematic_camera);
	cinematic_camera.global_position = cinematic_camera.global_position.lerp(
		target_pos,
		clampf(_follow_lerp_speed * delta, 0.0, 1.0)
	);
	
#Public helpers for following player 
func start_follow(target: Node2D) -> void:
	_follow_target = target;
	
func stop_follow() -> void:
	_follow_target = null;
	
#Check if camera is currently busy
func is_busy() -> bool:
	return _state == CameraState.CINEMATIC;
	
#Cancel the cinematic camera
func cancel() -> void:
	if _tween and _tween.is_valid():
		_tween.kill();
	_tween = null;
	
	#Hand back to player camera is possible
	var player_cam = _get_player_camera();
	if player_cam:
		_end_to_player(player_cam);
	_state = CameraState.PLAYER;
	
	#In case _end_to_player didn't run
	Game.pop_input_lock(LOCK_SOURCE);
	
#Pan to target and hold, does not return to player--for cutscenes
#Emits focus_reached when the pan hold completes, then waits. Caller must call release_hold() when ready to return the camera to teh player
func pan_to_world_position_and_hold(
	target_world_pos: Vector2,
	pan_duration: float = -1.0,
	hold_duration: float = 1.0,
) -> void:
	if is_busy():
		push_warning("pan_to_world_position_and_hold ignored: busy.");
		return;
		
	var player_cam = _get_player_camera();
	if player_cam == null:
		push_warning("pan_to_world_position_and_hold ignored: no player camera registered.");
		return;
		
	if pan_duration < 0.0: pan_duration = default_pan_duration;
	if hold_duration < 0.0: hold_duration = default_hold_duration;
	
	#Safety checks passed, continue with the cinematic camera
	_state = CameraState.CINEMATIC;
	Game.push_input_lock(LOCK_SOURCE);
	
	_sync_from_player_camera(player_cam);
	
	var start_pos = player_cam.get_screen_center_position();
	start_pos = _clamp_to_limits(start_pos, cinematic_camera);
	cinematic_camera.global_position = start_pos;
	cinematic_camera.offset = player_cam.offset;
	
	_begin_cinematic(player_cam);
	
	var clamped_target = _clamp_to_limits(target_world_pos, cinematic_camera);
	_start_tween_to(cinematic_camera, clamped_target, pan_duration);
	await _tween.finished;
	
	if hold_duration > 0.0:
		await get_tree().create_timer(hold_duration).timeout;
	
	#Complete--need to release hold
	focus_reached.emit(clamped_target);
	#State stays cinematic until release_hold() is called
	
#Public helper to return camera to player after cutscene plays
func release_hold() -> void:
	if _state != CameraState.CINEMATIC:
		push_warning("release_hold ignored: not in cinematic state");
		return;
		
	var player_cam = _get_player_camera();
	if player_cam == null:
		#Safety restore state even without a camera
		_state = CameraState.PLAYER;
		Game.pop_input_lock(LOCK_SOURCE);
		return;
	
	#Hand the camera control back to the player camera
	_end_to_player(player_cam);
	_state = CameraState.PLAYER;
	focus_finished.emit(player_cam.global_position);
	
#Returns camera to player with a tween before releasing
func release_hold_with_return(return_duration: float = -1.0) -> void:
	if _state != CameraState.CINEMATIC:
		return;
	if return_duration < 0.0:
		return_duration = default_return_duration;
		
	var player_cam = _get_player_camera();
	if player_cam == null:
		release_hold();
		return;
		
	var return_pos = _clamp_to_limits(player_cam.get_screen_center_position(), player_cam);
	_start_tween_to(cinematic_camera, return_pos, return_duration);
	await _tween.finished;
	
	_end_to_player(player_cam);
	_state = CameraState.PLAYER;
	focus_finished.emit(return_pos);
	
#Pan to designated position in world for cinematic camera and returns to player
func pan_to_world_position(
		target_world_pos: Vector2,
		pan_duration: float = -1.0,
		hold_duration: float = -1.0,
		return_duration: float = -1.0
	) -> void:
	if is_busy():
		push_warning("pan_to_world_position ignored: busy");
		return;
		
	var player_cam = _get_player_camera();
	if player_cam == null:
		push_warning("pan_to_world_position ignored: no player camera registered.");
		return;
		
	#Default settings
	if pan_duration < 0.0: pan_duration = default_pan_duration;
	if hold_duration < 0.0: hold_duration = default_hold_duration;
	if return_duration < 0.0: return_duration = default_return_duration;
	
	_state = CameraState.CINEMATIC;
	Game.push_input_lock(LOCK_SOURCE);
	
	#Sync cinematic camera settings from player (limits, etc)
	_sync_from_player_camera(player_cam);
	
	#Start cinematic cam exactly at current view position
	var start_pos := player_cam.get_screen_center_position();
	start_pos = _clamp_to_limits(start_pos, cinematic_camera);
	cinematic_camera.global_position = start_pos;
	cinematic_camera.offset = player_cam.offset;
	
	#Switch cameras only AFTER matching position so has seamless first frame
	_begin_cinematic(player_cam);
	
	#Pan to target (clamped)
	var clamped_target = _clamp_to_limits(target_world_pos, cinematic_camera);
	_start_tween_to(cinematic_camera, clamped_target,pan_duration);
	await _tween.finished;
	
	#Hold
	if hold_duration > 0.0:
		await get_tree().create_timer(hold_duration).timeout;
		
	#Return to player's current view position
	var return_pos := player_cam.get_screen_center_position()
	var clamped_return = _clamp_to_limits(return_pos, player_cam);
	
	#Signal focus has been reached (fires here, after pan+hold, before return)
	focus_reached.emit(clamped_target);
	
	_start_tween_to(cinematic_camera, clamped_return, return_duration);
	await _tween.finished;
	
	#Hand back to player camera
	_end_to_player(player_cam);
	_state = CameraState.PLAYER;
	focus_finished.emit(clamped_return);
	
#Begin the cinematic
func _begin_cinematic(player_cam: Camera2D) -> void:
	UIRouter.set_hud_visible(false);
	#Make cinematic camera current and player not current
	cinematic_camera.make_current();
	player_cam.position_smoothing_enabled = false;
	#Tell VisualFX shakes should apply to cinematic during cutscene
	VisualFX.set_active_camera(cinematic_camera);
		
#End the cinematic and go back to player camera
func _end_to_player(player_cam: Camera2D) -> void:
	#Hand control back to player
	player_cam.make_current();
	player_cam.reset_smoothing();
	player_cam.position_smoothing_enabled = true;
	#Restore VisualFX active camera to player
	VisualFX.set_active_camera(player_cam);
		
	#Remove input lock 
	Game.pop_input_lock(LOCK_SOURCE);
	UIRouter.set_hud_visible(true);
		
#Start tweening towards focus point
func _start_tween_to(cam: Camera2D, world_pos: Vector2, duration: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill();
		
	_tween = create_tween();
	_tween.set_trans(Tween.TRANS_SINE);
	_tween.set_ease(Tween.EASE_IN_OUT);
	_tween.tween_property(cam, "global_position", world_pos, max(duration, 0.001));
	
#Get the player camera
func _get_player_camera() -> Camera2D:
	#Use public getter from VisualFX autoload
	return VisualFX.get_player_camera();
	
#Get the parameters from the player camera so it can return properly
func _sync_from_player_camera(player_cam: Camera2D) -> void:
	#Copy limits and zoom so behavior matches bounds system
	cinematic_camera.limit_left = player_cam.limit_left;
	cinematic_camera.limit_right = player_cam.limit_right;
	cinematic_camera.limit_top = player_cam.limit_top;
	cinematic_camera.limit_bottom = player_cam.limit_bottom;
	cinematic_camera.limit_smoothed = false; #tween already smooth
	
	cinematic_camera.zoom = player_cam.zoom;
	
	#For cinematics, disable smoothing so tween is authorative
	cinematic_camera.position_smoothing_enabled = false;
	cinematic_camera.position_smoothing_speed = player_cam.position_smoothing_speed;
	
func _clamp_to_limits(pos: Vector2, cam: Camera2D) -> Vector2:
	var x: float = clampf(pos.x, float(cam.limit_left), float(cam.limit_right));
	var y: float = clampf(pos.y, float(cam.limit_top), float(cam.limit_bottom));
	return Vector2(x,y);
		
#region New item popup tween stuffs
func begin_item_get_zoom() -> void:
	var cam = _get_player_camera();
	if cam == null:
		push_error("begin_item_get_zoom: no player camera")
		return;
	
	_item_get_saved_zoom = cam.zoom;
	_item_get_saved_offset = cam.offset;
	
	#Kill any previous tween
	if _item_get_zoom_tween and _item_get_zoom_tween.is_valid():
		_item_get_zoom_tween.kill();
	
	_item_get_zoom_tween = create_tween();
	_item_get_zoom_tween.set_trans(Tween.TRANS_SINE);
	_item_get_zoom_tween.set_ease(Tween.EASE_OUT);
	#Allow tween to run while the game is paused
	_item_get_zoom_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS);

	var target_zoom: Vector2 = _item_get_saved_zoom * item_get_zoom_scale;
	_item_get_zoom_tween.tween_property(cam, "zoom", target_zoom, item_get_zoom_duration)
	_item_get_zoom_tween.parallel().tween_property(cam, "offset:y", _item_get_saved_offset.y + item_get_offset_y, item_get_zoom_duration);

#End the item zoom
func end_item_get_zoom() -> void:
	var cam = _get_player_camera();
	if cam == null:
		push_error("end_item_get_zoom: no player camera")
		return;
	
	#Kill any previous tween
	if _item_get_zoom_tween and _item_get_zoom_tween.is_valid():
		_item_get_zoom_tween.kill();

	_item_get_zoom_tween = create_tween();
	_item_get_zoom_tween.set_trans(Tween.TRANS_SINE);
	_item_get_zoom_tween.set_ease(Tween.EASE_IN_OUT);
	_item_get_zoom_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS);
	
	_item_get_zoom_tween.tween_property(cam, "zoom", _item_get_saved_zoom, item_get_zoom_duration);	
	_item_get_zoom_tween.parallel().tween_property(cam, "offset:y", _item_get_saved_offset.y, item_get_zoom_duration);
#endregion
