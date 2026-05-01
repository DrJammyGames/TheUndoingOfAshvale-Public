extends Resource
#Class name instead of an autoload for this
class_name PlayerStats;
#Data-driven stats for the player character
signal stats_changed();
signal died();

@export var luck: int = 0:
	set(value):
		luck = max(value, 0);
		stats_changed.emit();

@export var max_health: int = 50:
	set(value):
		max_health = max(value, 1);
		if health > max_health:
			health = max_health;
		stats_changed.emit();

@export var max_mana: int = 50:
	set(value):
		max_mana = max(value, 0);
		if mana > max_mana:
			mana = max_mana;
		stats_changed.emit();
		
@export var health: int = 50:
	set(value):
		health = clamp(value, 0, max_health);
		stats_changed.emit();
		if health <= 0:
			died.emit();

@export var mana: int = 50:
	set(value):
		mana = clamp(value, 0, max_mana);
		stats_changed.emit();
		
#Core combat stats--can add to later
@export var attack: int = 5:
	set(value):
		attack = max(value, 1);
		stats_changed.emit();
		
@export var defense: int = 0:
	set(value):
		defense = max(value, 0);
		stats_changed.emit();
		
#Optional base movement/attack speeds
@export var base_move_speed: float = 120.0;
@export var base_attack_speed: float = 1.0;

#Match to level system
@export var base_max_health: int = 50;
@export var base_attack: int = 5;
@export var base_defense: int = 0;
@export var base_luck: int = 0;
#region Health
func apply_damage(amount: int) -> void:
	if amount <= 0:
		return;
	health -= amount;
	
func heal(amount: int) -> void:
	if amount <= 0:
		return;
	health += amount;
#endregion
#region Mana
func spend_mana(amount: int) -> bool:
	if amount <= 0:
		return true;
	if mana < amount:
		return false;
	mana -= amount;
	return true;
	
func restore_mana(amount: int) -> void:
	if amount <= 0:
		return;
	mana += amount;
#endregion
#region Save and load stuffs
func to_dict() -> Dictionary:
	return {
		"health": health,
		"mana": mana,
		"attack": attack,
		"luck": luck,
		"defense": defense,
		"base_max_health": base_max_health,
		"base_attack": base_attack,
		"base_defense": base_defense,
		"base_luck": base_luck,
	}
func from_dict(data: Dictionary) -> void:
	base_max_health = int(data.get("base_max_health", 50));
	base_attack = int(data.get("base_attack", 5));
	base_defense = int(data.get("base_defense", 0));
	base_luck = int(data.get("base_luck", 0));
	#Apply base stats to live stats before restoring health
	max_health = base_max_health;
	#Live values restore from save; fall back if base are missing
	health = data.get("health", base_max_health);
	mana = data.get("mana", mana);
	attack = data.get("attack", base_attack);
	defense = data.get("defense", base_defense);
	luck = data.get("luck", base_luck);
#endregion
