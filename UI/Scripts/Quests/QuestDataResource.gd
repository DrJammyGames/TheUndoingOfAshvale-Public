extends Resource
class_name QuestDataResource

#Top-level resource for one quest.


#Unique identifier (e.g. "q_intro").
@export var quest_id: String = "";
@export var xp_reward: int = 0;

@export_group("Prerequisites")
@export var prereq_quests: Array[QuestDataResource] = [];

@export_group("Steps")
@export var steps: Array[QuestStepResource] = [];

#Auto-generates the display name localisation key
func get_name_key() -> String:
	return "quest.%s.name" % quest_id;
	
#Auto-generates the description localisation key
func get_desc_key() -> String:
	return "quest.%s.desc" % quest_id;
	
#Returns prereq quest_ids as strings, resolved from the linked resources
func get_prereq_ids() -> Array[String]:
	var ids: Array[String] = [];
	for req in prereq_quests:
		if req == null or req.quest_id.is_empty():
			continue;
		ids.append(req.quest_id);
	return ids;
