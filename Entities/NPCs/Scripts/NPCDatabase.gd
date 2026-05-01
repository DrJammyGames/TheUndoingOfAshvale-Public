extends Node

#List of NPCs
var _npcs: Dictionary = {} #npc_id (StringName) -> NPCData

func _ready() -> void:
	#Register all NPCs here
	for resource in NPCPreloadRegistry.ALL:
		if resource is NPCData:
			_register_npc(resource);
		else:
			push_warning("NPCDatabase: Non-NPCData entry in registry: %s" % resource.resource_path)
	
func _register_npc(npc: NPCData) -> void:
	#Safety checks
	if npc == null:
		return;
	if npc.id == StringName():
		push_warning("NPC has empty id: %s" % [npc]);
		return;
	if _npcs.has(npc.id):
		push_warning("Duplicate NPC id: %s" % [npc.id]);
		return;
		
	#Safety checks passed
	_npcs[npc.id] = npc;
#region Public helpers
#Check the list has the NPC 
func has_npc(npc_id: StringName) -> bool:
	return _npcs.has(npc_id);
#Get the NPC from the list
func get_npc(npc_id: StringName) -> NPCData:
	return _npcs.get(npc_id, null);
#Gets all the NPCs
func get_all_npcs() -> Array:
	return _npcs.values();
#Get the display name
func get_display_name(npc_id: StringName) -> String:
	var _npc = get_npc(npc_id);
	return _npc.display_name;
#endregion
