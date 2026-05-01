extends TransitionArea
class_name DoorTransitionArea

@onready var _anim: AnimatedSprite2D = %AnimatedSprite2D;

func interact(interactor: Node) -> void:
	if _is_transitioning:
		return;
	if not interactor.is_in_group("player"):
		return;
	if target_scene_path.is_empty():
		push_warning("DoorTransitionArea has no target_scene_path set")
		return;
		
	_is_transitioning = true;
	
	#Play SFX and animation together, then wait for animation to finish
	AudioManager.play_sfx("door_open");
	_anim.play("door_open");
	await _anim.animation_finished;
	#Save facing direction 
	GameState.player_facing_dir = interactor.facing_dir
	GameState.pending_door_sfx = "door_close";
	#Now hand off to the base transition logic
	Game.transition_player_to_area(target_scene_path, target_spawn_id)
