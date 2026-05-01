extends TextureButton
class_name CraftingRecipeIcon

signal icon_clicked(recipe: RecipeDataResource);

@onready var recipe_icon: TextureRect = %RecipeIcon;

var _recipe: RecipeDataResource = null;
var _is_unlocked: bool = false;

func setup(recipe: RecipeDataResource) -> void:
	_recipe = recipe;
	
	if recipe.result_item:
		recipe_icon.texture = recipe.result_item.icon_inv;
	_is_unlocked = CraftingSystem.is_unlocked(recipe.recipe_id);
	#Black out if the recipe is locked
	if _is_unlocked:
		modulate = Color(1,1,1,1);
	else:
		modulate = Color(0,0,0,1);
		
	#Prevent interaction if locked
	disabled = not _is_unlocked;
	
	pressed.connect(_on_pressed);
	mouse_entered.connect(_on_mouse_entered);
	mouse_exited.connect(_on_mouse_exited);
	
func _on_pressed() -> void:
	if _recipe == null:
		return;
	icon_clicked.emit(_recipe);
	
func _on_mouse_entered() -> void:
	if not GlobalTooltip:
		return;
	if _is_unlocked:
		GlobalTooltip.show_tooltip(_get_title(), _get_body());
	else:
		GlobalTooltip.show_tooltip("???", "???");
		
func _on_mouse_exited() -> void:
	if GlobalTooltip:
		GlobalTooltip.hide_tooltip();
		
func _get_title() -> String:
	if _recipe == null or _recipe.result_item == null:
		return "";
	return ItemDatabase.get_display_name(_recipe.result_item.item_id);
	
func _get_body() -> String:
	if _recipe == null:
		return "";
	var lines: Array[String] = [];
	#Result amount
	if _recipe.result_item != null and _recipe.result_amount > 1:
		lines.append("Produces: x%d" % _recipe.result_amount);
	#Ingredients
	if _recipe.ingredients.size() > 0:
		var parts: Array[String] = [];
		for ingredient in _recipe.ingredients:
			if ingredient.item != null:
				var ing_name: String = ItemDatabase.get_display_name(ingredient.item.item_id)
				parts.append("%s x%d" % [ing_name, ingredient.amount]);
		if not parts.is_empty():
			lines.append("Requires: %s" % ", ".join(parts));
	return "\n".join(lines);
