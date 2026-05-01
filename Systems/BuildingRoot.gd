extends Node2D
class_name BuildingRoot;

#Controls a building's visual stage by toggling overlay nodes
#Scalable--each building is self-contained and listens to quest progress and refreshes its stage

#Configuration
@export var building_id: String = ""; #e.g., town_hall
#Name of the child node that contains stage overlays
@export var stages_container_path: NodePath = NodePath("Stages");
#Name of the quest that will trigger it being repaired
@export var repair_quest_id: String = "";
#FocusMarket
@export var focus_point_path: NodePath = NodePath("FocusPoint");
#FX exports
@export var fx_root_path: NodePath = NodePath("FX");
@export var fx_particles_path: NodePath = NodePath("Particles");

#In script references
var _fx_root: CanvasItem = null;
var _fx_particles: GPUParticles2D = null;
#For multiple stages (example)
#Stage 0: default (no quest needed)
#Stage 1: unlock when q_townhall_patch completed
#Stage 2: unlock when q_townhall_upgrade completed
@export var stage_unlock_quest_ids: Array[String] = [];
#Debug
@export var debug_building_focus: bool = false;
var quest_system = QuestSystem;
#Internal variables
var _stages_container: Node = null;
var _stage_nodes: Array[Node] = [];
var _current_stage_index: int = -1;

#region Shader variables
@export_group("Stage Transition FX")
@export var stage_transition_enabled: bool = true;
@export var stage_transition_duration: float = 1.5;

@export var debug_stage_transition: bool = false;
@export var stage_visual_path: NodePath = NodePath("Base");
var _transition_tween: Tween = null;
#endregion

func _ready() -> void:
	_cache_stage_nodes();
	_cache_fx_nodes();
	_connect_to_quest_signals();
	refresh_stage(); #Ensure visuals load
	#Ensure FX hides on load if building isn't upgraded yet
	_apply_fx_for_stage(0);
	_init_harvestables();
	add_to_group("buildings");
	
#region Public helpers
func refresh_stage() -> void:
	#Compute the correct stage from quest completion and apply relevant visibility
	var desired_stage = _compute_desired_stage();
	_apply_stage(desired_stage);
	
func set_stage(stage_index: int) -> void:
	#Manual override
	_apply_stage(stage_index);
	
func get_focus_world_position() -> Vector2:
	var fp = get_node_or_null(focus_point_path) as Node2D;
	var p = (fp.global_position if fp != null else global_position);
	
	return p;
	
func play_upgrade_to_stage(stage_index: int) -> void:
	_apply_stage(stage_index);
#endregion
#region Internal helpers
#Computing what stage the building is on
func _compute_desired_stage() -> int:
	#If stage_unlock_quest_ids is provided, us it (multi-stage)
	#Else, fall back to a simple 2-stage model using repair_quest_id
	
	if stage_unlock_quest_ids.size() > 0:
		return _compute_multi_stage_from_quests();
		
	#Simple 2 stage model
	if _is_quest_completed(repair_quest_id):
		return 1;
	return 0;
	
#Function for computing the stage if there are multiple steps/stages
func _compute_multi_stage_from_quests() -> int:
	#Returns the highest stage whose unlock quest is completed
	#stage_unlock_quest_ids[0] can be "" to represent default stage
	var best_stage: int = 0;
	
	#If your stages list is shorter than your unlock list, clamp later in _apply_stage
	for i in range(stage_unlock_quest_ids.size()):
		var quest_id: String = stage_unlock_quest_ids[i];
		if quest_id == "":
			#Default stage, always available
			best_stage = max(best_stage, i);
			continue;
			
		if _is_quest_completed(quest_id):
			best_stage = max(best_stage, i);
	return best_stage;
	
func _apply_stage(stage_index: int) -> void:
	if _stage_nodes.size() == 0:
		return;
		
	var new_index: int = clamp(stage_index, 0, _stage_nodes.size() - 1);
	
	#If we don't know current stage, assume 0
	if _current_stage_index == -1:
		_current_stage_index = 0;
		
	if new_index == _current_stage_index:
		return;
		
	var old_index := _current_stage_index;
	_current_stage_index = new_index;
	#Get rid of any existing harvestables the player didn't clear
	_clear_remaining_harvestables();
	#Stop any existing transition tween
	if _transition_tween and _transition_tween.is_valid():
		_transition_tween.kill();
	_transition_tween = null;
	
	#If FX disabled, instant
	if not stage_transition_enabled:
		_apply_stage_instant(new_index);
		return;
	#For now: ONLY support fading Stage_0 out to reveal the finished Base underneath.
	#(Assumes your finished building is a sibling "Base" outside Stages.)
	if old_index == 0 and new_index == 1:
		var old_stage := _stage_nodes[0]; #Stage_0
		var old_ci := old_stage.get_node_or_null(stage_visual_path) as CanvasItem; #Stage_0/Base (TileMapLayer)
		
		if old_ci == null:
			push_warning("[BuildingRoot] Stage_0 Base not found for fade.");
			_apply_stage_instant(new_index);
			return;
			
		#Grab shader material to tween only if present
		var shader_mat = old_ci.material as ShaderMaterial;
			
		#Ensure Stage_0 is visible and starts fully opaque
		if old_stage is CanvasItem:
			(old_stage as CanvasItem).visible = true;
		old_ci.visible = true;
		old_ci.modulate.a = 1.0;
		
		#Start shader at 0 if it exists
		if shader_mat != null:
			shader_mat.set_shader_parameter("progress", 0.0);
		
		_transition_tween = create_tween();
		_transition_tween.set_trans(Tween.TRANS_SINE);
		_transition_tween.set_ease(Tween.EASE_IN_OUT);
		
		#Fade alpha + tween shader progress in parallel
		_transition_tween.parallel().tween_property(old_ci, "modulate:a", 0.0, stage_transition_duration);
		
		if shader_mat != null:
			_transition_tween.parallel().tween_method(
				func(v: float) -> void:
					#Guard in case something killed or changed the material mid-tween
					if shader_mat != null:
						shader_mat.set_shader_parameter("progress", v),
					0.0, 1.0, stage_transition_duration
			);
			
		_transition_tween.tween_callback(func() -> void:
			#Hide Stage_0 completely once faded (so it stops drawing / colliding if relevant)
			if old_stage is CanvasItem:
				(old_stage as CanvasItem).visible = false
				
			#Reset alpha so if you ever re-show Stage_0 later it isn't stuck transparent
			old_ci.modulate.a = 1.0
			#Reset shader progress for next time
			if shader_mat != null:
				shader_mat.set_shader_parameter("progress", 0.0);
			#Start the smoke plume and such when the tween finishes
			_apply_fx_for_stage(new_index);
		)
		
		return;
	#Anything else for now: keep it simple / instant
	_apply_stage_instant(new_index)
	
#Apply the VFX for the proper stage
func _apply_fx_for_stage(stage_index: int) -> void:
	#Stage_0 FX is off
	#Stage_1 FX is on
	var should_show: bool = stage_index >= 1;
	
	#FX is a Node2D, so using visible works
	if _fx_root != null:
		_fx_root.visible = should_show;
	#Stop simulation so it isn't running while hidden
	if _fx_particles != null:
		_fx_particles.emitting = should_show;
		
#Instantly apply, no tween
func _apply_stage_instant(new_index: int) -> void:
	push_warning("Had to instantly apply stage.");
	for i in range(_stage_nodes.size()):
		var stage := _stage_nodes[i];
		if stage is CanvasItem:
			(stage as CanvasItem).visible = (i == new_index);
			
		var ci := (stage as Node).get_node_or_null(stage_visual_path) as CanvasItem;
		if ci != null:
			ci.modulate.a = 1.0;
		_apply_fx_for_stage(new_index);
		
#Setup helpers
func _cache_stage_nodes() -> void:
	_stages_container = get_node_or_null(stages_container_path);
	_stage_nodes.clear();
	
	if _stages_container == null:
		push_warning("BuildingRoot '%s': Stages container not found at path: %s" % [name, stages_container_path]);
		return;
		
	for child in _stages_container.get_children():
		_stage_nodes.append(child);
		
	#Default initial: Stage_0 visible, others hidden
	for i in range(_stage_nodes.size()):
		var stage := _stage_nodes[i];
		if stage is CanvasItem:
			(stage as CanvasItem).visible = (i == 0);
			
	_current_stage_index = 0;
	
func _cache_fx_nodes() -> void:
	_fx_root = get_node_or_null(fx_root_path) as CanvasItem;
	if _fx_root == null:
		return;
		
	_fx_particles = _fx_root.get_node_or_null(fx_particles_path) as GPUParticles2D;
	
#Harvestables persistence
func _init_harvestables() -> void:
	if building_id.is_empty():
		return;
	if _stage_nodes.is_empty():
		return;
		
	#Harvestables live under Stage_0 only
	var stage0: Node = _stage_nodes[0];
	
	for child in stage0.get_children():
		var node = child as HarvestableNode;
		if node == null:
			continue;
		
		var flag_key = _harvestable_flag_key(node.name);
		
		if WorldFlags.has_flag(flag_key):
			#Already destroyed in a previous session, don't recreate
			node.queue_free();
		else:
			#Still alive, listen for destruction
			node.destroyed.connect(_on_building_harvestable_destroyed.bind(node.name));
	
func _on_building_harvestable_destroyed(_emitted_name: String, node_name: String) -> void:
	WorldFlags.set_flag(_harvestable_flag_key(node_name));
	
func _harvestable_flag_key(node_name: StringName) -> StringName:
	return &"building_harvestable:" + building_id + ":" + node_name;
	
func _clear_remaining_harvestables() -> void:
	if building_id.is_empty():
		return;
	if _stage_nodes.is_empty():
		return;
		
	var stage0: Node = _stage_nodes[0];
	
	for child in stage0.get_children():
		var node = child as HarvestableNode;
		if node == null:
			continue;
			
		#Write the flag so it stays gone on reload
		WorldFlags.set_flag(_harvestable_flag_key(node.name));
		node.queue_free();
#region Quest calls
func _connect_to_quest_signals() -> void:
	#Listen to quest completion updates so buildings just update themselves
	#Connect to UIRouter 
	if UIRouter == null:
		return;
		
	#Connects specifically to the quest banner finishing, not the quest, as the banner needs to finish
	var complete = UIRouter.quest_completion_ui_finished;
	if not complete.is_connected(_on_quest_completion_ui_finished):
		complete.connect(_on_quest_completion_ui_finished);

func _on_quest_completion_ui_finished(quest_id: String) -> void:
	if _quest_id_affects_building(quest_id):
		refresh_stage();
	
func _quest_id_affects_building(quest_id: String) -> bool:
	#Multi-stage quest list
	if stage_unlock_quest_ids.size() > 0:
		return stage_unlock_quest_ids.has(quest_id);
	#Simple 2 stage quest
	return quest_id == repair_quest_id;
	
func _is_quest_completed(quest_id: String) -> bool:
	if quest_id == "":
		return false;
		
	#Use the public calls from QuestSystem autoload
	return QuestSystem.is_quest_completed(quest_id);
#endregion
#endregion
