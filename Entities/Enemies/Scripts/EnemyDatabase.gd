extends Node;

var _enemies: Dictionary = {};

func _ready() -> void:
	for resource in EnemyPreloadRegistry.ALL:
		if resource is EnemyDataResource:
			var enemy: EnemyDataResource = resource;
			if enemy.id.is_empty():
				push_warning("EnemyDataResource missing id: %s" % resource.resource_path);
			elif _enemies.has(enemy.id):
				push_warning("EnemyDatabase: Duplicate enemy id '%s'" % enemy.id);
			else:
				_enemies[enemy.id] = enemy;
		else:
			push_warning("EnemyPreloadRegistry: Non-EnemyDataResource entry: %s" % resource.resource_path);
	
#region Public APIs
func has_enemy(enemy_id: String) -> bool:
	return _enemies.has(enemy_id);

func get_enemy(enemy_id: String) -> EnemyDataResource:
	if not _enemies.has(enemy_id):
		push_warning("EnemyDatabase: Unknown enemy_id %s" % enemy_id);
		return null;
	return _enemies[enemy_id];
	
func get_display_name(enemy_id: String) -> String:
	var enemy = get_enemy(enemy_id);
	if enemy == null:
		return enemy_id.capitalize();
	return tr(enemy.get_display_name_key());
	
func get_description(enemy_id: String) -> String:
	var enemy = get_enemy(enemy_id);
	if enemy == null:
		return "Unknown enemy";
	return tr(enemy.get_description_key());

func get_max_hp(enemy_id: String) -> int:
	var enemy = get_enemy(enemy_id);
	if enemy == null:
		return 10;
	return max(enemy.max_hp, 1);
	
func get_attack(enemy_id: String) -> int:
	var enemy = get_enemy(enemy_id);
	if enemy == null:
		return 5;
	return max(enemy.attack, 0);
	
func get_defense(enemy_id: String) -> int:
	var enemy = get_enemy(enemy_id);
	if enemy == null:
		return 0;
	return max(enemy.defense, 0);

func get_move_speed(enemy_id: String) -> float:
	var enemy = get_enemy(enemy_id);
	if enemy == null:
		return 50.0;
	return max(enemy.move_speed, 0.0);

func get_aggro_range(enemy_id: String) -> float:
	var enemy = get_enemy(enemy_id);
	if enemy == null:
		return 100.0;
	return max(enemy.aggro_range, 0.0);
	
func get_attack_cooldown(enemy_id: String) -> float:
	var enemy = get_enemy(enemy_id);
	if enemy == null:
		return 1.0;
	return max(enemy.attack_cooldown_sec, 0.0);
	
func get_xp_reward(enemy_id: String) -> int:
	var enemy = get_enemy(enemy_id);
	if enemy == null:
		return 5;
	return max(enemy.xp_reward, 0);
	
func get_gold_min(enemy_id: String) -> int:
	var enemy = get_enemy(enemy_id);
	if enemy == null:
		return 0;
	return max(enemy.gold_min, 0);
	
func get_gold_max(enemy_id: String) -> int:
	var enemy = get_enemy(enemy_id);
	if enemy == null:
		return 0;
	return max(enemy.gold_max, 0);
	
func get_ai_profile_id(enemy_id: String) -> String:
	var enemy = get_enemy(enemy_id);
	if enemy == null:
		return "melee_basic";
	return String(enemy.ai_profile_id);
	
#Simple string label like night,day,any
func get_spawn_tags(enemy_id: String) -> String:
	var enemy = get_enemy(enemy_id);
	if enemy == null:
		return "any";
	return String(enemy.spawn_tags);
	
func get_sprite_frames(enemy_id: String) -> SpriteFrames:
	var enemy = get_enemy(enemy_id);
	if enemy == null:
		return null;
	return enemy.sprite_frames;
	
func get_idle_animation(enemy_id: String) -> StringName:
	var enemy = get_enemy(enemy_id);
	if enemy == null:
		return &"idle";
	return enemy.idle_animation;
	
func get_drops(enemy_id: String) -> Array:
	var enemy = get_enemy(enemy_id);
	if enemy == null:
		return [];
		
	var result: Array = [];
	for drop in enemy.drops:
		if drop is EnemyDropData:
			var item_res: ItemDataResource = drop.item;
			if item_res == null or item_res.item_id.is_empty():
				continue;
			result.append({
				"item_id": item_res.item_id,
				"min": drop.min_drop,
				"max": drop.max_drop,
				"chance": drop.chance,
			})
	return result;
	
func get_all_enemies() -> Array[EnemyDataResource]:
	var result: Array[EnemyDataResource] = [];
	for e in _enemies.values():
		result.append(e);
	return result;
	
func get_location(enemy_id: String) -> String:
	var e = get_enemy(enemy_id);
	if e == null:
		return "";
	return tr(e.get_location_key());
	
func get_icon(enemy_id: String) -> Texture2D:
	var e = get_enemy(enemy_id);
	if e:
		return e.icon;
	return null;
#endregion
#region Internal helpers	
func _make_fallback_enemy(enemy_id: String) -> Dictionary:
	return {
		"id": enemy_id,
		"display_name_key": "enemy.%s.name" % enemy_id,
		"description_key": "enemy.%s.description" % enemy_id,
		"max_hp": 10,
		"attack": 1,
		"defense": 0,
		"move_speed": 50.0,
		"aggro_range": 120.0,
		"attack_range": 20.0,
		"attack_cooldown_sec": 1.0,
		"xp_reward": 0,
		"gold_min": 0,
		"gold_max": 0,
		"ai_profile_id": "melee_basic",
		"spawn_tags": "any",
		"drops": [],
	};
#endregion
