extends HBoxContainer
class_name QuestSummaryRow

@onready var name_label: Label = %NameLabel

func setup(quest_id: String) -> void:
	name_label.text = "-" + QuestDatabase.get_display_name(quest_id);
