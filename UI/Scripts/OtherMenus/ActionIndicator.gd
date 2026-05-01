extends HBoxContainer

#Reads the equipped weapon and last-used tool from Player
#and keeps the two HUD icons in sync

#Node refs
@onready var attack_icon: TextureRect = %AttackIcon;
@onready var attack_key: Label = %AttackKey;
@onready var tool_icon: TextureRect = %ToolIcon;
@onready var tool_key: Label = %ToolKey;

func _ready() -> void:
	#Set key labels from Input Map so rebinding works automatically
	attack_key.text = _get_key_label("attack");
	tool_key.text = _get_key_label("use_tool");
	
	#Wait for scene_changed since player is attached during scene load which happens after HUD is ready
	if Game:
		Game.player_ready.connect(_on_player_ready);
		
func _on_player_ready() -> void:
	#Wait an additional frame so the player is fully initiated
	await get_tree().process_frame;
	#Listen for tool and weapon changes from the player
	var player = Game.get_player();
	if player == null:
		push_warning("ActionIndicator: could not find player node.");
		return;
		
	#Reconnect safely each time — player persists but we need re-wire on every scene load
	if player.equipped_weapon_changed.is_connected(_on_weapon_changed):
		player.equipped_weapon_changed.disconnect(_on_weapon_changed)
	if player.equipped_tool_changed.is_connected(_on_tool_changed):
		player.equipped_tool_changed.disconnect(_on_tool_changed)
		
	player.equipped_weapon_changed.connect(_on_weapon_changed)
	player.equipped_tool_changed.connect(_on_tool_changed)
	
	_on_weapon_changed(player.get_equipped_weapon_id())
	_on_tool_changed(player.get_last_used_tool_id())

func _on_weapon_changed(item_id: String) -> void:
	if not item_id.is_empty():
		attack_icon.texture = ItemDatabase.get_icon_inv(item_id);
	else:
		attack_icon.texture = null;

func _on_tool_changed(item_id: String) -> void:
	if not item_id.is_empty():
		tool_icon.texture = ItemDatabase.get_icon_inv(item_id);
	else:
		tool_icon.texture = null;
		
#Reads the first bound key for an action and returns it as a display string
func _get_key_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "?";
	
	var events := InputMap.action_get_events(action);
	for event in events:
		if event is InputEventKey:
			#physical_keycode gives the layout-independent key label
			var keycode: int = event.physical_keycode;
			if keycode != KEY_NONE:
				#Gets the actual readable string
				return OS.get_keycode_string(keycode);
	return "?";
