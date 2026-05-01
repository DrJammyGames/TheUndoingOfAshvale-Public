extends Control
class_name EncyclopediaGridPanel

#Generic grid panel for the encyclopedia
#Behaviour is driven by the config dictionary passed into setup

#Required config keys:
#get_all : Callable -> Array
#get_icon: Callable(entry) -> Texture2D
#get_id: Callable(entry) -> String
#is_discovered: Callable(id) -> bool
#get_title: Callable(id) -> String
#get_body: Callable(id) -> String
#sort: Callable(a,b) -> bool --custom sorting

const ENCYCLOPEDIA_ICON_SCENE: PackedScene = preload("res://UI/Scenes/Encyclopedia/EncyclopediaIcon.tscn");

@onready var grid: GridContainer = %GridContainer;

var _config: Dictionary = {};

func setup(config: Dictionary) -> void:
	_config = config;
	rebuild();
	
func rebuild() -> void:
	if _config.is_empty():
		return;
	#Clear existing stuffs first
	for child in grid.get_children():
		child.queue_free();
		
	var entries: Array = _config.get_all.call();
	
	if _config.has("sort"):
		entries.sort_custom(_config.sort);
	else:
		#Default alphabetical by title
		entries.sort_custom(func(a,b):
			return _config.get_title.call(_config.get_id.call(a)) < _config.get_title.call(_config.get_id.call(b)))
	
	for entry in entries:
		var id: String = _config.get_id.call(entry);
		var discovered: bool = _config.is_discovered.call(id);
		var title: String = _config.get_title.call(id);
		var body: String = _config.get_body.call(id);
		var texture: Texture2D = _config.get_icon.call(entry);
		
		var icon: EncyclopediaIcon = ENCYCLOPEDIA_ICON_SCENE.instantiate();
		grid.add_child(icon);
		icon.setup(texture, discovered, title, body);
