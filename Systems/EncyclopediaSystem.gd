extends Node
#Tracks all player discoveries for the Encyclopedia tab
#Each category has its own dictionary keyed by ID
#Dialogue is grouped by npc_id for the per-NPC log view

#region Variable declarations
#Signals
signal harvestable_discovered(harvest_id: String);
signal enemy_discovered(enemy_id: String);
signal item_discovered(item_id: String);
signal recipe_discovered(recipe_id: String);
signal dialogue_line_logged(npc_id: String);

#Internal data
#Count of total breaks {harvest_id: int}
var _harvests: Dictionary = {}; 
#Count of total kills {enemy_id: int}
var _kills: Dictionary = {};
#Tracks first pickups {item_id: true}
var _items: Dictionary = {};
#Tracks unlocked recipes {recipe_id: true}
var _recipes: Dictionary = {};
#Tracks dialogue lines by npc
#{npc_id: Array[{dialogue_id, line_index, speaker, text}]}
var _dialogue: Dictionary = {};
#endregion

func _ready() -> void:
	#Item discovery--InventorySystem already tracks first-time acquisitions
	InventorySystem.first_time_item_acquired.connect(_on_item_acquired);
	#Recipe discovery--CraftingSystem emits recipe_unlocked for non-default recipes
	CraftingSystem.recipe_unlocked.connect(_on_recipe_unlocked);
	#Dialogue--DialogueSystem emits dialogue_line_shown
	DialogueSystem.dialogue_line_shown.connect(_on_dialogue_line_shown);
	
#region Public helpers
#Called from HarvestableNode._on_broken() 
func record_harvest(harvest_id: String) -> void:
	if harvest_id.is_empty():
		return;
	#Harvest id exists, check if already in dictionary
	var is_new: bool = not _harvests.has(harvest_id);
	#Add 1 to number of harvestables broken
	_harvests[harvest_id] = _harvests.get(harvest_id, 0) + 1;
	if is_new:
		#Add to the dictionary and emit signal if new
		harvestable_discovered.emit(harvest_id);
		
#Called from EnemySystems._die()
func record_kill(enemy_id: String) -> void:
	if enemy_id.is_empty():
		return;
	#There is an enemy, check if it's new
	var is_new: bool = not _kills.has(enemy_id);
	#Add 1 to number killed
	_kills[enemy_id] = _kills.get(enemy_id, 0) + 1;
	if is_new:
		enemy_discovered.emit(enemy_id);
		
#Query functions
func has_harvested(harvest_id: String) -> bool:
	return _harvests.has(harvest_id);
	
func get_harvest_count(harvest_id: String) -> int:
	return int(_harvests.get(harvest_id, 0));
	
func has_killed(enemy_id: String) -> bool:
	return _kills.has(enemy_id);
	
func get_kill_count(enemy_id: String) -> int:
	return int(_kills.get(enemy_id, 0));
	
func has_found_item(item_id: String) -> bool:
	return _items.has(item_id);
	
func has_unlocked_recipe(recipe_id: String) -> bool:
	return _recipes.has(recipe_id);
	
#Returns a copy of the dialogue log for a given npc_id
#Each entry is: {dialogue_id, line_index, speaker, text}
func get_dialogue_log(npc_id: String) -> Array:
	return _dialogue.get(npc_id, []).duplicate();
	
#Return all npc_ids that have at least one logged line
func get_npc_ids_with_dialogue() -> Array[String]:
	var result: Array[String] = [];
	for key in _dialogue.keys():
		result.append(str(key));
	return result;
	
#Save/load stuffs
func to_dict() -> Dictionary:
	#Serialise _dialogue: values are Array[Dictionary], safe to duplicate
	var dialogue_serialised: Dictionary = {};
	for npc_id in _dialogue.keys():
		dialogue_serialised[npc_id] = _dialogue[npc_id].duplicate(true);
	
	return {
		"harvests": _harvests.duplicate(),
		"kills": _kills.duplicate(),
		"items": _items.duplicate(),
		"recipes": _recipes.duplicate(),
		"dialogue": dialogue_serialised
	};
	
func from_dict(data: Dictionary) -> void:
	var harvests = data.get("harvests", {});
	_harvests = harvests.duplicate() if harvests is Dictionary else {};
	
	var items = data.get("items", {});
	_items = items.duplicate() if items is Dictionary else {};
	
	var kills = data.get("kills", {});
	_kills = kills.duplicate() if kills is Dictionary else {};
	
	var recipes = data.get("recipes", {});
	_recipes = recipes.duplicate() if recipes is Dictionary else {};
	
	var dialogue = data.get("dialogue", {});
	_dialogue = {};
	if dialogue is Dictionary:
		for npc_id in dialogue.keys():
			var lines = dialogue[npc_id];
			if lines is Array:
				_dialogue[npc_id] = lines.duplicate(true);
				
	#Resync defaults in case new recipes were added since last save
	_sync_default_recipes();
	
#Called by Game.start_new_game() alongside other system resets
func reset() -> void:
	_harvests.clear();
	_kills.clear();
	_items.clear();
	_recipes.clear();
	_dialogue.clear();
	#Seed defaults for fresh save
	_sync_default_recipes();
#endregion
#region Signal handlers
func _on_item_acquired(item_id: String, _amount: int) -> void:
	if item_id.is_empty() or _items.has(item_id):
		return;
	#Safety checks passed
	_items[item_id] = true;
	item_discovered.emit(item_id);
	
func _on_recipe_unlocked(recipe_id: String) -> void:
	if recipe_id.is_empty() or _recipes.has(recipe_id):
		return;
	_recipes[recipe_id] = true;
	recipe_discovered.emit(recipe_id);
	
#Receives: {dialogue_id, line_index, npc_id, speaker, text}
func _on_dialogue_line_shown(data: Dictionary) -> void:
	var npc_id: String = str(data.get("npc_id", ""));
	var speaker: String = str(data.get("speaker", ""));
	var text: String = str(data.get("text", ""));
	var dialogue_id: String = str(data.get("dialogue_id", ""));
	var line_index: int = int(data.get("line_index", 0));
	
	#Skip lines with no real content (empty text or unknown npc)
	if npc_id.is_empty() or text.is_empty():
		return;
		
	if not _dialogue.has(npc_id):
		_dialogue[npc_id] = [];
		
	#Avoid duplicate entires if the same line is emitted more than once
	for entry in _dialogue[npc_id]:
		if entry.get("dialogue_id") == dialogue_id and entry.get("line_index") == line_index:
			return;
	
	#Safety checks passed
	_dialogue[npc_id].append({
		"dialogue_id": dialogue_id,
		"line_index": line_index,
		"speaker": speaker,
		"text": text
	});
	#Emit signal
	dialogue_line_logged.emit(npc_id);
	
#Sends all currently unlocked by default recipes into _recipes
#Called after load and after new game
func _sync_default_recipes() -> void:
	for recipe_id in CraftingSystem._unlocked_recipe_ids:
		if not _recipes.has(recipe_id):
			_recipes[recipe_id] = true;
#endregion
