extends Node

var _recipes: Dictionary = {}; #recipe_id -> RecipeDataResource

func _ready() -> void:
	for resource in RecipesPreloadRegistry.ALL:
		if resource is RecipeDataResource:
			register(resource);
		else:
			push_warning("[RecipeDatabase] Non-RecipeDataResource entry: %s" % resource);
	
#Register a single recipe resource
func register(recipe: RecipeDataResource) -> void:
	if recipe == null or recipe.recipe_id.is_empty():
		push_warning("[RecipeDatabase] Tried to register a null or id-less recipe.")
		return;
	_recipes[recipe.recipe_id] = recipe;
	
#Public helper to get the recipe
func get_recipe(recipe_id: String) -> RecipeDataResource:
	return _recipes.get(recipe_id, null);
	
func get_recipes_of_type(type: RecipeDataResource.RecipeType) -> Array[RecipeDataResource]:
	var result: Array[RecipeDataResource] = [];
	for recipe in _recipes.values():
		if recipe.recipe_type == type:
			result.append(recipe);
	return result;
	
func get_all_recipes() -> Array[RecipeDataResource]:
	var result: Array[RecipeDataResource] = [];
	for recipe in _recipes.values():
		result.append(recipe);
	return result;
