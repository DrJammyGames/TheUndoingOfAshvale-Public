extends Control
class_name EncyclopediaDialoguePanel

#Two-level dialogue log
#Level 1: NPC Grid--uses static images of any NPCs that have logged dialogue
#GlobalTooltip shows on hover
#Level 2: (log view): scrollable list of DialogueLogEntry rows for the selected NPC

@export var encyclopedia_icon_scene: PackedScene;
@export var dialogue_log_entry: PackedScene;

#NPC grid view
@onready var npc_grid_view: Control = %NpcGridView;
@onready var npc_grid: GridContainer = %NpcGrid;

#Log view
@onready var log_view: Control = %LogView;
@onready var log_npc_name_label: Label = %LogNpcNameLabel;
@onready var dialogue_log_list: VBoxContainer = %DialogueLogList;
@onready var back_button: Button = %BackButton;

var _selected_npc_id: String = "";

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed);
	EncyclopediaSystem.dialogue_line_logged.connect(_on_dialogue_line_logged);
	rebuild();

#Called by EncyclopediaScreen when switching to this category
func rebuild() -> void:
	#Always return to npc grid when the category is re-entered
	_show_npc_grid();
	
#NPC grid
func _show_npc_grid() -> void:
	npc_grid_view.visible = true;
	log_view.visible = false;
	_build_npc_grid();
	
func _build_npc_grid() -> void:
	#Clear existing entries first
	for child in npc_grid.get_children():
		child.queue_free();
		
	var npc_ids: Array[String] = EncyclopediaSystem.get_npc_ids_with_dialogue();
	
	if npc_ids.is_empty():
		#Nothing to show yet
		return;
		
	for npc_id in npc_ids:
		var npc: NPCData = NPCDatabase.get_npc(npc_id);
		if npc == null:
			continue;
		var icon: EncyclopediaIcon = encyclopedia_icon_scene.instantiate();
		npc_grid.add_child(icon);
		
		var portrait: Texture2D = npc.portrait;
		var npc_name: String = npc.display_name;
		icon.setup(portrait, true, npc_name, "");
		
		#Override mouse filter for icons so we get click events too
		icon.mouse_filter = Control.MOUSE_FILTER_STOP;
		icon.gui_input.connect(_on_npc_icon_input.bind(npc_id));
		
#Log view
func _show_log_view(npc_id: String) -> void:
	_selected_npc_id = npc_id;
	npc_grid_view.visible = false;
	log_view.visible = true;
	
	var npc: NPCData = NPCDatabase.get_npc(npc_id);
	log_npc_name_label.text = npc.display_name if npc != null else npc_id;
	
	_build_log(npc_id);
	
func _build_log(npc_id: String) -> void:
	#Clear existing entries
	for child in dialogue_log_list.get_children():
		child.queue_free();
		
	var lines: Array = EncyclopediaSystem.get_dialogue_log(npc_id);
	for entry in lines:
		var speaker: String = str(entry.get("speaker", ""));
		var text: String = str(entry.get("text", ""));
		if text.is_empty():
			continue;
		var row = dialogue_log_entry.instantiate();
		dialogue_log_list.add_child(row);
		row.setup(speaker, text);
		
#region Signal handlers
func _on_npc_icon_input(event: InputEvent, npc_id: String) -> void:
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton;
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			GlobalTooltip.hide_tooltip();
			_show_log_view(npc_id);
	
func _on_back_pressed() -> void:
	_selected_npc_id = "";
	_show_npc_grid();
	
func _on_dialogue_line_logged(_npc_id: String) -> void:
	#If the log view is open for this NPC, rebuild it live
	if log_view.visible and _npc_id == _selected_npc_id:
		_build_log(_selected_npc_id);
	#If we're on the grid view, rebuild in case a new npc appeared
	elif npc_grid_view.visible:
		_build_npc_grid();
#endregion
