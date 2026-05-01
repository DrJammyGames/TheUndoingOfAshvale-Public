extends HBoxContainer;
class_name ItemSummaryRow;

@onready var icon_rect: TextureRect = %IconRect;
@onready var name_label: Label = %ItemLabel;

func setup(item_id: String, amount: int) -> void:
	var icon: Texture2D = ItemDatabase.get_icon_inv(item_id);
	#Only display the icon if it's been set
	if icon:
		icon_rect.texture = icon;
	else:
		icon_rect.hide();
		
	var display_name: String = ItemDatabase.get_display_name(item_id);
	#Already localised 
	name_label.text = "%s +%d" % [display_name, amount];
