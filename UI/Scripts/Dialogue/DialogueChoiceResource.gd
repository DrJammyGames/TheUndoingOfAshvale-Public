extends Resource
class_name DialogueChoiceResource

#A single choice option presented to the player.
#text_key: matches the localisation CSV 
#go_to_line: the line_name on the parent DialogueResource to jump to when chosen

@export var text_key: String = "";
@export var go_to_line: String = "";
