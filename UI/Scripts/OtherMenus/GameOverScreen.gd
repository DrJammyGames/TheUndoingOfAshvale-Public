extends Control
class_name GameOverScreen

#Node references
@onready var title_label: Label = %GameOverLabel;
@onready var load_save_button: Button = %LoadSaveButton;
@onready var return_to_title_button: Button = %ReturnTitleButton;

func _ready() -> void:
	#Set up localisation strings
	UIStringsDatabase.apply_to_header(title_label, "game_over");
	UIStringsDatabase.apply_to_button(load_save_button, "load_save");
	UIStringsDatabase.apply_to_button(return_to_title_button, "quit_to_main");
	
	if load_save_button:
		load_save_button.pressed.connect(_on_load_save_pressed);
	if return_to_title_button:
		return_to_title_button.pressed.connect(_on_return_to_title_pressed);
		
#Load last save
func _on_load_save_pressed() -> void:
	Analytics.log_event("game_over_load_save_pressed", {
		"has_save": SaveSystem.has_any_saves(),
	})
	#Await close so the modal is fully freed before load game fires
	await UIRouter.close_top_modal();
	
	#Then deal with loading data
	var slot: int = SaveSystem.get_latest_save_slot();
	if slot >= 0:
		#Save exists, load it via Game
		Game.load_game(slot);
	else:
		#No save exists (player died before any save)
		Game.start_new_game();
		
#Return the main menu
func _on_return_to_title_pressed() -> void:
	Analytics.log_event("game_over_return_to_title_pressed", {});
	#Close top modal first so modal stack is clean
	await UIRouter.close_top_modal();
	#No save on death, just return to title
	Game.return_to_title(false);
