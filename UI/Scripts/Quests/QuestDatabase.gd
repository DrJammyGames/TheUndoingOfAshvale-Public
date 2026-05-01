extends Node
#Loads all QuestDataResources from the preload registry

#Empty dictionary to fill with quest info
var _quests: Dictionary = {}; #quest_id (String) -> QuestData;


func _ready() -> void:
	_load_quests_from_registry();
	
#region Public helpers
#Check if quest exists in the quest array
func has_quest(quest_id: String) -> bool:
	return _quests.has(quest_id);

#Gets the quest based on the quest id
func get_quest(quest_id: String) -> Dictionary:
	if not _quests.has(quest_id):
		push_warning("QuestDatabase: Unknown quest_id '%s'" % quest_id);
		return _make_fallback_quest(quest_id);
	#Safety check passed, get return the quest
	return _quests[quest_id].duplicate(true);

#Get the correct name for the quest in the designated language
func get_display_name(quest_id: String) -> String:
	#Safety checks
	if not _quests.has(quest_id):
		#Return fallback--just the ID, but capitalised
		return quest_id.capitalize();
	#Get the proper name in the designated language
	var key: String = _quests[quest_id].get("display_name_key", quest_id);
	return tr(key);
	
#Gets the description of the quest to display in designated language 
func get_description(quest_id: String) -> String:
	if not _quests.has(quest_id):
		return "";
	var key: String = _quests[quest_id].get("description_key","");
	#If the description is blank, return blank, otherwise, get the designated language 
	return "" if key.is_empty() else tr(key);

#Gets which step of the quest the player is on
func get_step_count(quest_id: String) -> int:
	if not _quests.has(quest_id):
		return 0;
	var steps: Array = _quests[quest_id].get("steps", []);
	#Return how many steps it has
	return steps.size();

#Gets the text for which step the quest is at
func get_step_text(quest_id: String, step_index: int) -> String:
	#Safety check
	if not _quests.has(quest_id):
		return "";
	#Get the steps
	var steps: Array = _quests[quest_id].get("steps", []);
	#If the index is negative or larger than it should be, return empty
	if step_index < 0 or step_index >= steps.size():
		return "";
	#Get the current step
	var step: Dictionary = steps[step_index];
	#Get the key in the dictionary that matches the designated language text
	var key: String = step.get("text_key","");
	#If there's nothing, return empty. Else, designated language
	return "" if key.is_empty() else tr(key);
	
func get_xp_reward(quest_id: String) -> int:
	if not _quests.has(quest_id):
		return 0;
	return int(_quests[quest_id].get("xp_reward", 0));
	
#Gets all the info for the current step in the quest
func get_step_data(quest_id: String, step_index: int) -> Dictionary:
	if not _quests.has(quest_id):
		return {};
	var steps: Array = _quests[quest_id].get("steps", []);
	if step_index < 0 or step_index >= steps.size():
		return {};
	return steps[step_index];
	
#Returns all the registered quests
func get_all_quests() -> Array:
	#Returns Array[String] quest ids, sorted by display name (translated)
	var ids: Array = _quests.keys();
	#Later change this to be separated by main, side, etc. 
	ids.sort_custom(func(a,b) -> bool:
		return get_display_name(String(a)) < get_display_name(String(b)))
	return ids;
	
#Find the matching steps in the database
func find_matching_steps(event_type: String, payload: Dictionary) -> Array:
	var matches: Array = [];
	for quest_id in _quests.keys():
		var q: Dictionary = _quests[quest_id];
		var steps: Array = q.get("steps", []);
		for step_index in range(steps.size()):
			var step: Dictionary = steps[step_index];
			if String(step.get("event_type", "")) != event_type:
				continue;
			if not _step_matches_payload(step, payload):
				continue;
			matches.append({
				"quest_id": String(quest_id),
				"step_index": step_index,
			});
	return matches;
#endregion
#region Internal helpers
#Registers all the quests in the Quests resources folder
func _load_quests_from_registry() -> void:
	_quests.clear();
	for res in QuestPreloadRegistry.ALL:
		if not res is QuestDataResource:
			continue;
		_register_quest(res as QuestDataResource);
		
#Actually register the quest
func _register_quest(res: QuestDataResource) -> void:
	if res.quest_id.is_empty():
		push_error("QuestDatabase: QuestDataResource has empty quest_id, skipping %s" % res.resource_path);
		return;
	if _quests.has(res.quest_id):
		push_warning("QuestDatabase: Duplicate quest_id %s, skipping %s" % [res.quest_id, res.resource_path]);
		return;
		
	var data: Dictionary = {};
	data["id"] = res.quest_id;
	data["display_name_key"] = res.get_name_key();
	data["description_key"] = res.get_desc_key();
	data["prereq_ids"] = res.get_prereq_ids();
	data["xp_reward"] = res.xp_reward;
	
	var steps_out: Array = [];
	for i in range(res.steps.size()):
		var step: QuestStepResource = res.steps[i];
		if step == null:
			continue;
		steps_out.append(_normalise_step(step, res.quest_id, i));
	data["steps"] = steps_out;
	_quests[res.quest_id] = data;
	
func _normalise_step(step: QuestStepResource, quest_id: String, index: int) -> Dictionary:
	var out: Dictionary = {};
	out["text_key"] = step.get_resolved_text_key(quest_id, index);
	out["event_type"] = step.get_event_type_string();
	
	#An array in case there is more than one condition
	var conditions: Array = [];
	conditions.append({
		"key": step.get_condition_key_string(),
		"value": step.condition_value,
		"amount": max(1, step.condition_amount),
		"consume_amount": max(0, step.consume_amount)
	});
	
	#Second condition (if it exists)
	if step.has_condition_2():
		conditions.append({
			"key": step.get_condition_2_key_string(),
			"value": step.condition_2_value,
			"amount": max(1, step.condition_2_amount),
			"consume_amount": max(0, step.consume_2_amount),
		})
	
	
	out["conditions"] = conditions;
	return out;

func _step_matches_payload(step: Dictionary, payload: Dictionary) -> bool:
	var conditions: Array = step.get("conditions", []);
	if conditions.is_empty():
		return true;
	var event_type: String = String(step.get("event_type", ""));
	
	for cond in conditions:
		if typeof(cond) != TYPE_DICTIONARY:
			continue;
		#Get the info about the quest steps
		var key: String = String(cond.get("key", ""));
		var expected: String = String(cond.get("value", ""));
		if key.is_empty():
			continue;
			
		#Item quantity is verified later in notify_event
		if event_type == "deliver_items" and key == "item_id":
			if not payload.has(key):
				return false;
			if String(payload[key]) != expected:
				return false;
			continue;
			
		if not payload.has(key):
			return false;
		if String(payload[key]) != expected:
			return false;
	#Safety checks passed, return true
	return true;
	
#No quest exists, make a fallback one so nothing breaks
func _make_fallback_quest(quest_id: String) -> Dictionary:
	return {
		"id": quest_id,
		"display_name_key": quest_id,
		"description_key": "",
		"prereq_ids": [],
		"steps": [],
	}
#endregion
