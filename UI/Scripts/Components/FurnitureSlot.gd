extends Button
class_name FurnitureSlot

@onready var count_label: Label = %CountLabel;

func setup(item_id: String, count: int) -> void:
	icon = ItemDatabase.get_icon_inv(item_id);
	count_label.text = "x%d" % count;
