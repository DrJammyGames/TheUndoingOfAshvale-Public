extends Interactable

#Small chest world object opened by player interaction
#Placed and moved via decoration mode

@onready var sprite: AnimatedSprite2D = %Sprite;

#Whether the chest is currently open and UI is showing
var _is_open: bool = false;

func _ready() -> void:
	super._ready();
	add_to_group("placed_furniture");
	sprite.play("idle");
	
func interact(_interactor: Node = null) -> void:
	if _is_open:
		return;
	_open_chest();
	
func _open_chest() -> void:
	_is_open = true;
	AudioManager.play_sfx("chest_open");
	sprite.play("open");
	UIRouter.show_chest_ui();
	#Listen for the chest UI closing so we can reset state
	UIRouter.chest_ui_closed.connect(_on_chest_ui_closed, CONNECT_ONE_SHOT);
	
func _on_chest_ui_closed() -> void:
	_is_open = false;
	sprite.play_backwards("open");
	AudioManager.play_sfx("chest_close");
	#Wait for the closing animation to play, then stay idle
	await sprite.animation_finished;
	sprite.play("idle");
