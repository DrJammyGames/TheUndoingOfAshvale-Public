extends TextureButton
class_name ArmorSlot

@export var slot_icon: Texture2D;

@onready var slot_bg: TextureRect = %SlotBG;
@onready var empty_icon: TextureRect = %EmptyIcon;
@onready var item_icon: TextureRect = %ItemIcon;

func _ready() -> void:
	if slot_icon:
		empty_icon.texture = slot_icon;
	item_icon.visible = false;
	
#Call this when an item is equipped
#stubbed for post-thesis
func set_item(_item: ItemDataResource) -> void:
	pass;
	
#Call this to clear the slot
func clear_item() -> void:
	item_icon.texture = null;
	item_icon.visible = false;
	empty_icon.visible = true;
