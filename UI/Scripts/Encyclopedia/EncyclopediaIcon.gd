extends Control 
class_name EncyclopediaIcon

#Reusable icon for the encyclopedia grid
#Discovered entries show the real icon and full tooltip info
#Undisovered entries are black out with ??? tooltip

@onready var icon_rect: TextureRect = %Icon;

var _tooltip_title: String = "";
var _tooltip_body: String = "";
var _is_discovered: bool = false;

const UNDISCOVERED_TITLE: String = "???";
const UNDISCOVERED_BODY: String = "???";

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP;
	mouse_entered.connect(_on_mouse_entered);
	mouse_exited.connect(_on_mouse_exited);
	
#Called by each panel to populate the icons
#texture--the icon to display 
#discovered--whether the player has found this entry or not
#title--localised name for the tooltip header
#body localised description/stats for the tooltip body
func setup(texture: Texture2D, discovered: bool, title: String, body: String) -> void:
	_is_discovered = discovered;
	_tooltip_title = title;
	_tooltip_body = body;
	
	if icon_rect: 
		icon_rect.texture = texture;
		
	if discovered:
		modulate = Color(1,1,1,1);
	else:
		modulate = Color(0,0,0,1);
		
#Display tooltip
func _on_mouse_entered() -> void:
	if not GlobalTooltip:
		return;
	if _is_discovered:
		GlobalTooltip.show_tooltip(_tooltip_title, _tooltip_body);
	else:
		GlobalTooltip.show_tooltip(UNDISCOVERED_TITLE, UNDISCOVERED_BODY);
		
func _on_mouse_exited() -> void:
	if GlobalTooltip:
		GlobalTooltip.hide_tooltip();
