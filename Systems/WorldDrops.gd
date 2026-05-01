extends Node

#Global helper for spawning item pickups into the world
#Enemies, harvestables, chests, etc. can all use this

const PICKUP_SCENE_PATH = "res://Entities/Items/Scenes/ItemPickup.tscn";
const MAX_STACK_PER_PICKUP: int = 99;

var _pickup_scene: PackedScene = preload(PICKUP_SCENE_PATH);

#Function for dropping a single item_id--like trees dropping only wood
func spawn_item_drop(
	item_id: String,
	total_amount: int,
	origin: Node2D,
	options: Dictionary = {}
) -> void:
	#Safety check
	if item_id == "" or total_amount <= 0:
		return;
		
	#Where to attach the pickups in scene tree
	var parent: Node = options.get("parent", origin.get_parent());
	if parent == null:
		push_warning("WorldDrops.spawn_item_drop: parent is null, aborting.");
		return;
		
	#Visual/behaviour options
	var center_direction: Vector2 = options.get("center_direction", Vector2.ZERO);
	if center_direction == Vector2.ZERO:
		#Fallback, pick a random direction
		var random_angle: float = randf() * TAU;
		center_direction = Vector2.RIGHT.rotated(random_angle);
	
	center_direction = center_direction.normalized();
	
	#Radial distances from origin
	var min_distance: float = float(options.get("min_distance", 12.0));
	var max_distance: float = float(options.get("max_distance", 32.0));
	
	#What the source of the drop is
	var source_type: String = String(options.get("source_type", ""));
	var source_id: String = String(options.get("source_id", ""));
	
	#Behaviour flags
	var destroy_on_pickup: bool = options.get("destroy_on_pickup", true);
	var show_message_on_pickup: bool = options.get("show_message_on_pickup", true)
	var max_stack: int = int(options.get("max_stack", MAX_STACK_PER_PICKUP));
	
	var origin_pos = origin.global_position;	
	var remaining: int = total_amount;
	while remaining > 0:
		var this_stack: int = min(max_stack, remaining);
		remaining -= this_stack;
		
		#Create the pickup
		var pickup = _pickup_scene.instantiate();
		pickup.item_id = item_id;
		pickup.amount = this_stack;
		pickup.destroy_on_pickup = destroy_on_pickup;
		pickup.show_message_on_pickup = show_message_on_pickup;
		pickup.source_type = source_type;
		pickup.source_id = source_id;
		
		parent.add_child(pickup);
		
		#Analytics
		Analytics.log_event("world_drop_spawned", {
			"item_id": item_id,
			"amount": this_stack,
			"position_x": pickup.global_position.x,
			"position_y": pickup.global_position.y,
			"source_type": source_type,
			"source_id": source_id,
		});
		
		#Start at the resource position
		pickup.global_position = origin_pos;
		
		#Choose a random offset in a half-circle around center_direction
		var angle_offset: float = randf_range(-PI / 2.0, PI / 2.0); #-90 to +90 degrees
		var dir = center_direction.rotated(angle_offset).normalized();
		var radius: float = randf_range(min_distance, max_distance);
		var target_pos = origin_pos + dir * radius;
		#Ask the pickup to animate itself along an arc to that target
		if pickup.has_method("play_spawn_bounce"):
			pickup.play_spawn_bounce(target_pos);
		elif pickup.has_method("play_spawn_animation"):
			#Fallback 
			pickup.play_spawn_animation();
			
#Spawn multiple different items in one call
#Enemies, chests, etc
func spawn_multiple(
	drops: Array,
	origin: Node2D,
	options: Dictionary = {}
) -> void:
	for drop in drops:
		if not drop.has("item_id") or not drop.has("amount"):
			continue;
		var item_id: String = drop["item_id"];
		var amount: int = drop["amount"];
		if amount <= 0:
			continue;
		spawn_item_drop(item_id, amount, origin, options);
