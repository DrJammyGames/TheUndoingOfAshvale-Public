extends Resource
class_name DialogueResource;

#Top-level resource for one complete dialogue conversation.
#dialogue_id: unique string identifier (e.g. "caretaker_intro").
#Drives auto-generated localisation keys for all child lines.
#Must be unique across all .tres files in the dialogue resources folder.

#npc_id: the NPC this dialogue belongs to. Used by DialogueDatabase.find_best_dialogue_for_npc().

#Quest gating fields (mirror the old CSV columns):
#for_quest_id  — leave empty for generic dialogue (always eligible)
#quest_state   — "any" | "active" | "completed" | "not_started"
#min_step_index / max_step_index — -1 means no bound
#is_fallback   — lowest priority; only shown if nothing else matches

enum NpcId { CARETAKER, BLACKSMITH, WITCH };
enum QuestState { ANY, NOT_STARTED, ACTIVE, COMPLETED };
@export var dialogue_id: String = "";
@export var npc_id: NpcId = NpcId.CARETAKER; #default

@export_group("Quest Gating")
@export var for_quest_id: String = "";
@export var quest_state: QuestState = QuestState.ANY;
@export var min_step_index: int = -1;
@export var max_step_index: int = -1;
@export var is_fallback: bool = false;

@export_group("Lines")
@export var lines: Array[DialogueLineResource] = [];

#Convert enum to string
func get_npc_id_string() -> String:
	return NpcId.keys()[npc_id].to_lower();
	
func get_quest_state_string() -> String:
	return QuestState.keys()[quest_state].to_lower();
