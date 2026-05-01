extends Node
class_name InteractionSystem;

signal focus_changed(new_target, old_target);

var _player: Node2D = null;
var _interaction_area: Area2D = null;

var _current_focus: Interactable = null;

func setup(player: Node2D, interaction_area: Area2D) -> void:
	_player = player;
	_interaction_area = interaction_area;
	
func get_focused() -> Interactable:
	return _current_focus;

func refresh_focus() -> void:
	var old := _current_focus;
	_current_focus = _find_best_candidate();
	if _current_focus != old:
		focus_changed.emit(_current_focus, old);

func interact_best() -> void:
	refresh_focus();
	if _current_focus == null:
		return;
	#Need the method check here to ensure no crashes when trying to interact with something
	#that is not interactable
	if _current_focus.has_method("interact"):
		_current_focus.interact(_player);

#Public helpers for when the player enters and exits the interaction range
func on_interactable_entered() -> void:
	refresh_focus();
	
func on_interactable_exited() -> void:
	refresh_focus();
	
func _find_best_candidate() -> Interactable:
	if _player == null or _interaction_area == null:
		return null;
		
	_interaction_area.monitoring = true;
	var areas := _interaction_area.get_overlapping_areas();
	
	var best: Interactable = null;
	var best_score: float = INF;
	
	for a in areas:
		if a == null:
			continue;
			
		var candidate := _find_interactable_owner(a);
		if candidate == null:
			continue;
			
		#Distance score (closest wins)
		var cpos: Vector2 = (candidate as Node2D).global_position;
		var d: float = _player.global_position.distance_to(cpos);
		
			
		#Priority bias (higher priority should win)
		#Convert priority into a negative bonus so higher priority lowers score.
		var prio: int = candidate.interact_priority;
		
		var score := d - float(prio) * 1000.0;
		
		if score < best_score:
			best_score = score;
			best = candidate;
			
	return best;

func _find_interactable_owner(node: Node) -> Interactable:
	var cur := node;
	while cur != null:
		if cur is Interactable:
			return cur as Interactable;
		cur = cur.get_parent();
	return null;
