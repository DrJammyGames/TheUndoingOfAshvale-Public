extends AnimatedMenu
class_name OptionsMenu

enum Tab { AUDIO, GAMEPLAY, ACCESSIBILITY };

const OPTIONS_ROW_SCENE: PackedScene = preload("res://UI/Scenes/Options/OptionsRow.tscn");

#region Volume constants
const VOL_DB_MIN: float = -40.0;
const VOL_DB_MAX: float = 0.0;
const VOL_PERCENT_MIN: float = 0.0;
const VOL_PERCENT_MAX: float = 100.0;
const VOL_PERCENT_STEP: float = 5.0;
#endregion

#region Node refs
#Tab buttons
@onready var audio_tab_button: Button = %AudioTabButton;
@onready var gameplay_tab_button: Button = %GameplayTabButton;
@onready var accessibility_tab_button: Button = %AccessibilityTabButton;

#Panels
@onready var audio_panel: VBoxContainer = %AudioPanel;
@onready var gameplay_panel: VBoxContainer = %GameplayPanel;
@onready var accessibility_panel: VBoxContainer = %AccessibilityPanel;

#Reset to defaults button
@onready var audio_reset_button: Button = %AudioResetButton;
@onready var gameplay_reset_button: Button = %GameplayResetButton;
@onready var accessibility_reset_button: Button = %AccessibilityResetButton;
#endregion

#Stores spawned rows by setting id for later lookup (e.g. text speed dependency)
var _rows: Dictionary = {};
var _current_tab: int = Tab.AUDIO;

#Cached StyleBoxes assigned to toggle rows
#loaded once in _ready
var _style_normal: StyleBox = null;
var _style_pressed: StyleBox = null;

func _ready() -> void:
	#Inherit from AnimatedMenu
	super._ready();
	
	#Load StyleBoxes once for toggle rows
	_style_normal = load("res://FX/Themes/MainMenuButtonNormal.tres");
	_style_pressed = load("res://FX/Themes/MainMenuButtonPressed.tres");
	
	#Connect tab buttons
	audio_tab_button.toggled.connect(_on_audio_tab_toggled);
	gameplay_tab_button.toggled.connect(_on_gameplay_tab_toggled);
	accessibility_tab_button.toggled.connect(_on_accessibility_tab_toggled);
	
	#Save settings when close animation finishes
	close_animation_finished.connect(_on_close_animation_finished);
	
	#Build all tab content
	_build_audio_rows();
	_build_gameplay_rows();
	_build_accessibility_rows();
	
	#Set reset button text via localisation and move to bottom of each panel
	for btn in [audio_reset_button, gameplay_reset_button, accessibility_reset_button]:
		btn.text = UIStringsDatabase.get_text("reset_defaults");
		btn.get_parent().move_child(btn, -1);
	
	#Connect reset buttons
	audio_reset_button.pressed.connect(_on_reset_pressed.bind(Tab.AUDIO));
	gameplay_reset_button.pressed.connect(_on_reset_pressed.bind(Tab.GAMEPLAY));
	accessibility_reset_button.pressed.connect(_on_reset_pressed.bind(Tab.ACCESSIBILITY));
	
	#Apply text speed row disabled state based on current typewriter setting
	_update_text_speed_row_state();
	
	#Listen for external settings changes
	Settings.settings_changed.connect(_on_settings_changed);
	
	#Open on Audio tab by default since it's the first tab
	_set_tab(Tab.AUDIO);
	#Apply settings
	Settings.apply_settings_to_tree(get_tree());

#region Tab switching
func _set_tab(tab_index: int) -> void:
	_current_tab = tab_index;
	
	audio_panel.visible = (tab_index == Tab.AUDIO);
	gameplay_panel.visible = (tab_index == Tab.GAMEPLAY);
	accessibility_panel.visible = (tab_index == Tab.ACCESSIBILITY);
	
	#Apply the states to each button
	_apply_tab_button_state(audio_tab_button, tab_index == Tab.AUDIO);
	_apply_tab_button_state(gameplay_tab_button, tab_index == Tab.GAMEPLAY);
	_apply_tab_button_state(accessibility_tab_button, tab_index == Tab.ACCESSIBILITY);
	
func _apply_tab_button_state(button: Button, is_active: bool) -> void:
	_set_button_pressed_silent(button, is_active);
	if button.has_method("set_active"):
		button.set_active(is_active);
		
func _set_button_pressed_silent(button: Button, pressed: bool) -> void:
	button.set_block_signals(true);
	button.set_pressed(pressed);
	button.set_block_signals(false);
#endregion

#region Row builders
func _build_audio_rows() -> void:
	_spawn_stepper(audio_panel, {
		"id": "master_volume",
		"label_key": "master_volume",
		"get": func() -> float: return _db_to_percent(Settings.master_volume_db),
		"set": func(p: float) -> void:
			Settings.set_volumes(_percent_to_db(p), Settings.music_volume_db, Settings.sfx_volume_db),
		"min": VOL_PERCENT_MIN,
		"max": VOL_PERCENT_MAX,
		"step": VOL_PERCENT_STEP,
		"formatter": func(v: float) -> String: return _format_percent(v),
		"tooltip_key": "master_volume_tooltip",
	});
	_spawn_stepper(audio_panel, {
		"id": "music_volume",
		"label_key": "music_volume",
		"get": func() -> float: return _db_to_percent(Settings.music_volume_db),
		"set": func(p: float) -> void:
			Settings.set_volumes(Settings.master_volume_db, _percent_to_db(p), Settings.sfx_volume_db),
		"min": VOL_PERCENT_MIN,
		"max": VOL_PERCENT_MAX,
		"step": VOL_PERCENT_STEP,
		"formatter": func(v: float) -> String: return _format_percent(v),
		"tooltip_key": "music_volume_tooltip",
	});
	_spawn_stepper(audio_panel, {
		"id": "sfx_volume",
		"label_key": "sfx_volume",
		"get": func() -> float: return _db_to_percent(Settings.sfx_volume_db),
		"set": func(p: float) -> void:
			Settings.set_volumes(Settings.master_volume_db, Settings.music_volume_db, _percent_to_db(p)),
		"min": VOL_PERCENT_MIN,
		"max": VOL_PERCENT_MAX,
		"step": VOL_PERCENT_STEP,
		"formatter": func(v: float) -> String: return _format_percent(v),
		"tooltip_key": "sfx_volume_tooltip",
	});

func _build_gameplay_rows() -> void:
	_spawn_toggle(gameplay_panel, {
		"id": "typewriter",
		"label_key": "typewriter",
		"get": func() -> bool: return Settings.typewriter_enabled,
		"set": func(v: bool) -> void:
			Settings.set_typewriter_enabled(v);
			_update_text_speed_row_state(),
		"tooltip_key": "typewriter_tooltip",
	});
	_spawn_cycler(gameplay_panel, {
		"id": "text_speed",
		"label_key": "text_speed",
		"values_keys": ["slow", "normal", "fast"],
		"get": func() -> int: return int(Settings.text_speed_preset),
		"set": func(i: int) -> void: Settings.set_text_speed_preset(i as Settings.TextSpeed),
		"tooltip_key": "text_speed_tooltip",
	});
	_spawn_toggle(gameplay_panel, {
		"id": "guided_mode",
		"label_key": "guided_mode",
		"get": func() -> bool: return Settings.guided_mode,
		"set": func(v: bool) -> void: Settings.set_guided_mode(v),
		"tooltip_key": "guided_mode_tooltip",
	});

func _build_accessibility_rows() -> void:
	_spawn_toggle(accessibility_panel, {
		"id": "fullscreen",
		"label_key": "fullscreen",
		"get": func() -> bool: return Settings.fullscreen,
		"set": func(v: bool) -> void: Settings.set_fullscreen(v),
		"tooltip_key": "fullscreen_tooltip",
	});
	_spawn_cycler(accessibility_panel, {
		"id": "text_size",
		"label_key": "text_size",
		"values_keys": ["small", "medium", "large"],
		"get": func() -> int: return int(Settings.text_size_preset),
		"set": func(i: int) -> void: Settings.set_text_size_preset(i as Settings.TextSize),
		"tooltip_key": "text_size_tooltip",
	});
	_spawn_toggle(accessibility_panel, {
		"id": "camera_shake",
		"label_key": "camera_shake",
		"get": func() -> bool: return not Settings.reduce_screen_shake,
		"set": func(v: bool) -> void: Settings.set_reduce_screen_shake(not v),
		"tooltip_key": "camera_shake_tooltip",
	});
	_spawn_toggle(accessibility_panel, {
		"id": "calm_visual_mode",
		"label_key": "calm_visual_mode",
		"get": func() -> bool: return Settings.calm_visual_mode,
		"set": func(v: bool) -> void: Settings.set_calm_visual_mode(v),
		"tooltip_key": "calm_visual_mode_tooltip",
	});
	
#endregion

#region Row spawners
func _spawn_stepper(panel: VBoxContainer, config: Dictionary) -> void:
	var row: OptionsRow = OPTIONS_ROW_SCENE.instantiate();
	panel.add_child(row);
	row.setup_stepper(
		UIStringsDatabase.get_text(config["label_key"]),
		config["get"].call(),
		config["min"],
		config["max"],
		config["step"],
		config["formatter"]
	);
	var local_config = config;
	row.value_changed.connect(func(new_value: float) -> void:
		local_config["set"].call(new_value);
		Settings.apply_settings_to_tree(get_tree());
		Analytics.log_event("options_setting_changed", {
			"setting": local_config["id"],
			"value": new_value,
		});
	);
	_rows[config["id"]] = row;
	if config.has("tooltip_key"):
		row.setup_tooltip(UIStringsDatabase.get_text(config["tooltip_key"]));

func _spawn_cycler(panel: VBoxContainer, config: Dictionary) -> void:
	var row: OptionsRow = OPTIONS_ROW_SCENE.instantiate();
	panel.add_child(row);
	#Resolve display strings from UIStrings keys
	var display_values: Array[String] = [];
	for key in config["values_keys"]:
		display_values.append(UIStringsDatabase.get_text(key));
	row.setup_cycler(
		UIStringsDatabase.get_text(config["label_key"]),
		display_values,
		config["get"].call()
	);
	var local_config = config;
	row.value_changed.connect(func(new_value: float) -> void:
		local_config["set"].call(int(new_value));
		Settings.apply_settings_to_tree(get_tree());
		Analytics.log_event("options_setting_changed", {
			"setting": local_config["id"],
			"value": int(new_value),
		});
	);
	_rows[config["id"]] = row;
	if config.has("tooltip_key"):
		row.setup_tooltip(UIStringsDatabase.get_text(config["tooltip_key"]));

func _spawn_toggle(panel: VBoxContainer, config: Dictionary) -> void:
	var row: OptionsRow = OPTIONS_ROW_SCENE.instantiate();
	panel.add_child(row);
	#Pass StyleBoxes so toggle button can swap appearance
	row.style_normal = _style_normal;
	row.style_pressed = _style_pressed;
	row.setup_toggle(
		UIStringsDatabase.get_text(config["label_key"]),
		UIStringsDatabase.get_text("enabled"),
		UIStringsDatabase.get_text("disabled"),
		config["get"].call()
	);
	var local_config = config;
	row.value_changed.connect(func(new_value: float) -> void:
		var as_bool: bool = new_value > 0.5;
		local_config["set"].call(as_bool);
		Settings.apply_settings_to_tree(get_tree());
		Analytics.log_event("options_setting_changed", {
			"setting": local_config["id"],
			"value": as_bool,
		});
	);
	_rows[config["id"]] = row;
	if config.has("tooltip_key"):
		row.setup_tooltip(UIStringsDatabase.get_text(config["tooltip_key"]));
#endregion

#region Text speed dependency
func _update_text_speed_row_state() -> void:
	if not _rows.has("text_speed"):
		return;
	var text_speed_row: OptionsRow = _rows["text_speed"];
	var disabled: bool = not Settings.typewriter_enabled;
	text_speed_row.set_row_disabled(disabled);
#endregion

#region Sync
func _sync_from_settings() -> void:
	#Steppers and cyclers -- set_value takes a float
	if _rows.has("master_volume"):
		_rows["master_volume"].set_value(_db_to_percent(Settings.master_volume_db));
	if _rows.has("music_volume"):
		_rows["music_volume"].set_value(_db_to_percent(Settings.music_volume_db));
	if _rows.has("sfx_volume"):
		_rows["sfx_volume"].set_value(_db_to_percent(Settings.sfx_volume_db));
	if _rows.has("ui_scale"):
		_rows["ui_scale"].set_value(Settings.ui_scale * 100.0);
	if _rows.has("text_speed"):
		_rows["text_speed"].set_value(float(Settings.text_speed_preset));
	if _rows.has("text_size"):
		_rows["text_size"].set_value(float(Settings.text_size_preset));
	#Toggles -- set_value takes 1.0 for true, 0.0 for false
	if _rows.has("fullscreen"):
		_rows["fullscreen"].set_value(1.0 if Settings.fullscreen else 0.0);
	if _rows.has("typewriter"):
		_rows["typewriter"].set_value(1.0 if Settings.typewriter_enabled else 0.0);
	if _rows.has("guided_mode"):
		_rows["guided_mode"].set_value(1.0 if Settings.guided_mode else 0.0);
	if _rows.has("camera_shake"):
		_rows["camera_shake"].set_value(1.0 if not Settings.reduce_screen_shake else 0.0);
	if _rows.has("calm_visual_mode"):
		_rows["calm_visual_mode"].set_value(1.0 if Settings.calm_visual_mode else 0.0);
	_update_text_speed_row_state();

func _on_settings_changed() -> void:
	_sync_from_settings();
#endregion

#region Close handling
func _on_close_animation_finished() -> void:
	SaveSystem.save_settings_only();
#endregion

#region Tab button signal handlers
func _on_audio_tab_toggled(pressed: bool) -> void:
	if pressed:
		_set_tab(Tab.AUDIO);
	else:
		_set_button_pressed_silent(audio_tab_button, _current_tab == Tab.AUDIO);

func _on_gameplay_tab_toggled(pressed: bool) -> void:
	if pressed:
		_set_tab(Tab.GAMEPLAY);
	else:
		_set_button_pressed_silent(gameplay_tab_button, _current_tab == Tab.GAMEPLAY);

func _on_accessibility_tab_toggled(pressed: bool) -> void:
	if pressed:
		_set_tab(Tab.ACCESSIBILITY);
	else:
		_set_button_pressed_silent(accessibility_tab_button, _current_tab == Tab.ACCESSIBILITY);
#endregion

#region Reset handlers
func _on_reset_pressed(tab: int) -> void:
	match tab:
		Tab.AUDIO:
			Settings.reset_audio_defaults();
		Tab.GAMEPLAY:
			Settings.reset_gameplay_defaults();
		Tab.ACCESSIBILITY:
			Settings.reset_accessibility_defaults();
	Settings.apply_settings_to_tree(get_tree());
#endregion

#region Formatting helpers
func _format_percent(value: float) -> String:
	return "%d%%" % int(round(value));

func _db_to_percent(db: float) -> float:
	var t: float = (db - VOL_DB_MIN) / (VOL_DB_MAX - VOL_DB_MIN);
	return clamp(t, 0.0, 1.0) * 100.0;

func _percent_to_db(percent: float) -> float:
	var t: float = clamp(percent / 100.0, 0.0, 1.0);
	return VOL_DB_MIN + t * (VOL_DB_MAX - VOL_DB_MIN);
#endregion
