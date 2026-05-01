extends Control 
class_name InteractionPrompt

@onready var key_label: Label = %KeyLabel;
@onready var action_label: Label = %ActionLabel;

func _ready() -> void:
	visible = false;
	
func show_prompt(prompt_key: String) -> void:
	key_label.text = _get_key_label("interact");
	action_label.text = UIStringsDatabase.get_text(prompt_key);
	visible = true;
	
func hide_prompt() -> void:
	visible = false;
	
func _get_key_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "?";
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var keycode: int = event.physical_keycode;
			if keycode != KEY_NONE:
				return "[" + OS.get_keycode_string(keycode) + "]";
	return "?";
