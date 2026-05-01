extends AnimatedMenu;
class_name LoreTitleCard;

@onready var lore_label: RichTextLabel = %LoreDesc;
@onready var typewriter: TypewriterText = %TypewriterText;
@onready var prompt_label: Label = %PressAnyKey;

#Check if prompt_label can appear
var _is_text_finished: bool = false;

func _ready() -> void:
	super._ready();
	prompt_label.visible = false;
	#Get the text that will be displayed
	var text: String = UIStringsDatabase.get_text("lore_title_card");
	#Ensure player name is displayed
	text = text.replace("{player_name}", GameState.player_name);
	UIStringsDatabase.apply_to_label(prompt_label,"lore_title_card_press_any_key");
	#Wire Typewriter text
	if typewriter:
		typewriter.typing_finished.connect(_on_typing_finished);
		typewriter.start_typing(text);
	else:
		lore_label.text = text;
		prompt_label.visible = true;
	
#Show the prompt label when typing is finished
func _on_typing_finished() -> void:
	_is_text_finished = true;
	prompt_label.modulate.a = 0.0;
	prompt_label.visible = true;
	var tween = create_tween();
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT);
	tween.tween_property(prompt_label, "modulate:a", 1.0, 1.0);

func _unhandled_input(event: InputEvent) -> void:
	if not (event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel")):
		return;
	get_viewport().set_input_as_handled();
	#If we are still typing, first press skips to full text
	if typewriter and typewriter.is_typing():
		typewriter.skip_to_full();
		return;
		
	#Either the typewriter finished or the user hit a key to end the typewriter effect
	if _is_text_finished and prompt_label.modulate.a >= 1.0:
		#Player can hit any button to proceed
		_dismiss();
		
func _dismiss() -> void:
	Analytics.log_event("lore_title_card_dismissed", {});
	UIRouter.close_top_modal();
