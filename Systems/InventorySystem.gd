extends Node

#InventorySystem owns:
#Item counts and inventory layour

#Simple data driven inventory
signal inventory_changed(item_id: String);
#Signal for if it's a new item so the pop up plays
signal first_time_item_acquired(item_id: String, amount: int);
#QuestSystem signal
signal item_count_changed(item_id: String, amount: int);
#Tracks the items the player has obtained (for this save)
var _discovered_items: Dictionary = {}; #{item_id: true}

#Set the number of slots per row
const SLOTS_PER_ROW: int = 8;
#And number of starting rows
var _row_count: int = 1; #start with 8 inventory slots

var _items: Dictionary = {}; #item_id -> amount, etc.
var _layout: Array[String] = [] #size SLOT_COUNT, contains item_id or ""

func _ready() -> void:
	_ensure_layout_size();
	if not inventory_changed.is_connected(_on_inventory_changed):
		inventory_changed.connect(_on_inventory_changed);
	CraftingSystem.item_crafted.connect(_on_item_crafted);
	
func reset_inventory() -> void:
	#Clears all inventory data 
	#Capture state before wiping for analytics
	var unique_count: int = _items.size();
	var total_count: int = 0;
	for amount in _items.values():
		total_count += int(amount);
		
	_items.clear();
	_layout.clear();
	_discovered_items.clear();
	_row_count = 1;
	_ensure_layout_size();
	inventory_changed.emit("");
	
	#Analytics: inventory reset
	Analytics.log_event("inventory_reset", {
		"previous_unique_items": unique_count,
		"previous_total_items": total_count
	})

#region Counts API
func get_amount(item_id: String) -> int:
	#Returns current amount of an item in inventory
	#Always return an int >= 0
	if item_id.is_empty():
		return 0;
	return int(_items.get(item_id, 0));
	
#Sets an amount directly (useful for load, admin tools, crafting)
func set_amount(item_id: String, amount: int) -> void:
	#Rules: 
	#amount <= 0 removes the item from the inventory
	#emits inventory_changed only if the value actually change
	if item_id.is_empty():
		return;
		
	var old_amount: int = int(_items.get(item_id, 0));
	var new_amount: int = max(amount, 0);
	
	#If no change, do nothing
	if old_amount == new_amount:
		return;
		
	if new_amount == 0:
		_items.erase(item_id);
	else:
		_items[item_id] = new_amount;
	inventory_changed.emit(item_id);
	
	#Analytics unified hook for item amount changes
	Analytics.log_event("inventory_item_amount_changed", {
		"item_id": item_id, 
		"old_amount": old_amount,
		"new_amount": new_amount,
		"delta": new_amount - old_amount
	})

func get_slot_count() -> int:
	return _row_count * SLOTS_PER_ROW;
	
func set_row_count(new_row_count: int) -> void:
	if new_row_count <= _row_count:
		return;
	_row_count = new_row_count;
	_ensure_layout_size();
	inventory_changed.emit("");
	Analytics.log_event("inventory_expanded", {
		"new_row_count": new_row_count,
		"new_slot_count": get_slot_count()
	})
	
#Try to add item if inventory isn't full
func try_add_item(item_id: String, amount: int = 1) -> bool:
	#Returns false only when this is a NEW item and there is no free slot.
	if item_id.is_empty() or amount <= 0:
		push_warning("[Inv] try_add_item: item_id is empty or amount <= 0 (item_id='%s', amount=%d)" % [item_id, amount]);
		return false;
		
	var old_amount: int = get_amount(item_id);
	var is_new_stack: bool = old_amount == 0;
	var is_first_time_ever: bool = is_new_stack and not _discovered_items.has(item_id);
	
	#If we already have this item, stacking is always allowed.
	if old_amount > 0:
		_items[item_id] = old_amount + amount;
		inventory_changed.emit(item_id);
		return true;

	#New item: must have a free slot to be placeable.
	if not has_free_slot():
		#Analytics: failed to add due to full inventory
		Analytics.log_event("inventory_item_add_failed", {
			"item_id": item_id,
			"amount": amount,
			"reason": "no_free_slot"
		});
		return false;

	_items[item_id] = amount;
	_place_item_if_missing(item_id);
	inventory_changed.emit(item_id);
	
	#Mark as discovered (first time ever for this save)
	if is_first_time_ever:
		_discovered_items[item_id] = true;
		first_time_item_acquired.emit(item_id, amount);
	
	#Analytics: new item successfully added (first time)
	Analytics.log_event("inventory_item_added", {
		"item_id": item_id,
		"amount_added": amount,
		"new_amount": get_amount(item_id),
		"is_new_item": true,
		"is_first_time_ever": is_first_time_ever,
	});
	return true;
	
#Prevents having to repeat patterns down the line like if has_item then remove else...etc
func try_remove_item(item_id: String, amount: int = 1) -> bool:
	#Attempts to remove items
	#Returns true if successful
	if amount <= 0:
		return true;
		
	var current := get_amount(item_id);
	if current < amount:
		#Analytics: removal failed (not enough items)
		Analytics.log_event("inventory_item_remove_failed", {
			"item_id": item_id,
			"amount_requested": amount,
			"current_amount": current,
			"reason": "not_enough"
		})
		return false;
		
	set_amount(item_id, current - amount);
	#If we now have none, clear it from the layout as well
	if get_amount(item_id) <= 0:
		_remove_item_from_layout(item_id);
	inventory_changed.emit(item_id);
	return true;
	
	
func get_items() -> Dictionary:
	#Return a copy so callers don't accidentally mess with internal state
	return _items.duplicate();

func has_item(item_id: String, min_amount: int = 1) -> bool:
	return get_amount(item_id) >= min_amount;
	
#Check to see if the item has already been discovered
func has_discovered(item_id: String) -> bool:
	return _discovered_items.has(item_id);
	
func _on_inventory_changed(item_id: String) -> void:
	#Skip empty item_id
	if item_id.is_empty():
		return;
	#Only notify quest system on additions, not removals
	#if total_now is 0, the item was consumed/removed, not a pickup
	var total_now: int = get_amount(item_id);
	if total_now <= 0:
		return;
	#Safety checks passed, now call the signal that will notify QuestSystem
	item_count_changed.emit(item_id, total_now);
	
#Connection to CraftingSystem
func _on_item_crafted(payload: Dictionary) -> void:
	var item_id: String = payload.get("item_id","");
	var amount: int = int(payload.get("amount",1));
	if item_id.is_empty():
		return;
	var item: ItemDataResource = ItemDatabase.get_item(item_id);
	if item == null:
		return;
	if item.type == ItemDataResource.ItemType.FURNITURE:
		return; #Handled by DecorationSystem
	try_add_item(item_id, amount);
#endregion
#region Save stuffs
func to_dict() -> Dictionary:
	return {
		"items": _items.duplicate(),
		"layout": _layout.duplicate(),
		"discovered_items": _discovered_items.duplicate(),
		"row_count": _row_count,
	};
	
func from_dict(data: Dictionary) -> void:
	var loaded_items = data.get("items", {});
	_items = loaded_items.duplicate(true) if loaded_items is Dictionary else {};
	
	_row_count = int(data.get("row_count", 1));
	var loaded_layout = data.get("layout", []);
	_layout = [];
	if loaded_layout is Array:
		_layout = loaded_layout.duplicate();
	_ensure_layout_size();
	
	#Remove any layout items you no longer have
	for i in range(get_slot_count()):
		var id: String = String(_layout[i]);
		if not id.is_empty() and get_amount(id) <= 0:
			_layout[i] = "";
	
	inventory_changed.emit("");
	var loaded_discovered = data.get("discovered_items", {})

	if loaded_discovered is Dictionary:
		_discovered_items = loaded_discovered.duplicate(true);
	else:
		_discovered_items = {};
		
	#Analytics
	var unique_count: int = _items.size();
	var total_count: int = 0;
	for amount in _items.values():
		total_count += int(amount);
		
	Analytics.log_event("inventory_loaded", {
		"unique_items": unique_count,
		"total_items": total_count
	})
#endregion
#region Layout APIs
#Is the inventory full?
func has_free_slot() -> bool:
	_ensure_layout_size();
	for i in range(get_slot_count()):
		if String(_layout[i]).is_empty():
			return true;
	return false;
	
func _ensure_layout_size() -> void:
	if _layout.size() != get_slot_count():
		_layout.resize(get_slot_count());
	for i in range(get_slot_count()):
		if _layout[i] == null:
			_layout[i] = "";
			
func get_layout() -> Array[String]:
	#Return a copy to avoid external mutation
	_ensure_layout_size();
	return _layout.duplicate();
	
func get_slot_item(slot_index: int) -> String:
	_ensure_layout_size();
	if slot_index < 0 or slot_index >= get_slot_count():
		return ""
	return String(_layout[slot_index]);
	
func set_slot_item(slot_index: int, item_id: String) -> void:
	#Directly set which item is in a slot
	#Enforces one slot per item_id 
	_ensure_layout_size();
	if slot_index < 0 or slot_index >= get_slot_count():
		return;
		
	if not item_id.is_empty() and get_amount(item_id) <= 0:
		#Don't allow placing items you don't have
		return;
		
	#Remove this item from any other slot so it stays unique
	if not item_id.is_empty():
		_remove_item_from_layout(item_id);

	_layout[slot_index] = item_id;
	inventory_changed.emit(item_id);
	#Anayltics: Track hotbar/slot arrangement changes
	Analytics.log_event("inventory_slot_set", {
		"slot_index": slot_index,
		"item_id": item_id
	})
	
func clear_slot(slot_index: int) -> void:
	set_slot_item(slot_index, "");
	
func swap_slots(a: int, b: int) -> void:
	_ensure_layout_size();
	if a < 0 or a >= get_slot_count():
		return;
	if b < 0 or b >= get_slot_count():
		return;
	if a == b:
		return;
		
	var _item_a_before: String = String(_layout[a]);
	var _item_b_before: String = String(_layout[b]);
	var temp := _layout[a];
	_layout[a] = _layout[b];
	_layout[b] = temp;
	
	inventory_changed.emit(_item_a_before);
	
	#Analytics: slots swapped in the layout
	Analytics.log_event("inventory_slots_swapped", {
		"slot_a": a,
		"slot_b": b,
		"item_a": _item_a_before, #after swap
		"item_b": _item_b_before,
	})
	
func find_slot_of_item(item_id: String) -> int:
	_ensure_layout_size();
	if item_id.is_empty():
		return -1;
	for i in range(get_slot_count()):
		if _layout[i] == item_id:
			return i;
	return -1;
	
func _place_item_if_missing(item_id: String) -> void:
	#If item is already in layout, do nothing
	if find_slot_of_item(item_id) != -1:
		return;
		
	#Place into first empty slot
	for i in range(get_slot_count()):
		if String(_layout[i]).is_empty():
			_layout[i] = item_id;
			return;
			
func _remove_item_from_layout(item_id: String) -> void:
	_ensure_layout_size();
	for i in range(get_slot_count()):
		if _layout[i] == item_id:
			_layout[i] = "";
			
#endregion
