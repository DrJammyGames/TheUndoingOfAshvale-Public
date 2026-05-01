extends HBoxContainer
class_name OptionsRow;

signal value_changed(new_value: float);

enum Mode { STEPPER, CYCLER, TOGGLE }

@onready var option_label: Label = %OptionsLabel;
@onready var minus_button: Button = %MinusButton;
@onready var plus_button: Button = %PlusButton;
@onready var value_label: Label = %ValueLabel;
@onready var toggle_button: Button = %ToggleButton;

var _mode: Mode = Mode.STEPPER;

#Stepper buttons state
var _value: float = 0.0;
var _min: float = 0.0;
var _max: float = 100.0;
var _step: float = 1.0;
var _formatter: Callable;

#Cycler buttons state
var _cycle_values: Array[String] = [];
var _cycle_index: int = 0;

#Toggle buttons state
var _toggle_on_text: String = "";
var _toggle_off_text: String = "";
var _toggle_value: bool = false;

#Shared disabled state
var _is_disabled: bool = false;

#Tooltip state
var _tooltip_desc: String = "";
#StyleBoxes for toggle button state swap 
var style_normal: StyleBox = null;
var style_pressed: StyleBox = null;

#region Public setup
#For the stepper buttons
func setup_stepper(
	label_text: String,
	initial_value: float,
	min_value: float,
	max_value: float,
	step: float,
	formatter: Callable
) -> void:
	_mode = Mode.STEPPER;
	option_label.text = label_text;
	_value = initial_value;
	_min = min_value;
	_max = max_value;
	_step = step;
	_formatter = formatter;
	_connect_stepper_cycler_buttons();
	_apply_mode_visibility();
	_update_display();

#For the cycler buttons
func setup_cycler(
	label_text: String,
	values: Array[String],
	initial_index: int
) -> void:
	_mode = Mode.CYCLER;
	option_label.text = label_text;
	_cycle_values = values;
	_cycle_index = clampi(initial_index, 0, values.size() - 1);
	_connect_stepper_cycler_buttons();
	_apply_mode_visibility();
	_update_display();

#For the toggler buttons
func setup_toggle(
	label_text: String,
	on_text: String,
	off_text: String,
	initial_value: bool
) -> void:
	_mode = Mode.TOGGLE;
	option_label.text = label_text;
	_toggle_on_text = on_text;
	_toggle_off_text = off_text;
	_toggle_value = initial_value;
	if toggle_button:
		toggle_button.pressed.connect(_on_toggle_pressed);
	_apply_mode_visibility();
	_update_display();

#Set value externally without emitting signal
#used by _sync_from_settings
func set_value(value: float) -> void:
	match _mode:
		Mode.STEPPER:
			_value = clamp(value, _min, _max);
		Mode.CYCLER:
			_cycle_index = clampi(int(value), 0, _cycle_values.size() - 1);
		Mode.TOGGLE:
			_toggle_value = value > 0.5;
	_update_display();

func get_value() -> float:
	match _mode:
		Mode.STEPPER:
			return _value;
		Mode.CYCLER:
			return float(_cycle_index);
		Mode.TOGGLE:
			return 1.0 if _toggle_value else 0.0;
	return 0.0;

#Disable or re-enable the interactive controls on this row
func set_row_disabled(disabled: bool) -> void:
	_is_disabled = disabled;
	var alpha: float = 0.4 if disabled else 1.0;
	modulate.a = alpha;
	match _mode:
		Mode.STEPPER, Mode.CYCLER:
			if minus_button:
				minus_button.disabled = disabled;
			if plus_button:
				plus_button.disabled = disabled;
		Mode.TOGGLE:
			if toggle_button:
				toggle_button.disabled = disabled;
				
#Set up GlobalTooltip hover for this row
func setup_tooltip(desc: String) -> void:
	_tooltip_desc = desc;
	mouse_filter = Control.MOUSE_FILTER_STOP;
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered);
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited);
#endregion

#region Internal helpers
func _connect_stepper_cycler_buttons() -> void:
	#Guard against double-connecting if setup is called more than once
	if minus_button and not minus_button.pressed.is_connected(_on_minus_pressed):
		minus_button.pressed.connect(_on_minus_pressed);
	if plus_button and not plus_button.pressed.is_connected(_on_plus_pressed):
		plus_button.pressed.connect(_on_plus_pressed);

func _apply_mode_visibility() -> void:
	var is_toggle: bool = _mode == Mode.TOGGLE;
	if minus_button:
		minus_button.visible = not is_toggle;
	if plus_button:
		plus_button.visible = not is_toggle;
	if value_label:
		value_label.visible = not is_toggle;
	if toggle_button:
		toggle_button.visible = is_toggle;

func _update_display() -> void:
	match _mode:
		Mode.STEPPER:
			if value_label:
				if _formatter.is_valid():
					value_label.text = _formatter.call(_value);
				else:
					value_label.text = str(_value);
		Mode.CYCLER:
			if value_label and _cycle_index < _cycle_values.size():
				value_label.text = _cycle_values[_cycle_index];
		Mode.TOGGLE:
			if toggle_button:
				toggle_button.text = _toggle_on_text if _toggle_value else _toggle_off_text;
				_update_toggle_style();

func _update_toggle_style() -> void:
	if toggle_button == null:
		return;
	#Swap StyleBox to visually reflect on/off state
	#Falls back gracefully if styles were not assigned by OptionsMenu
	if _toggle_value:
		if style_pressed:
			toggle_button.add_theme_stylebox_override("normal", style_pressed);
		if style_normal:
			toggle_button.add_theme_stylebox_override("hover", style_normal);
	else:
		if style_normal:
			toggle_button.add_theme_stylebox_override("normal", style_normal);
		if style_normal:
			toggle_button.add_theme_stylebox_override("hover", style_normal);

func _on_minus_pressed() -> void:
	match _mode:
		Mode.STEPPER:
			_value = clamp(_value - _step, _min, _max);
		Mode.CYCLER:
			_cycle_index = wrapi(_cycle_index - 1, 0, _cycle_values.size());
	_update_display();
	value_changed.emit(get_value());

func _on_plus_pressed() -> void:
	match _mode:
		Mode.STEPPER:
			_value = clamp(_value + _step, _min, _max);
		Mode.CYCLER:
			_cycle_index = wrapi(_cycle_index + 1, 0, _cycle_values.size());
	_update_display();
	value_changed.emit(get_value());

func _on_toggle_pressed() -> void:
	_toggle_value = not _toggle_value;
	_update_display();
	value_changed.emit(get_value());
	
func _on_mouse_entered() -> void:
	if _tooltip_desc == "" or not GlobalTooltip:
		return;
	GlobalTooltip.show_tooltip(option_label.text, _tooltip_desc);

func _on_mouse_exited() -> void:
	GlobalTooltip.hide_tooltip();
#endregion
