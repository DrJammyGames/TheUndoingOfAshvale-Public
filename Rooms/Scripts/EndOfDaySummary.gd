extends Control;
class_name EndOfDaySummary;

const PLAYER_HOUSE_PATH: String = "res://Rooms/Scenes/PlayerHouse.tscn";
#Paths for the items and quests scenes to be populated
@export var item_row_scene: PackedScene;
@export var quest_row_scene: PackedScene;

#In-scene references
@onready var day_label: Label = %DayLabel;
@onready var gold_label: Label = %GoldLabel;
@onready var items_label: Label = %ItemsLabel;
@onready var items_container: GridContainer = %ItemsContainer;
@onready var quests_label: Label = %QuestsLabel;
@onready var quests_container: VBoxContainer = %QuestsContainer;
@onready var quest_nudge_label: Label = %QuestNudgeLabel;
@onready var confirm_button: Button = %ConfirmButton;

func _ready() -> void:
	var summary: Dictionary = DayNightSystem.get_daily_summary();
	DayNightSystem.reset_daily_tracking();
	_populate(summary);
	if confirm_button:
		confirm_button.pressed.connect(_on_confirm_pressed);
		UIStringsDatabase.apply_to_button(confirm_button, "confirm");
		confirm_button.grab_focus();

#Populate the information for the end of day summary
func _populate(summary: Dictionary) -> void:
	#Info for the header
	var day_text: String = UIStringsDatabase.get_text("end_of_day_title");
	var current_day: int = GameState.current_day - 1;
	day_text = day_text.replace("{day}", str(current_day));
	
	#Gold earned
	var gold_earned: int = summary.get("gold_earned", 0);
	var gold_text: String = UIStringsDatabase.get_text("end_of_day_gold_earned");
	gold_text = gold_text.replace("{amount}", str(summary.get("gold_earned", 0)));
	#Only show the gold label if the player earned any today
	if gold_earned > 0:
		gold_label.show();
	else:
		gold_label.hide();
		
	#Items gained
	var items_gained: Dictionary = summary.get("items_gained", {});
	#Only show if player gained items
	if items_gained.is_empty():
		items_container.hide();
		items_label.hide();
	else:
		items_label.show();
		UIStringsDatabase.apply_to_label(items_label, "items_gathered");
		for item_id in items_gained.keys():
			var amount: int = items_gained[item_id];
			if item_row_scene == null:
				push_warning("EndOfDayScreen: item_row_scene is not set.");
				break;
			var row: ItemSummaryRow = item_row_scene.instantiate() as ItemSummaryRow;
			items_container.add_child(row);
			row.setup(item_id, amount);
	
	#Quests completed
	var quests_completed: Array = summary.get("quests_completed", []);
	UIStringsDatabase.apply_to_label(quests_label, "completed");
	#Only show if player completed quests today
	if quests_completed.is_empty():
		quests_label.hide();
		quests_container.hide();
		quest_nudge_label.text = UIStringsDatabase.get_text("end_of_day_no_quests");
		quest_nudge_label.show();
	else:
		quest_nudge_label.hide();
		quests_label.show();
		for quest_id in quests_completed:
			if quest_row_scene == null:
				push_warning("EndOfSummaryScreen: quest_row_scene is not set.");
				break;
			var row: QuestSummaryRow = quest_row_scene.instantiate() as QuestSummaryRow;
			quests_container.add_child(row);
			row.setup(quest_id);
			
	#Set the text properly
	gold_label.text = gold_text;
	day_label.text = day_text;

func _on_confirm_pressed() -> void:
	Analytics.log_event("end_of_day_dismissed", {
		"new_day": GameState.current_day,
	})
	#Spawn facing down
	GameState.player_facing_dir = Vector2(0,1);
	Game.transition_player_to_area(PLAYER_HOUSE_PATH, "morning_spawn")
