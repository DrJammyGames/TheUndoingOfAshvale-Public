extends Resource 
class_name ItemDataResource;
#region Enums
enum ItemType {
	UNKNOWN,
	CONSUMABLE,
	RESOURCE,
	KEY_ITEM,
	TOOL,
	FURNITURE
}

enum ToolCategory {
	NONE,
	SWORD,
	AXE,
	HOE,
	PICKAXE,
	WATERING_CAN
}
#endregion

#Core data
@export var item_id: String = "";
@export var type: ItemType = ItemType.UNKNOWN;

#Logical data
@export var value: int = 0;
@export var sellable: bool = true;

#Consumable data
@export var consume_effect_value: int = 0;

#Tool data
@export var tool_category: ToolCategory = ToolCategory.NONE;
@export var base_power: int = 1;
@export var time_cost: float = 2.0;
#Presentation
@export var icon_inv: Texture2D;
@export var icon_world: Texture2D;
@export var pickup_sfx: AudioStream;
@export var use_sfx: AudioStream;

#Auto-generate keys for localisation
func get_name_key() -> String:
	if item_id.is_empty():
		return ""
	return "item.%s.name" % item_id.to_lower();
	
func get_description_key() -> String:
	if item_id.is_empty():
		return "";
	return "item.%s.description" % item_id.to_lower();
