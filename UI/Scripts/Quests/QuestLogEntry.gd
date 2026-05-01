extends VBoxContainer

@onready var title_label: Label = %TitleLabel;
@onready var step_list: VBoxContainer = %StepList;
@onready var step_template: HBoxContainer = %StepTemplate;


var _quest_id: String = "";

func setup(quest_id: String) -> void:
	_quest_id = quest_id;
	
	#Quest title
	title_label.text = QuestDatabase.get_display_name(quest_id);
	_populate_steps(quest_id);
	
func setup_message(message: String) -> void:
	_quest_id = "";
	title_label.text = message;
	_clear_steps();

#Populate the steps for the currently active quest
func _populate_steps(quest_id: String) -> void:
	_clear_steps();
	
	var total_steps: int = QuestDatabase.get_step_count(quest_id);
	if total_steps == 0:
		return;
	
	var current_index: int = QuestSystem.get_step_index(quest_id);
	var is_completed: bool = QuestSystem.get_quest_state(quest_id) == QuestSystem.STATE_COMPLETED;
	
	for i in range(total_steps):
		#Don't reveal the steps the player hasn't reached yet
		if not is_completed and i > current_index:
			break;
		
		var step_text: String = QuestDatabase.get_step_text(quest_id, i);
		if step_text.is_empty():
			continue;
			
		var is_done: bool = is_completed or i < current_index;
		
		#Append material progress to the active step only
		if not is_done and i == current_index:
			var suffix: String = _build_progress_suffix(quest_id, i);
			if not suffix.is_empty():
				step_text = "%s %s" % [step_text, suffix];
		
		var row: HBoxContainer = step_template.duplicate() as HBoxContainer;
		row.visible = true;
		#Add the row first, then get the info for it
		step_list.add_child(row);
	
		var step_label: Label = row.get_node("StepLabel");
		var checkmark: TextureRect = row.get_node("Checkmark");
		
		step_label.text = step_text;
		checkmark.visible = is_done;
		
		#Dim the label text for completed steps
		if is_done:
			step_label.add_theme_color_override("font_color", step_label.get_theme_color("font_color") * Color(1,1,1,0.4));
		
		
#Clear all the steps
func _clear_steps() -> void:
	for child in step_list.get_children():
		#Leave the templates in place, only remove spawned rows
		if child == step_template:
			continue;
		child.queue_free();
		 
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
