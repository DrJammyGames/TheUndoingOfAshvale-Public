extends Interactable;

@export var note_id = "";
@onready var notification_sprite: AnimatedSprite2D = %NotificationSprite;
var _message_read: bool = false;

func _ready() -> void:
	super._ready();
	#Get state of the read note from GameState and only show notification if it hasn't been read before
	if GameState.read_notes.has(note_id):
		_message_read = true;
	_refresh_visuals();


func interact(_interactor: Node = null) -> void:
	var title: String = ""; #Empty for note message
	var body: String = "The caretaker mentioned they wanted to see you this morning."
	
	UIRouter.show_sign_message(title, body);
	_message_read = true;
	GameState.read_notes[note_id] = true;
	#Ensure the notification sprite goes away
	_refresh_visuals();
	
		
func _refresh_visuals() -> void:
	if notification_sprite == null:
		return;
	
	if _message_read:
		notification_sprite.visible = false;
		notification_sprite.stop();
	else:
		notification_sprite.visible = true;
		notification_sprite.play();
	
