extends Resource
class_name QuestStepResource

#One step within a QuestDataResource


#What gameplay event completes this step 
enum EventType {
	TALK_TO_NPC,
	ITEM_PICKUP,
	ITEM_CRAFTED,
	DELIVER_ITEMS,
	ENEMY_KILLED,
	LOCATION_REACHED,
	PLACE_FURNITURE,
	BUILDING_BUILT,
	FLAG_SET,
}

#What field in the event payload to match against
enum ConditionKey {
	NPC_ID,
	ITEM_ID,
	ENEMY_TYPE,
	LOCATION_ID,
	BUILDING_ID,
	FLAG_NAME,
}

@export var event_type: EventType = EventType.TALK_TO_NPC;
@export_group("Condition")
@export var condition_key: ConditionKey = ConditionKey.NPC_ID;
#The expected value (e.g. "caretaker", "wood", "slime").
@export var condition_value: String = "";
#How many times the condition must be met (default 1)
@export var condition_amount: int = 1;
#How many of the item to consume on completion (0 = don't consume)
@export var consume_amount: int = 0;

#Second, optional condition for the quest step
@export_group("Condition 2 (Optional)")
@export var condition_2_key: ConditionKey = ConditionKey.ITEM_ID;
@export var condition_2_value: String = "";
@export var condition_2_amount: int = 1;
@export var consume_2_amount: int = 0;

@export_group("Localisation")
#Leave empty to auto-generate from parent quest_id + step index
@export var text_key: String = "";

#Returns the text_key to use at runtime.
#If text_key is filled manually, that wins.
#Otherwise auto-generates: "quest.<quest_id>.step.<index>"
func get_resolved_text_key(quest_id: String, step_index: int) -> String:
	if not text_key.is_empty():
		return text_key;
	if quest_id.is_empty():
		return "";
	return "quest.%s.step.%d" % [quest_id, step_index];
	
#Returns the event_type as the lowercase string QuestSystem expects
func get_event_type_string() -> String:
	return EventType.keys()[event_type].to_lower();
	
#Returns the condition_key as the lowercase string used in payload matching
func get_condition_key_string() -> String:
	return ConditionKey.keys()[condition_key].to_lower();
	
func get_condition_2_key_string() -> String:
	return ConditionKey.keys()[condition_2_key].to_lower();
	
#Returns true if there is a second condition
func has_condition_2() -> bool:
	return not condition_2_value.is_empty();
