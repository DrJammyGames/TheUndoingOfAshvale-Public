extends Node

#Emitted when a recipe is successfully crafted
#Already matches QuestStepResource.ITEM_CRAFTED event
signal item_crafted(payload: Dictionary);
#Emitted when a consumable is used--handled by player to apply effects
signal item_used(item_id: String);
#Emitted when a new recipe is unlocked
signal recipe_unlocked(recipe_id: String);
#HUD signals for pinning recipes
signal recipe_pinned(recipe_id: String);
signal recipe_unpinned(recipe_id: String);
signal recipe_pin_count_changed(recipe_id: String);
#Keep track of crafted items--first craft awards xp
var _crafted_item_ids: Array[String] = [];
#Persistent reference to unlocked recipes
var _unlocked_recipe_ids: Array[String] = [];
#Pinned recipes--allow the player to pin more than one
var _pinned_recipes: Dictionary = {}; #recipe_id -> int count


func _ready() -> void:
	#Unlock all default recipes at default
	#Later add unlockable blueprints
	_unlock_defaults();
	#Hook into LevelSystem for Level Up unlocks
	LevelSystem.leveled_up.connect(_on_level_up);
	
#region Unlock functions
func _unlock_defaults() -> void:
	for recipe in RecipeDatabase.get_all_recipes():
		if recipe.unlock_source == RecipeDataResource.UnlockSource.DEFAULT:
			_add_unlock(recipe.recipe_id);
			
#Public helper to unlock recipe--can be used in shops, from drops, level up, quests, etc
func unlock_recipe(recipe_id: String) -> void:
	if is_unlocked(recipe_id):
		return;
	_add_unlock(recipe_id);
	recipe_unlocked.emit(recipe_id);
	Analytics.log_event("recipe_unlocked", {
		"recipe_id": recipe_id,
	})

#Check if the recipe is already unlocked
func is_unlocked(recipe_id: String) -> bool:
	return _unlocked_recipe_ids.has(recipe_id);
	
#Add the unlocked recipe to the unlocked recipes list
func _add_unlock(recipe_id: String) -> void:
	if not _unlocked_recipe_ids.has(recipe_id):
		_unlocked_recipe_ids.append(recipe_id);
		
#Check all the unlocks for the specific type of recipe
func get_unlocked_recipes_of_type(type: RecipeDataResource.RecipeType) -> Array[RecipeDataResource]:
	var result: Array[RecipeDataResource] = [];
	for recipe in RecipeDatabase.get_recipes_of_type(type):
		if is_unlocked(recipe.recipe_id):
			result.append(recipe);
	return result;
#endregion
#region Crafting functions
#Public function to check if the recipe can be crafted or not
func can_craft(recipe_id: String) -> bool:
	var recipe: RecipeDataResource = RecipeDatabase.get_recipe(recipe_id);
	if recipe == null:
		return false;
	if not is_unlocked(recipe_id):
		return false;
	for ingredient in recipe.ingredients:
		if ingredient.item == null:
			return false;
		#Check combined inventory with from chest and player inventory
		if not ChestStorageSystem.has_combined(ingredient.item.item_id, ingredient.amount):
			return false;
	#Block if result would need a new inventory slot but the inventory is full
	#Furniture is handled by DecorationSystem, so that's fine
	#Existing items stack without needing a free slot
	if recipe.result_item.type != ItemDataResource.ItemType.FURNITURE:
		if not InventorySystem.has_item(recipe.result_item.item_id):
			if not InventorySystem.has_free_slot():
				return false;
	#Safety checks passed
	return true;
	
#Public function for actual crafting
func craft(recipe_id: String) -> bool:
	if not can_craft(recipe_id):
		return false;
	if DayNightSystem.is_night():
		return false;
		
	var recipe: RecipeDataResource = RecipeDatabase.get_recipe(recipe_id);
	
	#Remove all ingredients from inventory
	for ingredient in recipe.ingredients:
		ChestStorageSystem.try_remove_combined(ingredient.item.item_id, ingredient.amount);
	
	#Add the result to the inventory
	var result_id: String = recipe.result_item.item_id;
	
	#Fire the signal--captured by QuestSystem, InventorySystem, and DecorationSystem
	item_crafted.emit({"item_id": result_id, "amount": recipe.result_amount});
	
	#Pass the time
	DayNightSystem.advance_time(recipe.time_cost_ticks);
	
	#XP awarded on first craft of the result item
	if not _crafted_item_ids.has(result_id):
		_crafted_item_ids.append(result_id);
		LevelSystem.add_xp(recipe.xp_reward);
		Analytics.log_event("craft_first_time_xp", {
			"result_item_id": result_id,
			"xp_granted": recipe.xp_reward,
		})
	
	#Log the Analytics for crafting
	Analytics.log_event("item_crafted", {
		"recipe_id": recipe_id,
		"result_item_id": result_id,
		"result_amount": recipe.result_amount,
	});
	#Decrement pin count (auto-unpins at 0)
	_decrement_pin(recipe_id);
	return true;
#endregion
#region Consumable 
func use_item(item_id: String) -> bool:
	var item: ItemDataResource = ItemDatabase.get_item(item_id);
	if item == null:
		return false;
	if item.type != ItemDataResource.ItemType.CONSUMABLE:
		return false;
	if not InventorySystem.has_item(item_id):
		return false;
		
	#Safety checks passed	
	InventorySystem.try_remove_item(item_id, 1);
	item_used.emit(item_id);
	
	Analytics.log_event("item_used", {
		"item_id": item_id,
		"effect_value": item.consume_effect_value,
	})
	return true;
#endregion
#region Pinning helpers
func pin_recipe(recipe_id: String, count: int = 1) -> void:
	if is_pinned(recipe_id):
		return;
	_pinned_recipes[recipe_id] = clampi(count, 1, 99);
	recipe_pinned.emit(recipe_id);
	Analytics.log_event("recipe_pinned", {
		"recipe_id": recipe_id,
		"count": _pinned_recipes[recipe_id],
	})
	
func unpin_recipe(recipe_id: String) -> void:
	if not is_pinned(recipe_id):
		return;
	_pinned_recipes.erase(recipe_id);
	recipe_unpinned.emit(recipe_id);
	Analytics.log_event("recipe_unpinned", {
		"recipe_id": recipe_id
	})
	
#Return if a recipe is pinned already or not
func is_pinned(recipe_id: String) -> bool:
	return _pinned_recipes.has(recipe_id);
	
func get_pin_count(recipe_id: String) -> int:
	return _pinned_recipes.get(recipe_id, 0);
	
#Returns a list of the currently pinned recipes
func get_pinned_recipe_ids() -> Array[String]:
	var result: Array[String] = [];
	for key in _pinned_recipes.keys():
		result.append(str(key));
	return result;
	
#Called by craft() to decrement pin count after a successful craft
func _decrement_pin(recipe_id: String) -> void:
	if not is_pinned(recipe_id):
		return;
	var new_count: int = _pinned_recipes[recipe_id] - 1;
	if new_count <= 0:
		unpin_recipe(recipe_id);
	else:
		_pinned_recipes[recipe_id] = new_count;
		recipe_pin_count_changed.emit(recipe_id);
#endregion
#region Level-up unlock hook
func _on_level_up(new_level: int) -> void:
	for recipe in RecipeDatabase.get_all_recipes():
		if recipe.unlock_source == RecipeDataResource.UnlockSource.LEVEL_UP:
			#If the recipe isn't already unlocked, unlock it.
			if not is_unlocked(recipe.recipe_id) and new_level >= recipe.required_level:
				unlock_recipe(recipe.recipe_id);
#endregion
#region Save/load stuffs
func to_dict() -> Dictionary:
	return {
		"unlocked_recipe_ids": _unlocked_recipe_ids.duplicate(),
		"crafted_recipe_ids": _crafted_item_ids.duplicate(),
		"pinned_recipes": _pinned_recipes.duplicate(),
	}
	
func from_dict(data: Dictionary) -> void:
	var unlocked: Array = data.get("unlocked_recipe_ids", []);
	var crafted: Array = data.get("crafted_recipe_ids", []);
	_unlocked_recipe_ids = [];
	_crafted_item_ids = [];
	_pinned_recipes = {};
	for id in unlocked:
		_unlocked_recipe_ids.append(str(id));
	for crafted_item in crafted:
		_crafted_item_ids.append(str(crafted_item));
	#Restore pinned recipes
	var pinned_data: Dictionary = data.get("pinned_recipes", {});
	for key in pinned_data.keys():
		_pinned_recipes[str(key)] = int(pinned_data[key]);
	#Reunlock any default recipes in case new ones were added since the last save
	_unlock_defaults();
	
func reset() -> void:
	_unlocked_recipe_ids = [];
	_crafted_item_ids = [];
	_pinned_recipes = {};
	_unlock_defaults();
#endregion
