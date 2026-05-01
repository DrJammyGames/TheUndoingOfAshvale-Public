extends WorldScene;
class_name Town;

const HARVESTED_FLAG_PREFIX: StringName = &"town_harvested:";

@onready var _resource_nodes: Node2D = $YSortRoot/Interactables/ResourcesNodes;

func _ready() -> void:
	super._ready();
	#Ensure the harvested nodes stay that way
	_apply_harvested_state();
	#Only trigger if player just came from house and the intro scene hasn't been played before
	if not GameState.town_intro_played:
		Game.suppress_next_hud_show = true;
		call_deferred("_play_intro_cinematic");

func _apply_harvested_state() -> void:
	if _resource_nodes == null:
		push_warning("Town: ResourceNodes node not found.");
		return;
		
	for child in _resource_nodes.get_children():
		var node = child as HarvestableNode;
		if node == null:
			continue;
		var flag = HARVESTED_FLAG_PREFIX + node.name;
		if WorldFlags.has_flag(flag):
			node.queue_free();
			continue;
		node.destroyed.connect(_on_harvestable_destroyed);

func _on_harvestable_destroyed(node_name: String) -> void:
	WorldFlags.set_flag(HARVESTED_FLAG_PREFIX + node_name, true);
	
func _play_intro_cinematic() -> void:
	if GameState.town_intro_played:
		return;
	
	#Set GameState has played
	GameState.town_intro_played = true
	UIRouter.set_hud_visible(false);
	#Find caretaker in scene
	var caretaker := get_npc_by_id(&"caretaker");
	if caretaker == null:
		push_warning("Caretaker not found for intro cinematic.")
		return;
	
	#Slight delay so player fully spawns visually
	await get_tree().process_frame;
	#Pan to caretaker
	if VisualFX:
		VisualFX.play_focus_world_position_and_hold(
			(caretaker as Node2D).global_position,
			0.8,  #pan duration
			1.5,  #hold
		);
	
	#Wait for the camera to arrive at the caretaker
	var director = VisualFX.get_camera_director();
	if director == null:
		push_warning("CameraDirector not found, cannot await focus_reached.");
		return;
	#Safety checks passed
	await director.focus_reached;
	
	#Player walks to caretaker
	var player = Game.get_player() as Player;
	if player == null:
		push_warning("Player not found for intro scripted walk.");
		return;
	
	#Switch the cinematic camera to follow the player during the walk over to the caretaker
	director.start_follow(player);
	player.walk_to((caretaker as Node2D).global_position);
	await player.scripted_walk_finished;
	
	#Player reached caretaker, camera stops following, and dialogue can start after a brief pause
	director.stop_follow();
	await get_tree().create_timer(0.3).timeout;
	
	#Start intro dialogue
	DialogueSystem.start_dialogue("caretaker_intro", {"npc_id": "caretaker"});
	#When dialogue has ended, release teh camera hold back to player
	await DialogueSystem.dialogue_ended;
	director.release_hold();
	#Cutscene counts as the first step for the intro quest and therefore triggers it
	QuestSystem.notify_event("talk_to_npc", {"npc_id": "caretaker"});
