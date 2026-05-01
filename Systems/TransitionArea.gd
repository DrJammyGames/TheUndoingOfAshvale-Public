extends Interactable;
class_name TransitionArea;

#Scene to go to when this is used
@export_file("*.tscn") var target_scene_path: String = "";
#ID of the spawn point in the target scene
@export var target_spawn_id: String = "default_spawn";
@export var open_sfx: String = "";
@export var close_sfx: String = "";

#If they are already transitioning
var _is_transitioning: bool = false;

func _ready() -> void:
	#Call base Interactable _ready in case setup is needed
	super._ready();

func interact(interactor: Node) -> void:
	#Already transitioning somewhere
	if _is_transitioning:
		return;
		
	#Only the player can trigger transitions
	if not interactor.is_in_group("player"):
		return;
	#Safety check
	if target_scene_path.is_empty():
		push_warning("TransitionArea has no target_scene_path set");
		return;
		
	#Set transition to true
	_is_transitioning = true;
	#Play door open and close sounds if they are set in the inspector
	if not open_sfx.is_empty():
		AudioManager.play_sfx(open_sfx);
	if not close_sfx.is_empty():
		GameState.pending_door_sfx = close_sfx;
	
	#Call Game manager here
	Game.transition_player_to_area(target_scene_path, target_spawn_id);
