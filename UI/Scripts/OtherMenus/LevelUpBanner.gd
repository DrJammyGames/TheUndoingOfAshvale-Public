extends Control;
class_name LevelUpBanner;

signal finished;

@onready var title_label: Label = %TitleLabel;
@onready var level_label: Label = %LevelLabel;
@onready var stats_label: Label = %StatsLabel;
@onready var recipes_container: VBoxContainer = %RecipesContainer;
@onready var recipes_label: Label = %RecipesLabel;
@onready var inventory_label: Label = %InventoryLabel;
@onready var continue_label: Label = %ContinueLabel;
@onready var recipes_column: VBoxContainer = %RecipesColumn;
var _is_showing: bool = false;


func _ready() -> void:
	visible = false;
	#Must process while paused so input works
	process_mode = Node.PROCESS_MODE_ALWAYS;
	#Localisation stuffs
	if title_label:
		UIStringsDatabase.apply_to_label(title_label, "level_up");
	if continue_label:
		UIStringsDatabase.apply_to_label(continue_label, "level_up_continue");
		
func show_level_up(data: Dictionary) -> void:
	var new_level: int = data.get("new_level", 1);
	var prev_level: int = new_level - 1;
	
	#Level line
	level_label.text = str(prev_level) + " -> " + str(new_level);
	
	#Stat changes
	var lines: PackedStringArray = [];
	lines.append(UIStringsDatabase.get_text("level_up_hp").replace("{old}", str(data.get("old_max_health", 0))).replace("{new}", str(data.get("new_max_health", 0))));;
	lines.append(UIStringsDatabase.get_text("level_up_attack").replace("{old}", str(data.get("old_attack", 0))).replace("{new}", str(data.get("new_attack", 0))));
	lines.append(UIStringsDatabase.get_text("level_up_defense").replace("{old}", str(data.get("old_defense", 0))).replace("{new}", str(data.get("new_defense", 0))));
	lines.append(UIStringsDatabase.get_text("level_up_luck").replace("{old}", str(data.get("old_luck", 0))).replace("{new}", str(data.get("new_luck", 0))));
	stats_label.text = "\n".join(lines);
	
	#Unlocked recipes--show/hide entire column
	var recipes: Array = data.get("unlocked_recipes", []);
	#Only show if recipes have been unlocked
	if recipes.size() > 0:
		recipes_label.text = UIStringsDatabase.get_text("level_up_new_recipes");
		recipes_label.visible = true;
		#Clear old rows
		for child in recipes_container.get_children():
			child.queue_free();
		#Build icon and name rows
		for recipe_data in recipes:
			var row: HBoxContainer = HBoxContainer.new();
			row.alignment = BoxContainer.ALIGNMENT_CENTER;
			var icon: TextureRect = TextureRect.new();
			icon.texture = recipe_data["icon"];
			icon.custom_minimum_size = Vector2(32,32);
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE;
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
			row.add_child(icon);
			var label: Label = Label.new();
			label.text = str(recipe_data["name"]);
			label.theme = recipes_label.theme;
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER;
			row.add_child(label);
			recipes_container.add_child(row);
		recipes_column.visible = true;
	else:
		recipes_column.visible = false;
		
	#Inventory expansion
	if data.get("inventory_expanded", false):
		var slots: int = data.get("new_slot_count", 0);
		inventory_label.text = UIStringsDatabase.get_text("level_up_inventory").replace("{slots}", str(slots));
		inventory_label.visible = true;
	else:
		inventory_label.visible = false;
	
	visible = true;
	modulate.a = 1.0;
	_is_showing = true;
		
	
func _input(event: InputEvent) -> void:
	if not _is_showing:
		return;
	if event.is_pressed() and not event.is_echo():
		get_viewport().set_input_as_handled();
		_dismiss();
		
func _dismiss() -> void:
	_is_showing = false;
	visible = false;
	finished.emit();
