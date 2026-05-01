extends Node
class_name TypewriterText
#Typewriter effect for a RichTextLabel.
#Uses visible_characters so BBCode etc. still works.

@export var chars_per_second: float = 45.0;
@export var target_label_path: NodePath;
@export var tick_sfx_id: String = "dialogue_tick";
@export var tick_interval: int = 4; #Play sound every N characters
@export_group("Analytics")
@export var analytics_id: StringName = &"";
@export var enable_analytics: bool = false;

@onready var _label: RichTextLabel = get_node_or_null(target_label_path) as RichTextLabel;

var _full_text: String = "";
var _time_accum: float = 0.0;
var _is_typing: bool = false;
#Separate variable to get stuffs from settings
var _effective_chars_per_second: float = 45.0;
signal typing_finished;
signal typing_skipped;


func _ready() -> void:
	if _label == null:
		push_warning("TypewriterText: target_label_path is not set or not a RichTextLabel.");

#Public API to call when a new line arrives
func start_typing(text: String) -> void:
	if text != null:
		_full_text = text;
	else:
		_full_text = "";
	_time_accum = 0.0;
	
	if _label == null:
		return;
		
	_label.text = _full_text;
	#If Typewriter text is not enabled, just show all text
	if not Settings.typewriter_enabled:
		_label.visible_characters = -1;
		_is_typing = false;
		typing_finished.emit();
		_log_analytics("complete");
		return;
	
	#Otherwise, do typewrite stuffs
	_is_typing = true;
	#Start from 0 visible characters
	_label.visible_characters = 0;
	_effective_chars_per_second = chars_per_second * Settings.get_text_speed_multiplier();


func _process(delta: float) -> void:
	if not _is_typing:
		return;
	if _label == null:
		return;
	
	#Safety checks passed
	_time_accum += delta * _effective_chars_per_second;
	var target_visible: int = int(_time_accum);
	
	var total_chars := _get_total_characters();
	if total_chars <= 0:
		#Safety: stop if we can't measure properly
		_label.visible_characters = -1;
		_is_typing = false;
		typing_finished.emit()
		_log_analytics("complete");
		return;
		
	#Clamp to [0, total_chars]
	target_visible = clamp(target_visible, 0, total_chars);
		
	if target_visible != _label.visible_characters:
		_label.visible_characters = target_visible;
		if target_visible % tick_interval == 0:
			AudioManager.play_sfx(tick_sfx_id);
	if _label.visible_characters >= total_chars:
		_is_typing = false;
		typing_finished.emit();
		_log_analytics("complete");

func _get_total_characters() -> int:
	if _label == null:
		return 0;
	if _label.has_method("get_total_character_count"):
		return _label.get_total_character_count();
	#Fallback: approximate with string length
	return _full_text.length();

#Public API to check if typing is currently happening
func is_typing() -> bool:
	return _is_typing;

#Public function to allow player to skip the typewriter effect
func skip_to_full() -> void:
	if not _is_typing:
		return;
		
	_is_typing = false;
	
	if _label:
		#-1 means "all characters visible" for RichTextLabel
		_label.visible_characters = -1;
	typing_skipped.emit();
	#Also toggle finishing the text as it was skipped
	typing_finished.emit();
	_log_analytics("skipped");

#Log the analytics for the dialogue if it is enabled
func _log_analytics(outcome: String) -> void:
	if not enable_analytics:
		return;
	if analytics_id == &"":
		return;
	Analytics.log_event("dialogue_typewriter_" + outcome, {
		"dialogue_id": str(analytics_id),
		"scene": Analytics.get_scene_path(),
	})
