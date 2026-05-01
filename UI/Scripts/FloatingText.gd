extends Node2D;
#Need to adjust for accessibility

#How far upward the text floats
@export var float_distance: float = 24.0;
@export var lifetime: float = 2.0;
@onready var label: Label = $Label;

#Side to side movement variables
var wobble_amount: float = 0.0;
var wobble_phase: float = 0.0;
var base_position: Vector2;

func _ready() -> void:
	visible = true;
	modulate.a = 1.0;

func setup(text: String, duration: float = -1.0, color: Color = Color.WHITE) -> void:
	if label == null:
		return;
		
	#Set the text and color
	label.text = text;
	label.add_theme_color_override("font_color", color);
	#If caller didn't pass a duration, use exported lifetime
	var d := duration if duration > 0.0 else lifetime;
	
	#Set up the proper position
	await get_tree().process_frame;
	label.position = -label.size * 0.5;
	#Start the float and fade animation
	_play_animation(d);
	
func _play_animation(duration: float = 2.0):
	base_position = position;
	
	#Ensure fully visible at the start
	modulate.a = 1.0;
	#Animate wobble amplitude down over time
	wobble_amount = 4.0;
	#Random start so multiple texts don't sync
	wobble_phase = randf();
	
	#Create the tweens for floating text
	var tween := create_tween();
	tween.set_trans(Tween.TRANS_SINE);
	tween.set_ease(Tween.EASE_OUT);
	#Move up--y only, leave x for the wobble
	tween.tween_property(self, "position:y", base_position.y - float_distance, duration);
	#Fade out in parallel
	tween.parallel().tween_property(self, "modulate:a", 0.0, duration);
	tween.parallel().tween_property(self, "wobble_amount", 0.0, duration);
	
	#Free when done
	tween.finished.connect(func() -> void:
		queue_free()
)

#Applying a side to side wobble
func _process(delta: float) -> void:
	#Calm mode ensure we end centered and unrotated
	if Settings != null and Settings.calm_visual_mode:
		rotation = 0.0;
		position.x = base_position.x;
		return;
		
	if wobble_amount <= 0.0:
		rotation = 0.0;
		position.x = base_position.x;
		return;
	
	#There is wobble--continue with the rocking
	wobble_phase += delta * 8.0; #frequency
	rotation = sin(wobble_phase + 0.7) * deg_to_rad(3.0);
	position.x = base_position.x + sin(wobble_phase) * wobble_amount;
