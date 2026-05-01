extends Node

#Owns the shared chest item pool
#All chests in the world draw from and contribute to this single pool

signal chest_contents_changed(item_id: String);

#{item_id: int} how many of each item the is in chest storage
var _items: Dictionary = {};

#region Public helpers
func get_amount(item_id: String) -> int:
	if item_id.is_empty():
		return 0;
	return int(_items.get(item_id, 0));
	
func has_item(item_id: String, min_amount: int = 1) -> bool:
	return get_amount(item_id) >= min_amount;
	
#Get all the items in the chest storage
func get_all_items() -> Dictionary:
	return _items.duplicate();
	
#Add items to chest storage
func try_add_item(item_id: String, amount: int = 1) -> void:
	if item_id.is_empty() or amount <= 0:
		return;
	var current: int = get_amount(item_id);
	_items[item_id] = current + amount;
	chest_contents_changed.emit(item_id);
	
#Remove items from chest storage
#Returns false if not enough stock
func try_remove_item(item_id: String, amount: int = 1) -> bool:
	if not has_item(item_id, amount):
		return false;
	var new_amount: int = get_amount(item_id) - amount;
	if new_amount <= 0:
		_items.erase(item_id);
	else:
		_items[item_id] = new_amount;
	chest_contents_changed.emit(item_id);
	return true;
#endregion
#region Crafting ingredient support
#Called by CraftingSystem.can_craft to check combined player + chest stock
#Returns total available across both inventories
func get_combined_amount(item_id: String) -> int:
	return InventorySystem.get_amount(item_id) + get_amount(item_id);
	
func has_combined(item_id: String, min_amount: int = 1) -> bool:
	return get_combined_amount(item_id) >= min_amount;
	
#Removes the required amount, drawing from player inventory first then chest storage
#Returns false if combined total is insufficient
func try_remove_combined(item_id: String, amount: int) -> bool:
	if not has_combined(item_id, amount):
		return false;
	var remaining: int = amount;
	#Grab from player inventory first
	var from_player: int = mini(InventorySystem.get_amount(item_id), remaining);
	if from_player > 0:
		InventorySystem.try_remove_item(item_id, from_player);
		remaining -= from_player;
	#Draw remainder from chest
	if remaining > 0:
		try_remove_item(item_id, remaining);
	return true;
#endregion
#region Save/load stuffs
func reset() -> void:
	_items.clear();
	chest_contents_changed.emit("");
	
func to_dict() -> Dictionary:
	return {
		"items": _items.duplicate()
	};
	
func from_dict(data: Dictionary) -> void:
	var loaded = data.get("items", {});
	_items = {};
	for key in loaded:
		var amount: int = int(loaded[key]);
		if amount > 0:
			_items[str(key)] = amount;
	chest_contents_changed.emit("");
	Analytics.log_event("chest_storage_loaded", {
		"unique_items": _items.size(),
	});
#endregion
