extends Interactable
class_name NPCInteractable

@export var npc_path: NodePath
var _npc: NPC = null;

func _ready() -> void:
	super._ready();

	# Resolve NPC reference
	if npc_path != NodePath():
		_npc = get_node_or_null(npc_path) as NPC
	if _npc == null:
		#Sensible default: parent is the NPC
		_npc = get_parent() as NPC;

func interact(interactor: Node = null) -> void:
	if _npc == null:
		push_warning("NPCInteractable: NPC reference not set")
		return;
	_npc.interact(interactor);
