extends Control
class_name OverwriteConfirmDialogue;
signal overwrite_confirmed(slot: int);
signal overwrite_cancelled(slot: int);

var _slot: int = -1;

@onready var message_label: Label = %MessageLabel;
@onready var yes_button: Button = %YesButton;
@onready var no_button: Button = %NoButton;

func _ready() -> void:
	#Setup UI localisation stuffs
	UIStringsDatabase.apply_to_label(message_label, "overwrite");
	UIStringsDatabase.apply_to_button(yes_button, "confirm");
	UIStringsDatabase.apply_to_button(no_button, "cancel");
	if yes_button:
		yes_button.pressed.connect(_on_yes_pressed);
	if no_button:
		no_button.pressed.connect(_on_no_pressed);
		
func setup(slot: int) -> void:
	_slot = slot;
	
	#Hardcoded text for now--update later with UI localisation
	if message_label:
		message_label.text += " %d?" % (slot + 1);
		
func _on_yes_pressed() -> void:
	Analytics.log_event("overwrite_confirmed", {
		"slot": _slot,
	})
	overwrite_confirmed.emit(_slot);
	queue_free();
	
func _on_no_pressed() -> void:
	Analytics.log_event("overwrite_cancelled", {
		"slot": _slot,
	})
	overwrite_cancelled.emit(_slot);
	queue_free();
