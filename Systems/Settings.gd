extends Node
#Game options and ADHD accessibility settings

signal settings_changed();

#region Enums
enum TextSize { SMALL, MEDIUM, LARGE }
enum TextSpeed { SLOW, NORMAL, FAST }
#endregion

#region Variables
#Display
var fullscreen: bool = true;
var ui_scale: float = 1.0;

#Audio
var master_volume_db: float = 0.0;
var music_volume_db: float = 0.0;
var sfx_volume_db: float = 0.0;

#Gameplay
var typewriter_enabled: bool = true;
var text_speed_preset: TextSpeed = TextSpeed.NORMAL;
var guided_mode: bool = true;

#Accessibility
var text_size_preset: TextSize = TextSize.MEDIUM;
var reduce_screen_shake: bool = false;
var calm_visual_mode: bool = false;

var _base_font_sizes: Dictionary = {};
#endregion

#region Public helpers
func get_text_size_scale() -> float:
	#24px is the baseline (MEDIUM) SMALL = 16px, LARGE = 32px
	match text_size_preset:
		TextSize.SMALL:
			return 16.0 / 24.0;
		TextSize.LARGE:
			return 32.0 / 24.0;
		_:
			return 1.0;
			
func get_text_speed_multiplier() -> float:
	#Multiplier applied to TypewriterText.chars_per_second
	match text_speed_preset:
		TextSpeed.SLOW:
			return 0.5;
		TextSpeed.FAST:
			return 2.0;
		_:
			return 1.0;
			
func get_volume_db(sound_id: String) -> float:
	match sound_id:
		"master":
			return master_volume_db;
		"music":
			return music_volume_db;
		"sfx":
			return sfx_volume_db;
		_:
			return 0.0;
			
func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled;
	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN);
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);
		
func set_ui_scale(scale: float) -> void:
	ui_scale = scale;
	
func set_volumes(master_db: float, music_db: float, sfx_db: float) -> void:
	master_volume_db = master_db;
	music_volume_db = music_db;
	sfx_volume_db = sfx_db;
	
func set_typewriter_enabled(enabled: bool) -> void:
	typewriter_enabled = enabled;
	
func set_text_speed_preset(preset: TextSpeed) -> void:
	text_speed_preset = preset;
	
func set_guided_mode(enabled: bool) -> void:
	guided_mode = enabled;
	
func set_text_size_preset(preset: TextSize) -> void:
	text_size_preset = preset;
	
func set_reduce_screen_shake(enabled: bool) -> void:
	reduce_screen_shake = enabled;
	
func set_calm_visual_mode(enabled: bool) -> void:
	calm_visual_mode = enabled;

#region Reset to default
func reset_audio_defaults() -> void:
	master_volume_db = 0.0;
	music_volume_db = 0.0;
	sfx_volume_db = 0.0;
	
func reset_gameplay_defaults() -> void:
	typewriter_enabled = true;
	text_speed_preset = TextSpeed.NORMAL;
	guided_mode = true;
	
func reset_accessibility_defaults() -> void:
	set_fullscreen(true);
	text_size_preset = TextSize.MEDIUM;
	reduce_screen_shake = false;
	calm_visual_mode = false;
#endregion

func apply_settings_to_tree(tree: SceneTree) -> void:
	_apply_ui_settings(tree);
	#Notify everything that is listening
	settings_changed.emit();

func apply_text_size_to_node(node: Node) -> void:
	_apply_text_size_recursive(node);
	
func _apply_ui_settings(tree: SceneTree) -> void:
	if tree == null:
		return;
		
	var root = tree.root;
	if root == null:
		return;
		
	#Safety checks passed
	#Scale the UI Root so all UI respects ui_scale
	var scaled_ui_root = root.get_node_or_null("UIRoot/ScaledUIRoot");
	if scaled_ui_root and scaled_ui_root is Control:
		var ctrl := scaled_ui_root as Control;
		ctrl.scale = Vector2(ui_scale, ui_scale);
		ctrl.size = ctrl.get_viewport_rect().size / ui_scale;
		
	#Adjust text size for all Controls
	_apply_text_size_recursive(root);

func _apply_text_size_recursive(node: Node) -> void:
	#Can tighten later by using groups or tags for UI Controls
	if node is Control:
		var ctrl = node as Control;
		var id = ctrl.get_instance_id();
		var scale := get_text_size_scale();
		
		#Standard Controls (Label, Button, etc.)
		if ctrl.has_theme_font_size("font_size"):
			if not _base_font_sizes.has(id):
				_base_font_sizes[id] = ctrl.get_theme_font_size("font_size");
			var base: int = _base_font_sizes[id];
			ctrl.add_theme_font_size_override("font_size", int(round(base * scale)));
			
		#RichTextLabel uses "normal_font_size" instead
		if ctrl is RichTextLabel and ctrl.has_theme_font_size("normal_font_size"):
			var rid = id + 1; #Separate key so it doesn't collide
			if not _base_font_sizes.has(rid):
				_base_font_sizes[rid] = ctrl.get_theme_font_size("normal_font_size");
			var base_rich: int = _base_font_sizes[rid];
			ctrl.add_theme_font_size_override("normal_font_size", int(round(base_rich * scale)));
	
	for child in node.get_children():
		_apply_text_size_recursive(child);
#endregion

#region Save and load
func to_dict() -> Dictionary:
	return {
		"ui_scale": ui_scale,
		"text_size_preset": int(text_size_preset),
		"fullscreen": fullscreen,
		"master_volume_db": master_volume_db,
		"music_volume_db": music_volume_db,
		"sfx_volume_db": sfx_volume_db,
		"typewriter_enabled": typewriter_enabled,
		"text_speed_preset": int(text_speed_preset),
		"guided_mode": guided_mode,
		"reduce_screen_shake": reduce_screen_shake,
		"calm_visual_mode": calm_visual_mode,
	};

func from_dict(data: Dictionary) -> void:
	ui_scale = float(data.get("ui_scale", 1.0));
	text_size_preset = int(data.get("text_size_preset", TextSize.MEDIUM)) as TextSize;
	fullscreen = bool(data.get("fullscreen", false));
	master_volume_db = float(data.get("master_volume_db", 0.0));
	music_volume_db = float(data.get("music_volume_db", -4.0));
	sfx_volume_db = float(data.get("sfx_volume_db", -4.0));
	typewriter_enabled = bool(data.get("typewriter_enabled", true));
	text_speed_preset = int(data.get("text_speed_preset", TextSpeed.NORMAL)) as TextSpeed;
	guided_mode = bool(data.get("guided_mode", true));
	reduce_screen_shake = bool(data.get("reduce_screen_shake", false));
	calm_visual_mode = bool(data.get("calm_visual_mode", false));
	_settings_changed(false);
#endregion

#Trigger for settings being changed somewhere
func _settings_changed(emit: bool = true) -> void:
	if emit:
		settings_changed.emit();
