extends Control
class_name QuestArrow;

#How far from the player's screen centre the arrow orbits
@export var orbit_radius: float = 80.0;
#If the target is within this many pixels on screen, hide the arrow cause you're there
@export var hide_threshold: float = 64.0;
#How often in seconds to re-scan the scene for the best target
@export var resolve_interval: float = 0.5;
#Node ref for the arrow texture
@onready var arrow_texture: TextureRect = %ArrowTexture;
#spawn_id on the WalkThroughArea transition that leads to the forest
const FOREST_GATE_SPAWN_ID: String = "forest_entry";
#spawn_id that leads to town from forest
const TOWN_GATE_SPAWN_ID: String = "town_from_forest";
#Cache the last resolved target so we don't scan groups every frame
var _target_position: Vector2 = Vector2.ZERO;
var _has_target: bool = false;
#Accumulator for the resolve interval timer
var _resolve_timer: float = 0.0;

func _ready() -> void:
	#Continue procesing while paused so we can hide ourselves
	process_mode = Node.PROCESS_MODE_ALWAYS;
	#Start hidden until we confirm a target
	hide();
	#Re-resolve whatever the quest step changes
	QuestSystem.quest_updated.connect(_on_quest_updated);
	QuestSystem.quest_added.connect(_on_quest_updated);
	#Also re-resolve on scene change
	Game.scene_changed.connect(_on_scene_changed);
		
func _process(delta: float) -> void:
	if not _should_be_visible():
		hide();
		return;
		
	#Tick the resolve timer--rescan when it expires
	_resolve_timer -= delta;
	if _resolve_timer <= 0.0:
		_resolve_timer = resolve_interval;
		_resolve_target();
	
	if not _has_target:
		hide();
		return;
		
	#Convert the world-space target to screen space
	var player = Game.get_player() as Node2D;
	if player == null:
		hide();
		return;
		
	var cam = _get_camera();
	if cam == null:
		hide();
		return;
		
	var target_screen = _world_to_screen(_target_position, cam);
	
	#Player's screen position
	var player_screen = _world_to_screen((player as Node2D).global_position, cam);
	
	var diff = target_screen - player_screen;
	var dist = diff.length();
	
	#Hide when close enough
	if dist < hide_threshold:
		hide();
		return;
		
	#All safety checks passed, show arrow
	show();
	
	#Place arrow on a circle around the player's screen centre
	var direction = diff.normalized();
	var arrow_pos = player_screen + direction * orbit_radius;
	
	#Centre the control node on that point
	#pivot is the centre of the TextureRect, so need to offset by half its size
	if arrow_texture:
		var half = arrow_texture.size * 0.5;
		position = arrow_pos;
		#Rotate TextureRect's up = angle 0
		#Vector2.LEFT.angle_to(direction) gives the rotation needed
		arrow_texture.pivot_offset = half;
		#Sprite points left at first, so use LEFT
		arrow_texture.rotation = Vector2.LEFT.angle_to(direction);
	else:
		position = arrow_pos;
		
#region Internal helpers
#Visibility gate
func _should_be_visible() -> bool:
	#Respect the guided mode in Settings
	if not Settings.guided_mode:
		return false;
	if get_tree().paused:
		return false;
	#Hide during dialogue, modals, and paused state
	if UIRouter.get_banner_lock_count() > 0:
		return false;
	if UIRouter.is_modal_open():
		return false;
	#Must have an active quest as well
	var active = QuestSystem.get_active_quests();
	return not active.is_empty();
	
#Target resolution--rescan the scene and update _target_position/_has_target
#Called on a timer so we stay current without scanning every frame
func _resolve_target() -> void:
	var active = QuestSystem.get_active_quests();
	if active.is_empty():
		_has_target = false;
		return;
		
	var quest_id: String = String(active[0]);
	var step_index: int = QuestSystem.get_step_index(quest_id);
	var step_data: Dictionary = QuestDatabase.get_step_data(quest_id, step_index);
	
	if step_data.is_empty():
		_has_target = false;
		return;
		
	var event_type: String = step_data.get("event_type", "");
	
	match event_type:
		"talk_to_npc","deliver_items":
			_resolve_npc_target(step_data);
		"item_pickup":
			_resolve_item_target(step_data);
		_:
			_has_target = false;
	#If target wasn't found in this scene, point to the nearest scene exit
	if not _has_target:
		_resolve_exit_transition();
		
#Get the npc for this step in the quest
func _resolve_npc_target(step_data: Dictionary) -> void:
	var conditions: Array = step_data.get("conditions", []);
	var npc_id = "";
	for cond in conditions:
		if String(cond.get("key", "")) == "npc_id":
			npc_id = String(cond.get("value",""));
			break;
	if npc_id.is_empty():
		_has_target = false;
		return;
	
	for node in get_tree().get_nodes_in_group("npcs"):
		if node is NPC and String((node as NPC).get_npc_id()) == npc_id:
			_target_position = (node as Node2D).global_position;
			_has_target = true;
			return;
		
	_has_target = false;
	
#For item_pickup steps: look for harvestable first, then enemies, then forest gate fallback
func _resolve_item_target(step_data: Dictionary) -> void:
	#The condition value for item_pickup is an item_id
	#Find the harvestable or enemy whose drop_item_id matches
	var conditions: Array = step_data.get("conditions", []);
	var item_id: String = "";
	for cond in conditions:
		if String(cond.get("key", "")) == "item_id":
			item_id = String(cond.get("value", ""));
	if item_id.is_empty():
		_has_target = false;
		return;
		
	var player = Game.get_player() as Node2D;
	var player_pos = (player as Node2D).global_position if player else Vector2.ZERO;
	
	#Nearest matching harvestable in this scene
	var nearest_dist = INF;
	var nearest_pos: Vector2 = Vector2.ZERO;
	var found: bool = false;
	
	for node in get_tree().get_nodes_in_group("harvestables"):
		if node is HarvestableNode:
			var h = node as HarvestableNode;
			#Check if this harvestable drops the item we need
			if HarvestableDatabase.get_drop_item_id(h.harvest_id) == item_id:
				var d = player_pos.distance_to(h.global_position);
				if d < nearest_dist:
					nearest_dist = d;
					nearest_pos = h.global_position;
					found = true;
					
	if found:
		_target_position = nearest_pos;
		_has_target = true;
		return;
	#Wasn't found in harvestables, check for enemies instead
	var enemy_ids_that_drop: Array[String] = _get_enemy_ids_dropping(item_id);
	
	if not enemy_ids_that_drop.is_empty():
		nearest_dist = INF;
		found = false;
		
		for node in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(node):
				continue;
			if not node is Node2D:
				continue;
			if not "enemy_id" in node:
				continue;
			if enemy_ids_that_drop.has(String(node.enemy_id)):
				var d: float = player_pos.distance_to((node as Node2D).global_position);
				if d < nearest_dist:
					nearest_dist = d;
					nearest_pos = (node as Node2D).global_position;
					found = true;
		
		if found:
			_target_position = nearest_pos;
			_has_target = true;
			return;
	
	#Nothing is found in the current scene--point towards the transition to teh forest instad
	for node in get_tree().get_nodes_in_group("walk_through_transitions"):
		if node is WalkThroughArea:
			var wt = node as WalkThroughArea;
			if wt.target_spawn_id == FOREST_GATE_SPAWN_ID:
				_target_position = (wt as Node2D).global_position;
				_has_target = true;
				return;
			
	#Nothing found at all
	_has_target = false;
	
#Fallback: point to the nearest scene transition when the target isn't in the current scene tree
func _resolve_exit_transition() -> void:
	for node in get_tree().get_nodes_in_group("walk_through_transition"):
		if not node is WalkThroughArea:
			continue;
		var walk_through: WalkThroughArea = node as WalkThroughArea;
		if walk_through.target_spawn_id == TOWN_GATE_SPAWN_ID or walk_through.target_spawn_id == FOREST_GATE_SPAWN_ID:
			_target_position = (walk_through as Node2D).global_position;
			_has_target = true;
			return;
			
#Return every enemy_id whose drop table includes item_id
func _get_enemy_ids_dropping(item_id: String) -> Array[String]:
	var result: Array[String] = [];
	for enemy_res in EnemyDatabase.get_all_enemies():
		if not enemy_res is EnemyDataResource:
			continue;
		for drop in (enemy_res as EnemyDataResource).drops:
			if drop is EnemyDropData:
				var item_res: ItemDataResource = (drop as EnemyDropData).item;
				if item_res != null and item_res.item_id == item_id:
					result.append((enemy_res as EnemyDataResource).id);
					break;
	return result;
	
func _get_camera() -> Camera2D:
	var player = Game.get_player() as Node2D;
	if player == null:
		return null;
	#Player camera is a child of the player node
	for child in (player as Node).get_children():
		if child is Camera2D:
			return child as Camera2D;
	return null;
	
func _world_to_screen(world_pos: Vector2, _cam: Camera2D) -> Vector2:
	return get_viewport().get_canvas_transform() * world_pos;
	
#Quest signal connections
func _on_quest_updated(_quest_id: String) -> void:
	#Force immediate re-resolve next frame
	_resolve_timer = 0.0;
	
func _on_scene_changed(_path: String) -> void:
	_has_target = false;
	_resolve_timer = 0.0;
#endregion
