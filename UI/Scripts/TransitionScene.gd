extends CanvasLayer

@export var fade_duration: float = 0.25;

@onready var fade_rect: ColorRect = get_node_or_null("%FadeRect") as ColorRect


var _busy: bool = false;

func _ready() -> void:
	#Must keep animating even when game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS;
	layer = 999;
	#Start transparent
	if fade_rect:
		fade_rect.visible = true;
		var c = fade_rect.color;
		#Start fully opaque
		c.a = 1.0;
		fade_rect.color = c;
	
	#Start awith shader at no progress
	_set_shader_progress(0.0);
	
func is_busy() -> bool:
	return _busy;
	
#Fading in and out functions
func to_black() -> void:
	#Blackout should be boring--just black screen, no shader animation
	await _fade_to(1.0, false);
	
func to_clear(fancy: bool = true) -> void:
	#Reveal is fancy
	await _fade_to(0.0, fancy);
	

#Internal helper for the fading functions
func _fade_to(target_alpha: float, animate_shader: bool) -> void:
	#No fade rect exists, exit early
	if fade_rect == null:
		push_warning("Fade rect doesn't exist, abort early.")
		return;
	fade_rect.visible = true
	#Set busy to true
	_busy = true;
	
	#Alpha values
	var start_alpha = fade_rect.color.a;
	var end_alpha = target_alpha;
	#If we are not animating shader, lock its value immediately
	if not animate_shader:
		_set_shader_progress(0.0);
	
	var tween = create_tween();
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS);
	#Alpha of color rect
	tween.tween_method(
		func(a: float) -> void:
			var c = fade_rect.color;
			c.a = a;
			fade_rect.color = c,
		start_alpha,
		end_alpha,
		fade_duration
	)
	
	#Shader progress (parallel tween) only when revealing
	if animate_shader:
		#Ensure the progress matches the alpha value
		var start_progress = 1.0 - start_alpha;
		var end_progress = 1.0 - end_alpha;
		tween.parallel().tween_method(
			func(p: float) -> void:
				_set_shader_progress(p),
			start_progress,
			end_progress,
			fade_duration
		)
	await tween.finished;
	
	#Set busy back to false
	_busy = false;

#Helper to set progress in shader
func _set_shader_progress(value: float) -> void:
	var mat = fade_rect.material;
	if mat == null:
		return;
		
	var shader_mat = mat as ShaderMaterial;
	if shader_mat == null:
		return;
		
	shader_mat.set_shader_parameter("progress", value);
