extends Area2D;
class_name Interactable;

@export var prompt_text: String = "prompt_interact";
@export var interact_priority: int = 0; #higher = preferred

#Set up the state of the interactable
func _ready() -> void:
	monitoring = true;
	monitorable = true;

#Called by Player when trying to interact
#func interact(interactor: Node) -> void:
	##Intentionally empty--overidden in child scripts
	#pass;
