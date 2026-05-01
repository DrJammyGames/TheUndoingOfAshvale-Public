extends Interactable
class_name CraftingTable

func _ready() -> void:
	super._ready();
	#visible = false;
	#process_mode = Node.PROCESS_MODE_DISABLED;

func interact(_interactor: Node = null) -> void:
	UIRouter.show_crafting_menu();
