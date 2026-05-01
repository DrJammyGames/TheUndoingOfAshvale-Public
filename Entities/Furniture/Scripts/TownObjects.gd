extends Node2D

#Shared script for static town objects (lamp, fountain, etc.)
#Future: decoration mode will use can_be_moved to allow repositioning

@export var can_be_moved: bool = false;

@onready var sprite: AnimatedSprite2D = get_node_or_null("%Sprite");

func _ready() -> void:
	if sprite:
		sprite.play("idle");
