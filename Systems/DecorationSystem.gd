extends Node

#This autoload system handles two things:
#1 World furniture inventory--furniture the player has crafted but not yet placed
#2. Placed furniture registry: furniture instances currently in the world

#Signals
signal furniture_inventory_changed(item_id: String);
signal furniture_placed(item_id: String, world_pos: Vector2);
signal furniture_picked_up(item_id: String, world_pos: Vector2);
signal decoration_mode_unlocked;

#Internal state
#{item_id: amount}--how many of each furniture item the player has available to place
var _furniture_inventory: Dictionary = {};

#Array of placed instance data
#Each entry {item_id: String, scene_path: String, position: Vector2, instance_id: String}
#instance_id is a unique string so we can identify specific items
var _placed_furniture: Array = [];

#Check if decoration mode button is visible/accessible
var _is_unlocked: bool = false;

func _ready() -> void:
	#Connect to the CraftingSystems item_crafted signal
	CraftingSystem.item_crafted.connect(_on_item_crafted);
	#Ensure decoraing unlocks after quest completion
	QuestSystem.quest_completed.connect(_on_quest_completed);
	
#region Unlock
func unlock_decoration_mode() -> void:
	if _is_unlocked:
		return;
	_is_unlocked = true;
	WorldFlags.set_flag("decoration_mode_unlocked", true);
	decoration_mode_unlocked.emit();
	Analytics.log_event("decoration_mode_unlocked", {});
	
#Check if already unlocked
func is_unlocked() -> bool:
	return _is_unlocked;
	
func _on_quest_completed(quest_id: String) -> void:
	#Unlock decoration mode when the alchemist rebuild quest is done
	if quest_id != "q_rebuild_alchemist":
		return;
	unlock_decoration_mode();
#endregion
#region Furniture inventory--unplaced stock
func get_furniture_count(item_id: String) -> int:
	return int(_furniture_inventory.get(item_id, 0));
	
func has_furniture(item_id: String, amount: int = 1) -> bool:
	return get_furniture_count(item_id) >= amount;
	
func add_furniture(item_id: String, amount: int = 1) -> void:
	if item_id.is_empty() or amount <= 0:
		return;
	var current: int = get_furniture_count(item_id);
	_furniture_inventory[item_id] = current + amount;
	furniture_inventory_changed.emit(item_id);
	Analytics.log_event("furniture_added_to_world_inventory", {
		"item_id": item_id,
		"amount": amount, 
		"new_total": _furniture_inventory[item_id],
	});
	
#Returns false if teh player doesn't have enough stock
func remove_furniture(item_id: String, amount: int = 1) -> bool:
	if not has_furniture(item_id, amount):
		return false;
	var current: int = get_furniture_count(item_id);
	var new_amount: int = current - amount;
	if new_amount <= 0:
		_furniture_inventory.erase(item_id);
	else:
		_furniture_inventory[item_id] = new_amount;
	furniture_inventory_changed.emit(item_id);
	return true;
	
#Returns a copy of the full furniture inventory for UI display
func get_all_furniture() -> Dictionary:
	return _furniture_inventory.duplicate();
#endregion
#region Placed furniture registry
#Called by the placement system when the player confirms a furniture placement
#scene_path: the .tscn to instatiate in the world

#Returns the generated instance_id so the caller can tag the node
func register_placed_furniture(item_id: String, scene_path: String, world_pos: Vector2) -> String:
	if not remove_furniture(item_id):
		push_warning("DecorationSystem: tried to place %s but none in inventory" % item_id);
		return "";
	var instance_id: String = "%s_%d" % [item_id, Time.get_ticks_msec()];
	_placed_furniture.append({
		"item_id": item_id,
		"scene_path": scene_path,
		"position": world_pos,
		"instance_id": instance_id,
	});
	furniture_placed.emit(item_id, world_pos);
	Analytics.log_event("furniture_placed", {
		"item_id": item_id, 
		"position_x": world_pos.x,
		"position_y": world_pos.y,
		"instance_id": instance_id,
		});
	return instance_id;
	
#Called when a placed piece of furniture is picked back up
#Unregisters it and returns it the to the world's inventory
#Returns false if instance_id is not found
func unregister_placed_furniture(instance_id: String) -> bool:
	for i in range(_placed_furniture.size()):
		var entry: Dictionary = _placed_furniture[i];
		if entry.get("instance_id", "") == instance_id:
			var item_id: String = entry.get("item_id", "");
			var pos: Vector2 = entry.get("position", Vector2.ZERO);
			_placed_furniture.remove_at(i);
			add_furniture(item_id, 1);
			furniture_picked_up.emit(item_id, pos);
			Analytics.log_event("furniture_picked_up", {
				"item_id": item_id,
				"instance_id": instance_id,
			});
			return true;
	push_warning("DecorationSystem: unregister_placed_furniture instance_id not found for %s" % instance_id);
	return false;
	
#Returns a copy of all placed furniture data
#Used by the world scene to reinstatiate furniture on load
func get_placed_furniture() -> Array:
	return _placed_furniture.duplicate(true);
	
#Returns the data for a single placed instance, or an empty dict if not found
func get_placed_entry(instance_id: String) -> Dictionary:
	for entry in _placed_furniture:
		if entry.get("instance_id", "") == instance_id:
			return entry.duplicate();
	return {};
#endregion
#region Crafting intercept
#Called when CraftingSystem crafts anything
#If it's furniture, add to the world inventory
func _on_item_crafted(payload: Dictionary) -> void:
	var item_id: String = payload.get("item_id", "");
	var amount: int = int(payload.get("amount", 1));
	if item_id.is_empty():
		return;
	var item: ItemDataResource = ItemDatabase.get_item(item_id);
	if item == null:
		return;
	if item.type != ItemDataResource.ItemType.FURNITURE:
		return;
	#It's furniture, so add to world inventory
	add_furniture(item_id, amount);
#endregion
#region Save/load stuffs
func to_dict() -> Dictionary:
	#Serialise positions manually since Vector2 needs special handling for store_var
	var placed_serialised: Array = [];
	for entry in _placed_furniture:
		placed_serialised.append({
			"item_id": entry.get("item_id",""),
			"scene_path": entry.get("scene_path", ""),
			"pos_x": entry.get("position", Vector2.ZERO).x,
			"pos_y": entry.get("position", Vector2.ZERO).y,
			"instance_id": entry.get("instance_id",""),
		});
	return {
		"furniture_inventory": _furniture_inventory.duplicate(),
		"placed_furniture": placed_serialised,
		"is_unlocked": _is_unlocked,
	};
	
func from_dict(data: Dictionary) -> void:
	var inv = data.get("furniture_inventory", {});
	_furniture_inventory = {};
	for key in inv:
		_furniture_inventory[str(key)] = int(inv[key]);
		
	var placed = data.get("placed_furniture",[]);
	_placed_furniture = [];
	for entry in placed:
		if typeof(entry) != TYPE_DICTIONARY:
			continue;
		_placed_furniture.append({
			"item_id": str(entry.get("item_id","")),
			"scene_path": str(entry.get("scene_path","")),
			"position": Vector2(float(entry.get("pos_x", 0.0)), float(entry.get("pos_y", 0.0))),
			"instance_id": str(entry.get("instance_id", "")),
		});
	_is_unlocked = bool(data.get("is_unlocked", false));
	#Also restore the WorldFlag to stay in sync
	if _is_unlocked:
		WorldFlags.set_flag("decoration_mode_unlocked", true);
		
func restore_to_scene(world_scene: Node) -> void:
	var interactables: Node = world_scene.get_node_or_null("YSortRoot/Interactables");
	if interactables == null:
		push_warning("DecorationSystem: YSortRoot/Interactables not found, cannot restore furniture.");
		return;
	for entry in _placed_furniture:
		var scene_path: String = entry.get("scene_path", "");
		var world_pos: Vector2 = entry.get("position", Vector2.ZERO);
		var instance_id: String = entry.get("instance_id", "");
		if scene_path.is_empty() or instance_id.is_empty():
			continue;
		var packed: PackedScene = load(scene_path);
		if packed == null:
			push_warning("DecorationSystem: Failed to load furniture scene: %s" % scene_path);
			continue;
		var node: Node2D = packed.instantiate();
		node.global_position = world_pos;
		node.set_meta("decoration_instance_id", instance_id);
		node.set_meta("is_placed_furniture", true);
		node.add_to_group("placed_furniture");
		interactables.add_child(node);
	
func reset() -> void:
	_furniture_inventory.clear();
	_placed_furniture.clear();
	_is_unlocked = false;
	furniture_inventory_changed.emit("");
#endregion
