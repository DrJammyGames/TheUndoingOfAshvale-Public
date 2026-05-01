extends Camera2D

@export var follow_enabled: bool = true;
@export var smooth_speed: float = 6.0;

#Set the camerabounds node in the current room
@export var bounds_group: StringName = "camera_bounds";

#Reference to the player node
var _player: Node = null;

func _ready() -> void:
	top_level = false;
	position = Vector2.ZERO;
	#Make sure this camera ia active
	make_current();
	#Enable built-in camera2d smoothing
	position_smoothing_enabled = true;
	position_smoothing_speed = smooth_speed;
	
	#Camera2D is a child of the player, get the parent
	_player = get_parent();
	_apply_limits_from_bounds();
	#Reapply bounds whenever the active scene changes
	Game.scene_changed.connect(_on_scene_changed);
	#Set the camera is VisualFX
	VisualFX.set_player_camera(self);

#Scene changed, reset Camera
func _on_scene_changed(_new_scene_path: String) -> void:
	#Wait one frame so the new scene is fully in the tree
	await get_tree().process_frame;
	_apply_limits_from_bounds();
	if VisualFX.get_active_camera() == self:
		VisualFX.set_active_camera(self);
	
#Apply the limits from the CameraBounds node in the scene
func _apply_limits_from_bounds() -> void:
	var node := get_tree().get_first_node_in_group(bounds_group);
	if node == null:
		#No Camera bounds in this scene, disable smoothed limites
		limit_smoothed = false;
		return;
	if not node.has_method("get_bounds"):
		push_warning("Camera bounds node in group '%s' has no get_bounds() method" % bounds_group);
		return;
	
	var rect: Rect2 = node.get_bounds();
	#Set Camera2D limits in the world coordinates
	limit_left = int(rect.position.x);
	limit_top = int(rect.position.y);
	limit_right = int(rect.position.x + rect.size.x);
	limit_bottom = int(rect.position.y + rect.size.y);
	
	#Respect smoothing limits
	limit_smoothed = true;
	
	
	
