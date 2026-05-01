extends Resource;
class_name EnemyDataResource;
#region Exports for enemy info	
#Unique ID use in quests, save data, etc
@export var id: String = "";

#Stats
@export var max_hp: int = 10;
@export var attack: int = 1;
@export var defense: int = 0;
@export var move_speed: float = 50.0;

@export var aggro_range: float = 120.0;
@export var attack_range: float = 32.0;
@export var attack_cooldown_sec: float = 1.0;

@export var location_hint: LocationData.Location = LocationData.Location.FOREST;

#Rewards
@export var xp_reward: int = 0;
@export var gold_min: int = 0;
@export var gold_max: int = 0;

#Behvaiour
@export var ai_profile_id: StringName = &"melee_basic";
@export var spawn_tags: StringName = &"any"; #night, day, boss, etc

#Drops info--get from other resource
@export var drops: Array[EnemyDropData] = [];

#Optional paramaeters when sending quest events
#i.e., "enemy_id" : "slime"
@export var base_event_payload: Dictionary = {};

#Spriteframes for this enemy's AnimatedSprite2D
@export var sprite_frames: SpriteFrames;
#Default idle animation name
@export var idle_animation: StringName = &"idle";
@export var encyclopedia_icon: Texture2D = null;
#endregion

#Auto generate keys for localisation
func get_display_name_key() -> String:
	if id.is_empty():
		return "";
	return "enemy.%s.name" % id;
	
func get_description_key() -> String:
	if id.is_empty():
		return "";
	return "enemy.%s.description" % id;
	
#Get the localised location hint
func get_location_key() -> String:
	if id.is_empty():
		return "";
	var location_str: String = LocationData.Location.keys()[location_hint].to_lower();
	return "location.%s" % location_str;
