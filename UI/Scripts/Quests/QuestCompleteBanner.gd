extends Control
class_name QuestCompleteBanner;

signal finished(quest_id: String);

@onready var title_label: Label = %TitleLabel;
@onready var quest_name_label: Label = %QuestName;
@onready var continue_label: Label = %ContinueLabel;

var _is_showing: bool = false;
var _current_quest_id: String = "";

func _ready() -> void:
	visible = false;
	#Must process while paused so input works
	process_mode = Node.PROCESS_MODE_ALWAYS;
	#Default text
	if title_label:
		UIStringsDatabase.apply_to_label(title_label, "quest_completed");
	if continue_label:
		UIStringsDatabase.apply_to_label(continue_label, "level_up_continue");
		
#Public helper for UI
func show_for_quest(quest_id: String) -> void:
	_current_quest_id = quest_id;
	var quest_name = QuestDatabase.get_display_name(quest_id);
	if quest_name_label:
		quest_name_label.text = quest_name;
	
	visible = true;
	modulate.a = 1.0; #ensure fully visible
	_is_showing = true;
	
func _input(event: InputEvent) -> void:
	if not _is_showing:
		return;
	if event.is_pressed() and not event.is_echo():
		get_viewport().set_input_as_handled();
		_dismiss();
		
func _dismiss() -> void:
	_is_showing = false;
	visible = false;
	finished.emit(_current_quest_id);
	_current_quest_id = "";
