extends Control 
class_name EncyclopediaItemsPanel

#Displays all items in the game as a grid of EncyclopediaIcon nodes
#Discovered (picked up at least once) is full colour and tooltip
#Undiscovered = blacked out and ??? tooltip

const ENCYCLOPEDIA_ICON_SCENE: PackedScene = preload("res://UI/Scenes/Encyclopedia/EncyclopediaIcon.tscn");

@onready var grid: GridContainer = %ItemGrid;

func _ready() -> void:
	rebuild();
	
func rebuild() -> void:
	#Clear existing entries first
	for child in grid.get_children():
		child.queue_free();
		
	var all_items: Array[ItemDataResource] = ItemDatabase.get_all_items();
	
	#Sort by type
	all_items.sort_custom(func(a,b):
		var order: Dictionary = {
			ItemDataResource.ItemType.TOOL: 0,
			ItemDataResource.ItemType.CONSUMABLE: 1,
			ItemDataResource.ItemType.RESOURCE: 2,
			ItemDataResource.ItemType.KEY_ITEM: 3,
			ItemDataResource.ItemType.UNKNOWN: 4,
		}
		return order.get(a.type, 4) < order.get(b.type, 4);
	)
	
	for item in all_items:
		var icon: EncyclopediaIcon = ENCYCLOPEDIA_ICON_SCENE.instantiate();
		grid.add_child(icon);
		var discovered: bool = EncyclopediaSystem.has_found_item(item.item_id);
		var title: String = ItemDatabase.get_display_name(item.item_id);
		var body: String = _build_tooltip_body(item);
		
		icon.setup(item.icon_inv, discovered, title, body);
		
func _build_tooltip_body(item: ItemDataResource) -> String:
	var desc: String = ItemDatabase.get_description(item.item_id);
	var type_str: String = _type_label(item.type);
	return "%s\n\nType: %s" % [desc, type_str];
	
func _type_label(type: ItemDataResource.ItemType) -> String:
	match type:
		ItemDataResource.ItemType.CONSUMABLE:
			return "Consumable";
		ItemDataResource.ItemType.RESOURCE:
			return "Resource";
		ItemDataResource.ItemType.KEY_ITEM:
			return "Key Item";
		ItemDataResource.ItemType.TOOL:
			return "Tool";
		_:
			return "Unknown";
			
	
