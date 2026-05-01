extends Node
#Tracks quests and their states. Thin logic, data will live in QuestDatabase (JSON-backed)

#Signals let the UI and other systems react when quests change
#without QuestSystem needing to know about them directly
signal quest_added(quest_id: String);
signal quest_updated(quest_id: String);
signal quest_completed(quest_id: String);
signal quests_loaded;
#Simple string constants to represent quest states
const STATE_NOT_STARTED: String = "not_started";
const STATE_ACTIVE: String = "active";
const STATE_COMPLETED: String = "completed";

#Internal dictionary for quest references
var _quests: Dictionary = {}; #quest_id -> {"state": String, "step_index": int, }

func _ready() -> void:
	#Connect signals 
	InventorySystem.item_count_changed.connect(_on_item_count_changed);
	ChestStorageSystem.chest_contents_changed.connect(_on_chest_contents_changed);
	DecorationSystem.furniture_placed.connect(_on_furniture_placed);

#region Pubic helpers
func reset_quests() -> void:
	#Variable for analytics log
	var cleared_count = _quests.size();
	#Clears all quest data. Used when starting a new game
	_quests.clear();
	#Also mirror this info into GameState so saving/loading stays in sync
	_sync_to_gamestate();
	
	#Analytics
	if cleared_count > 0:
		Analytics.log_event("quests_reset", {
			"cleared_count": cleared_count
		});
	
func has_quest(quest_id: String) -> bool:
	#Returns true if the quest_id exists in our dictionary
	return _quests.has(quest_id);
	
func get_quest_state(quest_id: String) -> String:
	#Safely get the state string for a quest
	if not _quests.has(quest_id):
		return STATE_NOT_STARTED;
	return _quests[quest_id].get("state", STATE_NOT_STARTED);
	
func get_step_index(quest_id: String) -> int:
	#Safely get the current step index for a quest
	if not _quests.has(quest_id):
		return 0;
	return int(_quests[quest_id].get("step_index", 0));
	
func accept_quest(quest_id: String) -> void:
	#Begin or reactivate a quest
	#If the quest is already completed, we don't re-accept it
	if get_quest_state(quest_id) == STATE_COMPLETED:
		return;
		
	#Analytics variable
	var previous_state = get_quest_state(quest_id);
	#Create/update the quest entry
	_quests[quest_id] = {
		"state": STATE_ACTIVE,
		"step_index": 0,
	};
	#Mirror the data into GameState
	_sync_to_gamestate();
	#Notify the listeners that a quest was added and updated
	#UI or HUD can use these to show notifications
	quest_added.emit(quest_id);
	quest_updated.emit(quest_id);
	
	#Analytics
	Analytics.log_event("quest_accepted", {
		"quest_id": quest_id,
		"previous_state": previous_state,
		"step_index": get_step_index(quest_id)
	})
	_check_inventory_for_active_quest(quest_id);
	
func complete_quest(quest_id: String) -> void:
	#Mark a quest as completed if it exists
	if not _quests.has(quest_id):
		return;
	if _quests[quest_id].get("state") == STATE_COMPLETED:
		return;
	_quests[quest_id]["state"] = STATE_COMPLETED;
	_sync_to_gamestate();
	#Emit both a specific completed signal and a general updated signal
	quest_completed.emit(quest_id);
	quest_updated.emit(quest_id);
		
	#Analytics
	Analytics.log_event("quest_completed", {
		"quest_id": quest_id,
		"final_step_index": int(_quests[quest_id].get("step_index", 0))
	});
	
func advance_step(quest_id: String) -> void:
	#Move a quest to the next step
	if not _quests.has(quest_id):
		return;
	var data: Dictionary = _quests[quest_id];
	var previous_index: int = int(data.get("step_index", 0));
	var new_index: int = previous_index + 1;
	data["step_index"] = int(data.get("step_index", 0)) + 1;
	
	_quests[quest_id] = data;
	_sync_to_gamestate();
	quest_updated.emit(quest_id);
	#After advancing, check if the new step is already satisfied
	_check_inventory_for_active_quest(quest_id);
	#Analytics quest advanced from one step to the next
	#Useful for determining how long each step took
	Analytics.log_event("quest_step_advanced", {
		"quest_id": quest_id,
		"from_step_index": previous_index,
		"to_step_index": new_index
	})

func notify_event(event_type: String, payload: Dictionary = {}) -> void:
	#Called by gameplay systems (talking to NPCs, picking items, entering regions).
	#We ask QuestDatabase which quest steps match this event.
	var matches: Array = QuestDatabase.find_matching_steps(event_type, payload)
	for m in matches:
		var quest_id := String(m.get("quest_id", ""))
		if quest_id.is_empty():
			continue;
		var step_index := int(m.get("step_index", -1))
		if step_index < 0:
			continue;
			
		#Auto-accept if the quest hasn't started yet
		if get_quest_state(quest_id) == STATE_NOT_STARTED and step_index == 0:
			if not are_prereqs_met(quest_id):
				#Prereqs are not met, ignore this match
				continue;
			accept_quest(quest_id);
			
		if get_quest_state(quest_id) != STATE_ACTIVE:
			continue;
			
		#Only advance if we're currently on the matching step
		if get_step_index(quest_id) != step_index:
			continue;
		
		#Get the step information
		var step_data: Dictionary = QuestDatabase.get_step_data(quest_id, step_index);
		#For deliver_items, verify the player has enough before advancing
		if event_type == "deliver_items":
			var can_deliver: bool = true;
			for cond in step_data.get("conditions", []):
				if typeof(cond) != TYPE_DICTIONARY:
					continue;
				if String(cond.get("key", "")) != "item_id":
					continue;
				if not ChestStorageSystem.has_combined(String(cond.get("value", "")), int(cond.get("amount", 1))):
					can_deliver = false;
					break;
			if not can_deliver:
				continue;
				
		#For item_pickup, verfiy the player now holds the required amount
		if event_type == "item_pickup":
			var has_enough: bool = true;
			for cond in step_data.get("conditions", []):
				if typeof(cond) != TYPE_DICTIONARY:
					continue;
				if String(cond.get("key", "")) != "item_id":
					continue;
				if not ChestStorageSystem.has_combined(String(cond.get("value", "")), int(cond.get("amount", 1))):
					has_enough = false;
					break;
			if not has_enough:
				continue;
				
		advance_step(quest_id);
		
		#Auto-complete if we advanced past the last step
		var current_index: int = get_step_index(quest_id);
		var total_steps = QuestDatabase.get_step_count(quest_id);
		if total_steps > 0 and current_index >= total_steps:
			complete_quest(quest_id);
		
		#Consume items if this is a deliver_items step
		#Specifically AFTER advancing to avoid inventory_changed re-triggering quest steps
		if event_type == "deliver_items":
			var conditions: Array = step_data.get("conditions", []);
			for cond in conditions:
				if typeof(cond) != TYPE_DICTIONARY:
					continue;
				if String(cond.get("key", "")) != "item_id":
					continue;
				var consume: int = int(cond.get("consume_amount", 0));
				if consume > 0:
					var item_id: String = String(cond.get("value", ""));
					var removed: bool = ChestStorageSystem.try_remove_combined(item_id, consume);
					if removed:
						var hud = UIRouter.get_hud();
						if hud:
							var item_name: String = ItemDatabase.get_display_name(item_id);
							hud.show_message("-%d %s" % [consume, item_name], 2.0);
				
func get_active_quests() -> Array:
	#Returns an array of quest_ids currently in the ACTIVE state
	var list: Array = [];
	for quest_id in _quests.keys():
		if _quests[quest_id].get("state") == STATE_ACTIVE:
			list.append(quest_id);
	return list;

#Get which quests have been completed for prereqs
func get_completed_quests() -> Array:
	#Returns an array of quest_ids currently in the completed stated
	var list: Array = [];
	for quest_id in _quests.keys():
		if _quests[quest_id].get("state") == STATE_COMPLETED:
			list.append(quest_id);
	return list;
	
#Helper to check if prereqs have been met
func are_prereqs_met(quest_id: String) -> bool:
	#No prereqs defined -> always allowed
	if not QuestDatabase.has_quest(quest_id):
		return true;
	#Prereqs defined, check if they've been met
	var quest_data: Dictionary = QuestDatabase.get_quest(quest_id);
	var prereqs: Array = quest_data.get("prereq_ids", []);
	for prereq_id in prereqs:
		if not is_quest_completed(String(prereq_id)):
			return false;
	return true;
	
func is_quest_completed(quest_id: String) -> bool:
	return get_quest_state(quest_id) == STATE_COMPLETED;
	
#Returns true if talking to this NPC would start or advance a quest
func npc_has_quest_action(npc_id: String) -> bool:
	#Case 1 and 2--a talk_to_npc step would auto-start or advance a quest
	var payload: Dictionary = {"npc_id": npc_id};
	var matches = QuestDatabase.find_matching_steps("talk_to_npc", payload);
	for m in matches:
		var quest_id: String = String(m.get("quest_id", ""));
		var step_index: int = int(m.get("step_index", -1));
		if quest_id.is_empty() or step_index < 0:
			continue;
		var state = get_quest_state(quest_id);
		#Would auto-start a new quest
		if state == STATE_NOT_STARTED and step_index == 0 and are_prereqs_met(quest_id):
			return true;
		#Would advance the current step of an active quest
		if state == STATE_ACTIVE and get_step_index(quest_id) == step_index:
			return true;
	
	#Case 3: Npc has a delivery dialogue and the player has the items
	var best_dialogue = DialogueData.find_best_dialogue_for_npc(npc_id);
	if not best_dialogue.is_empty() and DialogueData.dialogue_is_delivery(best_dialogue):
		return true;
	return false;
	
#Save and load stuffs
func to_dict() -> Dictionary:
	#Called by SaveSystem to serialize quest data
	return {
		"quests": _quests.duplicate(true), #deep copy
	};

func from_dict(data: Dictionary) -> void:
	#Called by SaveSystem when loading a game
	var loaded = data.get("quests", {});
	_quests = loaded.duplicate(true);
	_sync_to_gamestate();
	quests_loaded.emit();
#endregion
#region Internal helpers
func _on_item_count_changed(item_id: String, amount: int) -> void:
	if item_id.is_empty() or amount < 0:
		return;
	notify_event("item_pickup", {
		"item_id": item_id,
		"amount": amount
	})
	
func _on_furniture_placed(item_id: String, _world_pos: Vector2) -> void:
	if item_id.is_empty():
		return;
	notify_event("place_furniture", {
		"item_id": item_id
	});
	
func _on_chest_contents_changed(item_id: String) -> void:
	if item_id.is_empty():
		return;
	notify_event("item_pickup", {
		"item_id": item_id,
		"amount": ChestStorageSystem.get_combined_amount(item_id),
	})
func _sync_to_gamestate():
	#Keep GameState in sync for save/load and debugging
	GameState.quest_states = _quests.duplicate(true);
	
func _check_inventory_for_active_quest(quest_id: String) -> void:
	#If the newly accepted quest's first step is item_pickup, fire a synthetic notify in case the player already has enough
	var step_index: int = get_step_index(quest_id);
	var step_data: Dictionary = QuestDatabase.get_step_data(quest_id, step_index);
	if step_data.get("event_type", "") != "item_pickup":
		return;
	var conditions: Array = step_data.get("conditions", []);
	for cond in conditions:
		if typeof(cond) != TYPE_DICTIONARY:
			continue;
		if String(cond.get("key", "")) != "item_id":
			continue;
		var item_id: String = String(cond.get("value", ""));
		var total: int = ChestStorageSystem.get_combined_amount(item_id);
		notify_event("item_pickup", {
			"item_id": item_id,
			"amount": total,
		});
		return; #One notify covers the step
#endregion
