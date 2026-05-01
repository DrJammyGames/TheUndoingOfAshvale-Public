extends Control
class_name HUD;

@export var stats: PlayerStats #Shared data model
@onready var health_bar: StatBar = %HealthBar;
@onready var mana_bar: StatBar = %ManaBar;
#Container for item pickup text
@onready var floating_text_container: Control = %FloatingText;
@onready var message_label: Label = %MessageLabel;
@onready var quest_label: Label = %QuestLabel;
#Save indicator
@onready var save_indicator: Control = %SaveIndicator;
var _save_tween: Tween = null;

#Export vars to drag and drop the scenes
@export var floating_text_scene: PackedScene;
@export var pinned_entry_scene: PackedScene;
@export var sign_message_panel_scene: PackedScene;
@export var interaction_prompt_scene: PackedScene;
@onready var pinned_recipes_container: VBoxContainer = %PinnedRecipesContainer;
#Signpost messages
@onready var sign_messages: Control = %SignMessages;

var _sign_panel: SignMessagePanel = null;
var _interaction_prompt: InteractionPrompt = null;
func _ready() -> void:
	#Hook into PlayerStats
	if stats:
		#Same resource Player uses
		stats.stats_changed.connect(_on_stats_changed);
		stats.died.connect(_on_stats_died);
		_on_stats_changed(); #initial update
	#Inventory
	InventorySystem.inventory_changed.connect(func(_item_id: String) -> void: _update_current_quest_label());
	ChestStorageSystem.chest_contents_changed.connect(func(_item_id: String) -> void: _update_current_quest_label());
	#Quest log
	QuestSystem.quest_added.connect(_on_quest_changed);
	QuestSystem.quest_updated.connect(_on_quest_changed);
	QuestSystem.quest_completed.connect(_on_quest_changed);
	QuestSystem.quests_loaded.connect(_update_current_quest_label);
	_update_current_quest_label();
	#DayNightSystem 
	DayNightSystem.night_entered.connect(_on_night_entered);
	Game.save_completed.connect(_on_save_completed);
	Game.player_ready.connect(_on_player_ready_for_prompt);
	CraftingSystem.recipe_pinned.connect(_on_recipe_pinned);
	CraftingSystem.recipe_unpinned.connect(_on_recipe_unpinned);
	#Spawn the sign panel for reading signs
	_spawn_sign_panel();
	_spawn_interact_prompt();

#region Public helpers
func show_message(text: String, duration: float = 4.0, world_pos: Variant = null, color: Color = Color("#f5ffe8")) -> void:
	if text.is_empty():
		return;
	if floating_text_scene == null:
		push_warning("HUD: FloatingText scene not assigned.");
		return;
		
	var instance := floating_text_scene.instantiate();
	floating_text_container.add_child(instance);
	
	var pos: Vector2;
	if world_pos is Vector2:
		pos = world_pos;
	else:
		#Fallback: try player position, else center of screen
		var player := Game.get_player() as Node2D
		if player != null:
			pos = player.global_position;
		else:
			pos = Vector2.ZERO;
	instance.global_position = _world_to_ui_position(pos) + Vector2(0, -16)
	var actual_duration := duration + randf_range(-0.1, 0.1);
	instance.setup(text, actual_duration, color);

#Show message from signpost's interact method
func show_sign(title: String, body: String) -> void:
	if _sign_panel == null:
		_spawn_sign_panel();
	if _sign_panel == null:
		return;
		
	_sign_panel.setup(title, body);
	_sign_panel.open();
	
#Hide the sign
func hide_sign() -> void:
	if _sign_panel != null:
		_sign_panel.close();

#Check if the sign is open--important for player movement and such
func is_sign_open() -> bool:
	return _sign_panel != null and _sign_panel.visible;
	
#Called by UIRouter when a modal opens--hide the interaction promot so it doesn't freeze on screen
func hide_interaction_prompt() -> void:
	if _interaction_prompt != null:
		_interaction_prompt.hide_prompt();
		
#Called by UIRouter when all modals close--re-check if player still has a focus target
func refresh_interaction_prompt() -> void:
	if _interaction_prompt == null:
		return;
	var player = Game.get_player();
	if player == null:
		return;
	var interaction_system = player.get_node_or_null("InteractionSystem") as InteractionSystem;
	if interaction_system == null:
		return;
	var focused: Interactable = interaction_system.get_focused();
	if focused != null:
		_interaction_prompt.show_prompt(focused.prompt_text);
		
#endregion
#region Internal helpers
func _on_stats_changed() -> void:
	if stats == null:
		return;
	health_bar.update_stat(stats.health, stats.max_health);
	mana_bar.update_stat(stats.mana, stats.max_mana);
	
func _on_stats_died() -> void:
	show_message(UIStringsDatabase.get_text("collapsed"), 3.0);
	
func _on_night_entered() -> void:
	show_message(UIStringsDatabase.get_text("night_entered"));
	
#Get the proper position for UI--convert world to UI points
func _world_to_ui_position(world_pos: Vector2) -> Vector2:
	var viewport := get_viewport();
	var canvas_xform: Transform2D = viewport.get_canvas_transform();
	return canvas_xform * world_pos;

func _spawn_sign_panel() -> void:
	if _sign_panel != null and is_instance_valid(_sign_panel):
		_sign_panel.queue_free();
		_sign_panel = null;
		
	if sign_message_panel_scene == null:
		push_warning("HUD: SignMessagePanel scene missing.");
		#Error, abort
		return;
	#Safety checks passed
	_sign_panel = sign_message_panel_scene.instantiate() as SignMessagePanel;
	sign_messages.add_child(_sign_panel);
	
	#Ensure it draws on top of HUD elements
	sign_messages.move_child(_sign_panel, sign_messages.get_child_count() - 1);

#Interaction prompt
func _spawn_interact_prompt() -> void:
	if _interaction_prompt != null and is_instance_valid(_interaction_prompt):
		_interaction_prompt.queue_free();
		_interaction_prompt = null;
	if interaction_prompt_scene == null:
		push_warning("HUD: InteractionPrompt scene missing.");
		return;
	_interaction_prompt = interaction_prompt_scene.instantiate() as InteractionPrompt;
	add_child(_interaction_prompt);
	
func _on_player_ready_for_prompt() -> void:
	#Wait a frame
	await get_tree().process_frame;
	var player = Game.get_player();
	if player == null:
		return;
	var interaction_system = player.get_node_or_null("InteractionSystem") as InteractionSystem;
	if interaction_system == null:
		return;
	if interaction_system.focus_changed.is_connected(_on_interact_focus_changed):
		interaction_system.focus_changed.disconnect(_on_interact_focus_changed);
	interaction_system.focus_changed.connect(_on_interact_focus_changed);
	
func _on_interact_focus_changed(new_target: Interactable, _old_taret: Interactable) -> void:
	if _interaction_prompt == null:
		return;
	if new_target == null:
		_interaction_prompt.hide_prompt();
	else:
		#Don't show prompt if any modal is open or the HUD itself is not visible
		if not visible or UIRouter.is_modal_open():
			return;
		#Nothing is open, show the prompt
		_interaction_prompt.show_prompt(new_target.prompt_text);
		
func _process(_delta: float) -> void:
	if _interaction_prompt == null or not _interaction_prompt.visible:
		return;
	var player = Game.get_player();
	if player == null:
		return;
	_interaction_prompt.position = _world_to_ui_position(player.global_position) + Vector2(0, -96);
#Save indicator
func _on_save_completed(success: bool) -> void:
	#Game didn't save properly, exit early
	if not success:
		return;
	#Safety checks passed, show save indicator
	_show_save_indicator();
	
#Internal helper function to show the save icon
func _show_save_indicator() -> void:
	if save_indicator == null:
		return;
	#Cancel any in-progress tween so rapid saves don't stack
	if _save_tween != null and _save_tween.is_valid():
		_save_tween.kill();
	#Proceed as normal now
	save_indicator.modulate.a = 1.0;
	save_indicator.visible = true;
	_save_tween = create_tween();
	_save_tween.tween_interval(2.0);
	_save_tween.tween_property(save_indicator, "modulate:a", 0.0, 0.6);
	_save_tween.tween_callback(func() -> void: save_indicator.visible = false);
	
#Recipes
func _on_recipe_pinned(recipe_id: String) -> void:
	var recipe: RecipeDataResource = RecipeDatabase.get_recipe(recipe_id);
	if recipe == null:
		return;
	var count: int = CraftingSystem.get_pin_count(recipe_id);
	var entry: PinnedRecipeEntry = pinned_entry_scene.instantiate();
	pinned_recipes_container.add_child(entry);
	entry.scale = Vector2(0.5, 0.5);
	entry.setup(recipe, count);
	
func _on_recipe_unpinned(recipe_id: String) -> void:
	for child in pinned_recipes_container.get_children():
		if child is PinnedRecipeEntry and child.get_recipe_id() == recipe_id:
			child.queue_free();
			return;
#endregion
#region Quests
func set_current_quest(text: String) -> void:
	quest_label.text = text;

#Quest has changed
func _on_quest_changed(_quest_id: String) -> void:
	_update_current_quest_label();
	
#Update the currently displayed quest
func _update_current_quest_label() -> void:
	#Simple rule: show the first active quest's current step
	#Can change to include "tracked quest" logic later
	if QuestSystem == null:
		set_current_quest("");
		return;
	
	#Get the current active quests for display
	var active_quests: Array = QuestSystem.get_active_quests();
	if active_quests.is_empty():
		#Nothing is active, display so
		set_current_quest("No active quest.");
		return;
	
	#There is a quest active, get the info
	var quest_id: String = active_quests[0];
	#Base step text
	var step_index: int = QuestSystem.get_step_index(quest_id);
	var step_text: String = QuestDatabase.get_step_text(quest_id, step_index);
	
	#If there's no step text, fall back to description
	if step_text.is_empty():
		step_text = QuestDatabase.get_description(quest_id);
	
	#Try to append material progress if this step has item-based conditions
	var progress_suffix = _build_progress_suffix(quest_id, step_index);
	if progress_suffix.is_empty():
		quest_label.text = step_text;
	else:
		quest_label.text = "%s %s" % [step_text, progress_suffix];
		
#Helper function to get all the proper data for the quest step
func _build_progress_suffix(quest_id: String, step_index: int) -> String:
	var step_data: Dictionary = QuestDatabase.get_step_data(quest_id, step_index);
	if step_data.is_empty():
		return "";
		
	var conditions: Array = step_data.get("conditions", []);
	if conditions.is_empty():
		return "";
	var parts: Array = [];
	for cond in conditions:
		if typeof(cond) != TYPE_DICTIONARY:
			continue;
		var cond_key: String = String(cond.get("key", ""));
		if cond_key != "item_id":
			continue;
		var item_id: String = String(cond.get("value", ""));
		if item_id.is_empty():
			continue;
		var required: int = int(cond.get("amount", 1));
		if required < 1:
			required = 1;
		
		#How many the player current has in inventory
		var current: int = ChestStorageSystem.get_combined_amount(item_id);
		parts.append("%d/%d" % [current, required]);
	if parts.is_empty():
		return "";
	#Wrap in parantheses to look nice
	return "(%s)" % ", ".join(parts);
#endregion
