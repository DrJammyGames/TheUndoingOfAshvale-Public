extends HBoxContainer
class_name DayBar

@onready var sun_icon: TextureRect = %SunIcon;
@onready var progress_bar: TextureProgressBar = %ProgressBar;
@onready var moon_icon: TextureRect = %MoonIcon;

func _ready() -> void:
	if DayNightSystem.has_signal("day_tick"):
		DayNightSystem.day_tick.connect(_on_day_tick);
	if DayNightSystem.has_signal("night_entered"):
		DayNightSystem.night_entered.connect(_on_night_entered);
	if DayNightSystem.has_signal("day_changed"):
		DayNightSystem.day_changed.connect(_on_day_entered);
	
	#Wait two secs to sync the day night system
	await get_tree().process_frame;
	await get_tree().process_frame;
	if Game.has_signal("scene_changed"):
		Game.scene_changed.connect(_on_scene_loaded);
	
func _on_day_tick(progress: float) -> void:
	_set_progress(progress);
	
func _on_night_entered() -> void:
	_set_progress(1.0);
	
#Reset the progress for the day
func _on_day_entered(_new_day: int) -> void:
	_set_progress(0.0);
	
func _set_progress(value: float) -> void:
	progress_bar.value = value * 100.0;
	
func _on_scene_loaded(_path: String) -> void:
	await get_tree().process_frame;
	await get_tree().process_frame;
	if DayNightSystem.is_night():
		_set_progress(1.0);
	else:
		var current_progress: float = DayNightSystem._ticks_today / DayNightSystem.ticks_per_day;;
		_set_progress(current_progress);
