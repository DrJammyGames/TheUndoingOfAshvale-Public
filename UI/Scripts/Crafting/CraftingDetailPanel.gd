extends VBoxContainer
class_name CraftingDetailPanel

signal back_pressed;

const INGREDIENT_SLOT_SCENE: PackedScene = preload("res://UI/Scenes/Crafting/CraftingIngredientSlot.tscn");

@onready var pin_count_container: HBoxContainer = %PinCountContainer;
@onready var pin_minus_button: Button = %PinMinusButton;
@onready var pin_count_label: Label = %PinCountLabel;
@onready var pin_plus_button: Button = %PinPlusButton;
@onready var back_button: Button = %BackButton;
@onready var result_icon: TextureRect = %ResultIcon;
@onready var result_label: Label = %ResultLabel;
@onready var night_hint_label: Label = %NightHintLabel;
@onready var inventory_full_label: Label = %InventoryFullLabel;
@onready var ingredients_container: HBoxContainer = %IngredientsContainer;
@onready var craft_button: Button = %CraftButton;
@onready var pin_button: Button = %PinButton;

var _recipe: RecipeDataResource = null;
var _ingredient_slots: Array[CraftingIngredientSlot] = [];
var _pin_count: int = 1;

func _ready() -> void:
	#Set up the buttons with localisation and connections
	if back_button:
		UIStringsDatabase.apply_to_button(back_button,"back");
		back_button.pressed.connect(_on_back_pressed);
		
	if craft_button:
		UIStringsDatabase.apply_to_button(craft_button, "craft_table_craft_button");
		craft_button.pressed.connect(_on_craft_pressed);
		
	if pin_button:
		UIStringsDatabase.apply_to_button(pin_button, "craft_table_pin_recipe_button");
		pin_button.pressed.connect(_on_pin_pressed);
	if pin_minus_button:
		pin_minus_button.pressed.connect(_on_pin_minus_pressed);
	if pin_plus_button:
		pin_plus_button.pressed.connect(_on_pin_plus_pressed);
		
	if night_hint_label:
		UIStringsDatabase.apply_to_label(night_hint_label, "craft_table_crafting_night_locked");
	if inventory_full_label:
		UIStringsDatabase.apply_to_label(inventory_full_label, "craft_table_inventory_full");
	#Connect signals
	if InventorySystem:
		InventorySystem.inventory_changed.connect(_on_inventory_changed);
	if CraftingSystem:
		CraftingSystem.recipe_pinned.connect(_on_pin_state_changed);
		CraftingSystem.recipe_unpinned.connect(_on_pin_state_changed);
		ChestStorageSystem.chest_contents_changed.connect(_on_inventory_changed);
#Populate the ingredients
func populate(recipe: RecipeDataResource) -> void:
	_recipe = recipe;
	_pin_count = 1;
	
	if recipe.result_item:
		result_icon.texture = recipe.result_item.icon_inv;
		result_label.text = ItemDatabase.get_display_name(recipe.result_item.item_id);
		if recipe.result_amount > 1:
			result_label.text += " x%d" % recipe.result_amount;
			
	_build_ingredient_slots();
	_refresh();
	
func _build_ingredient_slots() -> void:
	#Clear everything first
	for child in ingredients_container.get_children():
		child.queue_free();
	_ingredient_slots.clear();
	#Safety check
	if _recipe == null:
		return;
		
	#Now fill in the information
	for ingredient in _recipe.ingredients:
		var slot: CraftingIngredientSlot = INGREDIENT_SLOT_SCENE.instantiate();
		ingredients_container.add_child(slot);
		slot.setup(ingredient, "menu");
		_ingredient_slots.append(slot);

func _refresh() -> void:
	if _recipe == null:
		return;
	var is_night: bool = DayNightSystem.is_night();
	var can_craft: bool = CraftingSystem.can_craft(_recipe.recipe_id);
	#Disable the crafting button if the player can't currently craft the item
	craft_button.disabled = not can_craft;
	
	#Show a hint if it's night
	if night_hint_label:
		night_hint_label.visible = is_night;
	if inventory_full_label:
		var show_full: bool = false;
		if _recipe and _recipe.result_item:
			if _recipe.result_item.type != ItemDataResource.ItemType.FURNITURE:
				if not InventorySystem.has_item(_recipe.result_item.item_id):
					show_full = not InventorySystem.has_free_slot();
		inventory_full_label.visible = show_full;
	#Refresh ingredient slot amounts
	for i in range(_ingredient_slots.size()):
		if i < _recipe.ingredients.size():
			_ingredient_slots[i].refresh(_recipe.ingredients[i]);
			
	#Update pin button label
	var pinned: bool = CraftingSystem.is_pinned(_recipe.recipe_id);
	var pin_text: String = "";
	if pinned:
		pin_text = "craft_table_unpin_recipe_button";
	else:
		pin_text = "craft_table_pin_recipe_button"
	UIStringsDatabase.apply_to_button(pin_button,pin_text);
	#Show/hide quantity selector based on pin state
	if pin_count_container:
		pin_count_container.visible = not pinned;
	#Reset count when viewing a new recipe or after pinning
	if not pinned:
		_pin_count = 1;
		_update_pin_count_display();
	
func _on_back_pressed() -> void:
	back_pressed.emit();
	
func _on_craft_pressed() -> void:
	if _recipe == null:
		return;
		
	var success: bool = CraftingSystem.craft(_recipe.recipe_id);
	if not success:
		return;
	#Add a crafting sfx later
	#AudioManager.play_sfx("crafted");
	#Add some sort of visual indicator the the recipe was created
	_refresh();
	
func _on_pin_pressed() -> void:
	if _recipe == null:
		return;
	if CraftingSystem.is_pinned(_recipe.recipe_id):
		CraftingSystem.unpin_recipe(_recipe.recipe_id);
	else:
		CraftingSystem.pin_recipe(_recipe.recipe_id, _pin_count);
		
func _on_pin_minus_pressed() -> void:
	_pin_count = clampi(_pin_count - 1, 1, 99);
	_update_pin_count_display();
	
func _on_pin_plus_pressed() -> void:
	_pin_count = clampi(_pin_count + 1, 1, 99);
	_update_pin_count_display();
	
func _update_pin_count_display() -> void:
	if pin_count_label:
		pin_count_label.text = str(_pin_count);
		
func _on_inventory_changed(_item_id: String) -> void:
	_refresh();
	
func _on_pin_state_changed(_recipe_id: String) -> void:
	_refresh();
