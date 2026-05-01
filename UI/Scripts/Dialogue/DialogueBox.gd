extends AnimatedMenu
#UI Control shows speaker name, text, and choices
#Listens to DialogueSystem signals

@onready var dialogue_root: Control = $DialogueRoot;
@onready var panel: Panel = %DialoguePanel;
@onready var panel2: Panel = %SpeakerPanel;
@onready var speaker_label: Label = %SpeakerLabel;
@onready var text_label: RichTextLabel = %DialogueText;
@onready var choices_container: VBoxContainer = %ChoicesContainer;
@onready var hint_label: Label = %HintLabel;
@onready var typewriter: TypewriterText = %TypewriteText;

var choice_button_scene: PackedScene = preload("res://UI/Scenes/Buttons/ChoiceButton.tscn");
#Track whether the current line has choices or not
var _current_line_has_choices: bool = false;

func _ready() -> void:
	super._ready();

	#Connect to DialogueSystem signals
	DialogueSystem.dialogue_started.connect(_on_dialogue_started);
	DialogueSystem.line_changed.connect(_on_line_changed);
	DialogueSystem.choices_presented.connect(_on_choices_presented);
	DialogueSystem.dialogue_ended.connect(_on_dialogue_ended);
	if typewriter:
		typewriter.set_process(true); # ensure _process runs
		typewriter.typing_finished.connect(_on_typing_finished);
		typewriter.typing_skipped.connect(_on_typing_skipped);
	
func _unhandled_input(event: InputEvent) -> void:
	#Handle advance/skip input here
	#Only respond if the dialogue is active
	if not DialogueSystem.is_active():
		return;
	
	if event.is_pressed() and not event.is_echo():
		get_viewport().set_input_as_handled();
		#If there are no choices, this is either skip or next-line
		if not _current_line_has_choices:
			if typewriter and typewriter.is_typing():
				#First press: finish the line instantly
				typewriter.skip_to_full();
			else:
				#Line is fully visible: go to the next line
				DialogueSystem.next_line();
	#If there ARE choices, player must click a button instead
	elif event.is_action_pressed("ui_cancel"):
		#Allow skipping the conversation
		get_viewport().set_input_as_handled();
		DialogueSystem.skip_dialogue();
		

#region Internal helpers
func _on_dialogue_started(_dialogue_id: String) -> void:
	#Clear any previous info in the dialogue box
	_current_line_has_choices = false;
	_clear_choices();
	#Hide the health and such 
	UIRouter.set_hud_visible(false);
	
func _on_line_changed(line_data: Dictionary) -> void:
	#Update speaker and text
	var speaker: String = line_data.get("speaker","");
	var text: String = line_data.get("text", "");
	_current_line_has_choices = line_data.get("has_choices", false);
	
	speaker_label.text = speaker;
	#Wait a frame
	await get_tree().process_frame;
	panel2.custom_minimum_size.x = speaker_label.size.x + 24; 
	
	#Start typewriter effect if available
	if typewriter:
		#Optional: feed in a line id for analytics
		if typewriter.enable_analytics:
			typewriter.analytics_id = StringName(line_data.get("id", ""));
		typewriter.start_typing(text);
	else:
		#Fallback: just set the text
		text_label.text = text;
	
	#While typing, we don't show the "press key" hint yet
	_set_hint_visible(false)
	#Clear any previous choices buttons
	#They will be rebuilt if needed
	_clear_choices();
	
func _on_choices_presented(choices: Array) -> void:
	#Build a button for each choice
	_current_line_has_choices = true;
	_set_hint_visible(false);
	_clear_choices();
	
	for choice_dict in choices:
		var button: ChoiceButton = choice_button_scene.instantiate();
				
		var text_value: String = str(choice_dict.get("text", ""));
		var choice_id: String = str(choice_dict.get("id", ""));
		choices_container.add_child(button);
		button.set_choice_text(text_value);
		
		button.pressed.connect(func() -> void:
			DialogueSystem.choose_option(choice_id);
		)

		
#Hide the box when dialogue ends
func _on_dialogue_ended(_result_data: Dictionary) -> void:
	_current_line_has_choices = false;
	_clear_choices();
	#Play the AnimatedMenu close animation, then clean up
	play_close_animation();
	await close_animation_finished;
	#Only restore hud if nothing else is holding a banner lock
	#there's more dialogue to go
	UIRouter.pop_banner_lock("DialogueBox.close_animation_finished");
	if not DialogueSystem.is_active() and not UIRouter.has_queued_banners():
		UIRouter.set_hud_visible(true);
	queue_free();

func _clear_choices() -> void:
	#Remove all children from the choices container
	for child in choices_container.get_children():
		child.queue_free();

func _set_hint_visible(_show: bool) -> void:
	if hint_label == null:
		return;
	hint_label.visible = _show;
		
func _on_typing_finished() -> void:
	#Only show hint if there are no choices for this line
	if not _current_line_has_choices:
		_set_hint_visible(true);

func _on_typing_skipped() -> void:
	#When skip is pressed, we can also show the hint
	if not _current_line_has_choices:
		_set_hint_visible(true);
#endregion
