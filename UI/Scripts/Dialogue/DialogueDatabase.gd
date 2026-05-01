extends Node
#Gets the data from the preload registry like items
#dialogue_id -> full dialogue dict
var _dialogues: Dictionary = {};
#Build index by NPC as well
var _dialogues_by_npc: Dictionary = {}; #npc_id -> Array[String]

func _ready() -> void:
	for resource in DialoguePreloadRegistry.ALL:
		if resource is DialogueResource:
			_register_dialogue(resource);
		else:
			push_warning("DialogueDatabase: Non-DialogueResource entry in registry: %s" % resource.resource_path);
		
#region Public helpers
func has_dialogue(dialogue_id: String) -> bool:
	return _dialogues.has(dialogue_id);

func get_dialogue(dialogue_id: String) -> Dictionary:
	if not _dialogues.has(dialogue_id):
		push_warning("DialogueData: Unknown dialogue_id '%s'" % dialogue_id);
		return {};
	return _dialogues[dialogue_id].duplicate(true);

func get_all_ids() -> Array:
	return _dialogues.keys();
	
#Resolves a choices go_to_line name to a line index at runtime
func resolve_go_to_index(dialogue_id: String, go_to_line: String) -> int:
	if not _dialogues.has(dialogue_id):
		return -1;
	var name_map: Dictionary = _dialogues[dialogue_id].get("name_to_index", {});
	return int(name_map.get(go_to_line, -1));
	
#Public helper to pick the 'best dialogue' option based on Quests
func find_best_dialogue_for_npc(npc_id: String) -> String:
	if npc_id.is_empty():
		return "";
	
	var candidate_ids: Array = [];
	#Look through all the separate npc dialogue first
	if _dialogues_by_npc.has(npc_id):
		candidate_ids = _dialogues_by_npc[npc_id];
	#If nothing found, then just look through the whole possible dialogue list
	else:
		for id in _dialogues.keys():
			if String(_dialogues[id].get("npc_id", "")) == npc_id:
				candidate_ids.append(id);
	
	var best_id: String = "";
	var best_score: int = -999;
	
	#Loop through all the possible dialogue options for the npc
	for id in candidate_ids:
		var d: Dictionary = _dialogues[id];
		if not _dialogue_matches_quest_state(d):
			continue;
		#Get the score and pick the best dialogue option to display
		var score: int = _score_dialogue_candidate(d);
		if score > best_score:
			best_score = score;
			best_id = id;
	
	return best_id;
	
#Direct lookup for completion dialogue--bypasses scoring entirely
#Used by NPC auto-trigger after quest completion
func find_completion_dialogue_for_npc(npc_id: String, quest_id: String) -> String:
	if npc_id.is_empty() or quest_id.is_empty():
		return "";
	var candidate_ids: Array = _dialogues_by_npc.get(npc_id, []);
	for id in candidate_ids:
		var d: Dictionary = _dialogues[id];
		if String(d.get("for_quest_id", "")) == quest_id and String(d.get("quest_state", "any")) == "completed":
			return id;
	return "";
	
#Returns true if the given dialogue is on a deliver_items quest step
func dialogue_is_delivery(dialogue_id: String) -> bool:
	if not _dialogues.has(dialogue_id):
		return false;
	var d: Dictionary = _dialogues[dialogue_id];
	var quest_id: String = String(d.get("for_quest_id", ""));
	if quest_id.is_empty():
		return false;
	var min_step: int = int(d.get("min_step_index", -1));
	if min_step < 0:
		return false;
	var step_data: Dictionary = QuestDatabase.get_step_data(quest_id, min_step);
	return step_data.get("event_type", "") == "deliver_items";
	
#Returns true if the dialogue is for a deliver_items quest step but the player doesn't have enough
func dialogue_player_lacks_items(dialogue_id: String) -> bool:
	if not _dialogues.has(dialogue_id):
		return false;
	var d: Dictionary = _dialogues[dialogue_id];
	var quest_id: String = String(d.get("for_quest_id", ""));
	if quest_id.is_empty():
		return false;
		
	#Find the matching quest step for this dialogue's step index
	var min_step: int = int(d.get("min_step_index", -1));
	if min_step < 0:
		return false;
		
	var step_data: Dictionary = QuestDatabase.get_step_data(quest_id, min_step);
	if step_data.get("event_type", "") != "deliver_items":
		return false;
	
	#Check each item condition
	var conditions: Array = step_data.get("conditions", []);
	for cond in conditions:
		if typeof(cond) != TYPE_DICTIONARY:
			continue;
		if String(cond.get("key", "")) != "item_id":
			continue;
		var item_id: String = String(cond.get("value", ""));
		var required: int = int(cond.get("amount", 1));
		#Player has the items
		if not ChestStorageSystem.has_combined(item_id, required):
			return true;
	#Otherwise, player does not have the required amount
	return false;
	
#Returns the fallback dialogue for an NPC, ignoring deliver_items gating
#Used when player talks to an NPC but lacks the required delivery items
func find_fallback_dialogue_for_npc(npc_id: String) -> String:
	if npc_id.is_empty():
		return "";
	var candidate_ids: Array = _dialogues_by_npc.get(npc_id, []);
	for id in candidate_ids:
		var d: Dictionary = _dialogues[id];
		if bool(d.get("is_fallback", false)) and _dialogue_matches_quest_state(d):
			return id;
	return "";
#endregion
#region Internal helpers
#Helper to check for quest state
func _dialogue_matches_quest_state(d: Dictionary) -> bool:
	var quest_id: String = String(d.get("for_quest_id", ""));
	var quest_state: String = String(d.get("quest_state", "any"));
	var min_step: int = int(d.get("min_step_index", -1));
	var max_step: int = int(d.get("max_step_index", -1));
	
	if quest_id.is_empty():
		#Generic dialogue, always allowed
		return true;
		
	var current_state: String = QuestSystem.get_quest_state(quest_id);
	
	#Completion dialogues are handled separately
	#Keep them out of general scoring so they don't block fallbacks
	if quest_state == "completed":
		return false;
		
	#If the quest state the player is in has paramaters and those don't match the current state
	if quest_state != "any" and current_state != quest_state:
		return false;
	
	#Ensure dialogue doesn't play for quests that can't start yet due to prereqs
	if current_state == "not_started" and not QuestSystem.are_prereqs_met(quest_id):
		return false;
	
	#Get the proper step
	var step: int = QuestSystem.get_step_index(quest_id);
	if min_step >= 0 and step < min_step:
		return false;
	if max_step >= 0 and step > max_step:
		return false;
	
	return true;
	
func _register_dialogue(res: DialogueResource) -> void:
	if res.dialogue_id.is_empty():
		push_error("DialogueDatabase: DialogueResource has empty dialogue_id, skipping %s" % res.resource_path);
		return;
		
	#Build a name->index loop so choices can branch by line_name
	var name_to_index: Dictionary = {};
	
	for i in range(res.lines.size()):
		var line: DialogueLineResource = res.lines[i];
		if line == null:
			continue;
		
		#Allows me to leave line names empty except for those that have choices
		var resolved_name: String = line.line_name if not line.line_name.is_empty() else "line_%d" % i;
		if name_to_index.has(resolved_name):
			push_warning("DialogueDatabase: Duplicate line_name '%s' in dialogue '%s' (index %d) — first occurrence wins." 
				% [resolved_name, res.dialogue_id, i]);
		else:
			name_to_index[resolved_name] = i;
		
	#Convert each DialogueLineResource into the dict shape DialogueSystem expects
	var converted_lines: Array = [];
	for line_index in range(res.lines.size()):
		var _line: DialogueLineResource = res.lines[line_index];
		if _line == null:
			converted_lines.append({});
			continue;
		
		#Speaker key, auto-generated
		var speaker_key: String = _line.get_speaker_key();
		#text key-manual override or auto-generated
		var text_key: String = _line.get_resolved_text_key(res.dialogue_id, line_index);
		
		#Choices--convert go_to_line name->index id
		var choices: Array = [];
		
		for choice in _line.choices:
			if choice == null:
				continue;
			if choice.text_key.is_empty():
				push_warning("DialogueDatabase: Choice in line %s of %s has no text_key--skipping."
					% [_line.line_name, res.dialogue_id]);
				continue;
			if choice.go_to_line.is_empty():
				push_warning("DialogueDatabase: Choice in line %s of %s has no go_to_line--skipping."
					%[_line.line_name, res.dialogue_id]);
				continue;
			if not name_to_index.has(choice.go_to_line):
				push_warning("DialogueDatabase: Choice go_to_line %s not found in dialogue %s--skipping choice."
					% [choice.go_to_line, res.dialogue_id]);
				continue;
			
			choices.append({
				"id": choice.go_to_line,
				"text_key": choice.text_key,
				"go_to_index": name_to_index[choice.go_to_line],
			});
			
		#Actions--give_item as part of dialogue
		var actions: Array = [];
		if _line.give_item != null:
			var item_id: String = _line.give_item.item_id;
			if item_id.is_empty():
				push_warning("DialogueDatabase: give_item on line %s in %s has an empty item_id--skipping,"
					% [_line.line_name, res.dialogue_id]);
			else:
				var amount: int = max(1, _line.give_amount);
				actions.append({
					"type": "give_item",
					"item_id": item_id,
					"amount": amount,
				})
		if _line.deliver_item_id != null and _line.deliver_quest_id != null:
			actions.append({
				"type": "deliver_items",
				"quest_id": _line.deliver_quest_id.quest_id,
				"item_id": _line.deliver_item_id.item_id,
			});
			
		var line_dict: Dictionary = {
			"speaker_key": speaker_key,
			"text_key": text_key,
			"choices": choices,
		}
		
		#If there are options, add them to the line dictionary
		if actions.size() > 0:
			line_dict["actions"] = actions;
		#Append the converted lines with the info
		converted_lines.append(line_dict);
			
		_dialogues[res.dialogue_id] = {
			"id": res.dialogue_id,
			"npc_id": res.get_npc_id_string(),
			"for_quest_id": res.for_quest_id,
			"quest_state": res.get_quest_state_string(),
			"min_step_index": res.min_step_index,
			"max_step_index": res.max_step_index,
			"is_fallback": res.is_fallback,
			"lines": converted_lines,
			"name_to_index": name_to_index, #Kept for runtime jump resolution
		}
		#Index by npc_id for find_best_dialogue_for_npc
		var npc_id_string: String = res.get_npc_id_string();
		if not npc_id_string.is_empty():
			if not _dialogues_by_npc.has(npc_id_string):
				_dialogues_by_npc[npc_id_string] = [];
			_dialogues_by_npc[npc_id_string].append(res.dialogue_id);
			
#Helper function to actually score dialogue and determine which one should show
func _score_dialogue_candidate(d: Dictionary) -> int:
	var score: int = 0;
	
	var quest_id: String = String(d.get("for_quest_id", ""));
	var quest_state: String = String(d.get("quest_state", "any"));
	var min_step: int = int(d.get("min_step_index", -1));
	var max_step: int = int(d.get("max_step_index", -1));
	var is_fallback: bool = bool(d.get("is_fallback", false));
	
	if not quest_id.is_empty():
		score += 10;
	if quest_state != "any":
		score += 5;
	if min_step >= 0 or max_step >= 0:
		score += 3;
	if is_fallback:
		score -= 20; #Fallback dialogue only if nothing else matches
	return score; 
	
func _append_action_if_valid(actions: Array, action_type: String, item_id: String, amount_raw: Variant) -> void:
	action_type = action_type.strip_edges();
	item_id = item_id.strip_edges();
	
	if action_type.is_empty():
		return;
		
	#Support give_item--add more stuff later
	if action_type != "give_item":
		push_warning("DialogueData: Unknown action_type '%s' (skipping action)" % action_type);
		return;
		
	if item_id.is_empty():
		push_warning("DialogueData: give_item action missing item_id (skipping action.)")
		return;
		
	var amount: int = int(amount_raw);
	if amount < 1:
		amount = 1;
	
	actions.append({
		"type": action_type,
		"item_id": item_id,
		"amount": amount,
	});
#endregion
