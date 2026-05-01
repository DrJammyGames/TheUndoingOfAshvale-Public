extends Control;

@onready var desc_label: RichTextLabel = %ItemText;
@onready var typewriter: TypewriterText = %TypewriterText;
@onready var panel: Control = %Panel;
@onready var item_sprite: TextureRect = %ItemSprite;

var _item_id: String = "";

func _ready() -> void:
	#Make sure we grab focus and input
	set_process_input(true);
	#Wire Typewriter text
	if typewriter:
		typewriter.set_process(true);
	
func setup(item_id: String, amount: int = 1) -> void:
	_item_id = item_id;
	#Build the text we want to show
	var text: String = "";
	
	if ItemDatabase.has_item(item_id):
		var item_name: String = ItemDatabase.get_display_name(item_id);
		var description: String = ItemDatabase.get_description(item_id);
		var template: String = _get_obtained_template(item_name, amount);
		text = template % item_name + "\n" + description;
	else:
		text = "You obtained a mysterious item."
		
	#Typewriter settings
	if typewriter:
		typewriter.start_typing(text);
	#Fallback, no typewriter just set label
	elif desc_label:
		desc_label.text = text;
	item_sprite.texture = ItemDatabase.get_icon_world(item_id);
	
#Public getter called by Game/UIRouter to position popup above player
func position_above_player(player_world_pos: Vector2) -> void:
	if panel == null:
		return;
		
	var cam = get_viewport().get_camera_2d();
	if cam == null:
		return;
		
	#Ensure layout is ready so panel.size is valid
	await get_tree().process_frame;
	
	#Use the camera's canvas transform to map world -> UI/canvas coordinates
	var canvas_xform: Transform2D = cam.get_canvas_transform();
	var screen_pos: Vector2 = canvas_xform * player_world_pos;
	
	#Raise the popup slightly above the player
	screen_pos.y -= 96.0;
	
	var panel_size: Vector2 = panel.size;
	panel.global_position = screen_pos - (panel_size * 0.5);
		
func _input(event: InputEvent) -> void:
	#Only handle if visible and this is the active modal
	if not visible:
		return;
		
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled();
		#If we are still typing, first press skips to full text
		if typewriter and typewriter.is_typing():
			typewriter.skip_to_full();
		else:
			#Text is fully visible, close popup
			_close_popup();
			
func _close_popup() -> void:
	Analytics.log_event("ui_item_get_popup_closed", {
		"item_id": _item_id
	})
	#End the item-get cinematic on the player
	if Game.has_method("end_item_get_cinematic"):
		Game.end_item_get_cinematic();
	#Use the cental modal close path so pausing and unpausing stays the same
	if UIRouter.has_method("close_top_modal"):
		UIRouter.close_top_modal();
	else:
		queue_free();

#Get the correct article for the new item popup
func _get_obtained_template(item_name: String, amount: int) -> String:
	if amount > 1:
		return UIStringsDatabase.get_text("item_obtained_some")
	var first_letter: String = item_name.left(1).to_lower();
	#If the first letter is a vowel
	if first_letter in ["a", "e", "i", "o", "u"]:
		return UIStringsDatabase.get_text("item_obtained_an");
	return UIStringsDatabase.get_text("item_obtained_a");
