extends Control
class_name InventoryScreen

const ITEM_SLOT_SCENE: PackedScene = preload("res://UI/Scenes/Inventory/ItemSlot.tscn");

@onready var item_grid: GridContainer = %ItemGrid;
@onready var hint_label: Label = %HintLabel;
@onready var dragged_icon: TextureRect = %DraggedIcon;

#Track currently selected item id
var _current_item_id: String = "";
#Slots list for easy access
var _slots: Array[ItemSlot] = [];

#Drag/hold state
var _held_item_id: String = "";
var _held_from_index: int = -1;

func _ready() -> void:
	#Accessibility-friendly hints
	#hint_label.text = "Click to pick up an item, then click another slot to swap. Esc to close.";
	#Set dragged icon invisible on start
	dragged_icon.visible = false;
	set_process(false);
	#Subscribe to inventory changes
	if InventorySystem.has_signal("inventory_changed"):
		InventorySystem.inventory_changed.connect(_on_inventory_changed);
	#Build initial list
	_build_slots();
	_on_inventory_changed();

func _process(_delta: float) -> void:
	dragged_icon.global_position = get_viewport().get_mouse_position() + Vector2(16, 16);

#region Internal helpers
#Build the inventory slots
func _build_slots() -> void:
	#Clear any existing children first 
	for child in item_grid.get_children():
		child.queue_free();
	_slots.clear();
	
	#Rebuild slots
	for i in range(InventorySystem.get_slot_count()):
		var slot: ItemSlot = ITEM_SLOT_SCENE.instantiate() as ItemSlot;
		slot.slot_index = i;
		item_grid.add_child(slot);
		_slots.append(slot);
		#Connect when clicked
		slot.slot_clicked.connect(_on_slot_clicked);
		
#Update when inventory changes
func _on_inventory_changed(_item_id: String = "") -> void:
	#Render directly from InventorySystem layout
	var layout = InventorySystem.get_layout();
	
	#Rebuild slots if the layout size has changed
	if layout.size() != _slots.size():
		_build_slots();
	
	for i in range(_slots.size()):
		var slot := _slots[i];
		var item_id := String(layout[i]);
		if item_id.is_empty():
			slot.clear_item();
		else:
			slot.set_item(item_id, InventorySystem.get_amount(item_id));
			
	#Auto-select first non-empty slot
	_current_item_id = "";
	for i in range(layout.size()):
		var id := String(layout[i]);
		if not id.is_empty():
			_select_item(id);
			break;
			

#Clicked/swapping logic
func _on_slot_clicked(slot: ItemSlot) -> void:
	var target_index := slot.slot_index
	
	#Not holding anything -> pick up (remove from layout, not counts)
	if _held_item_id.is_empty():
		if slot.is_empty():
			return;
			
		_held_item_id = slot.item_id;
		_held_from_index = target_index;
		dragged_icon.texture = ItemDatabase.get_icon_inv(_held_item_id);
		
		#Remove from layout immediately (creates the "carrying" empty slot)
		InventorySystem.clear_slot(target_index);
		
		_select_item(_held_item_id);
		set_process(true);
		dragged_icon.visible = true;
		return;
		
	#Holding something -> place/swap into target
	if target_index == _held_from_index and slot.is_empty():
		#Drop back into the original place
		InventorySystem.set_slot_item(target_index, _held_item_id);
		_clear_held();
		return;
		
	#If target has item, swap by putting held into target and putting target into held_from_index
	if not slot.is_empty():
		var target_item := slot.item_id;
		InventorySystem.set_slot_item(target_index, _held_item_id);
		InventorySystem.set_slot_item(_held_from_index, target_item);
		_clear_held();
		_select_item(target_item);
		return;
		
	#Target empty: place held there
	InventorySystem.set_slot_item(target_index, _held_item_id);
	_clear_held();
	_select_item(slot.item_id); #slot will refresh after signal

	
#Clear held state
func _clear_held() -> void:
	_held_item_id = "";
	_held_from_index = -1;
	dragged_icon.texture = null;
	dragged_icon.visible = false;
	set_process(false);
		
#Select the item in the item slot
func _select_item(item_id: String) -> void:
	_current_item_id = item_id;

#endregion
