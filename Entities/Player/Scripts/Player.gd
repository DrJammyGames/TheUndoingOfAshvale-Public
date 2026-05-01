extends CharacterBody2D
class_name Player;
#Player controller:
#Movement and facing, interact and tool use, animation selection
#region Signals
signal death_animation_finished;
signal equipped_weapon_changed(item_id: String);
signal equipped_tool_changed(item_id: String);
signal scripted_walk_finished;
#endregion
#region Variable declarations
#region Enums
#Various player states for reference
enum PlayerState {
	IDLE,
	WALK,
	MELEE_ATTACK, #Also used for tool use
	HURT,
	DEATH,
	ITEM_GET, 
};
#What kind of tool is equipped 
enum ToolKind {
	NONE,
	SWORD,
	AXE,
	HOE,
	PICKAXE,
	WATERING_CAN,
}
#endregion
#region Constants
#Direction -> name mapping for animation suffixes
const DIR_DOWN := Vector2(0,1);
const DIR_UP := Vector2(0,-1);
const DIR_LEFT := Vector2(-1,0);
const DIR_RIGHT := Vector2(1,0);

#Which frame is the "hit" frame for the equipped tool
#Must match the exact name in the animationsprite2d
const ATTACK_HIT_FRAMES: Dictionary = {
	"axe_down": 3,
	"axe_left": 3,
	"axe_right": 3,
	"axe_up": 3,
	"pickaxe_down": 3,
	"pickaxe_left": 3,
	"pickaxe_right": 3,
	"pickaxe_up": 3,
	"melee_attack_down": 2,
	"melee_attack_left": 2,
	"melee_attack_right": 2,
	"melee_attack_up": 2,
};
#endregion
#region Exported properties
@export var stats: PlayerStats;
#Base move speed comes from stats, otherwise fall to this
@export var fallback_move_speed: float = 120.0;
#Fallback anim suffic when no item-specific animations exist
@export var default_tool_anim_suffix: String = "idle";
#endregion

#region Node references
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D;
#Cached reference to the interaction area
@onready var interaction_area: Area2D = $InteractionArea;
#Deterministic "in front" targeting
@onready var use_ray: RayCast2D = $UseRay;
#Add the interaction system
@onready var interaction_system: InteractionSystem = $InteractionSystem;
#Navigation for player
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D;
#endregion
#region State
#Runtime state
var state: PlayerState = PlayerState.IDLE;
var facing_dir: Vector2 = Vector2.DOWN; #Default facing down

#Current weapon equipped--later expand for other weapon types
var _equipped_weapon_id: String = ""; 
#Last used tool so it saves in the hud
var _last_used_tool_id: String = "";
#Which specific item (by item_id) is currently equipped for each tool kind
var _equipped_tools: Dictionary = {
	ToolKind.HOE: "",
	ToolKind.AXE: "",
	ToolKind.PICKAXE: "",
	ToolKind.SWORD: "",
}

#Hurt variables
var hurt_duration: float = 0.3;
var _hurt_timer: float = 0.0;
#Knockback velocity applied when taking damage
var _knockback_velocity: Vector2 = Vector2.ZERO;
#How quickly knockback slows down each second
var knockback_decay: float = 10.0; #Higher = stops faster
#Get the correct string for the using tool method
var _current_attack_method_name: String = "";
#Scripted walk state used by cutscenes
var _scripted_walk_active: bool = false;
#endregion
#endregion

func _ready() -> void:
	#Connect to stats signals 
	if stats:
		if not stats.died.is_connected(_on_stats_died):
			stats.died.connect(_on_stats_died);
	#When any animation finished, this signal fires
	#Use it to exit MELEE_ATTACK state
	if anim:
		anim.animation_finished.connect(_on_anim_finished);
	
	#Connect animation frame change signal so we know when a swing reaches impact frame
	if anim != null and not anim.frame_changed.is_connected(_on_anim_frame_changed):
		anim.frame_changed.connect(_on_anim_frame_changed);
	#Interaction system
	if interaction_system != null:
		interaction_system.setup(self, interaction_area);
		interaction_area.area_entered.connect(_on_interaction_area_entered);
		interaction_area.area_exited.connect(_on_interaction_area_exited);
	#Restore equipped weapon from GameState if available
	var saved_weapon: String = GameState.get_flag("equipped_weapon_id", "");
	if not saved_weapon.is_empty():
		_equipped_weapon_id = saved_weapon;
	#Auto-equip the first tool received so HUD isn't blan
	InventorySystem.first_time_item_acquired.connect(_on_first_time_item_acquired);
	#Initial animation state--defer the call so the AnimatedSprite2D is loaded and fully ready
	call_deferred("_update_animation");
	#Initial ray direction state
	_update_use_ray_direction();

#Handle movement every physics frame
func _physics_process(delta: float) -> void:
	#Game input is locked, no movement allowed
	if Game and Game.is_input_locked():
		if _scripted_walk_active:
			_process_scripted_walk();
		else:
			velocity = Vector2.ZERO;
		move_and_slide();
		return;
	#Stop movement if dialogue is active
	if DialogueSystem.is_active():
		velocity = Vector2.ZERO;
		state = PlayerState.IDLE;
		_update_animation(); #Switch to idle
		move_and_slide();
		return;
	#Death state--lock movement, just keep animation playing
	if state == PlayerState.DEATH:
		velocity = Vector2.ZERO;
		move_and_slide();
		_update_animation();
		return;
	#Hurt state--lock movement while timer is active
	if state == PlayerState.HURT:
		_hurt_timer -= delta;
		#Apply knockback decelaration
		if _knockback_velocity.length() > 0.0:
			#Move knockback velocity towards zero over time
			var decay_amount: float = knockback_decay * delta;
			_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, decay_amount);
		velocity = _knockback_velocity;
		move_and_slide();
		_update_animation();
		if _hurt_timer > 0.0:
			return;
		else:
			#Hurt timer finished, recover back to normal flow
			_knockback_velocity = Vector2.ZERO;
			state = PlayerState.IDLE;
	
	#Item-get cinematic state-no movement, just play post
	if state == PlayerState.ITEM_GET:
		velocity = Vector2.ZERO;
		move_and_slide();
		_update_animation();
		return;
	#Lock movement if attacking
	if state == PlayerState.MELEE_ATTACK:
		velocity = Vector2.ZERO;
		move_and_slide();
		_update_animation();
		return;
	#Movement--not attacking
	#1 get input vector in a clean way using Godot's helper
	var input_vec := Input.get_vector("move_left","move_right","move_up","move_down");
	#2 Decide movement and state based on input
	if input_vec.length() > 0.0:
		#Normalise to avoid faster diaganol movement
		input_vec = input_vec.normalized();
		velocity = input_vec * _get_move_speed();
		state = PlayerState.WALK;
		facing_dir = _snap_direction(input_vec);
	else:
		velocity = Vector2.ZERO;
		#Don't override attack info, only idle if not attacking
		if state != PlayerState.MELEE_ATTACK:
			state = PlayerState.IDLE;
	#3 Move the character with collision
	move_and_slide();
	#4 Update direction 
	_update_use_ray_direction();
	#5 Update animation based on new state and direction
	_update_animation();
	
#Handle interaction input here
func _unhandled_input(event: InputEvent) -> void:
	#Game says input is locked
	if Game and Game.is_input_locked():
		return;
	#Is a menu open
	if UIRouter.is_modal_open():
		return;
	#Is the dialogue system active
	if DialogueSystem.is_active():
		return;

	#Safety checks passed, can move
	if event.is_action_pressed("interact"):
		_try_interact();
		get_viewport().set_input_as_handled();
		return;
	#Attack key set as X
	if event.is_action_pressed("attack"):
		_handle_attack_action();
		get_viewport().set_input_as_handled();
		return;
	#Use tool
	if event.is_action_pressed("use_tool"):
		_handle_use_tool_action();
		get_viewport().set_input_as_handled();
		return;
		
#Restore the player's state on scene load
func restore_state() -> void:
	var saved_weapon: String = GameState.get_flag("equipped_weapon_id", "");
	if not saved_weapon.is_empty() and saved_weapon != _equipped_weapon_id:
		_equipped_weapon_id = saved_weapon;
		equipped_weapon_changed.emit(_equipped_weapon_id);
	var saved_tool: String = GameState.get_flag("last_used_tool_id", "");
	if not saved_tool.is_empty() and saved_tool != _last_used_tool_id:
		_last_used_tool_id = saved_tool;
		equipped_tool_changed.emit(_last_used_tool_id);
	if not GameState.player_stats.is_empty() and stats != null:
		stats.from_dict(GameState.player_stats);
#region Movement
func _get_move_speed() -> float:
	if stats:
		return stats.base_move_speed;
	#If nothing in stats, use fallback
	return fallback_move_speed;

#Snaps a general vector to the closest cardinal direction
#Helps keep animation clean even if diaganol
func _snap_direction(vec: Vector2) -> Vector2:
	if abs(vec.x) > abs(vec.y):
		#Horizontal dominates
		return DIR_RIGHT if vec.x > 0.0 else DIR_LEFT;
	else:
		#Vertical dominates
		return DIR_DOWN if vec.y > 0.0 else DIR_UP;

#Keeps RayCast2D pointing in the facing direction
func _update_use_ray_direction() -> void:
	if use_ray == null:
		return;
		
	var dist: float = 32.0;
	var offset = Vector2.ZERO;
	if facing_dir == DIR_UP:
		offset = Vector2(0, -dist);
	elif facing_dir == DIR_DOWN:
		offset = Vector2(0, dist);
	elif facing_dir == DIR_LEFT:
		offset = Vector2(-dist, 0);
	elif facing_dir == DIR_RIGHT:
		offset = Vector2(dist, 0);
		
	#Point the ray cast
	use_ray.target_position = offset;
	#Move the interaction_area to the same offset (local space)
	if interaction_area != null:
		interaction_area.position = offset;
		
#Function for player movement during cutscenes
func _process_scripted_walk() -> void:
	if nav_agent.is_navigation_finished():
		velocity = Vector2.ZERO;
		_scripted_walk_active = false;
		state = PlayerState.IDLE;
		_update_animation();
		scripted_walk_finished.emit();
		return;
	
	var next_pos = nav_agent.get_next_path_position();
	var dir = (next_pos - global_position).normalized();
	velocity = dir * _get_move_speed();
	facing_dir = _snap_direction(dir);
	state = PlayerState.WALK;
	_update_animation();
	
#Public function for cinematic calls
func walk_to(target_pos: Vector2) -> void:
	if nav_agent == null:
		push_warning("Player: walk_to called by NavigationAgent2D is missing.")
		return;
	#Safety check passed
	nav_agent.target_position = target_pos;
	_scripted_walk_active = true;
#endregion
#region Interactions
#Called when the player presses the interact button
#Look for any overlapping interactables in the InteractionArea
#Also what's ahead of player using raycast
#call their interact() method if they have one
func _try_interact() -> void:
	#Don't interact with world while any UI signal is open
	if UIRouter.is_modal_open():
		return;
	var hud = UIRouter.get_hud();
	if hud != null and hud.is_sign_open():
		return;
		
	if interaction_system == null:
		return;
	interaction_system.interact_best();
		
func _get_front_target() -> Node:
	if use_ray == null or not use_ray.is_colliding():
		return null;
		
	var collider := use_ray.get_collider();
	#Ray may hit a CollisionObject2D
	return collider as Node;
	
func _can_interact(node: Node) -> bool:
	return node is Interactable or node.has_method("interact");

#Connections for entering and exiting interaction area
func _on_interaction_area_entered(area: Area2D) -> void:
	if area is Interactable or area.get_parent() is Interactable:
		if not area.prompt_text.is_empty():
			interaction_system.on_interactable_entered();
		
func _on_interaction_area_exited(area: Area2D) -> void:
	if area is Interactable or area.get_parent() is Interactable:
		if not area.prompt_text.is_empty():
			interaction_system.on_interactable_exited();
#endregion
#region Combat
#Select correct animation and such based on tool
func _handle_attack_action() -> void:
	#No weapon equipped--nothing to do
	if _equipped_weapon_id.is_empty():
		return;
	_current_attack_method_name = "";
	_start_melee_attack();
			
func _start_melee_attack() -> void:
	#Don't restart the attack if we're already attacking
	if state == PlayerState.MELEE_ATTACK:
		return;
	#Enter the attack state
	state = PlayerState.MELEE_ATTACK;
	#Stop moving during attack
	velocity = Vector2.ZERO;
	#Play SFX
	AudioManager.play_sfx("swing_sword");
	#Play proper animation
	_update_animation();

func _perform_melee_attack_hit_in_front() -> void:
	#Prefer whatever is directly in front via the ray
	var raw_target = _get_front_target();
	if raw_target:
		#Build a small list of candidates: collider + its parent
		var candidates: Array = [raw_target];
		if raw_target is Node:
			var parent = raw_target.get_parent();
			if parent != null:
				candidates.append(parent);
		for candidate in candidates:
			if candidate != null and candidate.has_method("take_damage"):
				if _apply_melee_damage_to_target(candidate):
					return;
		
	#Fallback to overlap scan in the interaction area
	if interaction_area == null:
		return;
		
	for body in interaction_area.get_overlapping_bodies():
		if body == null:
			continue;
		#Directly damage the area if possible
		if body.has_method("take_damage"):
			if _apply_melee_damage_to_target(body):
				return;
	#Also check overlapping areas (for any area-based hurtboxes you might add later)
	for area in interaction_area.get_overlapping_areas():
		if area == null:
			continue;
		if area.has_method("take_damage"):
			if _apply_melee_damage_to_target(area):
				return;
				
		var parent = area.get_parent();
		if parent != null and parent.has_method("take_damage"):
			_apply_melee_damage_to_target(parent);
	
	#No enemy found--check for sword-type harvestables like grass
	var harvestable = _find_sword_harvestable_in_front();
	if harvestable != null:
		harvestable.on_sword_used(self);

func _find_sword_harvestable_in_front() -> HarvestableNode:
	#Raycaset check first
	var target = _get_front_target();
	if target != null:
		var h = _extract_harvestable(target);
		if h != null:
			return h;
	#Overlap fallback
	if interaction_area == null:
		return null;
	for area in interaction_area.get_overlapping_areas():
		var h = _extract_harvestable(area);
		if h != null:
			return h;
	return null;
	
func _extract_harvestable(node: Node) -> HarvestableNode:
	if node is HarvestableNode:
		return node;
	if node.get_parent() is HarvestableNode:
		return node.get_parent();
	return null;
				
#Actually apply the damage to the target
func _apply_melee_damage_to_target(target: Node) -> bool:
	if not target or not target.has_method("take_damage"):
		return false;
	var damage: int = _get_melee_attack_damage();
	
	var dir: Vector2 = Vector2.ZERO;
	if target is Node2D:
		#Knock enemy away from player
		dir = (target.global_position - global_position);
	var knockback_force: float = 120.0;
	
	target.call("take_damage", damage, dir, knockback_force);
	#Play hit enemy SFX
	AudioManager.play_sfx("sword_hit");
	Analytics.log_event("player_melee_hit", {
		"enemy_type": target.get("enemy_id"),
		"damage": damage,
		"weapon": _equipped_weapon_id,
		"scene": Analytics.get_scene_path(),
	})
	return true;
#How much damage the melee attack does
func _get_melee_attack_damage() -> int:
	if stats:
		return max(1, stats.attack);
	return 1;
#endregion
#region Tools
#When a tool-type item is first acquired and the HUD is empty, auto-equip it
func _on_first_time_item_acquired(item_id: String, _amount: int) -> void:
	if not _last_used_tool_id.is_empty():
		return;
	if not ItemDatabase.is_tool(item_id):
		return;
	#Ignore weapons (swords) those go into the weapon slot
	if ItemDatabase.get_tool_category(item_id) == ItemDataResource.ToolCategory.SWORD:
		return;
	_last_used_tool_id = item_id;
	GameState.set_flag("last_used_tool_id", item_id);
	equipped_tool_changed.emit(_last_used_tool_id);
	
func _handle_use_tool_action() -> void:
	var hud = UIRouter.get_hud();
	#Can't use tools at night
	if DayNightSystem.is_night():
		if hud:
			hud.show_message(
				UIStringsDatabase.get_text("night_tool_attempt"), 3.0,
				global_position - Vector2(16,16)
			);
		return;
		
	if state == PlayerState.MELEE_ATTACK:
		return;
	#Get the best tool for the harvestable in front of player
	var tool_id = _resolve_best_tool_for_harvestable();
	if tool_id.is_empty():
		#No matching tool found
		if hud:
			hud.show_message(UIStringsDatabase.get_text("nothing_to_harvest"), 2.0,
			global_position - Vector2(16,16)
		);
		return;
		
	#Map item_id to the method name HarvestableNode expects
	var method_name = _tool_id_to_method(tool_id);
	if method_name.is_empty():
		return;
		
	#Safety checks passed, perform tool action
	_start_tool_swing(method_name);
	
	#Update last used tool and notify HUD icon
	if _last_used_tool_id != tool_id:
		_last_used_tool_id = tool_id;
		GameState.set_flag("last_used_tool_id", tool_id);
		equipped_tool_changed.emit(_last_used_tool_id);
		
#Get the correct tool for the harvestable
func _resolve_best_tool_for_harvestable() -> String:
	#Find the harvestable with raycast first, Area2D fallback
	var target = _get_front_target();
	var harvestable: HarvestableNode = null;
	
	if target != null:
		if target is HarvestableNode:
			harvestable = target;
		elif target.get_parent() is HarvestableNode:
			harvestable = target.get_parent();
			
	if harvestable == null and interaction_area != null:
		for area in interaction_area.get_overlapping_areas():
			if area is HarvestableNode:
				harvestable = area;
				break;
			if area.get_parent() is HarvestableNode:
				harvestable = area.get_parent();
				break;
				
	if harvestable == null:
		return "";
		
	#Ask the database what tool this harvestable requires (set as export in HarvestableDataResource)
	var required = HarvestableDatabase.get_required_tool(harvestable.harvest_id);
	
	#Map the required tool enum to an item_id category to check in inventory
	var needed_category: int = _required_tool_to_item_category(required);
	if needed_category < 0:
		return "";
		
	#Find the best matching tool the player has
	var best_id: String = "";
	var best_power: int = -1;
	#Find the first matching item the player actually has
	for item_id in InventorySystem.get_items().keys():
		if InventorySystem.get_amount(item_id) <= 0:
			continue;
		if ItemDatabase.get_tool_category(item_id) == (needed_category as ItemDataResource.ToolCategory):
			var power: int = ItemDatabase.get_tool_base_power(item_id);
			if power > best_power:
				best_power = power;
				best_id = item_id;
		
	return best_id;
	
#Get the correct tool
func _required_tool_to_item_category(required: int) -> int:
	match required:
		HarvestableDataResource.RequiredTool.AXE:
			return ItemDataResource.ToolCategory.AXE;
		HarvestableDataResource.RequiredTool.PICKAXE:
			return ItemDataResource.ToolCategory.PICKAXE;
		HarvestableDataResource.RequiredTool.HOE:
			return ItemDataResource.ToolCategory.HOE;
		HarvestableDataResource.RequiredTool.NONE:
			#None means any tool is allowed
			return ItemDataResource.ToolCategory.NONE;
		_:
			return -1;
			
func _tool_id_to_method(item_id: String) -> String:
	var category = ItemDatabase.get_tool_category(item_id);
	match category:
		ItemDataResource.ToolCategory.AXE:
			return "on_axe_used";
		ItemDataResource.ToolCategory.PICKAXE:
			return "on_pickaxe_used";
		ItemDataResource.ToolCategory.HOE:
			return "on_hoe_used";
		_:
			return "";
			
func _start_tool_swing(method_name: String) -> void:
	if state == PlayerState.MELEE_ATTACK:
		return;
	state = PlayerState.MELEE_ATTACK;
	velocity = Vector2.ZERO;
	_current_attack_method_name = method_name;
	_update_animation();
	
#Generic tool helper: look in the interaction area and call a method
#on the first thing 
func _perform_tool_action_in_front(method_name: String) -> void:
	if method_name.is_empty():
		return;
		
	#Prefer front target (using the raycast)
	var target = _get_front_target();
	if target != null:
		_call_tool_method_on_target(target, method_name);
		return;
		
	#Fallback to overlap scan
	if interaction_area == null:
		return;
		
	for area in interaction_area.get_overlapping_areas():
		if area == null:
			continue;
		if _call_tool_method_on_target(area, method_name):
			return;
		var parent := area.get_parent();
		if parent != null and _call_tool_method_on_target(parent, method_name):
			return;
			
func _call_tool_method_on_target(node: Node, method_name: String) -> bool:
	if node.has_method(method_name):
		node.call(method_name, self);
		return true;
	#Otherwise, something wrong, just return false
	return false;

#Public helper called from weapon slot UI
func set_equipped_weapon(item_id: String) -> void:
	_equipped_weapon_id = item_id;
	GameState.set_flag("equipped_weapon_id", item_id);
	equipped_weapon_changed.emit(_equipped_weapon_id);
	_update_animation();
	
func get_equipped_weapon_id() -> String:
	return _equipped_weapon_id;
	
func get_last_used_tool_id() -> String:
	return _last_used_tool_id;
	
#Called from inventory when a tool is explictly equipped to a slot
func equip_tool(tool_kind: ToolKind, item_id: String) -> void:
	_equipped_tools[tool_kind] = item_id;
	
#Public helper to return the item id of the currently held tool
func get_equipped_tool_item_id(tool_kind: ToolKind) -> String:
	#Returns the item_id for the equipped tool
	if _equipped_tools.has(tool_kind):
		return String(_equipped_tools[tool_kind]);
	return "";
	
#Public function for tool damage
func get_tool_damage(tool_id: String = "") -> int:
	var id = tool_id;
	if id.is_empty():
		id = _last_used_tool_id;
	var dmg: int = ItemDatabase.get_tool_base_power(id);
	return max(1, dmg); #Returns 1 as default if something goes wrong

#Get the kind of tool the player is holding
func _get_tool_kind() -> ToolKind:
	#If we're mid tool-swing, use the tool being swung, not the weapon
	if not _current_attack_method_name.is_empty():
		if _last_used_tool_id.is_empty():
			return ToolKind.NONE;
		var category = ItemDatabase.get_tool_category(_last_used_tool_id);
		match category:
			ItemDataResource.ToolCategory.AXE:
				return ToolKind.AXE
			ItemDataResource.ToolCategory.HOE:
				return ToolKind.HOE
			ItemDataResource.ToolCategory.PICKAXE:
				return ToolKind.PICKAXE
			ItemDataResource.ToolCategory.WATERING_CAN:
				return ToolKind.WATERING_CAN
			_:
				return ToolKind.NONE
	#Otherwise weapon takes priority for idle/walk animation context
	#For animation purposes--weapon takes priority, then last used tool
	#if not _equipped_weapon_id.is_empty():
		#return ToolKind.SWORD;
	return ToolKind.NONE;
#endregion
#region Animation and state
#Public helper for getting idle player state
func is_player_idle() -> bool:
	return state == PlayerState.IDLE;

#Get the direction the player is facing
func _get_direction_name(dir: Vector2) -> String:
	if dir == DIR_DOWN:
		return "down";
	if dir == DIR_UP:
		return "up";
	if dir == DIR_LEFT:
		return "left";
	if dir == DIR_RIGHT:
		return "right";
	#Fallback if something weird happens
	return "down";

#Get the specfic animation depending on which tool is currently being held
func _get_attack_animation_name(tool_kind: ToolKind, dir_name: String) -> String:
	match tool_kind:
		ToolKind.SWORD:
			return "melee_attack_" + dir_name;
		ToolKind.AXE:
			return "axe_" + dir_name;
		ToolKind.HOE:
			return "hoe_" + dir_name;
		ToolKind.PICKAXE:
			return "pickaxe_" + dir_name;
		ToolKind.NONE:
			return "melee_attack_" + dir_name;
	return "";
	#return "melee_attack_" + dir_name;
	
#Determine which animation to play based on state and facing direction
func _update_animation() -> void:
	if anim == null:
		return;
	var dir_name: String = _get_direction_name(facing_dir);
	var anim_name: String = "";
	#Match the playerstate
	match state:
		PlayerState.IDLE:
			anim_name = "idle_" + dir_name;
		PlayerState.WALK:
			anim_name = "walk_" + dir_name;
		PlayerState.MELEE_ATTACK:
			anim_name = _get_attack_animation_name(_get_tool_kind(), dir_name);
		PlayerState.HURT:
			anim_name = "hurt_" + dir_name;
		PlayerState.DEATH:
			anim_name = "death_" + dir_name;
		PlayerState.ITEM_GET:
			#One-frame help animation, ignore direction
			anim_name = "item_get_down";
	#Something went wrong, no anim_name
	if anim_name.is_empty():
		return;
	#Only change animation if it's different to avoid restarting
	if anim.animation != anim_name:
		if anim.sprite_frames.has_animation(anim_name):
			anim.play(anim_name);
		elif anim.sprite_frames.has_animation("idle_down"):
			anim.play("idle_down");
				
#Called every time the AnimatedSprite2D CHANGES frame
#Used to detect a hit
func _on_anim_frame_changed() -> void:
	#Only care if currently attacking
	if anim == null or state != PlayerState.MELEE_ATTACK:
		return;
		
	var current_anim: String = anim.animation;
	var current_frame: int = anim.frame;
	
	#If this animation has no defined hit frame, do nothing
	if not ATTACK_HIT_FRAMES.has(current_anim):
		return;
		
	var hit_frame: int = int(ATTACK_HIT_FRAMES[current_anim]);
	#Reached the hit frame
	if current_frame == hit_frame:
		#Tools (axe/hoe/pickaxe) use the tool action path
		if _current_attack_method_name != "":
			_perform_tool_action_in_front(_current_attack_method_name);
		else:
			#Pure melee, damage enemies
			_perform_melee_attack_hit_in_front();
			
#Called whenever the AnimatedSprite2D finishes a non-looping animation
func _on_anim_finished() -> void:
	if anim == null:
		return;
		
	#If we were in the using tool/attacking state, go back to idle/walk
	if state == PlayerState.MELEE_ATTACK:
		#Clear the attack method name now that it's finished so it doesn't trigger multiple times
		_current_attack_method_name = "";
		#Check current input to decide whether to walk or idle
		var input_vec := Input.get_vector("move_left","move_right","move_up","move_down");
		if input_vec.length() > 0.0:
			state = PlayerState.WALK;
			facing_dir = _snap_direction(input_vec.normalized());
		else:
			state = PlayerState.IDLE;
		_update_animation();
		return;
	if state == PlayerState.DEATH:
		#Death animation just finished
		death_animation_finished.emit();
		#Don't change state, player visually stays dead
		return;
		
		
func start_item_get_cinematic(item_id: String) -> void:
	#Don't start if dead or already in cinematic
	if not is_alive():
		return;
	if state == PlayerState.ITEM_GET:
		return;
		
	#Freeze movement, set state, update anim
	velocity = Vector2.ZERO;
	state = PlayerState.ITEM_GET;
	_update_animation();
	
	#Ask the CameraDirector to handle zoom
	var director = VisualFX.get_camera_director();
	if director and director.has_method("begin_item_get_zoom"):
		director.begin_item_get_zoom();
		
	Analytics.log_event("player_item_get_cinematic_started", {
		"item_id": item_id,
	})
	
func end_item_get_cinematic() -> void:
	#Restore normal idle state if we were in item-get
	if state == PlayerState.ITEM_GET:
		state = PlayerState.IDLE;
		_update_animation();
	var director = VisualFX.get_camera_director();
	if director and director.has_method("end_item_get_zoom"):
		director.end_item_get_zoom();
		
	Analytics.log_event("player_item_get_cinematic_ended", {});

#endregion
#region Health and damage
#Called whenever any stats changes, health, mana, etc
func _on_stats_changed() -> void:
	pass;
	
#Public helper to get the player stats
func get_stats() -> PlayerStats:
	return stats;
	
#Public take damage helper
func take_damage(amount: int,
	knockback_dir: Vector2 = Vector2.ZERO,
	knockback_force: float = 0.0
	) -> void:
	#No PlayerStats found
	if stats == null:
		push_warning("Player has no stats resource assigned!");
		return;
	#Empty amount
	if amount <= 0:
		return;
	#Apply damage via stats resource
	stats.apply_damage(amount);
	Analytics.log_event("player_hit", {
		"damage": amount,
		"hp_after": stats.health,
		"hp_max": stats.max_health,
		"scene": Analytics.get_scene_path(),
	});
	#If health is 0 or below, _on_stats_died() handles death logic
	if stats.health <= 0:
		return;
	#Setup knockback velocity if requested
	if knockback_force > 0.0 and knockback_dir.length() > 0.0:
		_knockback_velocity = knockback_dir.normalized() * knockback_force;
	else:
		_knockback_velocity = Vector2.ZERO;
	#Otherwise, enter hurt state
	_enter_hurt_state();
	#Visual feedback of getting hit
	#VisualFX determines if it actually plays based off of Settings
	#Small camera shake
	if VisualFX:
		VisualFX.shake_camera(2.0, 0.12); #Strength, duration, can tweak
		#Red vignette flash
		VisualFX.damage_flash(0.7, 0.25); #intensity, duration, can tweak
	
func _enter_hurt_state() -> void:
	#Don't enter if we've already 'died'
	if stats and stats.health <= 0:
		return;
	#Otherwise, enter hurt state
	state = PlayerState.HURT;
	_hurt_timer = hurt_duration;
	_update_animation();

#Ensure player is alive--for enemy targeting and such
func is_alive() -> bool:
	if stats == null:
		return false;
	return stats.health > 0;
	
#Called when health hits 0
func _on_stats_died() -> void:
	#Enter death state for animations and such
	state = PlayerState.DEATH;
	velocity = Vector2.ZERO;
	#Stop player input/movement
	set_physics_process(true);
	set_process(false);
	_update_animation();
	#Wait for the death animation to finish, then tell Game to show the game over screen
	death_animation_finished.connect(_on_death_animation_finished, CONNECT_ONE_SHOT);

func _on_death_animation_finished() -> void:
	if Game and Game.has_method("trigger_game_over"):
		Game.trigger_game_over();
#endregion
