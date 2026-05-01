extends HoverButton;
class_name ChoiceButton;

@onready var choice_text: Label = $ChoiceText;

func _ready() -> void:
	#Ensure it inherits the hover button script
	super._ready();

func set_choice_text(value: String) -> void:
	choice_text.text = value;
