extends TransitionArea;
class_name WalkThroughArea;

#Can only enter area if indicated quest is completed or the id is left empty
@export var required_quest_id: String = "";

var _enter_ready: bool = false;

func _ready() -> void:
	super._ready();
	
	#Manage on body entered here
	body_entered.connect(_on_walk_through_entered);
	_enable_after_delay();
	
func _enable_after_delay() -> void:
	await get_tree().process_frame;
	_enter_ready = true;
	
func _on_walk_through_entered(body: Node) -> void:
	if not _enter_ready:
		return;
	if _is_transitioning:
		return;
	if not body.is_in_group("player"):
		return;
		
	if target_scene_path.is_empty():
		push_warning("WalkThroughArea has no target_scene_path set.");
		return;
	#Safety checks passed
	_is_transitioning = true;
	#Save direction before transition
	GameState.player_facing_dir = body.facing_dir;
	GameState.pending_walk_through = true;
	Game.transition_player_to_area(target_scene_path, target_spawn_id);
