extends Interactable;

@export var sign_id = "";
@onready var sign_sprite: Sprite2D = %SignSprite;

#Load paths for sign sprites
var blacksmith_sign = preload("res://Entities/Interactables/Sprites/sBlacksmithSign.png");
var town_hall_sign = preload("res://Entities/Interactables/Sprites/sTownHallSign.png");
var alchemist_sign = preload("res://Entities/Interactables/Sprites/sAlchemistSign.png");

func _ready() -> void:
	super._ready();
	match sign_id:
		"blacksmith":
			sign_sprite.texture = blacksmith_sign;
		"town_hall":
			sign_sprite.texture = town_hall_sign;
		"alchemist":
			sign_sprite.texture = alchemist_sign;

func interact(_interactor: Node = null) -> void:
	var title: String = "Notice";
	var body: String = "This place needs to be restored."
	
	UIRouter.show_sign_message(title, body);
	
	#Quest hook
	QuestSystem.notify_event("check_signpost", {"sign_id": sign_id});
