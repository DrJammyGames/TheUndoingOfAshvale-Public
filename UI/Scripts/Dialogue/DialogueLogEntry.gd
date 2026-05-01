extends HBoxContainer
class_name DialogueLogEntry

#Singular line of dialogue in the encyclopedia
#Speaker name and line text on the same row

@onready var speaker_label: Label = %SpeakerLabel;
@onready var line_label: Label = %LineLabel;

func setup(speaker: String, text: String) -> void:
	speaker_label.text = "%s: " % speaker;
	line_label.text = text;
