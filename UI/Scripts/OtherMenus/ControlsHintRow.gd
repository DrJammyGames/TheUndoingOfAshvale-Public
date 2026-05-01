extends HBoxContainer
class_name ControlHintRow

@onready var key_label: Label = %KeyLabel
@onready var action_label: Label = %ActionLabel

func setup(key_name: String, action_text: String) -> void:
	key_label.text = "[%s]" % key_name
	action_label.text = action_text
