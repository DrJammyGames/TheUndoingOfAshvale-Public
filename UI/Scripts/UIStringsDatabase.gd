extends Node

#Grabs the text from the localisation file registered in the project settings

#region Public helpers
#Get the localised text
func get_text(ui_id: String) -> String:
	return tr(ui_id);

#Helper for labels
func apply_to_label(label: Label, ui_id: String) -> void:
	if label == null:
		return;
		
	label.text = get_text(ui_id);
	#Analytics track that the text was applied
	#Analytics.log_event("ui_text_applied", {
		#"ui_id": ui_id,
		#"node_name": label.name,
		#"node_type": "Label",
	#})
	
#Helper for richtextlabels
func apply_to_richtextlabel(label: RichTextLabel, ui_id: String) -> void:
	if label == null:
		return;
		
	label.text = get_text(ui_id);
	#Analytics track that the text was applied
	#Analytics.log_event("ui_text_applied", {
		#"ui_id": ui_id,
		#"node_name": label.name,
		#"node_type": "Label",
	#})
#Small helper to wire a button in one call
func apply_to_button(button: BaseButton, ui_id: String) -> void:
	if button == null:
		return;
	
	button.text = get_text(ui_id);
	
	#Analytics.log_event("ui_text_applied", {
		#"ui_id": ui_id,
		#"node_name": button.name,
		#"node_type": "BaseButton",
	#})
	
#Helper for headers (titles and things)
func apply_to_header(label: Label, ui_id: String) -> void:
	if label == null:
		return;
		
	label.text = get_text(ui_id);
	
	#Analytics.log_event("ui_text_applied", {
		#"ui_id": ui_id,
		#"node_name": label.name,
		#"node_type": "Label"
	#})
#endregion
