extends Node2D
class_name NPC;

@export var npc_id: StringName;

@onready var quest_indicator: AnimatedSprite2D = %QuestIndicator;
@onready var animated_sprite: AnimatedSprite2D = %Sprite;
var _data: NPCData;
#Simple state enum 
enum State {
	IDLE,
	TALK,
	WALK,
}

var _state: State = State.IDLE;
#Track who is speaking
var _is_current_speaker: bool = false;
#Track what line the npc is currently on for dialogue
var _last_dialogue_id: String = "";
var _pending_completion_quest_id: String = "";
var _is_in_completion_sequence: bool = false;

func _ready() -> void:
	#Pull data from the NPCDatabase
	_data = NPCDatabase.get_npc(npc_id);
	#Add all NPCs in the scene to a group
	add_to_group("npcs");
	#Safety check
	if _data == null:
		push_warning("NPC '%s' has no NPCData in NPCDatabase." % [npc_id]);
		return;
	
	#Apply sprite frames from data if set
	if _data.sprite_frames != null and animated_sprite != null:
		animated_sprite.sprite_frames = _data.sprite_frames;
	#Start in idle state
	_set_state(State.IDLE);
	#Listen for Dialogue ending to return to idle after talking state
	DialogueSystem.dialogue_ended.connect(_on_dialogue_ended);
	_update_animation();
	
	#Quest indicator signals
	QuestSystem.quest_added.connect(_on_quest_state_changed);
	QuestSystem.quest_updated.connect(_on_quest_state_changed);
	QuestSystem.quest_completed.connect(_on_quest_state_changed);
	QuestSystem.quest_completed.connect(_on_quest_completed_for_dialogue);
	QuestSystem.quests_loaded.connect(_on_quest_state_changed);
	InventorySystem.item_count_changed.connect(_on_inventory_changed);
	ChestStorageSystem.chest_contents_changed.connect(_on_chest_changed);
	_refresh_quest_indicator();
	
func get_npc_id() -> StringName:
	return npc_id;
	
#Public function called when Player presses interact while in range
func interact(_player: Node) -> void:
	if _data == null:
		return;
		
	#Lock quest complete banners before quest events can be completed
	UIRouter.push_banner_lock("NPC.interact")
	
	var dialogue_id_str: String = DialogueData.find_best_dialogue_for_npc(get_npc_id());
	
	#If the best dialogue is a delivery but the player lacks the item,
	#use fall back instead
	if dialogue_id_str != "" and DialogueData.dialogue_player_lacks_items(dialogue_id_str):
		dialogue_id_str = DialogueData.find_fallback_dialogue_for_npc(get_npc_id());
	
	if dialogue_id_str.is_empty():
		UIRouter.pop_banner_lock("NPC.interact");
		return;
	
	var context: Dictionary = {
		"npc_id": String(_data.id),
		"npc_display_name": _data.display_name,
	}
	DialogueSystem.start_dialogue(dialogue_id_str, context);
	_last_dialogue_id = dialogue_id_str;
	_is_current_speaker = true;
	#Hide indicator during dialogue
	_refresh_quest_indicator();
	
	#Notify QuestSystem about the talk event
	var payload: Dictionary = {
		"npc_id": String(_data.id),
	};
	#Merge base_event_payload from data (so more keys per NPC)
	for key in _data.base_event_payload.keys():
		payload[key] = _data.base_event_payload[key];
	QuestSystem.notify_event("talk_to_npc", payload);
	
	#Release the banner lock so quest banner can fire
	UIRouter.pop_banner_lock("NPC.interact");

func _get_current_dialogue_id() -> StringName:
	#Simple version--use default for now
	return _data.default_dialogue_id;
	
#Animation helpers
func _set_state(new_state: State) -> void:
	if new_state == _state:
		return;
	_state = new_state;
	_update_animation();
	
func _update_animation() -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return;
	var frames := animated_sprite.sprite_frames;
	var anim_name: String = "";
	
	match _state:
		State.IDLE:
			anim_name = String(_data.idle_animation);
		State.TALK:
			anim_name = String(_data.idle_animation);
			#if _data.talk_animation != StringName():
				#anim_name = String(_data.talk_animation);
			#else:
				#Fallback to idle if no talking anim is configured
				
	if anim_name != "" and frames.has_animation(anim_name):
		animated_sprite.play(anim_name);
	else:
		#Cheap fallback--play first animation if the one configured is missing
		var names := frames.get_animation_names();
		if names.size() > 0:
			animated_sprite.play(names[0]);
			
#Called when any dialogue ends
func _on_dialogue_ended(_result_data: Dictionary) -> void:
	#Only react if this NPC is the active speaker
	if not _is_current_speaker:
		return;
	#Reset back to basics
	_is_current_speaker = false;
	_set_state(State.IDLE);
	_refresh_quest_indicator();
	
	#Auto-trigger completion dialogue if a quest just completed for this NPC
	if not _pending_completion_quest_id.is_empty() and not _is_in_completion_sequence:
		var quest_id: String = _pending_completion_quest_id;
		_pending_completion_quest_id = "";
		var completion_dialogue: String = DialogueData.find_completion_dialogue_for_npc(String(npc_id), quest_id);
		if not completion_dialogue.is_empty():
			var context: Dictionary = {
				"npc_id": String(_data.id),
				"npc_display_name": _data.display_name,
			};
			_is_in_completion_sequence = true;
			_is_current_speaker = true;
			UIRouter.push_banner_lock("NPC.completion_sequence");
			_refresh_quest_indicator();
			#Play building cinematic before completion dialogue if applicable
			await VisualFX.play_building_upgrade_cinematic(quest_id);
			await get_tree().process_frame;
			#Start the completion dialogue once the camera is back
			DialogueSystem.start_dialogue(completion_dialogue, context);
			await DialogueSystem.dialogue_ended;
			UIRouter.pop_banner_lock("NPC.completion_sequence");
			_is_in_completion_sequence = false;

func _refresh_quest_indicator() -> void:
	if quest_indicator == null:
		return;
		
	#Hide during active dialogue
	if _is_current_speaker:
		quest_indicator.visible = false;
		return;
	quest_indicator.visible = QuestSystem.npc_has_quest_action(String(npc_id));
	
	
func _on_quest_state_changed(_quest_id: String) -> void:
	_refresh_quest_indicator();

func _on_quest_completed_for_dialogue(quest_id: String) -> void:
	#Stash the quest_id if this NPC has a competion dialogue for it
	var completion_id: String = DialogueData.find_completion_dialogue_for_npc(String(npc_id), quest_id);
	if not completion_id.is_empty():
		_pending_completion_quest_id = quest_id;
		
func _on_inventory_changed(_item_id: String, _new_count: int) -> void:
	_refresh_quest_indicator();
	
func _on_chest_changed(_chest_id: String) -> void:
	_refresh_quest_indicator();
