extends Control 
class_name EncyclopediaScreen 

#Encyclopedia tab for the TabbedMenu
#Left sidebar--category icons 
#Panel--swaps content based on the selected category 
#Grid categories use a generic EncyclopediaGridPanel
#Dialogue category has a two-level layout (NPC grid -> log view_

enum Category {
	HARVESTABLES,
	ITEMS,
	ENEMIES,
	CRAFTING,
	QUESTS,
	DIALOGUE,
}

#region Node refs
#Category sidebar buttons
@onready var harvestables_button: Button = %HarvestablesButton;
@onready var items_button: Button = %ItemsButton;
@onready var enemies_button: Button = %EnemiesButton;
@onready var crafting_button: Button = %CraftingButton;
@onready var quests_button: Button = %QuestsButton;
@onready var dialogue_button: Button = %DialogueButton;

#Content panels (only one visible at a time)
@onready var harvestables_panel: EncyclopediaGridPanel = %HarvestablesPanel;
@onready var items_panel: EncyclopediaGridPanel = %ItemsPanel;
@onready var enemies_panel: EncyclopediaGridPanel = %EnemiesPanel;
@onready var crafting_panel: EncyclopediaGridPanel = %CraftingPanel;
@onready var quests_panel: Control = %QuestsPanel;
@onready var dialogue_panel: Control = %DialoguePanel;
#endregion

var _current_category: int = Category.HARVESTABLES;

func _ready() -> void:
	harvestables_button.toggled.connect(_on_category_toggled.bind(Category.HARVESTABLES));
	items_button.toggled.connect(_on_category_toggled.bind(Category.ITEMS));
	enemies_button.toggled.connect(_on_category_toggled.bind(Category.ENEMIES));
	crafting_button.toggled.connect(_on_category_toggled.bind(Category.CRAFTING));
	quests_button.toggled.connect(_on_category_toggled.bind(Category.QUESTS));
	dialogue_button.toggled.connect(_on_category_toggled.bind(Category.DIALOGUE));
	
	#Refresh when new discoveries come in while the menu is open
	EncyclopediaSystem.harvestable_discovered.connect(_on_discovery);
	EncyclopediaSystem.enemy_discovered.connect(_on_discovery);
	EncyclopediaSystem.item_discovered.connect(_on_discovery);
	EncyclopediaSystem.recipe_discovered.connect(_on_discovery);
	EncyclopediaSystem.dialogue_line_logged.connect(_on_discovery);
	
	#Tooltip hover for sidebar encyclopedia category buttons
	_setup_button_tooltip(harvestables_button, "enc_harvestables_title", "enc_harvestables_tooltip");
	_setup_button_tooltip(items_button, "enc_items_title", "enc_items_tooltip");
	_setup_button_tooltip(enemies_button, "enc_enemies_title", "enc_enemies_tooltip");
	_setup_button_tooltip(crafting_button, "enc_crafting_title", "enc_crafting_tooltip");
	_setup_button_tooltip(quests_button, "enc_quests_title", "enc_quests_tooltip");
	_setup_button_tooltip(dialogue_button, "enc_dialogue_title", "enc_dialogue_tooltip");
	
	#Wire the generic grid panels with their configs
	harvestables_panel.setup(_build_harvestables_config());
	items_panel.setup(_build_items_config());
	enemies_panel.setup(_build_enemies_config());
	crafting_panel.setup(_build_crafting_config());
	#Set the first category screen to open
	_set_category(Category.HARVESTABLES);
	
#Called by TabbedMenu when this tab becomes visible so the content is always fresh
func refresh() -> void:
	_set_category(_current_category);
	
#region Internal helpers
#Grid panel config builders
func _build_harvestables_config() -> Dictionary:
	return {
		"get_all": func(): return HarvestableDatabase.get_all_harvestables(),
		"get_id": func(h: HarvestableDataResource): return h.harvest_id,
		"get_icon": func(h: HarvestableDataResource):
			if h.encyclopedia_icon != null:
				return h.encyclopedia_icon;
			if h.world_sprites.size() > 0:
				return h.world_sprites[0];
			return null,
		"is_discovered": func(id: String): return EncyclopediaSystem.has_harvested(id),
		"get_title": func(id: String): return HarvestableDatabase.get_display_name(id),
		"get_body": func(id: String): return _build_harvestables_body(id),
	}
	
func _build_items_config() -> Dictionary:
	return {
		"get_all": func(): return ItemDatabase.get_all_items(),
		"get_id": func(item: ItemDataResource): return item.item_id,
		"get_icon": func(item: ItemDataResource): return item.icon_inv,
		"is_discovered": func(id: String): return EncyclopediaSystem.has_found_item(id),
		"get_title": func(id: String): return ItemDatabase.get_display_name(id),
		"get_body": func(id: String): return _build_item_body(id),
		"sort": func(a: ItemDataResource, b: ItemDataResource):
			var order: Dictionary = {
				ItemDataResource.ItemType.TOOL: 0,
				ItemDataResource.ItemType.CONSUMABLE: 1,
				ItemDataResource.ItemType.RESOURCE: 2,
				ItemDataResource.ItemType.KEY_ITEM: 3,
				ItemDataResource.ItemType.UNKNOWN: 4,
			};
			return order.get(a.type, 4) < order.get(b.type, 4),
	}
	
func _build_enemies_config() -> Dictionary:
	return {
		"get_all": func(): return EnemyDatabase.get_all_enemies(),
		"get_id": func(e: EnemyDataResource): return e.id,
		"get_icon": func(e: EnemyDataResource): return e.encyclopedia_icon,
		"is_discovered": func(id: String): return EncyclopediaSystem.has_killed(id),
		"get_title": func(id: String): return EnemyDatabase.get_display_name(id),
		"get_body": func(id: String): return _build_enemy_body(id),
	}
	
func _build_crafting_config() -> Dictionary:
	return{
		"get_all": func(): return RecipeDatabase.get_all_recipes(),
		"get_id": func(r: RecipeDataResource): return r.recipe_id,
		"get_icon": func(r: RecipeDataResource):
			return r.result_item.icon_inv if r.result_item != null else null,
		"is_discovered": func(id: String): return EncyclopediaSystem.has_unlocked_recipe(id),
		"get_title": func(id: String):
			var r: RecipeDataResource = RecipeDatabase.get_recipe(id);
			if r == null or r.result_item == null:
				return id;
			return ItemDatabase.get_display_name(r.result_item.item_id),
		"get_body": func(id: String): return _build_crafting_body(id),
	}
#Tooltip body builders
func _build_harvestables_body(id: String) -> String:
	var h: HarvestableDataResource = HarvestableDatabase.get_resource(id);
	if h == null:
		return "";
	#Otherwise, continue and set up the tooltip stuffs
	var lines: Array[String] = [];
	
	var drop_id: String = HarvestableDatabase.get_drop_item_id(id);
	if not drop_id.is_empty():
		var drop_name: String = ItemDatabase.get_display_name(drop_id);
		var drop_range: Vector2i = HarvestableDatabase.get_drop_amount_range(id);
		if drop_range.x == drop_range.y:
			lines.append("Drops: %s x%d" % [drop_name, drop_range.x]);
		else:
			lines.append("Drops: %s x%d-%d" % [drop_name, drop_range.x, drop_range.y]);
			
	var xp: int = HarvestableDatabase.get_xp_reward(id);
	if xp > 0:
		lines.append("XP: %d" % xp);
		
	lines.append("Harvested: %d" % EncyclopediaSystem.get_harvest_count(id));
	
	var location: String = HarvestableDatabase.get_location(id);
	if not location.is_empty():
		lines.append("Found in: %s" % location);
		
	return "\n".join(lines);

func _build_item_body(id: String) -> String:
	var item: ItemDataResource = ItemDatabase.get_item(id);
	if item == null:
		return "";
	var desc: String = ItemDatabase.get_description(id);
	var type_str: String = _item_type_label(item.type);
	return "%s\n\nType: %s" % [desc, type_str];
	
func _build_enemy_body(id: String) -> String:
	var e: EnemyDataResource = EnemyDatabase.get_enemy(id);
	if e == null:
		return "";
	var lines: Array[String] = [];
	
	lines.append("HP: %d" % e.max_hp);
	
	if e.drops.size() > 0:
		var drop_parts: Array[String] = [];
		for drop in e.drops:
			if drop.item != null:
				drop_parts.append(ItemDatabase.get_display_name(drop.item.item_id));
		if not drop_parts.is_empty():
			lines.append("Drops: %s" % ", ".join(drop_parts));
	
	if e.xp_reward > 0:
		lines.append("XP: %d" % e.xp_reward);
		
	lines.append("Defeated: %d" % EncyclopediaSystem.get_kill_count(id));
	
	var location: String = EnemyDatabase.get_location(id);
	if not location.is_empty():
		lines.append("Found in: %s" % location);
	return "\n".join(lines);
	
func _build_crafting_body(id: String) -> String:
	var r: RecipeDataResource = RecipeDatabase.get_recipe(id);
	if r == null:
		return "";
	var lines: Array[String] = [];
	
	#Result
	if r.result_item != null:
		var result_name: String = ItemDatabase.get_display_name(r.result_item.item_id);
		lines.append("Produces: %s x%d" % [result_name, r.result_amount]);
		
	#Ingredients
	if r.ingredients.size() > 0:
		var ingredient_parts: Array[String] = [];
		for ingredient in r.ingredients:
			if ingredient.item != null:
				var ing_name: String = ItemDatabase.get_display_name(ingredient.item.item_id);
				ingredient_parts.append("%s x%d" %[ing_name, ingredient.amount]);
		if not ingredient_parts.is_empty():
			lines.append("Requires: %s" % ", ". join(ingredient_parts));
			
	#Unlock source
	lines.append("Unlocked by: %s" % _unlock_source_label(r.unlock_source));
	
	#Required level
	if r.required_level > 1:
		lines.append("Required level: %d" % r.required_level);
		
	return "\n".join(lines);
	
func _item_type_label(type: ItemDataResource.ItemType) -> String:
	match type:
		ItemDataResource.ItemType.CONSUMABLE:
			return "Consumable";
		ItemDataResource.ItemType.RESOURCE:
			return "Resource";
		ItemDataResource.ItemType.KEY_ITEM:
			return "Key Item";
		ItemDataResource.ItemType.TOOL:
			return "Tool";
		_:
			return "Unknown";
		
func _unlock_source_label(source: RecipeDataResource.UnlockSource) -> String:
	match source:
		RecipeDataResource.UnlockSource.DEFAULT:
			return "Default";
		RecipeDataResource.UnlockSource.LEVEL_UP:
			return "Level up";
		RecipeDataResource.UnlockSource.SHOP:
			return "Shop";
		RecipeDataResource.UnlockSource.ENEMY_DROP:
			return "Enemy Drop";
		RecipeDataResource.UnlockSource.BLUEPRINT:
			return "Blueprint";
		_:
			return "Unknown";
			
func _set_category(new_category: int) -> void:
	_current_category = new_category;
	_apply_panels(new_category);
	_apply_button_states(new_category);
	_rebuild_current_panel();
	
func _apply_panels(category: int) -> void:
	harvestables_panel.visible = (category == Category.HARVESTABLES);
	items_panel.visible = (category == Category.ITEMS);
	enemies_panel.visible = (category == Category.ENEMIES);
	crafting_panel.visible = (category == Category.CRAFTING);
	quests_panel.visible = (category == Category.QUESTS);
	dialogue_panel.visible = (category == Category.DIALOGUE);
	
func _apply_button_states(category: int) -> void:
	for cat in Category.values():
		_set_button_pressed_silent(_button_for_category(cat), cat == category);
	
func _set_button_pressed_silent(button: Button, pressed: bool) -> void:
	button.set_block_signals(true);
	button.set_pressed(pressed);
	button.set_block_signals(false);
	
#Delegates rebuild to whichever panel is active
#Each panel script will expost a rebuild() method
func _rebuild_current_panel() -> void:
	match _current_category:
		Category.HARVESTABLES:
			harvestables_panel.rebuild();
		Category.ITEMS:
			items_panel.rebuild();
		Category.ENEMIES:
			enemies_panel.rebuild();
		Category.CRAFTING:
			crafting_panel.rebuild();
		Category.QUESTS:
			quests_panel.rebuild();
		Category.DIALOGUE:
			dialogue_panel.rebuild();

#Refresh the current panel when a new discovery comes in
func _on_discovery(_id = null) -> void:
	_rebuild_current_panel();

#Handle the button toggle 
func _on_category_toggled(pressed: bool, category: int) -> void:
	if pressed:
		_set_category(category);
	else:
		_set_button_pressed_silent(_button_for_category(category), _current_category == category);
		
func _button_for_category(category: int) -> Button:
	match category:
		Category.HARVESTABLES:
			return harvestables_button;
		Category.ITEMS:
			return items_button;
		Category.ENEMIES:
			return enemies_button;
		Category.CRAFTING:
			return crafting_button;
		Category.QUESTS:
			return quests_button;
		Category.DIALOGUE:
			return dialogue_button;
		_:
			return harvestables_button;
			
#Wire GlobalTooltip hover on a sidebar button
func _setup_button_tooltip(button: Button, title_key: String, desc_key: String) -> void:
	button.mouse_filter = Control.MOUSE_FILTER_STOP;
	button.mouse_entered.connect(func() -> void:
		if GlobalTooltip:
			GlobalTooltip.show_tooltip(
				UIStringsDatabase.get_text(title_key),
				UIStringsDatabase.get_text(desc_key)
			);
	);
	button.mouse_exited.connect(func() -> void:
		if GlobalTooltip:
			GlobalTooltip.hide_tooltip();
	);
#endregion
