extends Node

signal day_changed(new_day: int);
signal night_entered;
signal day_tick(progress: float);
#Time passes when using tools, like Littlewood
var ticks_per_day: float = 24.0;

var _ticks_today: float = 0.0;
var _is_night: bool = false;

#Daily tracking for end of day summary
var _day_start_gold: int = 0;
var _items_gained_today: Dictionary = {}; #item_id -> amount
var _quests_completed_today: Array[String] = [];

#Colours for the modulate tween
const COLOUR_DAY = Color(1.0,1.0,1.0);
const COLOUR_NIGHT = Color(0.50, 0.54, 0.71, 1.0);

func _ready() -> void:
	#Reset visual when a new scene loads
	Game.scene_changed.connect(_on_scene_changed);
	QuestSystem.quest_completed.connect(_on_quest_completed);
	_snapshot_day_start();
		
#region Public helpers
#Register that something happened to pass the time
#Includes harvesting resources and crafting for now
func advance_time(ticks: float) -> void:
	if _is_night:
		return;
	_ticks_today += ticks;
	#Only start to change the colour of the day once it reaches halfway
	if _ticks_today >= (ticks_per_day * 0.5):
		_update_modulate();
	day_tick.emit(_ticks_today / ticks_per_day);
	Analytics.log_event("day_tick", {
		"ticks_today": _ticks_today,
		"ticks_per_day": ticks_per_day,
		"current_day": GameState.current_day,
	})
	if _ticks_today >= ticks_per_day:
		_enter_night();

#Public helper to see if it's nighttime
func is_night() -> bool:
	return _is_night;
	
#Public helper to end the day--called from Bed scene
func end_day() -> void:
	#Log how many ticks the player spent and which day it is before resetting
	Analytics.log_event("day_ended", {
		"new_day": GameState.current_day + 1,
		"today": GameState.current_day,
		"ticks_spent_today": _ticks_today,
	})
	#Heal the player to full health when sleeping
	var player = Game.get_player();
	if player:
		var stats: PlayerStats = player.get_stats();
		if stats:
			stats.heal(stats.max_health - stats.health);
	GameState.current_day += 1;
	_is_night = false;
	_tween_modulate(COLOUR_DAY);
	Game.request_save();
	day_changed.emit(GameState.current_day);
	Game.show_end_of_day_screen();

func get_daily_summary() -> Dictionary:
	return {
		"day_completed": GameState.current_day,
		"gold_earned": GameState.gold - _day_start_gold,
		"items_gained": _items_gained_today.duplicate(),
		"quests_completed": _quests_completed_today.duplicate(),
	}
#Reset the tracking for the day
func reset_daily_tracking() -> void:
	_snapshot_day_start();
	_items_gained_today.clear();
	_quests_completed_today.clear();
	_ticks_today = 0.0;
	_tween_modulate(COLOUR_DAY);
	day_tick.emit(0.0);
	
#Called directly by ItemPickup on a successful collect
func record_item_gained(item_id: String, amount: int) -> void:
	if item_id.is_empty() or amount <= 0:
		return;
	_items_gained_today[item_id] = _items_gained_today.get(item_id, 0) + amount;

#Save stuffs
func to_dict() -> Dictionary:
	return {
		"ticks_today": _ticks_today,
		"is_night": _is_night,
		"day_start_gold": _day_start_gold,
		"items_gained_today": _items_gained_today.duplicate(),
		"quests_completed_today": _quests_completed_today.duplicate(),
	}
	
func from_dict(data: Dictionary) -> void:
	_ticks_today = data.get("ticks_today", 0.0);
	_is_night = data.get("is_night", false);
	_day_start_gold = int(data.get("day_start_gold", 0));
	_items_gained_today = data.get("items_gained_today", {}).duplicate();
	_quests_completed_today = Array(data.get("quests_completed_today", []), TYPE_STRING, "", null);
	
	#Restore the proper colour modulation
	_restore();
#endregion
#region Internal helpers
func _restore() -> void:
	#_update_modulate reads the ticks to lerp the colour correctly
	_sync_visual_state();
		
func _enter_night() -> void:
	_is_night = true;
	night_entered.emit();
	_tween_modulate(COLOUR_NIGHT);
	#Add show_message for HUD?
	Analytics.log_event("night_entered", {
		"current_day": GameState.current_day,
	})
	
#Update the colour modulation
func _update_modulate() -> void:
	var node = _get_modulate_node();
	if node == null:
		return;
	var half: float = ticks_per_day * 0.5;
	var t: float = (_ticks_today - half) / half;
	t = clampf(t, 0.0, 1.0);
	node.color = COLOUR_DAY.lerp(COLOUR_NIGHT, t);
	
#Snapshot of the start of the day
func _snapshot_day_start() -> void:
	_day_start_gold = GameState.gold;
	
func _on_quest_completed(quest_id: String) -> void:
	_quests_completed_today.append(quest_id);
	
#Tween the colour modulation
func _tween_modulate(target: Color) -> void:
	var node = _get_modulate_node();
	if node == null:
		return;
	var tween = create_tween();
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS);
	tween.tween_property(node, "color", target, 1.5);
	
func _get_modulate_node() -> CanvasModulate:
	return get_tree().get_first_node_in_group("night_modulate") as CanvasModulate;
	
#Function called when scene is changed
func _on_scene_changed(_scene_path: String) -> void:
	#When scene reloads, resync the modulate to current tick state
	_sync_visual_state();
			
func _sync_visual_state() -> void:
	await get_tree().process_frame;
	if _is_night:
		_tween_modulate(COLOUR_NIGHT);
	elif _ticks_today >= (ticks_per_day * 0.5):
		_update_modulate();
	else:
		_tween_modulate(COLOUR_DAY);
#endregion
