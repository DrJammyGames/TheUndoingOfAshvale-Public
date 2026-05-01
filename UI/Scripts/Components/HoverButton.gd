extends BaseButton;
class_name HoverButton;

#Reusable base button class that adds subtle hover/press scaling

@export_category("Hover / Press Settings")
@export var hover_scale: float = 1.05;
@export var press_scale: float = 0.97;
@export var hover_tween_time: float = 0.08;
@export var press_tween_time: float = 0.06;

#Treat keyboard/gamepad focus like hover
@export var focus_acts_as_hover: bool = true;

#Hook for analytics 
@export_category("Analytics")
@export var analytics_button_id: StringName = &"";
@export var enable_analytics_on_pressed: bool = false;

#Runtime variables
var _original_scale: Vector2 = Vector2.ONE;
var _is_hovered: bool = false;
var _is_pressed: bool = false;
var _has_focus_hover: bool = false;
#Persistent selected state
var _is_active: bool = false;

var _tween: Tween = null;

func _ready() -> void:
	#Remember whatever scale the button already has
	_original_scale = scale;
	
	#Ensure the scale happens around the center
	_update_pivot_to_center();
	#If the button resizes, kep pivot in center
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized);
	#Connect hover signals
	mouse_entered.connect(_on_mouse_entered);
	mouse_exited.connect(_on_mouse_exited);

	#Connect press signals
	button_down.connect(_on_button_down);
	button_up.connect(_on_button_up);

	#Focus (for keyboard and controller navigation)
	if focus_acts_as_hover:
		focus_entered.connect(_on_focus_entered);
		focus_exited.connect(_on_focus_exited);

	#Keep existing pressed() logic from scenes
	#Buttons have their own pressed logic in the Menus scripts
	pressed.connect(_on_pressed_analytics);

func _update_pivot_to_center() -> void:
	pivot_offset = size * 0.5;
	
func _on_resized() -> void:
	#Keep pivot centered if the button's size ever changes
	_update_pivot_to_center();

#Internal function to create the tween for hovering
func _create_tween() -> Tween:
	if _tween and _tween.is_valid():
		_tween.kill();
	_tween = create_tween();
	_tween.set_trans(Tween.TRANS_QUAD);
	_tween.set_ease(Tween.EASE_OUT);
	return _tween;

#Internal helper to update the scale of the button
func _update_target_scale() -> void:
	var target: Vector2 = _original_scale;
	
	#Pressed wins over hover
	if _is_pressed:
		target = _original_scale * press_scale;
	elif _is_active or _is_hovered or _has_focus_hover:
		target = _original_scale * hover_scale;
		
	#Set the duration of the effect
	var duration: float = hover_tween_time
	if _is_pressed:
		duration = press_tween_time;
	
	#Create the tween
	var tween = _create_tween();
	tween.tween_property(self, "scale", target, duration);

#When mouse enters the button
func _on_mouse_entered() -> void:
	_is_hovered = true;
	_update_target_scale();

#Mouse exits the button
func _on_mouse_exited() -> void:
	_is_hovered = false;
	_is_pressed = false;  #safety, in case mouse-up happens outside button
	_update_target_scale();

#Connect to pressing down on button
func _on_button_down() -> void:
	_is_pressed = true;
	AudioManager.play_sfx("button_click");
	_update_target_scale();

#Connect to releasing button
func _on_button_up() -> void:
	_is_pressed = false;
	_update_target_scale();

#Connect to focusing on button
func _on_focus_entered() -> void:
	_has_focus_hover = true;
	_update_target_scale();

#Connect to exiting focus
func _on_focus_exited() -> void:
	_has_focus_hover = false;
	_update_target_scale();

#Log analytics for button presses (if enabled)
func _on_pressed_analytics() -> void:
	if not enable_analytics_on_pressed:
		return;
		
	#If the button has an id
	if analytics_button_id != &"":
		Analytics.log_event("ui_button_pressed", {
			"button_id": str(analytics_button_id),
			"scene": Analytics.get_scene_path(),
		})
		
#Public helper called by TabbedMenu to mark this button as selected
func set_active(active: bool) -> void:
	_is_active = active;
	_update_target_scale();
