#Child of Interactable
extends Interactable;

class_name ItemPickup;

@export var item_id: String = "";
@export var amount: int = 1;
@export var destroy_on_pickup: bool = true;
@export var show_message_on_pickup: bool = true;

@onready var item_sprite: Sprite2D = %Sprite;
@onready var shadow_sprite: Sprite2D = %ShadowSprite;
@onready var count_label: Label = %CountLabel;

#Store buonce parameters so we can also calculate it for the shadow
var _bounce_speed: float = 0.0;
var _bounce_height: float = 0.0;
var _time_offset: float = 0.0;
#Ensure a slight delay in being able to pickup the items so they don't get sucked into the player upon drop
var _pickup_enabled: bool = false;
#Base values
var _shadow_base_scale: Vector2 = Vector2.ONE;
var _shadow_base_alpha: float = 1.0;
#Info for what the item is and where it came from
var source_type: String = "";
var source_id: String = "";

func _ready() -> void:
	#Call base Interactable _ready in case setup is needed
	super._ready();
	if not body_entered.is_connected(_on_pickup_body_entered):
		body_entered.connect(_on_pickup_body_entered);
	#region Shader stuffs
	#Ensure this item has its own material instance
	#Otherwise all dropped items will bounce identically
	if item_sprite and item_sprite.material is ShaderMaterial:
		item_sprite.material = item_sprite.material.duplicate();
		
	var shader_mat := item_sprite.material as ShaderMaterial;
	#Safety check
	if shader_mat == null:
		return;
		
	#Randomise bounce so each item feels slightly different
	#Variations in height, speed, and phase
	var random_height: float = randf_range(3.0, 6.0);
	#Random bounce speed
	var random_speed: float = randf_range(2.0, 4.0);
	#Random time offset so they don't sync
	var random_offset: float = randf_range(0.0, 10.0);
	
	#Set the parameters
	shader_mat.set_shader_parameter("bounce_height",  random_height);
	shader_mat.set_shader_parameter("bounce_speed", random_speed);
	shader_mat.set_shader_parameter("time_offset", random_offset);
	
	#Store for shadow calculation
	_bounce_speed = random_speed;
	_bounce_height = random_height;
	_time_offset = random_offset;
	
	#Set up the shadow bounce effects
	if shadow_sprite:
		_shadow_base_scale = shadow_sprite.scale;
		_shadow_base_alpha = shadow_sprite.modulate.a;
	#endregion
	var icon: Texture2D = ItemDatabase.get_icon_world(item_id);
	if icon != null and item_sprite != null:
		item_sprite.texture = icon;
	#Show count label 
	count_label.text = "x%d" % amount;
	_pickup_enabled = true;
	monitoring = true;
	
		
#Internal helper for pickup item upon collision
func _on_pickup_body_entered(body: Node) -> void:
	#Pickup hasn't been allowed yet, abort
	if not _pickup_enabled:
		return;
	#Delay is done, enable pickup again
	if body != null and body.is_in_group("player"):
		_collect(body);
		
#Collect the item
func _collect(player: Node) -> void:
	if item_id.is_empty():
		push_warning("ItemPickup has no item_id set");
		return;
		
	#Check if the item exists in the database (safety checks)
	if not ItemDatabase.has_item(item_id):
		push_warning("ItemPickup: Unknown item_id '%s'" % item_id);
		#Analytics: invalid pickup configuration
		Analytics.log_event("world_drop_collect_invalid", {
			"item_id": item_id,
			"amount": amount,
			"drop_position_x": global_position.x,
			"drop_position_y": global_position.y,
			"source_type": source_type,
			"source_id": source_id,
			"reason": "unknown_item_id",
		})
		return;
		
	#Check whether this item was known before we pick it up
	var was_discovered_before: bool = false;
	if InventorySystem.has_method("has_discovered"):
		was_discovered_before = InventorySystem.has_discovered(item_id);
	var hud = UIRouter.get_hud();
	#If this is a gold coin, add to gold, not inventory
	if item_id == "gold_coin":
		GameState.gold += amount;
		DayNightSystem.record_gold_earned(amount);
		if show_message_on_pickup:
			if hud:
				var msg_pos: Vector2 = global_position;
				if player is Node2D:
					msg_pos = (player as Node2D).global_position;
				hud.show_message("+%d Gold" % amount, 2.0, msg_pos);
			Analytics.log_event("gold_coin_collected", {
				"amount": amount,
				"total_gold": GameState.gold,
				"source_type": source_type,
				"source_id": source_id,
			});
		if destroy_on_pickup:
			queue_free();
		return;
	#Safety checks passed, try to add to inventory if room
	var added: bool = InventorySystem.try_add_item(item_id, amount);
	#Inventory emits a signal that the inventory has changed--this checks the QuestSystem as well
	if not added:
		#Inventory full (only happens for NEW item types)
		if show_message_on_pickup:
			
			if hud:
				hud.show_message("Inventory full.", 2.0, global_position);
			#Analytics: pickup failed due to full inventory
			Analytics.log_event("world_drop_collect_failed", {
				"item_id": item_id,
				"amount": amount,
				"drop_position_x": global_position.x,
				"drop_position_y": global_position.y,
				"source_type": source_type,
				"source_id": source_id,
				"reason": "inventory_full",
			})
		return;
	#Ensure this item is included in the end of day summary
	DayNightSystem.record_item_gained(item_id, amount);
	#HUD feedback--only show if it's not a new item
	if show_message_on_pickup and was_discovered_before:
		var item_name: String = ItemDatabase.get_display_name(item_id);
		if hud:
			var msg_pos: Vector2 = global_position;
			if player is Node2D:
				msg_pos = (player as Node2D).global_position;
			hud.show_message("+%d %s" % [amount, item_name], 
			2.0,
			msg_pos,
		);
	#Analytics pickup succeeded
	var total_after: int = InventorySystem.get_amount(item_id);
	var player_pos_x = 0.0;
	var player_pos_y = 0.0;
	if player is Node2D:
		var p2d = player as Node2D;
		player_pos_x = p2d.global_position.x;
		player_pos_y = p2d.global_position.y;
		
	Analytics.log_event("world_drop_collected", {
		"item_id": item_id,
		"amount": amount,
		"drop_position_x": global_position.x,
		"drop_position_y": global_position.y,
		"player_position_x": player_pos_x,
		"player_position_y": player_pos_y,
		"source_type": source_type,
		"source_id": source_id,
		"nventory_amount_after": total_after,
	})
	#Remove the pickable from the world
	if destroy_on_pickup:
		queue_free();

#Called by WorldDrops after spawn with target position already chosen
func play_spawn_bounce(target_pos: Vector2) -> void:
	var start_pos = global_position;
	
	#Start slightly smaller for a nice pop
	scale = Vector2(0.5, 0.5);
	
	var tween = create_tween();
	
	#Position tween via custom arc
	#Animate parameter t from 0 -> 1 and compute the arc
	tween.tween_method(
		Callable(self, "_apply_spawn_arc").bind(start_pos, target_pos),
		0.0,
		1.0,
		0.75 #Total duration for the movement
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT);
	
	#Scale pop to full size
	tween.parallel().tween_property(
		self, "scale", Vector2(1.0,1.0), 0.25
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT);

#Helper to compute a bouncy arce between start and target
func _apply_spawn_arc(t: float, start_pos: Vector2, target_pos: Vector2) -> void:
	#Base linear interpolation
	var pos = start_pos.lerp(target_pos, t);
	#Add a little hop to height using a sine curve
	#t=0 or 1 height = 0 t=0.5 -> max height
	var hop_height: float = -16.0 * sin(t * PI); #Negative y = up in screen coords
	pos.y += hop_height;
	
	global_position = pos;
	
#Public helper for spawning in with an animation
func play_spawn_animation() -> void:
	#Start slightly lifted and scaled down
	var target_pos = global_position;
	global_position = target_pos + Vector2(0,-10);
	
	scale = Vector2(0.2,0.2);
	modulate.a = 0.0;
	
	var tween = create_tween();
	
	#Fade in and pop downwards (0.25s)
	tween.tween_property(self, "modulate:a", 1.0, 0.25);
	tween.parallel().tween_property(
		self, "scale", Vector2(1.15,1.15), 0.25
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT);
	tween.parallel().tween_property(
		self, "global_position", target_pos + Vector2(0, -3), 0.25
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT);
	
	#Setle and slight squash (0.15s)
	tween.tween_property(
		self, "scale", Vector2(1.0,1.0), 0.15
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT);
	tween.parallel().tween_property(
		self, "global_position", target_pos, 0.15
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN);
		
	
func _process(_delta: float) -> void:
	#No shadow or bounce speed? Nothing to do
	if shadow_sprite == null or _bounce_speed == 0.0:
		return;
	
	#Calm visual mode--disable bounce
	if Settings.calm_visual_mode:
		item_sprite.position.y = 0.0;
		shadow_sprite.scale = _shadow_base_scale;
		shadow_sprite.modulate.a = _shadow_base_alpha;
		return;
	
	#There's something to do--compute the same bounce value as shader
	var time_seconds: float = Time.get_ticks_msec() / 1000.0;
	var phase: float = (time_seconds + _time_offset) * _bounce_speed;
	var bounce: float = abs(sin(phase)) #0 = ground, 1 = top
	item_sprite.position.y = -_bounce_height * bounce;
	#Shadow scale
	var scale_factor: float = 1.0 + 0.3 * (1.0 - bounce);
	shadow_sprite.scale = _shadow_base_scale * scale_factor;
	var min_alpha: float = 0.2; #At top
	var max_alpha: float = _shadow_base_alpha #at ground
	
	var alpha: float = lerp(min_alpha, max_alpha, 1.0 - bounce);
	var col := shadow_sprite.modulate;
	col.a = alpha;
	shadow_sprite.modulate = col;
