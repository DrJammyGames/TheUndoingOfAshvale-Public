extends AnimatedMenu
class_name CraftingScreen

enum Tab {
	SMELT,
	CRAFT,
	FURNITURE
};

const RECIPE_ICON_SCENE: PackedScene = preload("res://UI/Scenes/Crafting/CraftingRecipeIcon.tscn");

#region Node refs
#Tab buttons
@onready var smelt_tab_button: Button = %SmeltTabButton;
@onready var craft_tab_button: Button = %CraftTabButton;
@onready var furniture_tab_button: Button = %FurnitureTabButton;

#Panels
@onready var recipe_grid: GridContainer = %RecipeGrid;
@onready var detail_panel: CraftingDetailPanel = %DetailPanel;
#endregion

var _current_tab: int = Tab.SMELT; #int because it's an enum

func _ready() -> void:
	super._ready();
	
	if smelt_tab_button:
		smelt_tab_button.toggled.connect(_on_smelt_tab_toggled);
	if craft_tab_button:
		craft_tab_button.toggled.connect(_on_craft_tab_toggled);
	if furniture_tab_button:
		furniture_tab_button.toggled.connect(_on_furniture_tab_toggled);
	if detail_panel:
		detail_panel.back_pressed.connect(_on_detail_back_pressed);
	
	#Rebuid when a new recipe unlocks
	if CraftingSystem:
		CraftingSystem.recipe_unlocked.connect(_on_recipe_unlocked);
		
	_set_tab(Tab.SMELT);
	

#region Tab switching
func _set_tab(tab_index: int) -> void:
	_current_tab = tab_index;
	_show_grid();
	_build_grid();
	
	#Apply the states to the selected tab button
	_apply_tab_button_state(smelt_tab_button, tab_index == Tab.SMELT);
	_apply_tab_button_state(craft_tab_button, tab_index == Tab.CRAFT);
	_apply_tab_button_state(furniture_tab_button, tab_index == Tab.FURNITURE);
	
	Analytics.log_event("crafting_tab_switched", {
		"tab": _tab_name(tab_index),
	})
	
func _apply_tab_button_state(button: Button, is_active: bool) -> void:
	_set_button_pressed_silent(button, is_active);
	if button.has_method("set_active"):
		button.set_active(is_active);
		
func _set_button_pressed_silent(button: Button, pressed: bool) -> void:
	button.set_block_signals(true);
	button.set_pressed(pressed);
	button.set_block_signals(false);
#endregion
#region Grid
func _build_grid() -> void:
	#Clear anything existing first
	for child in recipe_grid.get_children():
		child.queue_free();
	var type: RecipeDataResource.RecipeType = _current_tab_to_type();
	#Show all recipes of this type--locked and unlocked
	var recipes: Array[RecipeDataResource] = RecipeDatabase.get_recipes_of_type(type);
	
	for recipe in recipes:
		var icon: CraftingRecipeIcon = RECIPE_ICON_SCENE.instantiate();
		recipe_grid.add_child(icon);
		icon.setup(recipe);
		icon.icon_clicked.connect(_on_icon_clicked);
		
func _show_grid() -> void:
	recipe_grid.visible = true;
	detail_panel.visible = false;
	
func _show_detail(recipe: RecipeDataResource) -> void:
	recipe_grid.visible = false;
	detail_panel.visible = true;
	detail_panel.populate(recipe);
#endregion
#region Signal handlers
func _on_icon_clicked(recipe: RecipeDataResource) -> void:
	_show_detail(recipe);
	
func _on_detail_back_pressed() -> void:
	_show_grid();
	
func _on_recipe_unlocked(_recipe_id: String) -> void:
	_build_grid();
#endregion
#region Tab button handlers
func _on_smelt_tab_toggled(pressed: bool) -> void:
	if pressed:
		_set_tab(Tab.SMELT);
	else:
		_set_button_pressed_silent(smelt_tab_button, _current_tab == Tab.SMELT);

func _on_craft_tab_toggled(pressed: bool) -> void:
	if pressed:
		_set_tab(Tab.CRAFT);
	else:
		_set_button_pressed_silent(craft_tab_button, _current_tab == Tab.CRAFT);
		
func _on_furniture_tab_toggled(pressed: bool) -> void:
	if pressed:
		_set_tab(Tab.FURNITURE);
	else:
		_set_button_pressed_silent(furniture_tab_button, _current_tab == Tab.FURNITURE);
#endregion
#region Internal helpers
#Get the type from the tab selected
func _current_tab_to_type() -> RecipeDataResource.RecipeType:
	match _current_tab:
		Tab.SMELT:
			return RecipeDataResource.RecipeType.SMELT;
		Tab.CRAFT:
			return RecipeDataResource.RecipeType.CRAFT;
		Tab.FURNITURE:
			return RecipeDataResource.RecipeType.FURNITURE;
		_:
			return RecipeDataResource.RecipeType.SMELT;
			
#Get the tab name for analytics
func _tab_name(idx: int) -> String:
	match idx:
		Tab.SMELT: 
			return "smelt";
		Tab.CRAFT:
			return "craft";
		Tab.FURNITURE:
			return "furniture";
		_: 
			return "unknown";
#endregion
