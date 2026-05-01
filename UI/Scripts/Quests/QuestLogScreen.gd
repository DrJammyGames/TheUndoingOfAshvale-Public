extends Control
class_name QuestLogScreen;

#First quest
@export var entry_scene: PackedScene;

@onready var quest_list: VBoxContainer = %QuestList;

func _ready() -> void:
	
	#Listen to quest changes so the log stays up to date
	if QuestSystem:
		if QuestSystem.has_signal("quest_added"):
			QuestSystem.quest_added.connect(_on_quest_changed);
		if QuestSystem.has_signal("quest_updated"):
			QuestSystem.quest_updated.connect(_on_quest_changed);
	 #Rebuild the quest log
	_rebuild();

#Quest has changed somehow, call the rebuild quest log function
func _on_quest_changed(_quest_id: String) -> void:
	_rebuild();
	
#Rebuild the quest log based on updated information
func _rebuild() -> void:
	#Clear old entries first
	for child in quest_list.get_children():
		child.queue_free();
	
	if entry_scene == null:
		push_warning("QuestLogScreen.entry_scene is not set");
		return;
	
	#Get the current active quests for display
	var active_quests: Array = QuestSystem.get_active_quests();
	#No quests are active--set text as so
	if active_quests.is_empty():
		var entry = entry_scene.instantiate();
		quest_list.add_child(entry);
		entry.setup_message("No quests active.");
		return;
	
	#Safety passed, quest active
	for quest_id in active_quests:
		var quest_id_str: String = String(quest_id);
		
		#This check is technically redundant since active_quests
		#already comes from QuestSystem, but it's harmless safety
		if not QuestSystem.has_quest(quest_id_str):
			continue;
			
		var entry = entry_scene.instantiate();
		quest_list.add_child(entry);
		entry.setup(quest_id_str);
		
