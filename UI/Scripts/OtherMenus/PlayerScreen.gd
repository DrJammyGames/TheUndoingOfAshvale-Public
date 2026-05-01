extends Control
class_name PlayerScreen

#region Node refs and vars
@onready var name_label: Label = %PlayerNameLabel;
@onready var hp_label: Label = %HPLabel;
@onready var attack_label: Label = %AttackLabel;
@onready var defense_label: Label = %DefenseLabel;
@onready var luck_label: Label = %LuckLabel;
@onready var gold_label: Label = %GoldLabel;

@onready var level_label: Label = %LevelLabel;
@onready var xp_bar: TextureProgressBar = %XPBar;
@onready var xp_label: Label = %XPLabel;
var _is_ready: bool = false;

@export var portrait_texture: Texture2D;

@onready var portrait_rect: TextureRect = %PortraitRect;
@onready var slot_hat: ArmorSlot = %SlotHat;
@onready var slot_ring_top: ArmorSlot = %SlotRingTop;
@onready var slot_ring_bottom: ArmorSlot = %SlotRingBottom;
@onready var slot_armor: ArmorSlot = %SlotArmor;
@onready var slot_boots: ArmorSlot = %SlotBoots;
@onready var slot_weapon: ArmorSlot = %SlotWeapon;
#endregion

func _ready() -> void:
	_is_ready = true;
	#Connect to stat changes
	_try_connect_player_stats();
	Game.player_ready.connect(_on_player_ready);
	
	LevelSystem.xp_changed.connect(_on_xp_changed);
	LevelSystem.leveled_up.connect(_on_level_up);
	GameState.gold_changed.connect(_on_gold_changed);
	
	_refresh_all();
	
#Re-run when tab becomes visible so data is never stale
func _notification(what: int) -> void:
	if not _is_ready:
		return;
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		_refresh_all();
		
#region Connection helpers
func _try_connect_player_stats() -> void:
	var player = Game.get_player();
	if player and player.has_method("get_stats"):
		var stats: PlayerStats = player.get_stats();
		stats.stats_changed.connect(_refresh_stats);
		
func _on_player_ready() -> void:
	_try_connect_player_stats();
	_refresh_all();
#endregion
#region Refresh stuffs
func _refresh_all() -> void:
	_refresh_stats();
	_refresh_level();
	_refresh_gold();
	_refresh_equipment();
	
#Refresh the player stats, attack and such
func _refresh_stats() -> void:
	var player = Game.get_player();
	if player == null or not player.has_method("get_stats"):
		return;
	var stats: PlayerStats = player.get_stats();
	if GameState.player_name != "":
		name_label.text = GameState.player_name 
	else:
		name_label.text = "Player";
	hp_label.text = UIStringsDatabase.get_text("stat_hp") \
		.replace("{hp}", str(stats.health)) \
		.replace("{max_hp}", str(stats.max_health));
	attack_label.text = UIStringsDatabase.get_text("stat_attack") \
		.replace("{attack}", str(stats.attack))
	defense_label.text = UIStringsDatabase.get_text("stat_defense") \
		.replace("{defense}", str(stats.defense));
	luck_label.text = UIStringsDatabase.get_text("stat_luck") \
		.replace("{luck}", str(stats.luck));
	
#Refresh the level info, xp progress and such
func _refresh_level() -> void:
	var lvl: int = LevelSystem.current_level;
	var xp: int = LevelSystem.current_xp;
	var needed: int = LevelSystem.xp_to_next_level();
	level_label.text = UIStringsDatabase.get_text("stat_level") \
		.replace("{level}", str(lvl));
	xp_bar.value = LevelSystem.xp_progress_ratio() * 100.0;
	if lvl >= LevelSystem.MAX_LEVEL:
		xp_label.text = UIStringsDatabase.get_text("stat_xp_max");
	else:
		xp_label.text = UIStringsDatabase.get_text("stat_xp") \
			.replace("{xp}", str(xp)) \
			.replace("{xp_needed}", str(needed));
		
#Refresh the amount of gold
func _refresh_gold() -> void:
	gold_label.text = UIStringsDatabase.get_text("stat_gold") \
		.replace("{gold}", str(GameState.gold));
		
func _refresh_equipment() -> void:
	if portrait_texture:
		portrait_rect.texture = portrait_texture;
	slot_hat.clear_item();
	slot_armor.clear_item();
	slot_boots.clear_item();
	slot_ring_bottom.clear_item();
	slot_ring_top.clear_item();
	slot_weapon.clear_item();
#endregion
#region Signal handlers
func _on_xp_changed(_current_xp: int, _xp_to_next: int) -> void:
	_refresh_level();
	
func _on_level_up(_new_level: int) -> void:
	_refresh_level();
	_refresh_stats();
	
func _on_gold_changed(_new_amount: int) -> void:
	_refresh_gold();
#endregion
	
