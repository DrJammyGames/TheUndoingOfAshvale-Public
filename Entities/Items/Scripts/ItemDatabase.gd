extends Node;

#Database that builds item info based off of resources in the items folder

var _items_by_id: Dictionary = {};

func _ready() -> void:
	for resource in ItemPreloadRegistry.ALL:
		if resource is ItemDataResource:
			var item: ItemDataResource = resource;
			if item.item_id.is_empty():
				push_warning("ItemDataResource missing id: %s" % resource.resource_path);
			elif _items_by_id.has(item.item_id):
				push_warning("Duplicate ItemDataResource id: %s" % item.item_id);
			else:
				_items_by_id[item.item_id] = item;
		else:
			push_warning("ItemPreloadRegistry: Non-ItemDataResource entry: %s" % resource.resource_path);
	
#region Public APIs
func has_item(item_id: String) -> bool:
	return _items_by_id.has(item_id);

func get_item(item_id: String) -> ItemDataResource:
	return _items_by_id.get(item_id, null);
	
func get_display_name(item_id: String) -> String:
	var item = get_item(item_id);
	if item == null:
		return item_id.capitalize();
	return tr(item.get_name_key());
	
func get_description(item_id: String) -> String:
	var item = get_item(item_id);
	if item == null:
		return "";
	return tr(item.get_description_key());

#Visual helpers
#Get the icon to be drawn in the world
func get_icon_world(item_id: String) -> Texture2D:
	var item = get_item(item_id);
	if item:
		return item.icon_world;
	return null;

#Get the icon to be drawn in the inventory
func get_icon_inv(item_id: String) -> Texture2D:
	var item = get_item(item_id);
	if item:
		return item.icon_inv;
	return null;
	
#SFX helpers
func get_pickup_sfx(item_id: String) -> AudioStream:
	var item = get_item(item_id);
	if item:
		return item.pickup_sfx;
	return null;
	
func get_use_sfx(item_id: String) -> AudioStream:
	var item = get_item(item_id);
	if item:
		return item.use_sfx;
	return null;
	
func get_type(item_id: String) -> ItemDataResource.ItemType:
	var item = get_item(item_id);
	if item:
		return item.type;
	return ItemDataResource.ItemType.UNKNOWN;

#Shop functions
func is_sellable(item_id: String) -> bool:
	var item = get_item(item_id);
	if item:
		return item.sellable;
	return false;

func get_value(item_id: String) -> int:
	var item = get_item(item_id);
	if item:
		return item.value;
	return 0;

#Tool helpers
func is_tool(item_id: String) -> bool:
	return get_type(item_id) == ItemDataResource.ItemType.TOOL;
	
func get_tool_base_power(item_id: String) -> int:
	var item = get_item(item_id);
	if item:
		return item.base_power;
	return 1;
	
func get_tool_time_cost(item_id: String) -> float:
	var item = get_item(item_id);
	if item:
		return item.time_cost;
	return 1.0;
	
func get_tool_category(item_id: String) -> ItemDataResource.ToolCategory:
	var item = get_item(item_id);
	if item:
		return item.tool_category;
	return ItemDataResource.ToolCategory.NONE;
	
func get_all_items() -> Array[ItemDataResource]:
	var result: Array[ItemDataResource] = [];
	for item in _items_by_id.values():
		result.append(item);
	return result;
#endregion
#region Internal helpers	
func _make_fallback_item(item_id: String) -> Dictionary:
	return {
		"item_id": item_id,
		"type": ItemDataResource.ItemType.UNKNOWN,
		"value": 0,
		"sellable": false,
		"name_key": "item.%s.name" % item_id,
		"description_key": "item.%s.description" % item_id,
		"tool": {}, #empty 
	}
#endregion
