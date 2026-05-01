extends Control
class_name EncyclopediaQuestsPanel

#Displays all completed quests via the existing QuestLogScreen

@export var entry_scene: PackedScene;

@onready var quest_list: VBoxContainer = %QuestList;

func _ready() -> void:
	QuestSystem.quest_completed.connect(_on_quest_completed);
	rebuild();

func rebuild() -> void:
	#Clear existing entries first
	for child in quest_list.get_children():
		child.queue_free();
		
	if entry_scene == null:
		push_warning("EncyclopediaQuestsPanel: entry_scene not set");
		return;
		
	#Safety checks passed
	var all_quests_ids: Array = QuestDatabase.get_all_quests();
	var has_any: bool = false;
	
	for quest_id in all_quests_ids:
		if QuestSystem.get_quest_state(str(quest_id)) != QuestSystem.STATE_COMPLETED:
			continue;
		var entry = entry_scene.instantiate();
		quest_list.add_child(entry);
		entry.setup(str(quest_id));
		has_any = true;
	
	if not has_any:
		var entry = entry_scene.instantiate();
		quest_list.add_child(entry);
		entry.setup_message("No completed quests yet.");
		
func _on_quest_completed(_quest_id: String) -> void:
	rebuild();
