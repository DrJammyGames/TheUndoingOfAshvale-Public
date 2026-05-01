extends Node2D
class_name CameraBounds;

@export var size: Vector2 = Vector2(640, 360);

func get_bounds() -> Rect2:
	#Treat global_position as top_left of bounds
	return Rect2(global_position,size);
