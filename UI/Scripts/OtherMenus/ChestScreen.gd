extends AnimatedMenu
#Top part: chest contents
#Bottom part: player inventory
#Click item in either panel to transfer it to the other

@export var item_slot_scene: PackedScene;

#Node refs
@onready var chest_grid: GridContainer = %ChestGrid;
@onready var player_grid: GridContainer = %PlayerGrid;
@onready var chest_label: Label = %ChestLabel;
@onready var player_label: Label = %PlayerLabel;

#State
var _chest_slots: Array[ItemSlot] = [];
var _player_slots: Array[ItemSlot] = [];

func _ready() -> void:
	super._ready();
	
	#Wire inventory changes
	InventorySystem.inventory_changed.connect(_on_inventory_changed);
	ChestStorageSystem.chest_contents_changed.connect(_on_chest_changed);
	
	#Apply labels
	UIStringsDatabase.apply_to_label(chest_label, "chest_contents");
	UIStringsDatabase.apply_to_label(player_label, "player_inventory");
	
	_build_chest_slots();
	_build_player_slots();
	_refresh_chest();
	_refresh_player();
	
	
#region Slot building
func _build_chest_slots() -> void:
	for child in chest_grid.get_children():
		child.queue_free();
	_chest_slots.clear();
	#Fixed grid size--chest has a generous fixed number of display slots
	#Empty slots are shown as empty, contents are driven by ChestStorageSystem
	var all_items: Dictionary = ChestStorageSystem.get_all_items();
	var slot_count: int = max(all_items.size() + 8, 16);
	for i in range(slot_count):
		var slot: ItemSlot = item_slot_scene.instantiate() as ItemSlot;
		slot.slot_index = i;
		chest_grid.add_child(slot);
		_chest_slots.append(slot);
		slot.slot_clicked.connect(_on_chest_slot_clicked);
		
func _build_player_slots() -> void:
	for child in player_grid.get_children():
		child.queue_free();
	_player_slots.clear();
	for i in range(InventorySystem.get_slot_count()):
		var slot: ItemSlot = item_slot_scene.instantiate() as ItemSlot;
		slot.slot_index = i;
		player_grid.add_child(slot);
		_player_slots.append(slot);
		slot.slot_clicked.connect(_on_player_slot_clicked);
	
#endregion
#region Refresh
func _refresh_chest() -> void:
	#Sort chest items by type then name
	var all_items: Dictionary = ChestStorageSystem.get_all_items();
	var sorted_ids: Array = _sort_items_by_type(all_items.keys());
	
	#Rebuild slots if item count has grown beyond current slot count
	if sorted_ids.size() > _chest_slots.size():
		_build_chest_slots();
	#Fill slots with sorted items, clear the rest
	for i in range(_chest_slots.size()):
		if i < sorted_ids.size():
			var item_id: String = sorted_ids[i];
			_chest_slots[i].set_item(item_id, ChestStorageSystem.get_amount(item_id));
		else:
			_chest_slots[i].clear_item();
			
func _refresh_player() -> void:
	var layout: Array[String] = InventorySystem.get_layout();
	#Rebuild if slot count changed (level up, for example)
	if layout.size() != _player_slots.size():
		_build_player_slots();
	for i in range(_player_slots.size()):
		var item_id: String = String(layout[i]);
		if item_id.is_empty():
			_player_slots[i].clear_item();
		else:
			_player_slots[i].set_item(item_id, InventorySystem.get_amount(item_id));

func _sort_items_by_type(ids: Array) -> Array:
	var order: Dictionary = {
		ItemDataResource.ItemType.TOOL: 0,
		ItemDataResource.ItemType.CONSUMABLE: 1,
		ItemDataResource.ItemType.RESOURCE: 2,
		ItemDataResource.ItemType.KEY_ITEM: 3,
		ItemDataResource.ItemType.FURNITURE: 4,
		ItemDataResource.ItemType.UNKNOWN: 5,
	};
	ids.sort_custom(func(a, b):
		var item_a: ItemDataResource = ItemDatabase.get_item(a);
		var item_b: ItemDataResource = ItemDatabase.get_item(b);
		var type_a: int = order.get(item_a.type if item_a else ItemDataResource.ItemType.UNKNOWN, 5);
		var type_b: int = order.get(item_b.type if item_b else ItemDataResource.ItemType.UNKNOWN, 5);
		if type_a != type_b:
			return type_a < type_b;
		return ItemDatabase.get_display_name(a) < ItemDatabase.get_display_name(b);
	);
	return ids;
#endregion
#region Click handlers
func _on_chest_slot_clicked(slot: ItemSlot) -> void:
	#Move item from chest to player inventory
	if slot.is_empty():
		return;
	var item_id: String = slot.item_id;
	var amount: int = ChestStorageSystem.get_amount(item_id);
	#Try to add to player inventory first
	if not InventorySystem.try_add_item(item_id, amount):
		#Inventory full, show message
		var hud = UIRouter.get_hud();
		if hud:
			hud.show_message(UIStringsDatabase.get_text("inventory_full"));
		return;
	#Removal from chest only if add successful
	ChestStorageSystem.try_remove_item(item_id, amount);
	Analytics.log_event("chest_item_withdrawn", {
		"item_id": item_id,
		"amount": amount
	});
	
func _on_player_slot_clicked(slot: ItemSlot) -> void:
	#Move item from player inventory to chest
	if slot.is_empty():
		return;
	var item_id: String = slot.item_id;
	var amount: int = InventorySystem.get_amount(item_id);
	InventorySystem.try_remove_item(item_id, amount);
	ChestStorageSystem.try_add_item(item_id, amount);
	Analytics.log_event("chest_item_deposited", {
		"item_id": item_id,
		"amount": amount,
	});
#endregion
#region Signal handlers
func _on_inventory_changed(_item_id: String = "") -> void:
	_refresh_player();
	
func _on_chest_changed(_item_id: String = "") -> void:
	_refresh_chest();
#endregion
