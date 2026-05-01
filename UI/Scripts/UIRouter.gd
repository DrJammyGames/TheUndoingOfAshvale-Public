extends Node
#Central UI Controller: opens/closes screens, talks to Game about pausing

var vignette_scene: PackedScene = preload("res://FX/Scenes/ScreenFXLayer.tscn");
var hud_scene: PackedScene = preload("res://UI/Scenes/OtherMenus/HUD.tscn");
var dialogue_box_scene: PackedScene = preload("res://UI/Scenes/Dialogue/DialogueBox.tscn");
var quest_complete_banner_scene: PackedScene = preload("res://UI/Scenes/Quests/QuestCompleteBanner.tscn");
var level_up_banner_scene: PackedScene = preload("res://UI/Scenes/OtherMenus/LevelUpBanner.tscn");
var options_scene: PackedScene = preload("res://UI/Scenes/Options/OptionsMenu.tscn");
var pause_menu_scene: PackedScene = preload("res://UI/Scenes/OtherMenus/PauseMenu.tscn");
var save_slots_scene: PackedScene = preload("res://UI/Scenes/OtherMenus/SaveSlotsMenu.tscn");
var name_entry_scene: PackedScene = preload("res://UI/Scenes/OtherMenus/NameEntryScene.tscn");
var tabbed_menu_scene: PackedScene = preload("res://UI/Scenes/OtherMenus/TabbedMenu.tscn");
var decoration_mode_ui_scene: PackedScene = preload("res://UI/Scenes/OtherMenus/DecorationModeUI.tscn");
var item_get_popup_scene: PackedScene = preload("res://UI/Scenes/NewItemPopup.tscn");
var game_over_scene: PackedScene = preload("res://UI/Scenes/OtherMenus/GameOverScreen.tscn");
var lore_title_card_scene: PackedScene = preload("res://UI/Scenes/OtherMenus/LoreTitleCard.tscn");
var control_hints_scene: PackedScene = preload("res://UI/Scenes/OtherMenus/ControlsHintScreen.tscn");
var bed_confirm_scene: PackedScene = preload("res://UI/Scenes/OtherMenus/BedConfirmDialogue.tscn");
var crafting_table_scene: PackedScene = preload("res://UI/Scenes/Crafting/CraftingScreen.tscn");
var chest_screen_scene: PackedScene = preload("res://UI/Scenes/OtherMenus/ChestScreen.tscn");

#The root CanvasLayer that all UI instances will live under
var _ui_root: CanvasLayer = null;
#Variable to allow for proper scaling
var _scaled_ui_root: Control = null;
#Persistent reference to the HUD instance
var _hud_instance: Control = null;
#Persistent reference to quest complete banner
var _quest_banner_instance: Control = null;
#Persistent reference to level up banner
var _level_up_banner_instance: Control = null;
#Level-up banner queue (mirrors quest banner pattern)
var _queued_level_ups: Array[int] = [];
var _is_flushing_level_ups: bool = false;
#Variables to control when quest banner is shown
var _ui_banner_lock_count: int = 0;
var _queued_quest_completions: Array[String] = [];
var _is_flushing_quest_banners: bool = false;
#Quest id -> building id to focus/upgrade
const QUEST_REPAIR_BUILDING_MAP := {
	"q_rebuild_town_hall": "town_hall",
	"q_rebuild_blacksmith": "blacksmith",
	"q_rebuild_alchemist": "alchemist",
};
#Trigger for in-world visual updates
signal quest_completion_ui_finished(quest_id: String);
#Signal that the chest UI has closed
signal chest_ui_closed;
#Current active topmost modal
var _current_modal: Control = null;
#Stack of opened modals
#This allows nested screens (options from Pause menu, etc)
var _modal_stack: Array[Control] = [];
#Safety check for if a modal is already closing
var _is_closing_modal: bool = false;
#Remember which tab was last active so Esc reopens to the same one
var _last_tabbed_menu_tab: String = "player";
var _pending_demo_complete: bool = false;

func _ready() -> void:
	#Wait a frame so other things can load first
	call_deferred("_deferred_ready");

func _deferred_ready() -> void:
	#Can be called manually from Main once UIRouter is ready
	_ensure_ui_root();
	_spawn_hud();
	_spawn_quest_complete_banner();
	_spawn_level_up_banner();
	_spawn_vignette_overlay();
	#Start with HUD hidden--spawn in Game once past title screen
	set_hud_visible(false);
	#Connect dialogue started system
	DialogueSystem.dialogue_started.connect(_on_dialogue_started);

#region Public helpers
#Turn hud off during dialogue (and later cutscenes)
func set_hud_visible(visible: bool) -> void:
	if _hud_instance:
		_hud_instance.visible = visible;
		
func get_hud() -> HUD:
	return _hud_instance;
	
func get_tabbed_menu() -> Control:
	for modal in _modal_stack:
		if modal is TabbedMenu:
			return modal;
	return null;
	
func show_inventory() -> void:
	#If tabbed menu is already open, just switch tab
	var tabbed_menu = get_tabbed_menu();
	if tabbed_menu:
		if _current_modal == tabbed_menu and tabbed_menu.has_method("is_inventory_tab_active") \
		and tabbed_menu.call("is_inventory_tab_active"):
			#Toggle off if already on top and inventory tab active
			close_top_modal();
		else:
			tabbed_menu.call_deferred("show_inventory_tab");
		return;
	#If not open at all, open the tabbed menu and request inventory tab
	_open_tabbed_menu("inventory");

func show_quest_log() -> void:
	#Same logic here for quest log
	var tabbed_menu = get_tabbed_menu();
	if tabbed_menu:
		if _current_modal == tabbed_menu and tabbed_menu.has_method("is_quest_tab_active") \
		and tabbed_menu.call("is_quest_tab_active"):
			close_top_modal();
		else:
			tabbed_menu.call_deferred("show_quest_tab");
		return;
		
	_open_tabbed_menu("quest");
	
func show_options() -> void:
	if options_scene == null:
		return;
		
	#If options is already on top, close it (toggle behaviour)
	if _current_modal != null and _current_modal.scene_file_path == options_scene.resource_path:
		close_top_modal();
		return;
		
	#If it's somewhere in the stack already, don't reopen
	if _is_modal_open_for_scene(options_scene):
		return;
	#Safety checks passed, open options menu
	_open_modal(options_scene);
	AudioManager.play_sfx("open_menu");
	
func toggle_pause_menu(source: String = "input") -> void:
	var tabbed_menu = get_tabbed_menu();
	
	#If the tabbed menu is already open
	if tabbed_menu:
		#If it's already on top and showing the Player info tab, close it
		if _current_modal == tabbed_menu:
			#Analytics
			Analytics.log_event("tabbed_menu_toggled", {
				"action": "close",
				"source": source,
				"remaining_modals": _modal_stack.size() -1,
				"via": "tabbed_menu"
			})
			close_top_modal();
		return;
		
	#If some other modal is open, ignore Esc for pausing
	if _current_modal != null:
		return;
	
	#No modal open, so open the tabbed menu on the Player info screen
	Analytics.log_event("tabbed_menu_toggled", {
		"action": "open",
		"source": source,
		"remaining_modals": _modal_stack.size(),
		"via": "tabbed_menu"
	})
	_open_tabbed_menu(_last_tabbed_menu_tab);
	
	
func show_slot_select_for_new_game() -> void:
	_show_save_slot_screen("new_game");

func show_slot_select_for_load_game() -> void:
	_show_save_slot_screen("load_game");
	
func show_name_entry_for_new_game() -> void:
	_ensure_ui_root();
	if name_entry_scene == null:
		push_warning("UIRouter: name_entry_scene is not set");
		return;
		
	var instance: Control = name_entry_scene.instantiate();
	_scaled_ui_root.add_child(instance);
	_modal_stack.append(instance);
	_current_modal = instance;
	
	Game.pause_game();

	Analytics.log_event("ui_modal_opened", {
		"scene_path": name_entry_scene.resource_path,
		"stack_depth": _modal_stack.size(),
		"modal_type": "name_entry_new_game"
	})

#Show the item popup message
func show_item_get_popup(item_id: String, player_world_pos: Vector2 = Vector2.INF, amount: int = 1) -> void:
	if item_id.is_empty():
		return;
	
	#First, open it
	_open_modal(item_get_popup_scene);
	var popup: Control = _current_modal;
	
	#Then call the popup setup method
	if popup.has_method("setup"):
		popup.call_deferred("setup", item_id, amount);
	#Position the popup relative to the player if we got a world position
	if player_world_pos != Vector2.INF and popup.has_method("position_above_player"):
		popup.call_deferred("position_above_player", player_world_pos);
	
	Analytics.log_event("ui_item_get_popup_shown", {
		"item_id": item_id,
		"scene": Analytics.get_scene_path(),
	})

#Show the message from the sign
func show_sign_message(title: String, body: String) -> void:
	_ensure_ui_root();
	if _hud_instance == null:
		return;
		
	var hud = _hud_instance as HUD;
	#If the hud doesn't exist
	if hud == null:
		return;
	
	#Pause game while sign is open
	Game.pause_game();
	hud.show_sign(title, body);
	
	#Hook close once so we can unpause when the sign closes
	call_deferred("_watch_sign_close");
		
#Show the game over screen
func show_game_over_screen() -> void:
	if game_over_scene == null:
		push_warning("[UIRouter]: game_over_screen_scene is not set.");
		return;
	Analytics.log_event("game_over_screen_shown", {
		"stack_depth": _modal_stack.size(),
	})
	_open_modal(game_over_scene);
	
#Lore title card for starting new game
func show_title_card() -> void:
	if lore_title_card_scene == null:
		push_warning("[UIRouter]: lore_title_card_scene is not set");
		return;
		
	#Safety check passed
	_ensure_ui_root();
	var instance: Control = lore_title_card_scene.instantiate();
	_scaled_ui_root.add_child(instance);
	_modal_stack.append(instance);
	_current_modal = instance;
	
	Analytics.log_event("lore_title_card_shown", {
		"stack_depth": _modal_stack.size(),
	})
	await instance.close_animation_finished;
	
#Controls hints for starting new game
func show_controls_hint() -> void:
	if control_hints_scene == null:
		push_warning("[UIRouter]: controls_hint_scene is not set");
		return;
		
	_ensure_ui_root();
	var instance: Control = control_hints_scene.instantiate();
	_scaled_ui_root.add_child(instance);
	_modal_stack.append(instance);
	_current_modal = instance;
	#Not calling Game.pause_game()--want the player to be able to move
	Analytics.log_event("controls_hint_shown", {
		"stack_depth": _modal_stack.size()
	})
	
#Show confirm save and end day message
func show_bed_confirm() -> void:
	_ensure_ui_root();
	if bed_confirm_scene == null:
		return;
	#Safety checks passed
	var popup = bed_confirm_scene.instantiate() as BedConfirmDialogue;
	_scaled_ui_root.add_child(popup);
	Game.pause_game();
	popup.flow_completed.connect(func(accepted: bool) -> void:
		popup.queue_free()
		if not accepted:
			Game.unpause_game();
			return;
		DayNightSystem.end_day()
	, CONNECT_ONE_SHOT);
	Analytics.log_event("bed_confirm_shown", {
		"current_day": GameState.current_day,
	})
	
#Open crafting menu
func show_crafting_menu() -> void:
	if _is_modal_open_for_scene(crafting_table_scene) or crafting_table_scene == null:
		return;
	#Otherwise, good to open modal
	_open_modal(crafting_table_scene, Callable(), true, true);
	
func show_chest_ui() -> void:
	if _is_modal_open_for_scene(chest_screen_scene) or chest_screen_scene == null:
		return;
	var instance: Control = _open_modal(chest_screen_scene);
	#When the chest screen closes, emit the chest_ui_closed for the chest world object
	if instance.has_signal("close_animation_finished"):
		instance.close_animation_finished.connect(func() -> void:
			chest_ui_closed.emit()
		, CONNECT_ONE_SHOT);
		
#Open decorating menu
func show_decoration_mode_ui() -> void:
	if not is_modal_open():
		return;
	#Close the tabbed menu with its normal animation first then spawn the decoration ui
	call_deferred("_close_then_open_decoration");
	
#Internal call to first close teh tabbed menu, then open the decoration mode UI
func _close_then_open_decoration() -> void:
	#Close the TabbedMenu that's open on top
	await close_top_modal(true);
	if _is_modal_open_for_scene(decoration_mode_ui_scene) or decoration_mode_ui_scene == null:
		return;
	_open_modal(decoration_mode_ui_scene);
	
#Hide panel
func hide_decoration_mode_ui() -> void:
	#Find and free any active decoration UI
	for child in _scaled_ui_root.get_children():
		if child is DecorationModeUI:
			child.queue_free();
			return;
			
func close_top_modal(keep_paused: bool = false) -> void:
	if _modal_stack.is_empty():
		return;
	if _is_closing_modal:
		return;
	
	_is_closing_modal = true;
	var modal: Control = _modal_stack.pop_back();
	var closed_scene_path: String = "";
	#Play close animation if the modal supports it, then free
	if modal.has_signal("close_animation_finished"):
		modal.play_close_animation(); 
		await modal.close_animation_finished;
	if is_instance_valid(modal):
		#Remember which tab was active before freeing
		if modal is TabbedMenu:
			_last_tabbed_menu_tab = (modal as TabbedMenu).get_current_tab_name();
		closed_scene_path = modal.scene_file_path;
		modal.queue_free();
		
	#Generic Analytics for modal close
	Analytics.log_event("ui_modal_closed", {
		"scene_path": closed_scene_path,
		"stack_depth": _modal_stack.size(),
	})
	#Select new current modal if any
	if _modal_stack.size() > 0:
		_current_modal = _modal_stack.back();
	else:
		_current_modal = null;
	if Game.is_world_scene():
		AudioManager.play_sfx("close_menu");
	if _current_modal == null and not keep_paused:
		Game.unpause_game();
	#Refresh interaction prompt now that all modals are closed
	if _current_modal == null and _hud_instance and _hud_instance.has_method("refresh_interaction_prompt"):
		_hud_instance.refresh_interaction_prompt();
	#Set back to false
	_is_closing_modal = false;

#Force-close all modals immediately with no animation.
#Called before scene transitions so modals don't persist across them.
func clear_all_modals() -> void:
	for modal in _modal_stack:
		if is_instance_valid(modal):
			modal.queue_free();
	_modal_stack.clear();
	_current_modal = null;

func is_modal_open() -> bool:
	return _current_modal != null;
	
#Quest banner public helpers
func push_banner_lock(_source: String = "unknown") -> void:
	_ui_banner_lock_count += 1;
	
func pop_banner_lock(_source: String = "unknown") -> void:
	_ui_banner_lock_count = max(_ui_banner_lock_count - 1, 0);
	if _ui_banner_lock_count == 0:
		_flush_queued_quest_banners();

func get_banner_lock_count() -> int:
	return _ui_banner_lock_count;
	
#Check if any banners are queued
func has_queued_banners() -> bool:
	if _queued_quest_completions.size() > 0:
		return true;
	if _queued_level_ups.size() > 0:
		return true;
	if _quest_banner_instance and _quest_banner_instance.visible:
		return true;
	if _level_up_banner_instance and _level_up_banner_instance.visible:
		return true;
	return false;
#endregion
#region Internal helpers
#Make sure there is a CanvasLayer for UI
#This keeps the UI independent of camera movement	
func _ensure_ui_root() -> void:
	if _ui_root == null:
		_ui_root = CanvasLayer.new();
		_ui_root.name = "UIRoot";
		_ui_root.process_mode = Node.PROCESS_MODE_ALWAYS;
		get_tree().root.add_child(_ui_root);
		#Create a child Control that will be what is actually scaled
		_scaled_ui_root = Control.new();
		_scaled_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE;
		_scaled_ui_root.name = "ScaledUIRoot";
		_scaled_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT);
		_scaled_ui_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
		_scaled_ui_root.size_flags_vertical = Control.SIZE_EXPAND_FILL;
		_ui_root.add_child(_scaled_ui_root);
		_scaled_ui_root.child_entered_tree.connect(_on_scaled_ui_child_added);
		#After it's added, move the tooltip under the UI root
		_attach_tooltip_to_ui_root();
	else:
		#If called again and scaled root is missing for some reason, recreate it
		if _scaled_ui_root == null or not is_instance_valid(_scaled_ui_root):
			_scaled_ui_root = Control.new();
			_scaled_ui_root.name = "ScaledUIRoot";
			_scaled_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT);
			_scaled_ui_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
			_scaled_ui_root.size_flags_vertical = Control.SIZE_EXPAND_FILL;
			_ui_root.add_child(_scaled_ui_root);
		
#Internal function to apply the proper text settings
func _on_scaled_ui_child_added(_node: Node) -> void:
	#Defer so the scene's full subtree is ready before walking it
	Settings.call_deferred("apply_text_size_to_node", _node);
	
#Open the tabbed menu on the correct tab
func _open_tabbed_menu(initial_tab: String) -> void:
	_ensure_ui_root();
	#If the tabbed_menu_scene is empty, push warning and exit
	if tabbed_menu_scene == null:
		push_warning("UIRouter: tabbed_menu_scene is not set");
		return;
		
	var instance: Control = tabbed_menu_scene.instantiate();
	_scaled_ui_root.add_child(instance);
	_modal_stack.append(instance);
	_current_modal = instance;
	
	#Ensure Game is paused with this open
	Game.pause_game();
	
	#Ensure interaction prompt gets hidden
	_hud_instance.hide_interaction_prompt();
	
	if instance.has_method("set_initial_tab"):
		instance.call("set_initial_tab", initial_tab);
	AudioManager.play_sfx("open_menu");
	#Analytics
	Analytics.log_event("ui_modal_opened", {
		"scene_path": tabbed_menu_scene.resource_path,
		"stack_depth": _modal_stack.size(),
		"modal_type": "tabbed_menu",
		"initial_tab": initial_tab
	})


	
func _attach_tooltip_to_ui_root() -> void:
	if GlobalTooltip == null:
		return;
	#Get parent
	var parent := GlobalTooltip.get_parent(); 
	#If it's already parented correctly, do nothing
	if parent == _ui_root:
		return;
	#Detach from old parent (likely /root)
	if parent != null:
		parent.remove_child(GlobalTooltip);
	#Attach to the UI Canvas layer instead
	_scaled_ui_root.add_child(GlobalTooltip);
	#Ensure it draws on top of other UI
	_scaled_ui_root.move_child(GlobalTooltip, _scaled_ui_root.get_child_count() - 1);

func _spawn_hud() -> void:
	#Frees any existing HUD instance (safety if we ever respawn)
	if _hud_instance:
		_hud_instance.queue_free();
	#Instantiate the HUD scene and add it under the UI root
	_hud_instance = hud_scene.instantiate() as Control;
	_scaled_ui_root.add_child(_hud_instance);

#Spawn the complete quest banner
func _spawn_quest_complete_banner() -> void:
	if is_instance_valid(_quest_banner_instance):
		_quest_banner_instance.queue_free();
		_quest_banner_instance = null;
		
	if quest_complete_banner_scene == null:
		return;
		
	_quest_banner_instance = quest_complete_banner_scene.instantiate() as QuestCompleteBanner;
	_scaled_ui_root.add_child(_quest_banner_instance);
	var banner = _quest_banner_instance as QuestCompleteBanner;
	if banner and not banner.finished.is_connected(_on_quest_banner_finished):
		banner.finished.connect(_on_quest_banner_finished);
	#Draw above HUD, below tooltip
	_place_under_global_tooltip(_quest_banner_instance);
	
	#Hook into quest system
	if QuestSystem and QuestSystem.has_signal("quest_completed"):
		if not QuestSystem.quest_completed.is_connected(_on_quest_completed):
			QuestSystem.quest_completed.connect(_on_quest_completed);

#Check the quest has been completed
func _on_quest_completed(quest_id: String) -> void:
	#If dialogue is currently open, queue the quest banner
	if not _can_show_banners_now():
		_queued_quest_completions.append(quest_id);
		return;
	#Otherwise, show immediately
	_show_banner_now(quest_id);

#Helper for demo completion message
func _try_show_demo_complete() -> void:
	if not _pending_demo_complete:
		return;
	_pending_demo_complete = false;
	show_sign_message("Demo Completed!", "Thank you for playing The Undoing of Ashvale! You have finished the five available quests, but feel free to continue exploring or crafting!")

#Internal helper to show banner now
func _can_show_banners_now() -> bool:
	if _ui_banner_lock_count > 0:
		return false;
	if _current_modal != null:
		return false;
	if _quest_banner_instance and _quest_banner_instance.visible:
		return false;
	if _level_up_banner_instance and _level_up_banner_instance.visible:
		return false;
	#Otherwise, we're good, show the banner
	return true;
	
#Actually show the quest banner
func _show_banner_now(quest_id: String) -> void:
	if _quest_banner_instance == null:
		return;
	_hud_instance.hide_interaction_prompt();
	Game.pause_game();
	set_hud_visible(false);
	(_quest_banner_instance as QuestCompleteBanner).show_for_quest(quest_id);
	
#Implement the flush for quest banner and dialogues
func _flush_queued_quest_banners() -> void:
	if _is_flushing_quest_banners:
		return;
	if not _can_show_banners_now():
		return;
	if _quest_banner_instance == null:
		return;
		
	_is_flushing_quest_banners = true;
	
	var banner = _quest_banner_instance as QuestCompleteBanner;
	if banner == null:
		_is_flushing_quest_banners = false;
		return;
		
	while _queued_quest_completions.size() > 0 and _can_show_banners_now():
		var quest_id = _queued_quest_completions.pop_front();
		
		set_hud_visible(false);
		Game.pause_game();
		#Show banner
		banner.show_for_quest(quest_id);
		
		#Wait until it's actually finished
		await banner.finished;
		#Signal that the banner has finished
		quest_completion_ui_finished.emit(quest_id);
		
		#Check if final quest of vertical slice demo
		if quest_id == "q_witch_crafting_table":
			_pending_demo_complete = true;
		
		#If a dialogue or modal started while showing, stop flushing
		if not _can_show_banners_now():
			break;
	
	_is_flushing_quest_banners = false;
	#Chain any queued level-ups now that quest banners are done
	_flush_queued_level_ups();
	if _queued_level_ups.is_empty() and not _is_flushing_level_ups:
		if _current_modal == null:
			Game.unpause_game();
		set_hud_visible(true);
		_try_show_demo_complete();
	
#The quest banner has finished, can update UI elsewhere
func _on_quest_banner_finished(quest_id: String) -> void:
	#Only fired if it wasn't handeled by the flushing path
	if _is_flushing_quest_banners:
		return;
	quest_completion_ui_finished.emit(quest_id);
	if quest_id == "q_witch_crafting_table":
		_pending_demo_complete = true;
	#Chain any queued level-ups
	if _queued_level_ups.size() > 0:
		call_deferred("_flush_queued_level_ups");
	else:
		if _current_modal == null:
			Game.unpause_game();
		set_hud_visible(true);
		_try_show_demo_complete();
	
#Spawn the level-up banner 
func _spawn_level_up_banner() -> void:
	if is_instance_valid(_level_up_banner_instance):
		_level_up_banner_instance.queue_free();
		_level_up_banner_instance = null;
	if level_up_banner_scene == null:
		return;
	_level_up_banner_instance = level_up_banner_scene.instantiate() as LevelUpBanner;
	_scaled_ui_root.add_child(_level_up_banner_instance);
	var banner = _level_up_banner_instance as LevelUpBanner;
	if banner and not banner.finished.is_connected(_on_level_up_banner_finished):
		banner.finished.connect(_on_level_up_banner_finished);
	_place_under_global_tooltip(_level_up_banner_instance);
	#Hook into LevelSystem
	if LevelSystem and not LevelSystem.leveled_up.is_connected(_on_leveled_up):
		LevelSystem.leveled_up.connect(_on_leveled_up);

#Queue the level-up for display
func _on_leveled_up(new_level: int) -> void:
	_queued_level_ups.append(new_level);
	#If nothing is blocking, flush on the next frame
	if _can_show_banners_now():
		call_deferred("_flush_queued_level_ups");
		
#Show the level-up banner immediately
func _show_level_up_now(new_level: int) -> void:
	if _level_up_banner_instance == null:
		return;
	var data: Dictionary = _build_level_up_data(new_level);
	Game.pause_game();
	set_hud_visible(false);
	(_level_up_banner_instance as LevelUpBanner).show_level_up(data);
	
#Build the data dictionary for the banner display
func _build_level_up_data(new_level: int) -> Dictionary:
	var stats: PlayerStats = null;
	var player = Game.get_player();
	if player and player.has_method("get_stats"):
		stats = player.get_stats();
	#Stats are already updated by the time we get here so
	#compute old values by subtracting the per-level constants
	var data: Dictionary = {
		"new_level": new_level,
		"old_max_health": (stats.max_health - LevelSystem.HP_PER_LEVEL),
		"new_max_health": stats.max_health,
		"old_attack": (stats.attack - LevelSystem.ATTACK_PER_LEVEL),
		"new_attack": stats.attack,
		"old_defense": (stats.defense - LevelSystem.DEFENSE_PER_LEVEL),
		"new_defense": stats.defense,
		"old_luck": (stats.luck - LevelSystem.LUCK_PER_LEVEL),
		"new_luck": stats.luck,
		"unlocked_recipes": [] as Array[Dictionary],
		"inventory_expanded": LevelSystem.INVENTORY_MILESTONES.has(new_level),
		"new_slot_count": LevelSystem.INVENTORY_MILESTONES.get(new_level, 0) * LevelSystem.SLOTS_PER_ROW,
	};
	
	#Find the recipes that unlock exactly at this level and show it's name and icon
	for recipe in RecipeDatabase.get_all_recipes():
		if recipe.unlock_source == RecipeDataResource.UnlockSource.LEVEL_UP \
		and recipe.required_level == new_level and recipe.result_item:
			data["unlocked_recipes"].append({
				"name": ItemDatabase.get_display_name(recipe.result_item.item_id),
				"icon": recipe.result_item.icon_inv,
			});
	return data;
	
#Process queued level-ups sequentially
func _flush_queued_level_ups() -> void:
	if _is_flushing_level_ups:
		return;
	if not _can_show_banners_now():
		return;
	if _level_up_banner_instance == null:
		return;
	_is_flushing_level_ups = true;
	var banner = _level_up_banner_instance as LevelUpBanner;
	if banner == null:
		_is_flushing_level_ups = false;
		return;
	while _queued_level_ups.size() > 0 and _can_show_banners_now():
		set_hud_visible(false);
		Game.pause_game();
		var level: int = _queued_level_ups.pop_front();
		_show_level_up_now(level);
		await banner.finished;
		#Unpause between level-ups (pause again at top of next iteration)
		if _current_modal == null:
			Game.unpause_game();
	_is_flushing_level_ups = false;
	set_hud_visible(true);
	_try_show_demo_complete();
	
#Handle banner dismissed (only fires outside the flushing path)
func _on_level_up_banner_finished() -> void:
	if _is_flushing_level_ups:
		return;
	if _current_modal == null:
		Game.unpause_game();
	set_hud_visible(true);
	_try_show_demo_complete();
	#Flush any remaining quest banners that may have queued
	if _queued_quest_completions.size() > 0:
		call_deferred("_flush_queued_quest_banners");
		
		
func _watch_sign_close() -> void:
	#Avoid multiple watchers stacking
	if _hud_instance == null:
		return;
		
	var hud = _hud_instance as HUD;
	if hud == null:
		return;
		
	#Wait until sign closes, then unpause
	while hud.is_sign_open():
		await get_tree().process_frame;
		
	#If no modal is open, resume game
	if _current_modal == null:
		Game.unpause_game();
#Only open if it doesn't already exist
func _is_modal_open_for_scene(scene: PackedScene) -> bool:
	if scene == null:
		return false;
	var target_path: String = scene.resource_path;
	if target_path.is_empty():
		return false;
		
	for modal in _modal_stack:
		#Nodes instantiated from a scene have a scene_file_path set
		if modal is Node and (modal as Node).scene_file_path == target_path:
			return true;
	
	return false;
	
#Internal helper: open a new modal screen from a PackedScene
func _open_modal(scene: PackedScene, setup: Callable = Callable(), 
	pause: bool = true, play_sfx: bool = false) -> Control:
	_ensure_ui_root();
	var instance: Control = scene.instantiate();
	_scaled_ui_root.add_child(instance);
	_modal_stack.append(instance);
	_current_modal = instance;
	if pause:
		Game.pause_game();
	if play_sfx:
		AudioManager.play_sfx("open_menu");
	if setup.is_valid():
		setup.call(instance);
	if _hud_instance and _hud_instance.has_method("hide_interaction_prompt"):
		_hud_instance.hide_interaction_prompt();
		
	Analytics.log_event("ui_modal_opened", {
		
	});
	return instance;

#Open save slots menu
func _show_save_slot_screen(mode: String) -> void:
	_ensure_ui_root();
	
	if save_slots_scene == null:
		push_warning("[UIRouter]: save_slots_scene is not set.");
		return;
		
	#Safety checks passed
	var instance: Control = save_slots_scene.instantiate();
	
	#Configure the mode on the instance
	if instance.has_method("setup"):
		instance.call("setup", mode);
	#Specialised _open_modal inlined here
	_scaled_ui_root.add_child(instance);
	_modal_stack.append(instance);
	_current_modal = instance;
	
	Game.pause_game();
	AudioManager.play_sfx("open_menu");
	Analytics.log_event("ui_modal_opened", {
		"scene_path": save_slots_scene.resource_path,
		"stack_depth": _modal_stack.size(),
		"slot_mode": mode,
	})

#Implement the dialogue box in scene
func _on_dialogue_started(_dialogue_id: String) -> void:
	_ensure_ui_root();
	if dialogue_box_scene == null:
		return;
	#Hide HUD before box appears
	set_hud_visible(false);
	#Lock quest banners until dialogue is fully closed
	push_banner_lock("DialogueSystem.dialogue_started");
	#Spawn and place the dialogue box
	var instance: Control = dialogue_box_scene.instantiate();
	_scaled_ui_root.add_child(instance);
	AudioManager.play_sfx("open_menu");
	_place_under_global_tooltip(instance);
	Analytics.log_event("dialogue_box_spawned", {
		"dialogue_id": _dialogue_id
	})

#Always ensure nodes that share a parent with GlobalTooltip draw just under it
func _place_under_global_tooltip(node: Node) -> void:
	if node == null or GlobalTooltip == null:
		return;
	var parent = node.get_parent();
	if parent == null:
		return;
	#Can only meaningfully reorder if tooltip shares the same parent
	if GlobalTooltip.get_parent() != parent:
		return;
		
	var children = parent.get_children();
	var tooltip_index = children.find(GlobalTooltip);
	if tooltip_index == -1:
		return;
		
	#Place this node just below the tooltip in draw order
	var target_index = max(tooltip_index -1, 0);
	parent.move_child(node, target_index);
	
#Check if the scene is on top
func _is_scene_on_top(scene: PackedScene) -> bool:
	if _current_modal == null or scene == null:
		return false;
	return (_current_modal.scene_file_path == scene.resource_path);

#Spawn the vignette overlay for colour effects, etc
func _spawn_vignette_overlay() -> void:
	if _ui_root == null:
		_ensure_ui_root();
	if vignette_scene == null:
		return;
	#Safety checks passed, instantiate the overlay
	var vignette_overlay = vignette_scene.instantiate();
	_ui_root.add_child(vignette_overlay);
	#Find the ShaderMaterial on child node
	var vignette_node = vignette_overlay.get_node_or_null("Vignette");
	if vignette_node and vignette_node is CanvasItem:
		var mat = (vignette_node as CanvasItem).material;
		if mat is ShaderMaterial:
			VisualFX.set_vignette_material(mat);
			#Set baseline vignette
			mat.set_shader_parameter("vignette_rgb", Color(0,0,0));
			mat.set_shader_parameter("vignette_opacity", 0.3);
	#Ensure it draws under tooltip but above HUD, etc
	_place_under_global_tooltip(vignette_overlay);
#endregion
