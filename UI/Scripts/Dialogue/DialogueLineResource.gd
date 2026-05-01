extends Resource
class_name DialogueLineResource

#One line of dialogue within a DialogueResource.

#line_name: a short snake_case identifier unique within this dialogue (e.g. "greet", "quest_offer").
#Used by choices to branch via go_to_line. Also drives auto-generated localisation keys.

#speaker_id: matches the NPC id (e.g. "caretaker"). Auto-generates the speaker_key.

#text_key: manually enter the localisation CSV key, OR leave empty to auto-generate
#from the parent dialogue_id + line_name (set via get_text_key()).

#choices: leave empty for a straight-through line. Add DialogueChoiceResources to branch.

#give_item / give_amount: drop an ItemDataResource here to hand the player an item when this line is reached.
enum SpeakerId { PLAYER, CARETAKER, BLACKSMITH, WITCH };

@export var line_name: String = "";
@export var speaker_id: SpeakerId = SpeakerId.CARETAKER;
@export var text_key: String = "";

@export var choices: Array[DialogueChoiceResource] = [];

@export var give_item: ItemDataResource = null;
@export var give_amount: int = 1;

@export var deliver_quest_id: QuestDataResource = null;
@export var deliver_item_id: ItemDataResource = null;
#Auto-generates the speaker localisation key from speaker_id.
func get_speaker_key() -> String:
	return "speaker.%s" % SpeakerId.keys()[speaker_id].to_lower();

#Returns the text_key to use at runtime.
#If text_key is filled in manually, that wins.
#Otherwise auto-generates: "dialogue.<dialogue_id>.<line_index>"
func get_resolved_text_key(dialogue_id: String, line_index: int) -> String:
	if not text_key.is_empty():
		return text_key;
	if dialogue_id.is_empty():
		return "";
	return "dialogue.%s.%d" % [dialogue_id, line_index];
