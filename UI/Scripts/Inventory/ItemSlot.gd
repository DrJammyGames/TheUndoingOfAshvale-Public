extends TextureButton

class_name ItemSlot

signal slot_clicked(slot: ItemSlot);

@export var slot_index: int = -1;

var item_id: String = "";
var amount: int = 0;

@onready var icon_rect: TextureRect = %Icon;
@onready var quantity_label: Label = %QuantityLabel;

func _ready() -> void:
	#Basic visuals for empty slots
	_refresh_visuals();
	
	#Set up button press and tooltips
	pressed.connect(_on_pressed);
	mouse_entered.connect(_on_mouse_entered);
	mouse_exited.connect(_on_mouse_exited);
	
#region Public helpers
#Set the item in the slot
func set_item(id: String, amt: int) -> void:
	item_id = id;
	amount = max(amt, 0);
	if amount == 0:
		item_id = "";
	_refresh_visuals();
	
#Clear an item in the slot
func clear_item() -> void:
	item_id = "";
	amount = 0;
	_refresh_visuals();
	
#Check if anything is there
func is_empty() -> bool:
	return item_id == "" or amount <= 0;
#endregion
#region Internal helpers
#Refresh the visuals for the inventory
func _refresh_visuals() -> void:
	#Nothing in slot
	if is_empty():
		if icon_rect:
			#No icon
			icon_rect.texture = null;
		if quantity_label:
			#No text
			quantity_label.text = "" if amount <= 1 else "x%d" % amount;
		#Visually show nothing
		#But keep slot enabled so we can still click on the buttons
		disabled = false; 
	#Something is in the slot
	else:
		disabled = false;
		if icon_rect:
			#Set the texture from ItemDatabase
			icon_rect.texture = ItemDatabase.get_icon_inv(item_id);
		if quantity_label:
			#Set quantity label based on amount
			quantity_label.text = "x%d" % amount;

#Clicked on item in slot
func _on_pressed() -> void:
	slot_clicked.emit(self);
	
#Tooltip hovering entered
func _on_mouse_entered() -> void:
	if is_empty():
		return;
		
	var item_name: String = ItemDatabase.get_display_name(item_id);
	var desc: String = ItemDatabase.get_description(item_id);
	
	#Autoload global tooltip for everywhere
	if GlobalTooltip:
		GlobalTooltip.show_tooltip(item_name, desc);
		
#Exited slot, hide tooltip
func _on_mouse_exited() -> void:
	if GlobalTooltip:
		GlobalTooltip.hide_tooltip();
#endregion
