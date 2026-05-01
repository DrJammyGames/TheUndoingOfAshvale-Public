extends Node
#High level logic game flow and scene orchestration
#Keeps the game logic thin: delegates to other singletons

#Other nodes can listen to this to know when the current scene has changed
signal scene_changed(new_scene_path: String);
#Signal save successful and completed
signal save_completed(success: bool);
#Player node has fully loaded
signal player_ready();
#Keep a reference to the currently loaded "world" scene
var _current_scene: Node = null;
var _current_scene_path: String = "";
var _is_changing_scene: bool = false;
var suppress_next_hud_show: bool = false;
#Controls hint flag
var _pending_controls_hint: bool = false;
#Title card flag
var _pending_title_card: bool = false;

#For now, hardcoded the town scene path
#Using a String instead of PackedScene so we can store it in GameState for saving/loading
const TOWN_SCENE_PATH: String = "res://Rooms/Scenes/Town.tscn";
const PLAYER_HOUSE_PATH: String = "res://Rooms/Scenes/PlayerHouse.tscn"
const TITLE_SCREEN_PATH: String = "res://Rooms/Scenes/TitleScreen.tscn";
const PLAYER_SCENE_PATH: String = "res://Entities/Player/Scenes/Player.tscn";
const END_OF_DAY_SCREEN_PATH: String = "res://Rooms/Scenes/EndOfDaySummary.tscn";
#Input locke stack supports nested locks, dialogue, cutscene, etc
var _input_lock_count: int = 0;
var _input_lock_sources: Array[String] = [];
var _player: Node = null;
#Track how long scene changes take
var _scene_change_start_time: float = 0.0;

func _ready() -> void:
	#Set proper randomisation throughout the game
	randomize();
	#Set default language; must match the column header in your CSV (en, fr, de, etc.)
	TranslationServer.set_locale("en");
	#Allow this node to keep getting input even while the game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS;
	#Load persisted settings
	SaveSystem.load_settings_only();      
	#Apply them immediately    
	Settings.apply_settings_to_tree(get_tree());
	#Go to title screen
	_change_scene(TITLE_SCREEN_PATH);
	InventorySystem.first_time_item_acquired.connect(_on_first_time_item_acquired);
	#Connect save on quest completion
	QuestSystem.quest_completed.connect(_on_quest_completed_autosave);	

#Input lock functions
func push_input_lock(source: String = "unknown") -> void:
	_input_lock_count += 1;
	_input_lock_sources.append(source);
	
func pop_input_lock(source: String = "unknown") -> void:
	_input_lock_count = max(_input_lock_count - 1, 0);
	#Remove one matching source if present so it stays tidy
	var idx = _input_lock_sources.find(source);
	if idx != -1:
		_input_lock_sources.remove_at(idx);
	else:
		#Fallback pop last if no match
		if _input_lock_sources.size() > 0:
			_input_lock_sources.pop_back();
			
func is_input_locked() -> bool:
	return _input_lock_count > 0;
	
#Public helper for get player
func get_player() -> Node:
	if is_instance_valid(_player):
		return _player;
	else:
		return null;
	
func _unhandled_input(event: InputEvent) -> void:
	#If a hard lock is active, ignore global shortcuts
	if is_input_locked():
		return;
	#Also block input if dialogue is active
	if DialogueSystem.is_active():
		return;
		
	#Open the inventory with shortcut i
	if event.is_action_pressed("ui_inventory"):
		Analytics.log_event("inventory_shortcut_pressed", {})
		UIRouter.show_inventory();
		get_viewport().set_input_as_handled();
		return;
		
	#Open the quest log with shortcut q
	if event.is_action_pressed("ui_quest_log"):
		Analytics.log_event("quest_log_shortcut_pressed", {})
		UIRouter.show_quest_log();
		get_viewport().set_input_as_handled();
		return;
		
	#Close screens/pause menu toggle
	if event.is_action_pressed("ui_cancel"):
		#Specifically the top modal if one is open
		if UIRouter.is_modal_open():
			Analytics.log_event("ui_cancel_close_modal", {})
			UIRouter.close_top_modal();
		else:
			#No other modal open, toggle pause menu instead
			#Only open if in world scene
			if _current_scene is WorldScene:
				Analytics.log_event("pause_input_pressed", {
					"scene": Analytics.get_scene_path(),
				})
				UIRouter.toggle_pause_menu("input");
		get_viewport().set_input_as_handled();
		return;
		
#Public function called in TitleScreen
func start_new_game(slot: int = -1) -> void:
	#Decide which slot this game belongs to
	var actual_slot: int = slot;
	if actual_slot < 0:
		actual_slot = _choose_default_save_slot();
		
	#Ensure there is a name
	var _name = GameState.player_name.strip_edges();
	if _name == "":
		_name = "Player";
	#Apply saved or default settings to current SceneTree
	Settings.apply_settings_to_tree(get_tree());
	#Rest and setup state
	GameState.reset_state();
	#reset_state also overwrites current_save_slot, so ensure it's set
	GameState.current_save_slot = actual_slot;
	GameState.player_name = _name;
	
	Analytics.log_event("start_new_game", {
		"slot": actual_slot,
		"player_name_length": _name.length(),
		"is_default_name": _name == "Player"
	})
	
	InventorySystem.reset_inventory();
	DayNightSystem.reset_daily_tracking();
	LevelSystem.reset();
	QuestSystem.reset_quests();
	EncyclopediaSystem.reset();
	DecorationSystem.reset();
	ChestStorageSystem.reset();
	CraftingSystem.reset();
	WorldFlags.reset();
	#Choose the starting spawn point in PlayerHouse
	GameState.pending_spawn_id = "house_start";
	GameState.current_scene_path = PLAYER_HOUSE_PATH;
	#Set flags before _change_scene so it's ready when the transition completes
	_pending_title_card = true;
	_pending_controls_hint = true;
	#Go to the the player house as starting area
	_change_scene(PLAYER_HOUSE_PATH);

func load_game(slot: int) -> void:
	var success: bool = SaveSystem.load_from_slot(slot);
	
	#Analytics
	Analytics.log_event("load_requested", {
		"slot": slot,
		"success": success
	})
	#Ask the SaveSystem to load, then sync scene/world accordingly
	if success:
		GameState.current_save_slot = slot;
		#Ensure player's health is set back to max and they are in idle state
		if _player != null and is_instance_valid(_player) and _player.stats != null:
			_player.state = _player.PlayerState.IDLE;
		#After loading, this will tell us what scene to load into
		var scene_path = GameState.current_scene_path;
		if scene_path == "":
			#Later will need to find what room they were in and load that instead
			scene_path = PLAYER_HOUSE_PATH;
		#Ensure no modals are on screen 
		UIRouter.clear_all_modals();
		unpause_game();
		_change_scene(scene_path);
		#After the scene is ready, position the player, etc.
	else:
		push_warning("Failed to load game from slot %d" % slot);

#Called after the player's death animation finishes
#The player is already in DEATH state and input is not locked by pause yet
func trigger_game_over() -> void:
	Analytics.log_event("game_over_triggered", {
		"scene": _current_scene_path,
		"has_save": SaveSystem.has_any_saves(),
	})
	UIRouter.show_game_over_screen();

func request_save(slot: int = -1) -> bool:
	var actual_slot: int = slot;
	if actual_slot < 0:
		#No slot set yet, choose a default one
		if GameState.current_save_slot < 0:
			GameState.current_save_slot = _choose_default_save_slot();
		actual_slot = GameState.current_save_slot;
		
	#Sync player position into GameState before serialising
	if _player != null and is_instance_valid(_player):
		GameState.player_position = _player.global_position;
		#Restore player stats so health can't be exploited
		if _player.stats != null:
			GameState.player_stats = _player.stats.to_dict();
		Analytics.log_event("player_position_saved", {
			"slot": actual_slot,
			"x": GameState.player_position.x,
			"y": GameState.player_position.y,
			"scene_path": _current_scene_path,
		})
	var success: bool = SaveSystem.save_to_slot(actual_slot);
	Analytics.log_event("save_requested", {
		"slot": actual_slot,
		"success": success
	});
	save_completed.emit(success);
	return success;

#Handler for autosave after quest completion and such
func _on_quest_completed_autosave(_quest_id: String) -> void:
	if GameState.current_save_slot < 0:
		return;
	#Otherwise, good to go
	request_save();
	
func _choose_default_save_slot() -> int:
	#Prefer first empty slot, otherwise fall back to 0
	for i in range(SaveSystem.MAX_SAVE_SLOTS):
		if not SaveSystem.has_save_in_slot(i):
			return i;
	return 0;
	
func transition_player_to_area(scene_path: String, spawn_id: String) -> void:
	#Used for town -> house, house -> town, etc
	#Will be called by doors/interactables
	#var from_scene_path = _current_scene_path;
	GameState.pending_spawn_id = spawn_id;
	GameState.current_scene_path = scene_path;
	
	#Analytics: player requested a transition (before it actually starts)
	#Analytics.log_event("scene_transition_requested", {
		#"from_scene_path": from_scene_path,
		#"to_scene_path": scene_path,
		#"spawn_id": spawn_id,
	#});
	
	_change_scene(scene_path);

#Public function for return to title screen
func return_to_title(save_before: bool = false, slot: int = -1) -> void:
	var actual_slot: int = slot;
	if actual_slot < 0:
		if GameState.current_save_slot >= 0:
			actual_slot = GameState.current_save_slot;
		else:
			actual_slot = _choose_default_save_slot();
			
	var save_success: bool = true;
	if save_before:
		Analytics.log_event("return_to_title_save_requested", {
			"slot": slot,
			"from_scene": get_tree().current_scene.scene_file_path if get_tree().current_scene else ""
		})
		save_success = request_save(slot);
		
	Analytics.log_event("return_to_title", {
		"from_scene": get_tree().current_scene.scene_file_path if get_tree().current_scene else "",
		"save_before": save_before,
		"save_success": save_success,
		"slot": actual_slot
	})
	SaveSystem.save_settings_only();
	#Safety ensure game is unpaused before changing scenes
	unpause_game();
	#Ensure all modals are closed
	UIRouter.clear_all_modals();
	#Later add a check to ensure it only goes to title screen if the save is successful
	_change_scene(TITLE_SCREEN_PATH);

#Public function to go to the end of the day screen
func show_end_of_day_screen() -> void:
	UIRouter.clear_all_modals();
	unpause_game();
	_change_scene(END_OF_DAY_SCREEN_PATH);
	
#Attach the player to the world and place them
func _attach_and_place_player(world: Node, spawn_id: String) -> void:
	#Only place player if it's a world scene--not the title screen or other menus
	var world_scene := world as WorldScene;
	if world_scene == null:
		return;
	
	#Ensure player exists first
	_ensure_player_exists();
	if _player == null or not is_instance_valid(_player):
		push_error("[Game]: _attach_and_place_player called but _player is missing");
		Analytics.log_event("player_attach_failed", {
			"scene_path": _current_scene_path,
			"reason": "player_missing",
			"spawn_id": spawn_id,
		})
		return;
	
	#Parent the player under the world's Actors container
	#Fixes draw order, YSort integration, lighting, and camera limits
	if world_scene.actors == null:
		push_warning("WorldScene has no Actors node. Add a Node2D name 'Actors'.");
	else:
		var current_parent = _player.get_parent();
		if current_parent != world_scene.actors:
			#First time attaching the player
			if current_parent == null:
				world_scene.actors.add_child(_player);
			else:
				#Already in the tree somewhere else, safe to reparent
				_player.reparent(world_scene.actors);
			
	#Positioing
	var used_spawn_id = spawn_id;
	var spawn_point: Node2D = null;
	
	#If we have a spawn_id, try to use the matching spawn point
	if not spawn_id.is_empty():
		spawn_point = world_scene.get_spawn_point(spawn_id);
		if spawn_point == null:
			push_warning("No SpawnPoint with id '%s' found in the scene." % spawn_id);
	
	#No spawn id, or spawn lookup failed, used saved position if available
	if spawn_point == null and spawn_id.is_empty():
		#Loaded from save path
		_player.global_position = GameState.player_position;
		#Restore facing direction from GameState
		_player.facing_dir = GameState.player_facing_dir;
		_player.call("_update_animation");
	else:
		#We did find a spawn point, snap to it
		if spawn_point != null:
			_player.global_position = spawn_point.global_position;
			#Restore facing direction from GameState
			_player.facing_dir = GameState.player_facing_dir;
			#Start player as mid-walk like we just came from the other area
			#Only if the state was set
			if GameState.pending_walk_through:
				_player.state = _player.PlayerState.WALK;
			_player.call("_update_animation");
		
	#Ensure player camera is the current one
	var player_cam = VisualFX.get_player_camera();
	if player_cam:
		player_cam.make_current();
		#Keep VisualFX shake targeting aligned as well
		VisualFX.set_active_camera(player_cam);
		#Force snap camera to player position so smoothing doesn't drift from death position
		player_cam.position_smoothing_enabled = false;
		await get_tree().process_frame;
		player_cam.position_smoothing_enabled = true;
	#Restore the players state 
	_player.restore_state();
	player_ready.emit();
	Analytics.log_event("player_attached_to_scene", {
		"scene_path": _current_scene_path,
		"spawn_id": used_spawn_id,
		"has_spawn_id": not used_spawn_id.is_empty(),
		"spawn_point_found": spawn_point != null,
		"place_from_saved_position": spawn_point == null and spawn_id.is_empty(),
	})

#Check if there is a player and create it in the scene if not
func _ensure_player_exists() -> void:
	#Keeps player consistent across world scene changes
	if _player != null and is_instance_valid(_player):
		return;
	
	var player_scene: PackedScene = load(PLAYER_SCENE_PATH);
	if player_scene == null:
		push_error("[Game]: failed to load Player scene at %s" % PLAYER_SCENE_PATH);
		return;
		
	_player = player_scene.instantiate() as CharacterBody2D;
	if _player == null:
		push_error("[Game]: Player scene is not a CharacterBody2D.")
		return;
	
	#Safety checks passed
	_player.add_to_group("player");
	_player.name = "Player";
	
	Analytics.log_event("player_instance_created", {
		"scene_path": PLAYER_SCENE_PATH,
	})
	
#Internal helper for loading/unloading scenes
func _change_scene(scene_path: String) -> void:
	#Scene is already changing, exit early
	if _is_changing_scene:
		return;
	#Set to true
	_is_changing_scene = true;
	
	#Mark when the transition begins for analytics
	_scene_change_start_time = Time.get_unix_time_from_system();
	var from_scene_path = _current_scene_path;
	var pending_spawn_id = GameState.pending_spawn_id;
	#Analytics: scene transition actually started
	Analytics.log_event("scene_transition_started", {
		"from_scene_path": from_scene_path,
		"to_scene_path": scene_path,
		"spawn_id": pending_spawn_id,
	});
	
	#Lock input while transitioning
	push_input_lock("scene_transition");
	#Autosave on a scene transition
	if GameState.current_save_slot >= 0:
		request_save();
		
	#Fade to black
	await TransitionScene.to_black();
	#Ensure the black frame renders before swapping scenes
	await get_tree().process_frame;
		
	#If there was a previous scene, free it to avoid memory leaks
	if _current_scene != null:
		_current_scene.queue_free();
		_current_scene = null;
		
	#Load the PackedScene resource from disk
	var packed := load(scene_path) as PackedScene;
	if packed == null:
		push_error("Failed to load scene: %s" % scene_path);
		#Analytics: transition failed due to load error
		Analytics.log_event("scene_transition_failed", {
			"from_scene_path": from_scene_path,
			"to_scene_path": scene_path,
			"reason": "load_failed",
		});
		
		#Fade back in so player isn't stuck in the black screen
		await TransitionScene.to_clear();
		pop_input_lock("scene_transition");
		_is_changing_scene = false;
		return;
	
	#Instantiate the scene (turn the PackedScene into a live node tree)
	_current_scene = packed.instantiate();
	#Add it to the root of the SceneTree so it becomes the current world/scene
	get_tree().root.add_child(_current_scene);
	#Save bookkeeping details
	_current_scene_path = scene_path;
	GameState.current_scene_path = scene_path;
	#Set the human readable name for the save screen
	if _current_scene is WorldScene and not _current_scene.location_name.is_empty():
		GameState.current_location_name = _current_scene.location_name;
	#Let anyone who cares know the scene changed
	scene_changed.emit(scene_path);
	
	#Analytics: scene resource instatiated and set as current
	#Analytics.log_event("scene_changed", {
		#"scene_path": scene_path,
		#"is_world_scene": _current_scene is WorldScene,
	#});
	
	#Wait one frame so onready vars resolve reliably
	await get_tree().process_frame;
	#Place player now
	_attach_and_place_player(_current_scene, GameState.pending_spawn_id);
	GameState.pending_spawn_id = "";
	#Restore decorations in WorldScene scenes
	if _current_scene is WorldScene and not _current_scene.location_name.is_empty():
		DecorationSystem.restore_to_scene(_current_scene); 
	#Wait for world to say it's ready, or fall back to a frame
	if _current_scene.has_method("is_world_ready_for_reveal"):
		#Poll until the world marks itself as ready
		while not _current_scene.is_world_ready_for_reveal():
			await get_tree().process_frame;
	else:
		#Fallback at least one extra frame to be safe
		await get_tree().process_frame;
	
	
	#Give it a sec to have the player see the screen
	await get_tree().process_frame;
	#Then show the lore title card before returning things to player if it's the first time
	if _pending_title_card:
		#Don't use the fancy shader animation, just fade
		TransitionScene.to_clear(false);
		_pending_title_card = false;
		await UIRouter.show_title_card();
	else:
		#Fade back in normally using the shader
		await TransitionScene.to_clear();
		
	#Toggle HUD is this is a world scene
	var hud_visible: bool = _current_scene is WorldScene and not suppress_next_hud_show;
	suppress_next_hud_show = false;
	UIRouter.set_hud_visible(hud_visible);
	
	#Ensure player can move again
	pop_input_lock("scene_transition");
	#Show controls hint on first entry if requested
	if _pending_controls_hint:
		_pending_controls_hint = false;
		UIRouter.show_controls_hint();
	_is_changing_scene = false;
	#Analytics: transition fully completed (including faded and player placement)
	var duration_sec: float = Time.get_unix_time_from_system() - _scene_change_start_time;
	Analytics.log_event("scene_transition_completed", {
		"from_scene_path": from_scene_path,
		"to_scene_path": scene_path,
		"duration_sec": duration_sec,
		"hud_visible": hud_visible,
	})
		
func pause_game() -> void:
	#Pauses the entire SceneTree
	#UI on a different CanvasLayer will still work by default
	get_tree().paused = true;
	
func unpause_game() -> void:
	#Unpauses the game
	get_tree().paused = false;
	
#Track playtime
func _process(delta: float) -> void:
	#Only count when game is not paused and in a world scene
	if get_tree().paused:
		return;
	if _current_scene is WorldScene:
		GameState.total_play_time_sec += delta;

func _on_first_time_item_acquired(item_id: String, amount: int) -> void:
	#Tell player to enter the item-get pose and zoom
	if _player:
		_player.start_item_get_cinematic(item_id);
	#Show the popup 
	UIRouter.show_item_get_popup(item_id, _player.global_position, amount);
	var hud = UIRouter.get_hud();
	if hud:
		UIRouter.set_hud_visible(false);
func end_item_get_cinematic() -> void:
	if _player:
		_player.end_item_get_cinematic();
	var hud = UIRouter.get_hud();
	if hud:
		#Only restore if dialogue isn't active
		if not DialogueSystem.is_active():
			UIRouter.set_hud_visible(true);
		
#Public getter to check if we're in a world scene
func is_world_scene() -> bool:
	return _current_scene is WorldScene;
	
func get_current_scene() -> Node:
	return _current_scene;
