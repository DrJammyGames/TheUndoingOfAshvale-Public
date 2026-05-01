extends Node

#Owns XP and level progression for the player
#Other systems react to the signals so there are no direct calls

signal xp_changed(current_xp: int, xp_to_next: int);
signal leveled_up(new_level: int);

const MAX_LEVEL: int = 20; #can increase later
const BASE_XP: int = 80; #XP required to reach level 2
const RAMP_FACTOR: float = 1.2; #Each level costs 20% more xp than the last

#Stat increases applied per level-up
const HP_PER_LEVEL: int = 10;
const ATTACK_PER_LEVEL: int = 1;
const DEFENSE_PER_LEVEL: int = 1;
const LUCK_PER_LEVEL: int = 1;

#Inventory row milestones -> rows unlocked
const INVENTORY_MILESTONES: Dictionary = {
	5: 2, #2 rows = 16 slots
	10: 3,
	20: 4, #32 slots max
};
const SLOTS_PER_ROW: int = 8;

var current_level: int = 1;
var current_xp: int = 0;

#Precomputed xp thresholds-index 0 = XP needed to reach level 2, etc.
var _xp_thresholds: Array[int] = [];

func _ready() -> void:
	_build_xp_table();
	QuestSystem.quest_completed.connect(_on_quest_completed);
	
func _build_xp_table() -> void:
	#Clear thresholds
	_xp_thresholds.clear();
	var cost: float = BASE_XP;
	for i in range(MAX_LEVEL - 1):
		_xp_thresholds.append(int(cost));
		cost *= RAMP_FACTOR;
		
#region Public helpers
func add_xp(amount: int) -> void:
	if current_level >= MAX_LEVEL:
		return;
	if amount <= 0:
		return;
		
	current_xp += amount;
	Analytics.log_event("xp_gained", {
		"amount": amount,
		"total_xp": current_xp,
		"level": current_level,
	});
	
	#Level up look--handles multi-level gains in one cell
	while current_level < MAX_LEVEL:
		var needed: int = xp_to_next_level();
		if current_xp < needed:
			break;
		current_xp -= needed;
		current_level += 1;
		_on_level_up(current_level);
	var hud = UIRouter.get_hud();
	if hud:
		hud.show_message("+%d XP" % amount);
	xp_changed.emit(current_xp, xp_to_next_level());
	
#Calculate xp need to reach the next level
func xp_to_next_level() -> int:
	if current_level >= MAX_LEVEL:
		return 0;
	return _xp_thresholds[current_level - 1];
	
func xp_progress_ratio() -> float:
	var needed: int = xp_to_next_level();
	if needed <= 0:
		return 1.0;
	return float(current_xp) / float(needed);
	
#region Save and load stuffs
func to_dict() -> Dictionary:
	return {
		"current_level": current_level,
		"current_xp": current_xp
	};
	
func from_dict(data: Dictionary) -> void:
	current_level = int(data.get("current_level", 1));
	current_xp = int(data.get("current_xp", 0));
	#Re-emit so HUD reflects loaded state
	xp_changed.emit(current_xp, xp_to_next_level());
	
#Reset on new game
func reset() -> void:
	current_level = 1;
	current_xp = 0;
	xp_changed.emit(current_xp, xp_to_next_level());
#endregion
#endregion
#region Internal helpers
#Level up consequences
func _on_level_up(new_level: int) -> void:
	#Raise base stats
	var stats: PlayerStats = _get_stats();
	if stats:
		stats.base_max_health += HP_PER_LEVEL;
		stats.max_health = stats.base_max_health;
		#Heal player to new max health
		stats.health = stats.max_health;
		stats.base_attack += ATTACK_PER_LEVEL;
		stats.attack = stats.base_attack;
		stats.base_defense += DEFENSE_PER_LEVEL;
		stats.defense = stats.base_defense;
		stats.base_luck += LUCK_PER_LEVEL;
		stats.luck = stats.base_luck;
	#Expand inventory if this is a milestone level
	if INVENTORY_MILESTONES.has(new_level):
		var new_row_count: int = INVENTORY_MILESTONES[new_level];
		InventorySystem.set_row_count(new_row_count);
		
	#Crafting hook--add in here later blueprints and such
	Analytics.log_event("level_up", {
		"new_level": new_level
	});
	leveled_up.emit(new_level);
	
#Get the PlayerStats
func _get_stats() -> PlayerStats:
	var player = Game.get_player();
	if player:
		return player.get_stats();
	return null;
	
#Connect to completed quest
func _on_quest_completed(quest_id: String) -> void:
	#Get the amount of xp from the QuestDatabase
	var xp: int = QuestDatabase.get_xp_reward(quest_id);
	if xp > 0:
		add_xp(xp);

#endregion
