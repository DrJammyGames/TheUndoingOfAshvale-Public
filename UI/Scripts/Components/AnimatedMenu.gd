extends Control;
class_name AnimatedMenu;
#Signals UIRouter to close menu
signal close_animation_finished;
#Base class for any menu that should "pop in" when opened.
# Works nicely with UIRouter: animation plays automatically in _ready().

@export_group("Animated Panel")
#Which child node should be animated. If empty, the menu root (self) is used.
@export var panel_root_path: NodePath;

@export_group("Animation Settings")
@export var open_scale_start: float = 0.5;
@export var open_duration: float = 0.15;
@export var close_scale_end: float = 0.5;
@export var close_duration: float = 0.15;
@export var use_fade: bool = false;

@export_group("Analytics (Optional)")
#For any extra per-menu analytics on open.
@export var analytics_menu_id: StringName = &"";
@export var enable_analytics_on_open: bool = false;

var _panel_root: Control = null;
var _anim_tween: Tween = null;

func _ready() -> void:
	#Resolve and prepare the panel root first
	_resolve_panel_root();
	_log_open_analytics_if_enabled();
	#Defer the animation until first layout pass to ensure everything has been set
	_play_open_animation_deferred();

func _resolve_panel_root() -> void:
	if panel_root_path != NodePath(""):
		_panel_root = get_node_or_null(panel_root_path) as Control;
	if _panel_root == null:
		#Fallback: animate the menu root itself
		_panel_root = self;
		
	#Keep pivot centered if layout/size changes
	if not _panel_root.resized.is_connected(_on_panel_resized):
		_panel_root.resized.connect(_on_panel_resized);

func _setup_pivot_centering() -> void:
	if _panel_root == null:
		return;
	_panel_root.pivot_offset = _panel_root.size * 0.5;

#Ensure things stay centered even if resized
func _on_panel_resized() -> void:
	_setup_pivot_centering();

func _create_tween() -> Tween:
	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill();
	_anim_tween = create_tween();
	_anim_tween.set_trans(Tween.TRANS_QUAD);
	_anim_tween.set_ease(Tween.EASE_OUT);
	return _anim_tween;

func _play_open_animation_deferred() -> void:
	#Wait a few frames so Godot can adjust layouts
	
	await get_tree().process_frame;
	_setup_pivot_centering();
	_play_open_animation();

func _play_open_animation() -> void:
	if _panel_root == null:
		return;
		
	#Start slightly smaller & possibly transparent
	_panel_root.scale = Vector2.ONE * open_scale_start;
	if use_fade:
		var c = _panel_root.modulate;
		c.a = 0.0;
		_panel_root.modulate = c;
		
	var tween = _create_tween()
	if use_fade:
		tween.tween_property(_panel_root, "modulate:a", 1.0, open_duration);
	tween.parallel().tween_property(_panel_root, "scale", Vector2.ONE, open_duration);

func play_close_animation() -> void:
	if _panel_root == null:
		close_animation_finished.emit();
		return;
		
	var tween = _create_tween();
	tween.set_ease(Tween.EASE_IN); #Snap in, not out
	if use_fade:
		tween.tween_property(_panel_root, "modulate:a", 0.0, close_duration);
	tween.parallel().tween_property(_panel_root, "scale", Vector2.ONE * close_scale_end, close_duration);
	await tween.finished;
	close_animation_finished.emit();

#If bool is enabled, get further analytics
func _log_open_analytics_if_enabled() -> void:
	if not enable_analytics_on_open:
		return;
	if analytics_menu_id == &"":
		return;
		
	Analytics.log_event("ui_menu_opened", {
		"menu_id": str(analytics_menu_id),
		"scene": Analytics.get_scene_path(),
	})
