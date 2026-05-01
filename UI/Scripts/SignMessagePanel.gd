extends Control
class_name SignMessagePanel;

signal closed

@onready var title_label: Label = %Title;
@onready var body_label: Label = %Body;
@onready var hint_label: Label = %Hint;
@onready var got_it_button: Button = %GotItButton;

func _ready() -> void:
	visible = false;
	mouse_filter = Control.MOUSE_FILTER_STOP;
	set_process_unhandled_input(true);
	got_it_button.pressed.connect(_on_got_it_pressed);
	UIStringsDatabase.apply_to_button(got_it_button,"controls_hint_got_it")
	

func setup(title: String, body: String, hint: String = "Press Interact to close") -> void:
	title_label.text = title;
	body_label.text = body;
	hint_label.text = hint;

func open() -> void:
	visible = true;
	got_it_button.grab_focus();

func close() -> void:
	visible = false;
	get_viewport().set_input_as_handled();
	closed.emit();

func _on_got_it_pressed() -> void:
	close();
	
