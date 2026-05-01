extends HBoxContainer
class_name CraftingRecipeRow

signal craft_requested;

@onready var result_icon: TextureRect = %ResultIcon;
@onready var result_label: Label = $ResultLabel;
@onready var ingredients_container: HBoxContainer = %IngredientsContainer;
@onready var craft_button: Button = %CraftButton;

var _recipe: RecipeDataResource = null;

func setup(recipe: RecipeDataResource) -> void:
	_recipe = recipe;
	
	#Set the result icon and name
	if recipe.result_item:
		result_icon.texture = recipe.result_item.icon_inv;
		result_label.text = ItemDatabase.get_display_name(recipe.result_item.item_id);
		if recipe.result_amount > 1:
			result_label.text += " x%d" % recipe.result_amount;
	
	_build_ingredient_display();
	refresh_craftability();
	if craft_button:
		UIStringsDatabase.apply_to_button(craft_button, "craft_table_craft_button");
		craft_button.pressed.connect(_on_craft_pressed);
		
#Public helper to refresh what can be crafted
func refresh_craftability() -> void:
	if _recipe == null:
		return;
	var can_craft: bool = CraftingSystem.can_craft(_recipe.recipe_id);
	#Disable craft button if the item can't be crafted
	craft_button.disabled = not can_craft;
	
	#Gray out the row but keep it visible so the player can still see it
	if can_craft:
		modulate = Color(1,1,1,1);
	else:
		modulate = Color(0.6,0.6,0.6,1);
		
func _build_ingredient_display() -> void:
	#Clear any existing ingredient nodes
	for child in ingredients_container.get_children():
		child.queue_free();
		
	if _recipe == null:
		return;
		
	for ingredient in _recipe.ingredients:
		if ingredient.item == null:
			continue;
			
		#Each ingredient: icon + amount label
		
		
#Pressing the crafting button--emit signal
func _on_craft_pressed() -> void:
	craft_requested.emit();
