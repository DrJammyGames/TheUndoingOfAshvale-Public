extends Control
class_name NameEntryScreen

@onready var name_label: Label = %NamePlayerLabel;
@onready var name_line_edit: LineEdit = %NameLineEdit;
@onready var confirm_button: Button = %ConfirmButton;
@onready var cancel_button: Button = %CancelButton;

func _ready() -> void:
	#Set up localised strings
	UIStringsDatabase.apply_to_label(name_label, "name_player");
	UIStringsDatabase.apply_to_button(confirm_button, "confirm");
	UIStringsDatabase.apply_to_button(cancel_button, "cancel");
	if confirm_button:
		confirm_button.pressed.connect(_on_confirm_pressed);
	if cancel_button:
		cancel_button.pressed.connect(_on_cancel_pressed);
		
	if name_line_edit:
		name_line_edit.grab_focus();
		name_line_edit.text_submitted.connect(_on_name_submitted);
func _on_confirm_pressed() -> void:
	if name_line_edit == null:
		return;
		
	var _name = name_line_edit.text.strip_edges();
	if _name == "":
		_name = "Player";
	#Set the player's name
	GameState.player_name = _name;
	
	Analytics.log_event("name_entry_confirmed", {
		"name_length": _name.length(),
		"is_default": _name == "Player",
	})
	
	#Name has been entered, close this modal then open the slot selection for new game
	UIRouter.close_top_modal();
	if UIRouter.has_method("show_slot_select_for_new_game"):
		UIRouter.show_slot_select_for_new_game();
		
func _on_cancel_pressed() -> void:
	Analytics.log_event("name_entry_canceled", {});
	UIRouter.close_top_modal();

func _on_name_submitted(_text: String) -> void:
	confirm_button.grab_focus();
	confirm_button.button_pressed = true;
	await get_tree().create_timer(0.1).timeout;
	confirm_button.button_pressed = false;
	_on_confirm_pressed();
