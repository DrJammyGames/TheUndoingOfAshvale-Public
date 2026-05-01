extends HBoxContainer
class_name PinnedRecipeEntry

const INGREDIENT_SLOT_SCENE: PackedScene = preload("res://UI/Scenes/Crafting/CraftingIngredientSlot.tscn");

@onready var recipe_icon: TextureRect = %RecipeIcon;
@onready var count_label: Label = %CountLabel;
@onready var ingredients_container: HBoxContainer = %IngredientsContainer;
@onready var unpin_button: Button = %UnpinButton;

var _recipe: RecipeDataResource = null;
var _count: int = 1;
var _ingredient_slots: Array[CraftingIngredientSlot] = [];

func setup(recipe: RecipeDataResource, count: int = 1) -> void:
	_recipe = recipe;
	_count = count;
	
	if recipe.result_item:
		recipe_icon.texture = recipe.result_item.icon_inv;
		
	if unpin_button:
		unpin_button.pressed.connect(_on_unpin_pressed);
	
	InventorySystem.inventory_changed.connect(_on_inventory_changed);
	ChestStorageSystem.chest_contents_changed.connect(_on_inventory_changed);
	CraftingSystem.recipe_pin_count_changed.connect(_on_pin_count_changed);
	_build_ingredient_slots();
	refresh();
	
func _build_ingredient_slots() -> void:
	#Clear entries first
	for child in ingredients_container.get_children():
		child.queue_free();
	_ingredient_slots.clear();
	
	if _recipe == null:
		return;
		
	for ingredient in _recipe.ingredients:
		var slot: CraftingIngredientSlot = INGREDIENT_SLOT_SCENE.instantiate();
		ingredients_container.add_child(slot);
		slot.setup(ingredient, "pinned");
		_ingredient_slots.append(slot);
		
func refresh() -> void:
	if _recipe == null:
		return;
	#Update count label
	if count_label:
		count_label.text = "x%d" % _count;
		count_label.visible = _count > 1;
	#Resize if different number of ingredients
	for i in range(_ingredient_slots.size()):
		if i < _recipe.ingredients.size():
			_ingredient_slots[i].refresh(_recipe.ingredients[i], _count);
			
func get_recipe_id() -> String:
	if _recipe == null:
		return "";
	return _recipe.recipe_id;

func _on_unpin_pressed() -> void:
	if _recipe == null:
		return;
	CraftingSystem.unpin_recipe(_recipe.recipe_id);
	
func _on_inventory_changed(_item_id: String) -> void:
	refresh();

func _on_pin_count_changed(recipe_id: String) -> void:
	if _recipe == null:
		return;
	if recipe_id != _recipe.recipe_id:
		return;
	_count = CraftingSystem.get_pin_count(_recipe.recipe_id);
	refresh();
