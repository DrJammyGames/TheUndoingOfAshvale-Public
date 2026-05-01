extends Interactable;
class_name Bed;

func interact(_interactor: Node = null) -> void:
	UIRouter.show_bed_confirm();
