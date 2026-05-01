extends Control
class_name DecorationModeUI

#Full-screen overlay for decoration mode
#Handles: free camera movement, furniture sidebar, placement ghost, save/exit

#Signals
signal decoration_saved_and_exited;
signal decoration_exited_without_saving;

#Constants
const CAMERA_SPEED: float = 200.0;
const CAMERA_EDGE_MARGIN: float = 20.0; #pixels from edge to trigger edge scroll
const GHOST_VALID_COLOUR: Color = Color(0.5,1.0,0.5,0.6);
const GHOST_INVALID_COLOUR: Color = Color(1.0, 0.4, 0.4, 0.6);
const LOCK_SOURCE: String = "decoration_mode";

#Node refs
@onready var sidebar: Control = %Sidebar;
@onready var sidebar_toggle_button: Button = %SidebarToggleButton;
@onready var furniture_list: GridContainer = %FurnitureList;
@onready var save_exit_button: Button = %SaveExitButton;
@onready var exit_button: Button = %ExitButton;
@onready var hint_label: Label = %HintLabel;
@onready var ghost_rect: TextureRect = %GhostRect;
@onready var unsaved_popup: Control = %UnsavedPopup;
@onready var unsaved_confirm_button: Button = %UnsavedConfirmButton;
@onready var unsaved_cancel_button: Button = %UnsavedCancelButton;

#Runtime state
var _sidebar_open: bool = true;
var _selected_item_id: String = "";
var _is_placing: bool = false;
var _has_unsaved_changed: bool = false;
var _sidebar_tween: Tween = null;
#Decoration camera--free roaming during decoration mode
var _deco_camera: Camera2D = null;
#Track placed instance this session for undo support 
var _session_placements: Array = [];
#Tilemap refs for placement validation
var _collision_tilemap: TileMapLayer = null;
var _ysort_tilemaps: Array[TileMapLayer] = [];
var _ysort_root: Node2D = null;
var _sidebar_open_offset: float = 0.0;

func _ready() -> void:
	UIRouter.set_hud_visible(false);
	process_mode = Node.PROCESS_MODE_ALWAYS;
	#Wire the buttons
	sidebar_toggle_button.pressed.connect(_on_sidebar_toggle_pressed);
	save_exit_button.pressed.connect(_on_save_exit_pressed);
	exit_button.pressed.connect(_on_exit_pressed);
	unsaved_confirm_button.pressed.connect(_on_unsaved_confirm_pressed);
	unsaved_cancel_button.pressed.connect(_on_unsaved_cancel_pressed);
	
	#Wire furniture inventory changes
	DecorationSystem.furniture_inventory_changed.connect(_on_furniture_inventory_changed);
	
	#Hide ghost icon and popup to start
	ghost_rect.visible = false;
	unsaved_popup.visible = false;
	
	#Show first-time hint if needed
	if not WorldFlags.has_flag("decoration_hint_shown"):
		hint_label.visible = true;
		WorldFlags.set_flag("decoration_hint_shown");
	else:
		hint_label.visible = false;
		
	#Rebuild the sidebar contents
	_rebuild_furniture_list();
	#Spawn and configure the decoration camera
	await get_tree().process_frame;
	_setup_deco_camera();
	_find_tilemaps();
	
	Analytics.log_event("decoration_mode_entered", {});
	
func _exit_tree() -> void:
	#Always clean up camera and input lock on close
	_teardown_deco_camera();
	UIRouter.set_hud_visible(true);
	
#region Camera setup
func _setup_deco_camera() -> void:
	#Create a fresh Camera2D for decoration mode
	#Start it at the player's current position
	_deco_camera = Camera2D.new();
	_deco_camera.name = "DecorationCamera";
	#Copy limits from the player camera so we stay in bounds
	var player_cam: Camera2D = VisualFX.get_player_camera();
	
	if player_cam:
		_deco_camera.limit_left = player_cam.limit_left;
		_deco_camera.limit_right = player_cam.limit_right;
		_deco_camera.limit_top = player_cam.limit_top;
		_deco_camera.limit_bottom = player_cam.limit_bottom;
	var player: Node2D = Game.get_player();
	if player:
		_deco_camera.global_position = player.global_position;
	_deco_camera.position_smoothing_enabled = false;
	#Add to current scene and make the current camera
	get_tree().current_scene.add_child(_deco_camera);
	_deco_camera.make_current();
	
func _teardown_deco_camera() -> void:
	if is_instance_valid(_deco_camera):
		_deco_camera.queue_free();
		_deco_camera = null;
	#Restore the player camera
	var player_cam: Camera2D = VisualFX.get_player_camera();
	if player_cam:
		player_cam.make_current();
		player_cam.reset_smoothing();
		player_cam.position_smoothing_enabled = true;
		VisualFX.set_active_camera(player_cam);
#endregion
#region Input
func _unhandled_input(event: InputEvent) -> void:
	#Dismiss hint on any input
	if hint_label.visible:
		hint_label.visible = false;

	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton;
		#Left click--place item or pick up furniture
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if _is_placing:
				_confirm_placement(get_viewport().get_mouse_position());
			else:
				_try_pickup_at(get_viewport().get_mouse_position());
			get_viewport().set_input_as_handled();
			return;
		#Right click--cancel placement
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if _is_placing:
				_cancel_placement();
			get_viewport().set_input_as_handled();
			return;
			
func _process(delta: float) -> void:
	_handle_camera_movement(delta);
	if _is_placing:
		_update_ghost_position();
		
func _handle_camera_movement(delta: float) -> void:
	if _deco_camera == null:
		return;
	var move = Vector2.ZERO;
	#WASD camera movement
	if Input.is_action_pressed("move_up"):
		move.y -= 1.0;
	if Input.is_action_pressed("move_down"):
		move.y += 1.0;
	if Input.is_action_pressed("move_left"):
		move.x -= 1.0;
	if Input.is_action_pressed("move_right"):
		move.x += 1.0;
		
	#Edge scrolling
	var mouse_pos: Vector2 = get_viewport().get_mouse_position();
	var viewport_size: Vector2 = get_viewport_rect().size;
	if mouse_pos.x < CAMERA_EDGE_MARGIN:
		move.x -= 1.0;
	if mouse_pos.x > viewport_size.x - CAMERA_EDGE_MARGIN:
		move.x += 1.0;
	if mouse_pos.y < CAMERA_EDGE_MARGIN:
		move.y -= 1.0;
	if mouse_pos.y > viewport_size.y - CAMERA_EDGE_MARGIN:
		move.y += 1.0;
	if move != Vector2.ZERO:
		_deco_camera.global_position += move.normalized() * CAMERA_SPEED * delta;
#endregion
#region Placement
func _start_placement(item_id: String) -> void:
	_selected_item_id = item_id;
	_is_placing = true;
	ghost_rect.visible = true;
	#Set the icon texture for the ghost preview
	var icon: Texture2D = ItemDatabase.get_icon_inv(item_id);
	if icon:
		ghost_rect.texture = icon;
	ghost_rect.modulate = GHOST_VALID_COLOUR;
	
func _update_ghost_position() -> void:
	#Snap ghost to mouse position in screen space
	var mouse_pos: Vector2 = get_viewport().get_mouse_position();
	var snapped_pos: Vector2 = mouse_pos.snapped(Vector2(32,32));
	ghost_rect.global_position = snapped_pos - (ghost_rect.size * 0.5);
	
	#Convert screen position to world position for validation
	var viewport_size: Vector2 = get_viewport_rect().size;
	var world_pos: Vector2 = _deco_camera.global_position + (mouse_pos - viewport_size * 0.5);
	world_pos = world_pos.snapped(Vector2(32,32));
	
	#Tint based on validity
	if _is_placement_valid(world_pos):
		ghost_rect.modulate = GHOST_VALID_COLOUR;
	else:
		ghost_rect.modulate = GHOST_INVALID_COLOUR;
		
func _confirm_placement(screen_pos: Vector2) -> void:
	if _selected_item_id.is_empty():
		return;

	#Convert viewport-space mouse position to world position via deco camera
	var viewport_size: Vector2 = get_viewport_rect().size;
	var world_pos: Vector2 = _deco_camera.global_position + (screen_pos - viewport_size * 0.5);
	world_pos = world_pos.snapped(Vector2(32, 32));
	
	#Block if it is an invalid tile for placement
	if not _is_placement_valid(world_pos):
		return;
		
	#Set the scene path for this furniture item
	var scene_path: String = _get_furniture_scene_path(_selected_item_id);
	if scene_path.is_empty():
		push_warning("DecorationModeUI: No scene path for furniture item %s" % _selected_item_id);
		return;
	
	#Register with DecorationSystem which removes from the world inventory
	var instance_id: String = DecorationSystem.register_placed_furniture(
		_selected_item_id, scene_path, world_pos
	);
	if instance_id.is_empty():
		return;
		
	#Spawn the actual furniture node in the world
	_spawn_furniture_node(scene_path, world_pos, instance_id);
	#Set unsaved changes to true since a change was made
	_has_unsaved_changed = true;
	_session_placements.append(instance_id);
	
	#If player has no more of this item, cancel placement mode
	if not DecorationSystem.has_furniture(_selected_item_id):
		_cancel_placement();
		
	#Rebuild sidebar to reflect new count
	_rebuild_furniture_list();

#Check if the placement is valid
func _is_placement_valid(world_pos: Vector2) -> bool:
	#Check collision tilemap first
	if _collision_tilemap != null:
		var cell: Vector2i = _collision_tilemap.local_to_map(
			_collision_tilemap.to_local(world_pos)
		);
		if _collision_tilemap.get_cell_source_id(cell) != -1:
			return false;
	
	#Check any tilemaplayer under ysortroot
	for tilemap in _ysort_tilemaps:
		var cell: Vector2i = tilemap.local_to_map(tilemap.to_local(world_pos));
		if tilemap.get_cell_source_id(cell) != -1:
			return false;
	
	#Check all of the non-tilemaplayer stuffs under ysortroot
	if _ysort_root != null:
		if _check_ysort_overlap(_ysort_root, world_pos):
			return false;
			
	#Check existing placed furniture for an overlap check
	for entry in DecorationSystem.get_placed_furniture():
		var placed_pos: Vector2 = entry.get("position", Vector2.ZERO);
		if placed_pos.distance_to(world_pos) < 16.0:
			return false;
	
	#Passed all the safety checks, ok to place furniture here
	return true;
	
func _cancel_placement() -> void:
	_selected_item_id = "";
	_is_placing = false;
	ghost_rect.visible = false;
	#Clear the texture
	ghost_rect.texture = null;
	
func _try_pickup_at(screen_pos: Vector2) -> void:
	#Convert screen position to world position
	var viewport_size: Vector2 = get_viewport_rect().size;
	var world_pos: Vector2 = _deco_camera.global_position + (screen_pos - viewport_size * 0.5);
	
	#Find the cloest placed furniture node within pickup range
	var closest_node: Node2D = null;
	var closest_dist: float = 32.0; 
	for node in get_tree().get_nodes_in_group("placed_furniture"):
		if not is_instance_valid(node):
			continue;
		var dist: float = (node as Node2D).global_position.distance_to(world_pos);
		if dist < closest_dist:
			closest_dist = dist;
			closest_node = node as Node2D;
	#Nothing is there, exit
	if closest_node == null:
		return;
	
	#Something is there, get it's info
	var instance_id: String = closest_node.get_meta("decoration_instance_id", "");
	var item_id: String = _get_item_id_from_instance(instance_id);
	if item_id.is_empty():
		return;
	
	#Remove from scene
	closest_node.queue_free();
	#Return to inventory via DecorationSystem
	DecorationSystem.unregister_placed_furniture(instance_id);
	#Remove from session tracking if it was placed this session
	_session_placements.erase(instance_id);
	#Mark unsaved
	_has_unsaved_changed = true;
	#Start placement mode with this item
	_start_placement(item_id);
	_rebuild_furniture_list();
	
func _get_item_id_from_instance(instance_id: String) -> String:
	for entry in DecorationSystem.get_placed_furniture():
		if entry.get("instance_id", "") == instance_id:
			return entry.get("item_id", "");
	return "";
	
func _check_ysort_overlap(node: Node, world_pos: Vector2) -> bool:
	for child in node.get_children():
		if child is TileMapLayer:
			continue;
		if child.is_in_group("placed_furniture"):
			continue;
		if child.is_in_group("player"):
			continue;
		#If its a Node2D with a real position, check proximity
		if child is Node2D:
			var node2d: Node2D = child as Node2D;
			#Only check leaf nodes with actual positions
			if node2d.get_child_count() == 0 or node2d.global_position != Vector2.ZERO:
				if node2d.global_position.distance_to(world_pos) < 32.0:
					return true;
		#Recurse into children
		if _check_ysort_overlap(child,world_pos):
			return true;
	return false;
	
func _spawn_furniture_node(scene_path: String, world_pos: Vector2, instance_id: String) -> void:
	var packed: PackedScene = load(scene_path);
	if packed == null:
		push_warning("DecorationModeUI: Failed to load furniture scene: %s" % scene_path);
		return;
	var node: Node2D = packed.instantiate();
	node.global_position = world_pos;
	#Tag with instance_id so it can be found later for pickup/move
	node.set_meta("decoration_instance_id", instance_id);
	node.set_meta("is_placed_furniture", true);
	node.add_to_group("placed_furniture");
	#Place under YSortRoot/Interactables in the current world scene
	var world_scene: Node = Game.get_current_scene();
	if world_scene == null:
		push_warning("DecorationModeUI: No current world scene found.");
		return;
	var interactables: Node = world_scene.get_node_or_null("YSortRoot/Interactables");
	if interactables == null:
		push_warning("DecorationModeUI: YSortRoot/Interactables not found in current scene.");
		get_tree().current_scene.add_child(node);
		return;
	#Add to world scene--under a specific node
	interactables.add_child(node);
	
#Returns the scene path for a given furniture item_id
func _get_furniture_scene_path(item_id: String) -> String:
	#Convert snake_case item_id to PascalCase for scene filename
	#i.e., small_chest -> SmallChest
	var parts: PackedStringArray = item_id.split("_");
	var pascal: String = "";
	for part in parts:
		pascal += part.capitalize();
	return "res://Entities/Furniture/Scenes/%s.tscn" % pascal;
	
func _find_tilemaps() -> void:
	var world_scene: Node = Game.get_current_scene();
	if world_scene == null:
		return;
	_collision_tilemap = world_scene.get_node_or_null("CollisionLayer/Collisions") as TileMapLayer;
	_ysort_root = world_scene.get_node_or_null("YSortRoot") as Node2D;
	#Collect every TileMapLayer anywhere under YSortRoot
	_ysort_tilemaps.clear();
	if _ysort_root != null:
		_collect_tilemaps(_ysort_root);
		
func _collect_tilemaps(node: Node) -> void:
	for child in node.get_children():
		if child is TileMapLayer:
			_ysort_tilemaps.append(child as TileMapLayer);
		_collect_tilemaps(child);
#endregion
#region Sidebar
func _rebuild_furniture_list() -> void:
	#Clear existing entries first
	for child in furniture_list.get_children():
		child.queue_free();
		
	var all_furniture: Dictionary = DecorationSystem.get_all_furniture();
	#Sort by display name
	var sorted_ids: Array = all_furniture.keys();
	sorted_ids.sort_custom(func(a,b):
		return ItemDatabase.get_display_name(a) < ItemDatabase.get_display_name(b));
	
	for item_id in sorted_ids:
		var count: int = all_furniture[item_id];
		if count <= 0:
			continue;
		var btn: FurnitureSlot = preload("res://UI/Scenes/Buttons/FurnitureSlot.tscn").instantiate();
		furniture_list.add_child(btn);
		btn.setup(item_id, count);
		btn.pressed.connect(_on_furniture_item_pressed.bind(item_id));
		
func _on_sidebar_toggle_pressed() -> void:
	_sidebar_open = not _sidebar_open;
	#Kill any running tween first
	if _sidebar_tween and _sidebar_tween.is_valid():
		_sidebar_tween.kill();
	_sidebar_tween = create_tween();
	_sidebar_tween.set_trans(Tween.TRANS_SINE);
	_sidebar_tween.set_ease(Tween.EASE_IN_OUT);
	#Slide sidebar right (off screen) or back left (on screen)
	var button_width: float = sidebar_toggle_button.size.x;
	var target_offset: float;
	if _sidebar_open:
		target_offset = _sidebar_open_offset;
	else: 
		target_offset = _sidebar_open_offset + sidebar.size.x - button_width;
	_sidebar_tween.tween_property(sidebar, "offset_left", target_offset, 0.2);
	#Update text on button arrow
	sidebar_toggle_button.text = ">" if _sidebar_open else "<";
	
func _on_furniture_item_pressed(item_id: String) -> void:
	_start_placement(item_id);
	
func _on_furniture_inventory_changed(_item_id: String) -> void:
	_rebuild_furniture_list();
#endregion
#region Save exit stuffs
func _on_save_exit_pressed() -> void:
	Game.request_save();
	_has_unsaved_changed = false;
	_close_decoration_mode();
	decoration_saved_and_exited.emit();
	Analytics.log_event("decoration_mode_saved_and_exited", {});
	
func _on_exit_pressed() -> void:
	if _has_unsaved_changed:
		unsaved_popup.visible = true;
	else:
		_close_decoration_mode();
		decoration_exited_without_saving.emit();
		
#Confirm exit without saving
func _on_unsaved_confirm_pressed() -> void:
	#Roll back session placements
	_rollback_session_placement();
	unsaved_popup.visible = false;
	_close_decoration_mode();
	decoration_exited_without_saving.emit();
	Analytics.log_event("decoration_mode_exited_without_saving", {});
	
func _on_unsaved_cancel_pressed() -> void:
	#Go back to decorating
	unsaved_popup.visible = false;
	
func _rollback_session_placement() -> void:
	#Remove all node placed this session and return them to world inventory
	for instance_id in _session_placements:
		#Find the best node in the scene
		var nodes = get_tree().get_nodes_in_group("placed_furniture");
		for node in nodes:
			if node.has_meta("decoration_instance_id") \
			and node.get_meta("decoration_instance_id") == instance_id:
				node.queue_free();
				break;
		#Return to world inventory
		DecorationSystem.unregister_placed_furniture(instance_id);
	_session_placements.clear();
	
func _close_decoration_mode() -> void:
	UIRouter.close_top_modal();
#endregion
