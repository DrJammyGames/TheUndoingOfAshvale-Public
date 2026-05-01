extends Node

#Declare in scene tree variables
@onready var title_label: Label = %GameTitle;
@onready var new_game_button: Button = %NewGameButton;
@onready var continue_button: Button = %ContinueButton;
@onready var load_button: Button = %LoadButton;
@onready var options_button: Button = %OptionsButton;
@onready var quit_button: Button = %QuitButton;
@onready var title_camera: Camera2D = %TitleCamera;
func _ready() -> void:
	#Setup buttons based on ButtonDatabase (translations and such)
	UIStringsDatabase.apply_to_header(title_label, "main_menu_title");
	UIStringsDatabase.apply_to_button(new_game_button, "new_game");
	UIStringsDatabase.apply_to_button(continue_button, "continue");
	UIStringsDatabase.apply_to_button(load_button, "load");
	UIStringsDatabase.apply_to_button(options_button, "options");
	UIStringsDatabase.apply_to_button(quit_button, "quit");
	
	new_game_button.pressed.connect(_on_new_game_pressed);
	continue_button.pressed.connect(_on_continue_pressed);
	load_button.pressed.connect(_on_load_pressed);
	options_button.pressed.connect(_on_options_pressed);
	quit_button.pressed.connect(_on_quit_pressed);
	#Disable Continue if no save exists 
	var has_save: bool = SaveSystem.has_any_saves();
	continue_button.disabled = not has_save;
	if VisualFX:
		VisualFX.set_active_camera(title_camera);
	#Apply settings
	Settings.apply_settings_to_tree(get_tree());
	
	
#New game + slot select
func _on_new_game_pressed() -> void:
	Analytics.log_event("title_new_game_pressed", {})
	
	#Hook into UIRouter to show save screen modal
	if UIRouter.has_method("show_name_entry_for_new_game"):
		UIRouter.show_name_entry_for_new_game();
	else:
		#fallback just start a new game with default slot selection
		if Game and Game.has_method("start_new_game"):
			#Later add open a select slot menu
			Game.start_new_game();
		else:
			#Fallback go straight to Player House scene
			get_tree().change_scene_to_file("res://Scenes/Rooms/PlayerHouse.tscn");
		
#Continue game
func _on_continue_pressed() -> void:
	Analytics.log_event("title_continue_pressed", {})
	var slot = SaveSystem.get_latest_save_slot();
	if slot < 0:
		#No valid slot found, just be safe
		push_warning("Continue pressed, but no save slots found.");
		return;
	Game.load_game(slot);
		
#Load game (select from save slots)
func _on_load_pressed() -> void:
	Analytics.log_event("title_load_game_pressed", {});
	
	if UIRouter.has_method("show_slot_select_for_load_game"):
		UIRouter.show_slot_select_for_load_game();
	else:
		#Fallback behave like continue
		var slot: int = SaveSystem.get_latest_save_slot();
		if slot < 0:
			push_warning("Load pressed, but no save slots found.");
			return;
		Game.load_game(slot);

#Options menu--tied in with UIRouter
func _on_options_pressed() -> void:
	#Reuse global options modal via UIRouter
	if UIRouter and UIRouter.has_method("show_options"):
		UIRouter.show_options();
	else:
		push_warning("UIRouter.show_options() not available.");
		
#Quit game
func _on_quit_pressed() -> void:
	Analytics.log_event("title_quit_pressed", {});
	SaveSystem.save_settings_only();
	get_tree().quit();
