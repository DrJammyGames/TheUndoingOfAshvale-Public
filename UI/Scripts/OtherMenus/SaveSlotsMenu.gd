extends Control;
class_name SaveSlotScreen;

enum Mode {
	NEW_GAME,
	LOAD_GAME
}
var _mode: Mode = Mode.NEW_GAME;

@onready var title_label: Label = %SaveSlotLabel;
@onready var slot_buttons: Array[Button] = [
	%SlotZeroButton,
	%SlotOneButton,
	%SlotTwoButton
]
@onready var cancel_button: Button = %CancelButton;

var overwrite_dialogue_scene: PackedScene = preload("res://UI/Scenes/OtherMenus/OverwriteConfirmDialogue.tscn");

#Called by UIRouter to configure the screen
func setup(mode_str: String) -> void:
	if mode_str == "load_game":
		_mode = Mode.LOAD_GAME;
	else:
		_mode = Mode.NEW_GAME;
		
	Analytics.log_event("save_slot_screen_opened",{
		"mode": mode_str,
	})
	#Refresh the visuals
	_refresh_ui();
	
func _ready() -> void:
	#Default UI in case setup wasn't called for some reason
	_refresh_ui();
	
	#Wrap these in tiny functions that injects the proper save slot int 
	#Ensures we only need a singular _on_slot_pressed instead of three seaprate functions
	for i in range(slot_buttons.size()):
		var btn = slot_buttons[i]
		if btn:
			btn.pressed.connect(func() -> void:
				_on_slot_pressed(i)
			);
	if cancel_button:
		cancel_button.pressed.connect(_on_cancel_pressed);
		
func _refresh_ui() -> void:
	#Change later for localisation stuffs
	if title_label:
		if _mode == Mode.NEW_GAME:
			title_label.text = "Select Save Slot";
		else:
			title_label.text = "Select Load Slot";
	
	for i in range(slot_buttons.size()):
		var btn = slot_buttons[i];
		if btn:
			_setup_slot_button(btn, i);
	
func _setup_slot_button(btn: Button, slot: int) -> void:
	if btn == null:
		return;
	
	var has_save: bool = SaveSystem.has_save_in_slot(slot);
	var base_label: String = "Slot %d" % (slot + 1);
	
	#No save exists, no metadata to grab
	if not has_save:
		if _mode == Mode.NEW_GAME:
			btn.text = "%s - Empty" % base_label;
			btn.disabled = false;
		else:
			btn.text = "%s - Empty" % base_label;
			btn.disabled = true;
		return;
	
	#There is a save file, pull metadata
	var meta = SaveSystem.get_slot_metadata(slot);
	var player_name: String = String(meta.get("player_name", ""));
	if player_name.is_empty():
		player_name = "Unamed";
	
	var location_name: String = String(meta.get("location_name", ""));
	var scene_path: String = String(meta.get("scene_path", ""));
	var location: String = ""; 
	if not location_name.is_empty():
		location = location_name;
	else:
		_format_location(scene_path);
	var playtime_sec: float = float(meta.get("playtime_sec", 0.0));
	var playtime_str = _format_playtime(playtime_sec);
	var info_line = "%s: %s" % [location, playtime_str];
	var label = "%s - %s\n%s" % [base_label, player_name, info_line];
	
	if _mode == Mode.NEW_GAME:
		label += " (Overwrite)"
		btn.disabled = false;
	else:
		btn.disabled = false;
		
	btn.text = label;	
	
func _on_slot_pressed(slot: int) -> void:
	var mode_str: String = "";
	if _mode == Mode.NEW_GAME:
		mode_str = "new_game";
	else:
		mode_str = "load_game";
		
	Analytics.log_event("save_slot_selected", {
		"slot": slot,
		"mode": mode_str,
	})
	
	if _mode == Mode.NEW_GAME:
		#If slot already has a save, ask for confirmation
		if SaveSystem.has_save_in_slot(slot):
			_show_overwrite_confirm(slot);
		else:
			_start_new_game_in_slot(slot);
	else:
		if Game.has_method("load_game"):
			Game.load_game(slot);
		#Close this modal
		UIRouter.close_top_modal();
	
#Helpers for new game
func _start_new_game_in_slot(slot: int) -> void:
	if Game.has_method("start_new_game"):
		#Start a new game in this slot
		Game.start_new_game(slot);
	UIRouter.close_top_modal();
	
func _show_overwrite_confirm(slot: int) -> void:
	if overwrite_dialogue_scene == null:
		#Fallback, something is misconfigured so just start the game
		_start_new_game_in_slot(slot);
		return;
		
	var dialogue = overwrite_dialogue_scene.instantiate() as OverwriteConfirmDialogue;
	if dialogue == null:
		_start_new_game_in_slot(slot);
		return;
		
	#Add dialogue as a child of this so it appears on top
	add_child(dialogue);
	dialogue.setup(slot);
	
	#Listen for confirm or cancel
	dialogue.overwrite_confirmed.connect(_on_overwrite_confirmed);
	dialogue.overwrite_cancelled.connect(_on_overwrite_cancelled);
	
func _on_overwrite_confirmed(slot: int) -> void:
	Analytics.log_event("overwrite_confirm_slot", {
		"slot": slot,
	})
	_start_new_game_in_slot(slot);
	
func _on_overwrite_cancelled(slot: int) -> void:
	#No extra behaviour needed, just log the analytics
	Analytics.log_event("overwrite_confirm_closed_without_override", {
		"slot": slot
	})
func _on_cancel_pressed() -> void:
	var mode_str: String = "";
	if _mode == Mode.NEW_GAME:
		mode_str = "new_game";
	else:
		mode_str = "load_game";
	Analytics.log_event("save_slot_cancelled", {
		"mode": mode_str,
	})
	UIRouter.close_top_modal();

#Functions for formatting stuffs displayed in save slots screen
func _format_playtime(sec: float) -> String:
	var total_minutes = int(sec / 60.0);
	var hours = total_minutes / 60;
	var minutes = total_minutes % 60;
	
	if hours > 0:
		return "%d %02dm" % [hours, minutes];
	else:
		return "%d min" % max(minutes, 1); #avoids 0 mins being weird

func _format_location(scene_path: String) -> String:
	if scene_path.is_empty():
		return "Unknown";
		
	var file = scene_path.get_file().get_basename();
	
	match file:
		"PlayerHouse":
			return "Player House";
		"Town":
			return "Town";
		_:
			file = file.replace("_", " ");
			return file.capitalize(); #Crude, but works
	
