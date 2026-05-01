extends AnimatedMenu;
class_name BedConfirmDialogue;

#UIRouter connects to this once, fires only when the full flow is complete
signal flow_completed(accepted: bool);

@onready var confirm_button: Button = %ConfirmButton;
@onready var cancel_button: Button = %CancelButton;
@onready var check_label: Label = %BedConfirmLabel;

#Add end of day scene here

func _ready() -> void:
	super._ready();
	if confirm_button:
		confirm_button.pressed.connect(_on_confirmed);
		UIStringsDatabase.apply_to_button(confirm_button, "confirm");
	if cancel_button:
		cancel_button.pressed.connect(_on_cancelled);
		UIStringsDatabase.apply_to_button(cancel_button, "cancel");
	check_label.text = UIStringsDatabase.get_text("save_end_day");
	
#Player confirms save and end day
func _on_confirmed() -> void:
	Analytics.log_event("bed_confirm_accepted", {
		"current_day": GameState.current_day,
	})
	#Close self, then show end of day screen
	close_animation_finished.connect(func(): flow_completed.emit(true), CONNECT_ONE_SHOT);
	play_close_animation();

#Player cancels and doesn't save for the night
func _on_cancelled() -> void:
	Analytics.log_event("bed_confirm_cancelled", {
		"current_day": GameState.current_day,
	})
	close_animation_finished.connect(func(): flow_completed.emit(false), CONNECT_ONE_SHOT);
	play_close_animation();
