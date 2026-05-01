extends Control;
class_name PauseMenu

#@onready var title_label: Label = %PauseLabel;
@onready var resume_button: Button = %ResumeButton;
@onready var save_button: Button = %SaveButton;
@onready var options_button: Button = %OptionsButton;
@onready var quit_button: Button = %QuitButton;



func _ready() -> void:
	#Set up the localised text
	#UIStringsDatabase.apply_to_header(title_label, "pause_menu_title");
	UIStringsDatabase.apply_to_button(resume_button, "resume");
	UIStringsDatabase.apply_to_button(save_button, "save_game");
	UIStringsDatabase.apply_to_button(options_button, "options");
	UIStringsDatabase.apply_to_button(quit_button, "quit_to_main");
	
	#Hook up buttons
	if resume_button:
		resume_button.pressed.connect(_on_resume_pressed);
	if save_button:
		save_button.pressed.connect(_on_save_pressed);
	if options_button:
		options_button.pressed.connect(_on_options_pressed);
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed);
	
func _on_resume_pressed() -> void:
	Analytics.log_event("pause_resume_clicked", {
		"scene": Analytics.get_scene_path(),
	});
	UIRouter.close_top_modal();
	
func _on_save_pressed() -> void:
	var success: bool = false;
	
	if Game.has_method("request_save"):
		#Let game decide the correct slot
		success = Game.request_save();
		
	#After saving, GameState.current_save_slot should be set
	var slot_used = GameState.current_save_slot;
	if slot_used < 0:
		#Fallback in case there is an error
		slot_used = 0;
	Analytics.log_event("pause_save_clicked", {
		"slot": slot_used,
		"success": success,
		"scene": Analytics.get_scene_path(),
	})
	#Add feedback to show player their game has been saved later

	
func _on_options_pressed() -> void:
	Analytics.log_event("pause_options_clicked", {
		"scene": Analytics.get_scene_path(),
	})
	UIRouter.show_options();
	
func _on_quit_pressed() -> void:
	Analytics.log_event("pause_quit_to_title_clicked", {
		"scene": Analytics.get_scene_path(),
		"save_on_quit": true,
	});
	#Close the pause menu when returning to title screen
	UIRouter.toggle_pause_menu("input");
	#Access Game's return to title
	if Game.has_method("return_to_title"):
		#return_to_title selects save slot
		Game.return_to_title(true);
