extends Node
#Handles dialogue state and progression, but not the UI drawing
#Script knows what dialogue is happening, but not how it is displayed on screen
#region Signals
#UI can use this to show the dialogue box
signal dialogue_started(dialogue_id: String);
#UI updates the text
signal line_changed(line_data: Dictionary);
#Each choice is usually a dictionary with id + text
signal choices_presented(choices: Array); #each: {"id": String, "text": String}
#Can be used later for quest hooks, etc
signal dialogue_ended(result_data: Dictionary);
#The dialogue requires an action to happen as well
signal dialogue_action_fired(action: Dictionary, context: Dictionary);
#Signal for encyclopedia
signal dialogue_line_shown(data: Dictionary);
#endregion

#region Variable declaration
#Prevent refiring actions when revisiting same line
var _fired_action_line_indices: Dictionary = {}; #int -> true
#ID of the currently active dialogue
var _current_dialogue_id: String = "";
#Index of the current line within that dialogue
var _current_line_index: int = 0;
#Raw dialogue data loaded from disk
var _current_dialogue_data: Dictionary = {}; #Structure might change depending on how I store dialogue
#Current context
var _current_context: Dictionary = {};
#Flag check for if dialogue is current active
var _is_active: bool = false;
#endregion

#region Public helpers
#Allows other systems to check if dialogue is currently happening
func is_active() -> bool:
	return _is_active;
	
#Called by NPCs or interactables to begin a dialogue
func start_dialogue(dialogue_id: String, context: Dictionary = {}) -> void:
	#Load dialogue from disk or memory
	_current_dialogue_data = _load_dialogue_data(dialogue_id);
	if _current_dialogue_data.is_empty():
		push_warning("Dialogue '%s' not found in database." % dialogue_id);
		return;
	
	#Safety check passed
	_current_dialogue_id = dialogue_id;
	_current_line_index = 0;
	_is_active = true;
	_current_context = context;
	_fired_action_line_indices.clear();
	
	#Notify UI that dialogue has started
	dialogue_started.emit(dialogue_id);
	
	#Analytics
	Analytics.log_event("dialogue_started", {
		"dialogue_id": dialogue_id,
	})
	
	#Immediately emit the first line so UI can display it
	_emit_current_line();
	
#Public reference for next line
func next_line() -> void:
	if not _is_active:
		return;
	_advance_line();
	
#Called by the UI when the player selects a dialogue choice
#Later this will branch dialogue, trigger quest changes, and set flags in gamestate
func choose_option(_choice_id: String) -> void:
	#Update internal state and move to next line
	if not _is_active:
		return;
	
	#Analytics: track which choice placer picked at this line
	Analytics.log_event("dialogue_choice_selected", {
		"dialogue_id": _current_dialogue_id,
		"line_index": _current_line_index,
		"choice_id": _choice_id,
	})
		
	#Update internal state and move to next line
	#Implement branching logic here later
	_advance_line();
	
#Allows player to skip dialogue early
#Important for accessibility
func skip_dialogue() -> void:
	#Will need a skip or cancel button
	if not _is_active:
		return;
		
	#Log the player skipped the dialogue
	Analytics.log_event("dialogue_skipped", {
		"dialogue_id": _current_dialogue_id,
		"line_index": _current_line_index
	});
	
	_end_dialogue({"reason": "skipped"});
	
#endregion
#region Internal helpers and getters
#Move dialogue forward by one line
func _advance_line() -> void:
	#Fire actions on the line player just confirmed past
	var lines: Array = _current_dialogue_data.get("lines", []);
	if _current_line_index < lines.size():
		var leaving_line = lines[_current_line_index];
		if typeof(leaving_line) == TYPE_DICTIONARY:
			_process_line_actions(leaving_line);
			
	_current_line_index += 1;
	#If we've moved past the last line, end the dialogue
	if _current_line_index >= lines.size():
		_end_dialogue({"reason": "end_of_dialogue"});
		return;
	#Otherwise, go to next line
	_emit_current_line();

#Emit the current line in the UI
func _emit_current_line() -> void:
	if not _is_active:
		return;
	var lines: Array = _current_dialogue_data.get("lines", []);
	var line_any = lines[_current_line_index];
	if typeof(line_any) != TYPE_DICTIONARY:
		_end_dialogue({"reason": "invalid_line"})
		return;
	var line: Dictionary = line_any;
	#Get correct keys from line
	var speaker_key: String = str(line.get("speaker_key", ""));
	var text_key: String = str(line.get("text_key",""));
	var raw_choices: Array = line.get("choices", []);
	
	#Translate speaker and text (use fallback if key is missing)
	var speaker: String = "";
	if not speaker_key.is_empty():
		if speaker_key != "speaker.player":
			speaker = tr(speaker_key);
		else:
			speaker = GameState.player_name;
	var text: String = "";
	if not text_key.is_empty():
		text = tr(text_key);
	#Build translated choices with {id, text} for the UI
	var choices: Array = [];
	for choice_dict in raw_choices:
		if typeof(choice_dict) != TYPE_DICTIONARY:
			continue;
		
		var choice_id: String = str(choice_dict.get("id", ""));
		var choice_text_key: String = str(choice_dict.get("text_key", ""));
		var choice_text: String = "";
		
		if not choice_text_key.is_empty():
			choice_text = tr(choice_text_key);
			
		choices.append({
			"id": choice_id,
			"text": choice_text,
		})
	var has_choices: bool = choices.size() > 0;
	var line_data: Dictionary = {
		"speaker": speaker,
		"text": text,
		"has_choices": choices.size() > 0,
	}
	#Analytics of the line shown to the player
	Analytics.log_event("dialogue_line_shown", {
		"dialogue_id": _current_dialogue_id,
		"line_index": _current_line_index,
		"speaker_key": speaker_key,
		"text_key": text_key,
		"has_choices": has_choices,
		"choice_count": choices.size(),
	})
	
	#Show what line to display
	line_changed.emit(line_data);
	#Store the info for encyclopedia
	dialogue_line_shown.emit({
		"dialogue_id": _current_dialogue_id,
		"line_index": _current_line_index,
		"npc_id": str(_current_context.get("npc_id", "")),
		"speaker": speaker,
		"text": text
	});
	#If there are choices, we also tell UI to show them
	if choices.size() > 0:
		choices_presented.emit(choices);

#Ends current dialogue and reset state
func _end_dialogue(result_data: Dictionary = {}) -> void:
	#Fire ended signal first so listeners can queue a follow-up
	var reason: String = String(result_data.get("reason", "unknown"));
	#Analytics dialogue ended for this reason
	Analytics.log_event("dialogue_ended", {
		"dialogue_id": _current_dialogue_id,
		"final_line_index": _current_line_index,
		"reason": reason,
	})
	#Notidy UI that it's ended so the dialogue box can be hidden
	dialogue_ended.emit(result_data);
	
	#Clear all the internal info--resets for next dialogue
	_current_dialogue_id = "";
	_current_line_index = 0;
	_current_dialogue_data = {};
	_current_context = {};
	_fired_action_line_indices.clear();
	_is_active = false;

#Helper function for actually doing things during dialogue
func _process_line_actions(line: Dictionary) -> void:
	if not _is_active:
		return;
	#Only fire once per line index
	if _fired_action_line_indices.has(_current_line_index):
		return;
	var actions_in = line.get("actions", []);
	if typeof(actions_in) != TYPE_ARRAY or actions_in.is_empty():
		return;
		
	#Safety checks passed
	_fired_action_line_indices[_current_line_index] = true;
	for a in actions_in:
		if typeof(a) != TYPE_DICTIONARY:
			continue;
		
		var action: Dictionary = a;
		var action_type: String = String(action.get("type", "")).strip_edges();
		
		#Analytics generic action hook
		Analytics.log_event("dialogue_action_triggered", {
			"dialogue_id": _current_dialogue_id,
			"line_index": _current_line_index,
			"action_type": action_type
		})
		#Match statement for the action type
		match action_type:
			"give_item":
				_handle_action_give_item(action);
			"deliver_items":
				var quest_id: String = String(action.get("quest_id", ""));
				var item_id: String = String(action.get("item_id", ""));
				var npc_id: String = String(_current_context.get("npc_id", ""));
				if not quest_id.is_empty() and not item_id.is_empty():
					QuestSystem.notify_event("deliver_items", {
						"npc_id": npc_id,
						"item_id": item_id,
					});
			_:
				push_warning("DialogueSystem: Unknown action type '%s' in dialogue '%s' line %d"
					% [action_type, _current_dialogue_id, _current_line_index]);
		#Signal that dialogue action has fired
		dialogue_action_fired.emit(action, _current_context);
		
#Deal with being given an item
func _handle_action_give_item(action: Dictionary) -> void:
	var item_id: String = String(action.get("item_id", "")).strip_edges();
	var amount: int = int(action.get("amount", 1));
	if amount < 1:
		amount = 1;
	#Safety check
	if item_id.is_empty():
		push_warning("DialogueSystem: give_item action missing item_id (dialogue=%s line=%d)"
			%[_current_dialogue_id, _current_line_index]);
			
		Analytics.log_event("dialogue_give_item_invalid", {
			"dialogue_id": _current_dialogue_id,
			"line_index": _current_line_index,
			"reason": "missing_item_id",
		})
		return;
		
	#Ensure item exists
	if not ItemDatabase.has_item(item_id):
		push_warning("DialogueSystem: give_item uknown item_id '%s' (dialogue=%s line =%d)"
			%[item_id, _current_dialogue_id, _current_line_index]);
		
		Analytics.log_event("dialogue_give_item_invalid", {
			"dialogue_id": _current_dialogue_id,
			"line_index": _current_line_index,
			"item_id": item_id,
			"reason": "unkown_item_id"
		});
		return;
	#Route furniture items to DecorationSystem, everything else to player inventory
	var added: bool = false;
	var item: ItemDataResource = ItemDatabase.get_item(item_id);
	if item != null and item.type == ItemDataResource.ItemType.FURNITURE:
		DecorationSystem.add_furniture(item_id, amount);
		added = true;
	else:
		added = InventorySystem.try_add_item(item_id, amount);
	if not added:
		#Later implement a force add or drop-to-world fallback
		var hud = UIRouter.get_hud();
		if hud:
			var item_name: String = ItemDatabase.get_display_name(item_id);
			hud.show_message("Inventory full--couldn't receive %s" % item_name, 2.5);
		push_warning("DialogueSystem: Inventory full. Couldn't give %dx %s." % [amount, item_id]);
		
		Analytics.log_event("dialogue_give_item_failed", {
			"dialogue_id": _current_dialogue_id,
			"line_index": _current_line_index,
			"item_id": item_id,
			"amount": amount,
			"reason": "inventory_full"
		})
		return;
		
	#If the item is a weapon, auto-equip it to the player's weapon slot
	if ItemDatabase.get_tool_category(item_id) == ItemDataResource.ToolCategory.SWORD:
		var player = Game.get_player();
		if player and player.has_method("set_equipped_weapon"):
			player.set_equipped_weapon(item_id);
	
	#Succeful item grant
	Analytics.log_event("dialogue_give_item_success", {
		"dialogue_id": _current_dialogue_id,
		"line_index": _current_line_index,
		"item_id": item_id,
		"amount": amount
	});
	
#Loads dialogue content from the preload files
func _load_dialogue_data(dialogue_id: String) -> Dictionary:
	if DialogueData == null:
		push_error("DialogueSystem: DialogueData autload is missing or not named correctly.");
		return {};
	if not DialogueData.has_dialogue(dialogue_id):
		push_warning("DialogueSystem: Dialogue '%s' not found. Known ids: %s"
			% [dialogue_id, DialogueData.get_all_ids()])
		return {};
	return DialogueData.get_dialogue(dialogue_id);
#endregion
