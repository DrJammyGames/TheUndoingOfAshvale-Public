extends HBoxContainer
class_name StatBar;

@export var stat_name: String = "HP";

@onready var bar: TextureProgressBar = %Bar;
@onready var value_label: Label = %ValueLabel;

func _ready() -> void:
	#Safe defaults
	bar.min_value = 0;
	bar.max_value = 1;
	bar.value = 1;
	_update_label(1,1);
	
func update_stat(current: int, max_value: int) -> void:
	if bar == null or value_label == null:
		return;
	var safe_max: int = max(max_value, 1);
	var safe_current: int = clamp(current, 0, safe_max);
	
	bar.min_value = 0;
	bar.max_value = safe_max;
	bar.value = safe_current;
	_update_label(safe_current, safe_max);
	
func _update_label(current: int, max_value: int) -> void:
	value_label.text = "%s: %d / %d" % [stat_name, current, max_value];
