extends PanelContainer

@onready var item_name_label: Label = %ItemName;
@onready var item_desc_label: RichTextLabel = %ItemDesc;

#How far to draw away from mouse
@export var mouse_offset: Vector2 = Vector2(16,16);
@export var min_width: float = 160.0;

#Setup parameters
func _ready() -> void:
	visible = false;
	mouse_filter = Control.MOUSE_FILTER_IGNORE;
	
	#Setup panel settings
	set_anchors_preset(Control.PRESET_TOP_LEFT);
	position = Vector2.ZERO;
	
	
#region Public helpers
func show_tooltip(item_name: String, item_desc: String) -> void:
	#No text, so hide tooltip
	if item_name == "":
		hide_tooltip();
		return;
	
	#Set the text
	item_name_label.text = item_name;
	item_desc_label.text = item_desc;
	item_desc_label.visible = item_desc != "";
	#Reset so panel recalculates from content
	size = Vector2.ZERO;
	#Let layout update the panel's size
	await get_tree().process_frame;
	
	var panel_size: Vector2 = size;
	#Mouse position in viewport coordinates
	#Set here instead of where tooltip gets called
	var mouse_pos: Vector2 = get_viewport().get_mouse_position();
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size;
	var pos: Vector2 = mouse_pos + mouse_offset;
	
	#Clamp within viewport
	pos.x = clampf(pos.x, 0.0, viewport_size.x - panel_size.x);
	pos.y = clampf(pos.y, 0.0, viewport_size.y - panel_size.y);
		
	global_position = pos;
	visible = true;
#Hide tooltip
func hide_tooltip() -> void:
	visible = false;
#endregion
