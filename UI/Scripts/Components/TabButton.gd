extends Button 
class_name TabButton

@export var tab_label_key: String = "";

@onready var tab_label: Label = $TabLabel;

func _ready() -> void:
	button_down.connect(_on_button_down);
	if tab_label_key != "":
		UIStringsDatabase.apply_to_label(tab_label, tab_label_key);
	tab_label.visible = false;
	
func set_active(active: bool) -> void:
	tab_label.visible = active;
	#Set the width to draw the icon and label properly
	if active:
		custom_minimum_size.x = _get_expanded_width();
	else:
		custom_minimum_size.x = 32;
	
func _on_button_down() -> void:
	AudioManager.play_sfx("button_click");
	
func _get_expanded_width() -> float:
	var label_width: float = tab_label.get_minimum_size().x + 4; #Adds a small buffer on the side
	var tab_width: float = 32.0;
	return tab_width + label_width;
