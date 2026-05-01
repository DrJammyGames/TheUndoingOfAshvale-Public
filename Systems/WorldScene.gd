extends Node2D
class_name WorldScene;
#Base script for any "world" scene (Town, House, Dungeon)
#The game will autoload will: instantiate this scene, parent the player under actors, ask this world for spawn points by id
@export var actors_path: NodePath = NodePath("Actors");
@export var spawn_points_path: NodePath = NodePath("SpawnPoints");
#Human readble name of the area for the save slot
@export var location_name: String = "";
@onready var actors: Node2D = get_node_or_null(actors_path) as Node2D;
@onready var spawn_points_root: Node = get_node_or_null(spawn_points_path);

#Scene is loaded--start the transition
signal world_ready_for_reveal;
var _has_marked_ready: bool = false;

func _ready() -> void:
	_ensure_camera_director();
	#Mark ready *synchronously* now
	mark_world_ready_for_reveal();
	#Play door close SFX if arriving through a door
	if not GameState.pending_door_sfx.is_empty():
		AudioManager.play_sfx(GameState.pending_door_sfx);
		GameState.pending_door_sfx = "";
	
func get_spawn_point(spawn_id: String) -> SpawnPoint:
	#Deterministic lookup under SpawnPoints root. 
	if spawn_points_root == null or spawn_id == "":
		return null;
	
	for child in spawn_points_root.get_children():
		var sp := child as SpawnPoint;
		if sp != null and sp.spawn_id == spawn_id:
			return sp;
	
	#else return nothing
	return null;
	
#Get the NPCs in the scene tree
func get_npc_by_id(id: StringName) -> Node:
	#Fast path: search only within this scene, not the whole tree
	for n in get_tree().get_nodes_in_group("npcs"):
		if not is_instance_valid(n):
			continue;
		if not is_ancestor_of(n):
			continue;
		if n.has_method("get_npc_id") and n.call("get_npc_id") == id:
			return n;
	return null;

#Ensure the camera has a director
func _ensure_camera_director() -> void:
	if get_node_or_null("CameraDirector") != null:
		return;
	var director = CameraDirector.new();
	director.name = "CameraDirector";
	
	var cam = Camera2D.new();
	cam.name = "CinematicCamera";
	director.add_child(cam);
	add_child(director);

func mark_world_ready_for_reveal() -> void:
	if _has_marked_ready:
		return;
	_has_marked_ready = true;
	world_ready_for_reveal.emit();
	#Analytics: world scene signalled that it's ready
	Analytics.log_event("world_scene_ready_for_reveal", {
		"scene_path": GameState.current_scene_path,
		"has_camera_director": get_node_or_null("CameraDirector") != null,
	})
	
func is_world_ready_for_reveal() -> bool:
	return _has_marked_ready;
