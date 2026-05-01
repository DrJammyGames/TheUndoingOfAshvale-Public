extends Node

signal gold_changed(new_amount: int);

#region Variable declaration
var gold: int = 0:
	set(value):
		gold = max(value, 0);
		gold_changed.emit(gold);
#Runtime data 
#Single source of truth for what gets saved/loaded
#General
var current_scene_path: String = "";
var current_location_name: String = "";
#I.e., spawn point name after transition
var pending_spawn_id: String = "";
var pending_door_sfx: String = ""; 
var pending_walk_through: bool = false;
#Player
var player_position: Vector2 = Vector2.ZERO;
var player_facing_dir: Vector2 = Vector2.DOWN;
var player_name: String = "";
var total_play_time_sec: float = 0.0;
var player_stats: Dictionary = {};

#Quests and flags
var quest_states: Dictionary = {}; #quest_id -> serialised quest info
var world_flags: Dictionary = {}; #door_unlocked -> bool, etc.
#Notes read in world
var read_notes: Dictionary = {};
#Has the intro scene been played
var town_intro_played: bool = false;
#Save slot
var current_save_slot: int = -1; #Slot not chosen yet
#Day/night cycle
var current_day: int = 1;
var forest_last_generated_day: int = -1; #never generated
var forest_layout: Dictionary = {};

#Analytics
var player_uid: String = ""
#endregion 

#Reset the current GameState
func reset_state() -> void:
	current_scene_path = "";
	current_location_name = "";
	pending_spawn_id = "";
	pending_walk_through = false;
	pending_door_sfx = "";
	player_position = Vector2.ZERO;
	player_facing_dir = Vector2.DOWN;
	player_stats.clear();
	gold = 0;
	quest_states.clear();
	world_flags.clear();
	read_notes.clear();
	town_intro_played = false;
	current_save_slot = -1;
	player_name = "";
	total_play_time_sec = 0.0;
	current_day = 1;
	forest_last_generated_day = -1;
	forest_layout.clear();
	player_uid = "";
	
func set_flag(flag_name: String, value: Variant) -> void:
	world_flags[flag_name] = value;
	
func get_flag(flag_name: String, default_value: Variant = false) -> Variant:
	return world_flags.get(flag_name, default_value);
	
func set_player_position(pos: Vector2) -> void:
	player_position = pos;
	
func get_player_position() -> Vector2:
	return player_position;
	
func to_dict() -> Dictionary:
	#Called by SaveSystem
	#Safe for Godot's store_var/get_var
	#Will need to change if switching to JSON format
	return {
		"current_scene_path": current_scene_path,
		"current_location_name": current_location_name,
		"pending_spawn_id": pending_spawn_id,
		"player_position": player_position,
		"player_facing_dir": player_facing_dir,
		"player_stats": player_stats,
		"gold": gold,
		"quest_states": quest_states,
		"world_flags": world_flags,
		"read_notes": read_notes,
		"current_save_slot": current_save_slot,
		"player_name": player_name,
		"total_play_time_sec": total_play_time_sec,
		"town_intro_played": town_intro_played,
		"current_day": current_day,
		"forest_last_generated_day": forest_last_generated_day,
		"forest_layout": forest_layout,
		"player_uid": player_uid,
	};
	
func from_dict(data: Dictionary) -> void:
	#Load fields with defaults for backward compatibility
	current_scene_path = data.get("current_scene_path", "");
	current_location_name = data.get("current_location_name", "");
	pending_spawn_id = data.get("pending_spawn_id", "");
	player_position = data.get("player_position", Vector2.ZERO);
	player_facing_dir = data.get("player_facing_dir",Vector2.DOWN);
	player_stats = data.get("player_stats", {});
	gold = data.get("gold", 0);
	quest_states = data.get("quest_states", {});
	world_flags = data.get("world_flags", {});
	read_notes = data.get("read_notes", {});
	current_save_slot = int(data.get("current_save_slot", -1));
	player_name = data.get("player_name", "");
	total_play_time_sec = float(data.get("total_play_time_sec", 0.0));
	town_intro_played = data.get("town_intro_played", false);
	current_day = int(data.get("current_day", 1));
	forest_last_generated_day = int(data.get("forest_last_generated_day", -1));
	forest_layout = data.get("forest_layout", {});
	player_uid = data.get("player_uid", "");
