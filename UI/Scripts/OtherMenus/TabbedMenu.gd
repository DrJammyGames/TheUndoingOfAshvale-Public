extends AnimatedMenu
class_name TabbedMenu;
enum Tab {
	PLAYER,
	INVENTORY,
	QUEST,
	ENCYCLOPEDIA,
	PAUSE_MENU
}

#Node refs
#Tab content panels
@onready var player_tab: Control = %PlayerTab;
@onready var inventory_tab: Control = %InventoryTab;
@onready var quest_tab: Control = %QuestTab;
@onready var encyclopedia_tab: Control = %EncyclopediaTab;
@onready var pause_tab: Control = %PauseTab;
@onready var decoration_mode_button: Button = %DecorationModeButton;
#Tab buttons
@onready var player_tab_button: TabButton = %Player;
@onready var inventory_tab_button: TabButton = %Inventory;
@onready var quest_tab_button: TabButton = %Quests;
@onready var encyclopedia_tab_button: TabButton = %Encyclopedia;
@onready var pause_tab_button: TabButton = %Pause;

var _current_tab_index: int = Tab.PLAYER; #Enums are automatically ints
var _is_initialised: bool = false;
#Tracks whether set_initial_tab was called before a deferred fallback fires
var _initial_tab_was_set: bool = false;

func _ready() -> void:
	super._ready();
	#Connect button toggled signals
	player_tab_button.toggled.connect(_on_player_button_toggled);
	inventory_tab_button.toggled.connect(_on_inventory_button_toggled);
	quest_tab_button.toggled.connect(_on_quest_button_toggled);
	encyclopedia_tab_button.toggled.connect(_on_encyclopedia_button_toggled);
	pause_tab_button.toggled.connect(_on_pause_button_toggled);
	#Decoration mode button, only visible when unlocked and in the correct location
	decoration_mode_button.visible = DecorationSystem.is_unlocked();
	decoration_mode_button.pressed.connect(_on_decoration_mode_pressed);
	DecorationSystem.decoration_mode_unlocked.connect(_on_decoration_mode_unlocked);
	
	_is_initialised = true;
	#Don't apply a tab yet, wait until UIRouter has called set_initial_tab
	call_deferred("_apply_initial_tab_if_not_set");
	
#Only fires if UIRouter never called set_initial_tab this frame
func _apply_initial_tab_if_not_set() -> void:
	if not _initial_tab_was_set:
		_apply_tab(_current_tab_index);

	
#region Public helpers
#Set the intial tab to open
func set_initial_tab(tab_name: String) -> void:
	_initial_tab_was_set = true;
	match tab_name:
		"player":
			_current_tab_index = Tab.PLAYER;
		"inventory":
			_current_tab_index = Tab.INVENTORY;
		"quest":
			_current_tab_index = Tab.QUEST;
		"encyclopedia":
			_current_tab_index = Tab.ENCYCLOPEDIA;
		"pause", "system":
			_current_tab_index = Tab.PAUSE_MENU;
		#Default to player
		_:
			_current_tab_index = Tab.PLAYER;
			
	if _is_initialised:
		_apply_tab(_current_tab_index);
	#Analytics: initial tab view
	Analytics.log_event("tabbed_menu_tab_switched", {
		"new_tab": _tab_name_from_index(_current_tab_index),
		"source": "initial"
	})
	
#Show the Player tab
func show_player_tab() -> void:
	_set_tab(Tab.PLAYER, "explicit_player");
	
#Show the inventory tab
func show_inventory_tab() -> void:
	_set_tab(Tab.INVENTORY, "explicit_inventory");
	
#Show the quest tab
func show_quest_tab() -> void:
	_set_tab(Tab.QUEST, "explicit_quest");
	
#Show the encyclopedia stuffs
func show_encyclopedia_tab() -> void:
	_set_tab(Tab.ENCYCLOPEDIA, "explicit_encyclopedia");
	
#Show the pause menu stuffs
func show_pause_tab() -> void:
	_set_tab(Tab.PAUSE_MENU, "explicit_pause");
	
#Checks for if tabs are open
func is_player_tab_active() -> bool:
	return _current_tab_index == Tab.PLAYER;

func is_inventory_tab_active() -> bool:
	return _current_tab_index == Tab.INVENTORY;
	
func is_quest_tab_active() -> bool:
	return _current_tab_index == Tab.QUEST;
	
func is_encyclopedia_tab_active() -> bool:
	return _current_tab_index == Tab.ENCYCLOPEDIA;
	
func is_pause_tab_active() -> bool:
	return _current_tab_index == Tab.PAUSE_MENU;
	
#Get what the current tab is 
func get_current_tab() -> int:
	return _current_tab_index;
	
#Returns the current tab as a string for UIRouter to remember
func get_current_tab_name() -> String:
	return _tab_name_from_index(_current_tab_index);
#endregion
#region Internal helpers
func _set_tab(new_index: int, source: String) -> void:
	#Pressing the active tab again, do nothing
	if new_index == _current_tab_index and _is_initialised:
		#Re-enforce correct button state in case Godot untoggled it
		_apply_tab(_current_tab_index);
		return;
		
	_current_tab_index = new_index;
	_apply_tab(new_index);
	Analytics.log_event("tabbed_menu_tab_switched", {
		"new_tab": _tab_name_from_index(new_index),
		"source": source,
	})
	
#Applies visibility and button pressed states to match tab_index
func _apply_tab(tab_index: int) -> void:
	#Show only the matching panel
	player_tab.visible = (tab_index == Tab.PLAYER);
	inventory_tab.visible = (tab_index == Tab.INVENTORY);
	quest_tab.visible = (tab_index == Tab.QUEST);
	encyclopedia_tab.visible = (tab_index == Tab.ENCYCLOPEDIA);
	pause_tab.visible = (tab_index == Tab.PAUSE_MENU);
	
	#Set active tab on top
	#player_tab_button.z_index = 1 if tab_index == Tab.PLAYER else 0;
	#inventory_tab_button.z_index = 1 if tab_index == Tab.INVENTORY else 0;
	#quest_tab_button.z_index = 1 if tab_index == Tab.QUEST else 0;
	#pause_tab_button.z_index = 1 if tab_index == Tab.PAUSE_MENU else 0;
	
	#Button states
	_apply_button_state(player_tab_button, tab_index == Tab.PLAYER);
	_apply_button_state(inventory_tab_button, tab_index == Tab.INVENTORY);
	_apply_button_state(quest_tab_button, tab_index == Tab.QUEST);
	_apply_button_state(encyclopedia_tab_button, tab_index == Tab.ENCYCLOPEDIA);
	_apply_button_state(pause_tab_button, tab_index == Tab.PAUSE_MENU);
	
	#Refresh the encylopedia if that's the tab that is open
	if tab_index == Tab.ENCYCLOPEDIA:
		encyclopedia_tab.refresh();
	
#Syncs a button's pressed state and triggers the HoverButton animation if this button is becoming the active tab
func _apply_button_state(button: Button, is_active: bool) -> void:
	_set_button_pressed_silent(button, is_active);
	
	#Trigger the HoverButton scale animation
	button.set_active(is_active);
		
#Sets a buttons pressed state while blocked the toggled signal to avoid loops
func _set_button_pressed_silent(button: Button, pressed: bool) -> void:
	button.set_block_signals(true);
	button.set_pressed(pressed);
	button.set_block_signals(false);
	
#region Button signal handlers
func _on_player_button_toggled(pressed: bool) -> void:
	if pressed:
		_set_tab(Tab.PLAYER, "user_click");
	else:
		#Don't allow untoggling, keep active tab pressed
		_set_button_pressed_silent(player_tab_button, _current_tab_index == Tab.PLAYER);
		
func _on_inventory_button_toggled(pressed: bool) -> void:
	if pressed:
		_set_tab(Tab.INVENTORY, "user_click");
	else:
		_set_button_pressed_silent(inventory_tab_button, _current_tab_index == Tab.INVENTORY);
		
func _on_quest_button_toggled(pressed: bool) -> void:
	if pressed:
		_set_tab(Tab.QUEST, "user_click");
	else:
		_set_button_pressed_silent(quest_tab_button, _current_tab_index == Tab.QUEST);

func _on_encyclopedia_button_toggled(pressed: bool) -> void:
	if pressed:
		_set_tab(Tab.ENCYCLOPEDIA, "user_click");
	else:
		_set_button_pressed_silent(encyclopedia_tab_button, _current_tab_index == Tab.ENCYCLOPEDIA);
		
func _on_pause_button_toggled(pressed: bool) -> void:
	if pressed:
		_set_tab(Tab.PAUSE_MENU, "user_click");
	else:
		_set_button_pressed_silent(pause_tab_button, _current_tab_index == Tab.PAUSE_MENU);

#Decoration mode stuffs
func _on_decoration_mode_unlocked() -> void:
	decoration_mode_button.visible = true;
	
func _on_decoration_mode_pressed() -> void:
	UIRouter.show_decoration_mode_ui();
#endregion
	
#Internal helper to get the name of the current tab
func _tab_name_from_index(idx: int) -> String:
	match idx:
		Tab.PLAYER:
			return "player";
		Tab.INVENTORY:
			return "inventory";
		Tab.QUEST:
			return "quest";
		Tab.ENCYCLOPEDIA:
			return "encyclopedia";
		Tab.PAUSE_MENU:
			return "pause";
		_:
			return "unknown";
			
#Can add a close button as well with _on_close_pressed()
#endregion
