extends AnimatedMenu
class_name ControlsHintScreen

#Reads key bindings live from InputMap so it'll update with rebinding

#Actions to display, in order [action_name, label_text]
const CONTROL_ROWS: Array = [
	["move_up", "controls_hint_move_up"],
	["move_down", "controls_hint_move_down"],
	["move_left", "controls_hint_move_left"],
	["move_right", "controls_hint_move_right"],
	["attack", "controls_hint_attack"],
	["use_tool", "controls_hint_use_tool"],
	["interact", "controls_hint_interact"],
]
@onready var title_label: Label = %TitleLabel;
@onready var rows_container: VBoxContainer = %RowsContainer;
@onready var got_it_button: Button = %GotItButton;
var controls_hint_row: PackedScene = preload("res://UI/Scenes/OtherMenus/ControlsHintRow.tscn")
func _ready() -> void:
	super._ready();
	#Set up strings localisation
	UIStringsDatabase.apply_to_header(title_label, "controls_hint_title");
	UIStringsDatabase.apply_to_button(got_it_button, "controls_hint_got_it");
	_build_rows();
	if got_it_button:
		got_it_button.pressed.connect(_on_got_it_pressed);
	#Give button focus immediately so user can confirm without mouse
	got_it_button.grab_focus();
	
#Build one row per control entry
func _build_rows() -> void:
	#Clear any placeholder children from the scene
	for child in rows_container.get_children():
		child.queue_free();
		
	for row_data in CONTROL_ROWS:
		var action: String = row_data[0];
		var ui_id: String = row_data[1];
		var key_name: String = _get_primary_key_name(action);
		var action_text: String = UIStringsDatabase.get_text(ui_id);
		
		var row: ControlHintRow = controls_hint_row.instantiate()
		rows_container.add_child(row)
		#setup() is called after add_child so @onready vars are resolved
		row.setup(key_name, action_text);
		
#Resolve the human-readable name for the first keyboard event on an action
#Returns a sensible fallback if action is unbound
func _get_primary_key_name(action: String) -> String:
	if not InputMap.has_action(action):
		return "?";
		
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			#physical_keycode gives the layout-independent key label
			var keycode: int = event.physical_keycode;
			if keycode != KEY_NONE:
				#Gets the actual readable string
				return OS.get_keycode_string(keycode);
	return "?";
	
#User closes hint
func _on_got_it_pressed() -> void:
	Analytics.log_event("controls_hint_dismissed", {
		"scene": Analytics.get_scene_path(),
	})
	UIRouter.close_top_modal();
