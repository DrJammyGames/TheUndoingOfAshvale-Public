extends Area2D
class_name HarvestableNode;

#Signal for specific node_name for restoring Town
signal destroyed(node_name: String);

@export var harvest_id: String = "";

@onready var resource_sprite: Sprite2D = $Sprite;

#Visual variables
@onready var _anim: AnimationPlayer = $AnimationPlayer;
@onready var _dust: GPUParticles2D = $Dust;
@onready var _collision: CollisionShape2D = %InteractionArea;
const TREE_SLICE_SHADER = preload("res://FX/Shaders/TreeSlice.gdshader");
const GRASS_BREAK_STRIP = preload("res://Entities/Harvestables/Sprites/sGrassBreakingFrames.png");
const HARVESTABLE_SCENE = preload("res://Entities/Harvestables/Scenes/HarvestableNode.tscn");

@onready var _visual: CanvasItem = %Sprite; #Specifically for tree slice effect
var _hits_taken: int = 0;

func _ready() -> void:
	#Ensure the harvestable is in the group for the guided arrow
	add_to_group("harvestables");
	#Ensure unique material per instance so flash doesn't effect all the nodes
	if resource_sprite and resource_sprite.material is ShaderMaterial:
		resource_sprite.material = resource_sprite.material.duplicate();
	
	#After duplication, grab a reference
	var shader_mat := resource_sprite.material as ShaderMaterial;
	if shader_mat == null:
		return;
		
	#Configure the wind based on harvest_id--only for trees
	var is_tree := (harvest_id == "small_tree" or harvest_id == "medium_tree");
	
	#Turn on wind for trees
	if is_tree:
		shader_mat.set_shader_parameter("enable_wind", true);
		
		#Give each tree a slightly different movement pattern
		#Random float value for variety between
		var random_offst: float = randf() * 100.0;
		shader_mat.set_shader_parameter("offset", random_offst);
		
		#Optional-adjust where wind starts on the tree
		shader_mat.set_shader_parameter("heightOffset", 0.5);
	else:
		#Disable wind for ore, stumps, etc, anything that isn't a tree
		shader_mat.set_shader_parameter("enable_wind", false);
	
	#Safety checks
	if harvest_id.is_empty():
		push_warning("HarvestableNode: harvest_id is empty");
		return;
		
	if not HarvestableDatabase.has_harvestable(harvest_id):
		push_warning("HarvestableNode: unknown harvest_id '%s'" % harvest_id);
		return;
	
	#Set sprite from database
	var tex = HarvestableDatabase.get_world_sprite_texture(harvest_id);
	if tex and resource_sprite:
		resource_sprite.texture = tex;
	#Ensure the collisionshape is roughly the size of the sprite
	_update_hitbox_to_visual();
		
#These are what the Player calls vis _perform_tool_action_in_front
func on_axe_used(player: Node) -> void:
	_handle_tool_use(player, Player.ToolKind.AXE);

func on_pickaxe_used(player: Node) -> void:
	_handle_tool_use(player, Player.ToolKind.PICKAXE);

func on_hoe_used(player: Node) -> void:
	_handle_tool_use(player, Player.ToolKind.HOE);

func on_sword_used(player: Node) -> void:
	_handle_tool_use(player, Player.ToolKind.SWORD);
	
func _handle_tool_use(player: Node, tool_kind: Player.ToolKind) -> void:
	if harvest_id.is_empty():
		return;
	
	#Check if the tool is valid for this harvestable
	var required_tool = HarvestableDatabase.get_required_tool(harvest_id);
	if not _is_correct_tool(required_tool, tool_kind):
		#Analytics: player used the wrong tool on this harvestable
		Analytics.log_event("harvestable_wrong_tool_used", {
			"harvest_id": harvest_id,
			"required_tool": int(required_tool),
			"tool_kind": int(tool_kind), #int because it's an enum
			"position_x": global_position.x,
			"position_y": global_position.y,
		})
		return;
		
	#Otherwise, it is the correct tool, take hit
	_hits_taken += player.get_tool_damage();
	_show_hit_feedback();
	
	#Play hit sound
	var hit_stream = HarvestableDatabase.get_hit_sfx(harvest_id);
	AudioManager.play_sfx_stream(hit_stream);
	
	#Get the max hits from the database
	var max_hits = HarvestableDatabase.get_max_hits(harvest_id);
	#Analytics: a valid hit landed on this harvestable
	Analytics.log_event("harvestable_hit", {
		"harvest_id": harvest_id,
		"tool_kind": int(tool_kind),
		"hits_taken": _hits_taken,
		"max_hits": max_hits,
		"position_x": global_position.x,
		"position_y": global_position.y,
	})
	#Break if it's taken enough hits
	if _hits_taken >= max_hits:
		_on_broken(player, tool_kind);

#Check if the correct tool is being used and return a boolean value
func _is_correct_tool(required: int, tool_kind: Player.ToolKind) -> bool:
	match required:
		HarvestableDataResource.RequiredTool.AXE:
			return tool_kind == Player.ToolKind.AXE
		HarvestableDataResource.RequiredTool.PICKAXE:
			return tool_kind == Player.ToolKind.PICKAXE
		HarvestableDataResource.RequiredTool.HOE:
			return tool_kind == Player.ToolKind.HOE
		HarvestableDataResource.RequiredTool.SWORD:
			return tool_kind == Player.ToolKind.SWORD;
		HarvestableDataResource.RequiredTool.NONE:
			#NONE = any tool allowed
			return true
		_:
			#Unknown requirement → treat as "wrong tool"
			return false;
	
#Do something to make it obvious the node was hit
func _show_hit_feedback() -> void:
	if resource_sprite == null:
		return;
		
	#Get the material for flash
	var mat := resource_sprite.material;
	
	if mat == null or not (mat is ShaderMaterial):
		return;
		
	#Start fully flashed
	mat.set_shader_parameter("hit_amount", 1.0);
	#Save original position
	var original_pos := resource_sprite.position;
	#Smoothly tween hit_amount back to 0
	var tween := get_tree().create_tween();
	tween.set_trans(Tween.TRANS_SINE);
	tween.set_ease(Tween.EASE_OUT);
	
	#Flash fade
	tween.tween_method(
		func(value: float) -> void:
			mat.set_shader_parameter("hit_amount", value),
			1.0, 0.0, 0.3
	);
	
	#Optional extra shake--shader handles it now
	#Small shake a bit left/right then back
	tween.parallel().tween_method(
		func(offset: float) -> void:
			resource_sprite.position = original_pos + Vector2(offset, 0.0),
			0.5,-0.5,0.5
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT);
	
	tween.tween_callback(
		func() -> void:
			resource_sprite.position = original_pos;
	)
	
#Resource broke
func _on_broken(player: Node, tool_kind: Player.ToolKind) -> void:
	#Analytics: harvestable fully broken
	var player_pos_x = 0.0;
	var player_pos_y = 0.0;
	if player is Node2D:
		var p2d = player as Node2D;
		player_pos_x = p2d.global_position.x;
		player_pos_y = p2d.global_position.y;
		
	var max_hits: int = HarvestableDatabase.get_max_hits(harvest_id);
	
	Analytics.log_event("harvestable_broken", {
		"harvest_id": harvest_id,
		"tool_kind": int(tool_kind),
		"hits_taken": _hits_taken,
		"max_hits": max_hits,
		"position_x": global_position.x,
		"position_y": global_position.y,
		"player_position_x": player_pos_x,
		"player_position_y": player_pos_y,
	})
	#Start break vfx
	_start_break_sequence(player);
	#Add xp to the player on node break
	var xp: int = HarvestableDatabase.get_xp_reward(harvest_id);
	if xp > 0:
		LevelSystem.add_xp(xp);
	EncyclopediaSystem.record_harvest(harvest_id);
	#Pass time based on the equipped tool's time cost
	var base_cost: float = 0.0;
	var size_mult: float = HarvestableDatabase.get_size_multiplier(harvest_id);
	
	if player and player.has_method("get_equipped_tool_item_id"):
		var item_id: String = player.get_equipped_tool_item_id(tool_kind);
		base_cost = ItemDatabase.get_tool_time_cost(item_id);
	DayNightSystem.advance_time(base_cost * size_mult);
	#One-shot a tutorial pop-up of how time passes
	if not WorldFlags.get_flag(&"tutorial_time_passes"):
		WorldFlags.set_flag(&"tutorial_time_passes", true);
		UIRouter.show_sign_message(
			UIStringsDatabase.get_text("time_passes_title"),
			UIStringsDatabase.get_text("time_passes_body")
		);
	
func _start_break_sequence(player: Node) -> void:
	#Prevent any further interaction
	if _collision:
		_collision.set_deferred("disabled", true);
	#Drop items now so they feel synced with the impact
	_drop_items(player);
	
	if _should_use_tree_slice_effect():
		await _play_tree_slice_effect(player);
	elif _should_use_grass_break():
		await _play_grass_break_effect();
	else:
		await _play_default_break_effect();
	
	#Play some VFX
	if _dust:
		_dust.emitting = false;
		_dust.restart();
		_dust.emitting = true;
	VisualFX.shake_camera(4.0, 0.25);
	destroyed.emit(name);
	queue_free();

#Check if the harvestable is a tree that will use the tree slice shader
func _should_use_tree_slice_effect() -> bool:
	return harvest_id == "small_tree" or harvest_id == "medium_tree";
	
func _should_use_grass_break() -> bool:
	return harvest_id == "grass";
	
#Helper function for break animation for everthing besides trees
func _play_default_break_effect() -> void:
	#Play break animation if it exists, then free it
	if _anim and _anim.has_animation("break"):
		_anim.play("break");
		await _anim.animation_finished;
	else:
		#Fallback--quick shrink via tween
		var tween = create_tween();
		tween.tween_property(self, "scale", Vector2(0.0,0.0), 0.2)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		await tween.finished;

#Function specifically for grass
func _play_grass_break_effect() -> void:
	if resource_sprite == null:
		await get_tree().process_frame;
		return;
	#Strip the hit flash material so it doesn't interfere
	resource_sprite.material = null;
	#Swap to break animation strip
	resource_sprite.texture = GRASS_BREAK_STRIP;
	resource_sprite.hframes = 5;
	resource_sprite.frame = 0;
	
	#Step through frames over -0.3 seconds
	var tween = create_tween();
	tween.tween_method(
		func(f: float) -> void: resource_sprite.frame = int(f),
		0.0, 4.0, 0.3
	);
	await tween.finished;
	
#Function specifically for trees
func _play_tree_slice_effect(player: Node) -> void:
	if _visual == null:
		return;
		
	var sprite_owner = _visual as CanvasItem;
	if sprite_owner == null:
		return;
		
	#Important--creating new shader just for the break effect
	#Allows all nodes to keep the hit shader
	var shader_mat = ShaderMaterial.new();
	shader_mat.shader = TREE_SLICE_SHADER;
	sprite_owner.material = shader_mat;
	
	#Pixel size from texture width
	var pixel_size: float = 32.0;
	if sprite_owner is Sprite2D and (sprite_owner as Sprite2D).texture:
		pixel_size = float((sprite_owner as Sprite2D).texture.get_width())
	
	#Cut near the base of the tree
	shader_mat.set_shader_parameter("slice_y", 0.75);
	shader_mat.set_shader_parameter("pixel_size", pixel_size);
	shader_mat.set_shader_parameter("fall_progress", 0.0);
	shader_mat.set_shader_parameter("expansion_factor", 1.0);
	
	#Determine fall direction away from player
	var dir: float = 1.0;
	if player is Node2D:
		dir = sign(global_position.x - (player as Node2D).global_position.x);
		if dir == 0.0:
			dir = 1.0; #default to right if perfectly aligned
	shader_mat.set_shader_parameter("fall_direction", dir);
	shader_mat.set_shader_parameter("max_angle", PI / 2.0);
	
	#Animation fall_progress from 0 to 1
	var tween = create_tween();
	tween.tween_method(
		func(val: float) -> void: shader_mat.set_shader_parameter("fall_progress", val),
		0.0, 1.0, 1.0
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN);
	await tween.finished;
	
	#Spawn the stump after the canopy has fallen
	_spawn_stump();

func _spawn_stump() -> void:
	var stump: HarvestableNode = HARVESTABLE_SCENE.instantiate();
	stump.harvest_id = "tree_stump";
	
	#Align stump bottom to tree bottom
	var tree_bottom: float = global_position.y;
	if resource_sprite and resource_sprite.texture:
		tree_bottom = global_position.y + resource_sprite.texture.get_height() / 2.0;
		
	var stump_tex = HarvestableDatabase.get_world_sprite_texture("tree_stump");
	var stump_y: float = tree_bottom;
	if stump_tex:
		stump_y = tree_bottom - stump_tex.get_height() / 2.0;
	
	stump.global_position = Vector2(global_position.x, stump_y);
	get_parent().call_deferred("add_child", stump);
	
#Set what the broken resource drops from harvestable database
func _drop_items(player: Node) -> void:
	#Look up drop info in the database
	var drop_id = HarvestableDatabase.get_drop_item_id(harvest_id);
	#If it's empty, return
	if drop_id == "":
		return;
		
	var item_range = HarvestableDatabase.get_drop_amount_range(harvest_id);
	var amount: int = randi_range(item_range.x, item_range.y);
	#Safety check
	if amount <= 0:
		return;
	
	#Get direction to spawn items in world
	var forward_dir: Vector2 = Vector2.ZERO;
	if player is Node2D:
		forward_dir = (player.global_position - global_position).normalized();
		
	#Delegate to the shared world drop system
	WorldDrops.spawn_item_drop(
		drop_id,
		amount,
		self,
		{
			#Use direction from resource to player as center of half-circle
			"center_direction": forward_dir,
			"min_distance": 32.0, #How far from the node items can land
			"max_distance": 96.0,
			"source_type": "harvestable",
			"source_id": harvest_id
		}
	)

func _update_hitbox_to_visual() -> void:
	if resource_sprite == null or _collision == null:
		return;
	if _collision.shape == null:
		return;
		
	#Safety checks passed, resize collision
	var sprite_size: Vector2 = _get_visual_pixel_size(resource_sprite);
	if sprite_size == Vector2.ZERO:
		return;
		
	#Apply local scale of the visual in case I ever scale the sprites
	var scaled_size = sprite_size * resource_sprite.scale;
	
	var shape = _collision.shape;
	if shape is RectangleShape2D:
		shape.size = scaled_size;
	#Can add other shapes here if ever needed, but the collision is a rectangle so should be enough
	
func _get_visual_pixel_size(visual: Node2D) -> Vector2:
	if visual is Sprite2D:
		var sprite = visual as Sprite2D;
		if sprite.texture:
			return sprite.texture.get_size();
	elif visual is AnimatedSprite2D:
		var anim = (visual as AnimatedSprite2D);
		var frames = anim.sprite_frames;
		if frames:
			var current_anim: StringName = anim.animation;
			if current_anim == "":
				#Fallback, first animation, first frame
				var anims = frames.get_animation_names();
				if anims.size() > 0:
					current_anim = anims[0];
			if current_anim != "":
				var tex = frames.get_frame_texture(current_anim, 0);
				if tex:
					return tex.get_size();
	return Vector2.ZERO;
		
