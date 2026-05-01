extends CharacterBody2D;


#region Variable declaration
@export var enemy_id: String = "";
@export var target_group: StringName = &"player";

#Node refs
@onready var anim: AnimatedSprite2D = %Sprite;
@onready var aggro_area: Area2D = %AggroArea;
@onready var attack_area: Area2D = %AttackArea;
@onready var attack_cooldown_timer: Timer = %AttackCoolDownTimer;

#Runtime state
enum State {
	IDLE,
	CHASE,
	ATTACK,
	HURT,
	DEAD 
};
#Direction constants
const DIR_DOWN := Vector2(0,1);
const DIR_UP := Vector2(0,-1);
const DIR_LEFT := Vector2(-1,0);
const DIR_RIGHT := Vector2(1,0);
var facing_dir = DIR_DOWN; #Placement direction
var _state: State = State.IDLE;
var _target: Node2D = null;

#Enemy variables from database--set and hold fallback values
var _max_hp: int = 10;
var _hp: int = 10;
var _attack: int = 1;
var _defense: int = 0;
var _move_speed: float = 50.0;
var _aggro_range: float = 120.0;
var _attack_range: float = 20.0;
var _attack_cooldown_sec: float = 1.0;
var _ai_profile_id: String = "melee_basic";

#Check for attack timer cooldown
var _is_attack_ready: bool = true;
var _attack_in_progress: bool = false;

#Knockback and hurt state
var _knockback_velocity: Vector2 = Vector2.ZERO;
var _knockback_damping: float = 600.0; #how quickly knockback decays
var _hurt_timer: float = 0.0;
var _hurt_duration: float = 0.5;
var _death_linger_duration: float = 0.50; #seconds to hold death frame

#endregion

func _ready() -> void:
	#Load the info from the database
	_load_data_from_database();
	#Apply the visuals based on enemy ID
	_apply_visuals();
	#Configure the aggro and attack ranges
	_configure_ranges();
	
	#Timers
	attack_cooldown_timer.one_shot = true;
	attack_cooldown_timer.timeout.connect(_on_attack_cooldown_timeout);
	
	if anim != null:
		anim.animation_finished.connect(_on_anim_finished);
	#Add to enemies group
	add_to_group("enemies");
	#Begin idle animation
	_update_animation();
	
#Get state and such based on delta time
func _physics_process(delta: float) -> void:
	#If dead, return
	if _state == State.DEAD:
		return;
		
	#Ensure a target exists at all
	if _target == null or not is_instance_valid(_target):
		_target = _find_target();
		
	#Ensure the target is alive
	if _target != null and not _is_target_alive():
		_target = null;
		_set_state(State.IDLE);
		velocity = Vector2.ZERO;
		move_and_slide();
		return;
		
	#State machine
	match _state:
		State.IDLE:
			_tick_idle(delta);
		State.CHASE:
			_tick_chase(delta);
		State.ATTACK:
			_tick_attack(delta);
		State.HURT:
			_tick_hurt(delta);

#Data loading/setup
func _load_data_from_database() -> void:
	if enemy_id.is_empty():
		push_warning("Enemy: enemy_id is empty. Using fallback stats.");
		return;
		
	if EnemyDatabase == null:
		push_error("Enemy: EnemyDatabase autoload missing.");
		return;
		
	#Safety checks passed	
	var data: EnemyDataResource = EnemyDatabase.get_enemy(enemy_id);
	if data == null:
		push_warning("Enemy: No data for enemy_id '%s'." % enemy_id);
		return;
		
	#Get the actual values from the database
	_max_hp = max(data.max_hp, 1);
	_hp = _max_hp;
	_attack = max(data.attack, 0);
	_defense = max(data.defense, 0);
	_move_speed = max(data.move_speed, 0.0);
	_aggro_range = max(data.aggro_range, 0.0);
	_attack_range = max(data.attack_range, 0.0);
	_attack_cooldown_sec = max(data.attack_cooldown_sec, 0.0);
	_ai_profile_id = String(data.ai_profile_id);
	

#Apply the proper visuals based on enemy_id and EnemyData resource
func _apply_visuals() -> void:
	var frames = EnemyDatabase.get_sprite_frames(enemy_id);
	if frames:
		anim.sprite_frames = frames;
	
	
#Check that the player target is actually alive
func _is_target_alive() -> bool:
	if _target == null:
		return false;
	if not is_instance_valid(_target):
		return false;
		
	#Ensure player target is alive
	if _target.has_method("is_alive"):
		return _target.is_alive();
		
	#Fallback--target doesn't expose is_alive, assume it's alive
	return true;
	
#Get the attack and aggro ranges and set the collision shapes
func _configure_ranges() -> void:
	var aggro_shape = aggro_area.get_node_or_null("CollisionShape2D");
	if aggro_shape and aggro_shape.shape is CircleShape2D:
		(aggro_shape.shape as CircleShape2D).radius = _aggro_range;
		
	var attack_shape = attack_area.get_node_or_null("CollisionShape2D");
	if attack_shape and attack_shape.shape is CircleShape2D:
		(attack_shape.shape as CircleShape2D).radius = _attack_range;
		
#region State ticks
func _tick_idle(_delta: float) -> void:
	velocity = Vector2.ZERO;
	move_and_slide();
	
	if _target == null:
		return;
		
	if _is_target_in_aggro():
		_set_state(State.CHASE);
		
func _tick_chase(_delta: float) -> void:
	#No target, go back to idle
	if _target == null:
		_set_state(State.IDLE);
		return;
		
	#Get distance to target
	var to_target = _target.global_position - global_position;
	var dist = to_target.length();
	
	#Lose aggro state if target is too far
	if dist > _aggro_range * 1.25:
		_set_state(State.IDLE);
		return;
		
	#Switch to attacking if within range and cooldown is ready
	if dist <= _attack_range and _is_attack_ready:
		_set_state(State.ATTACK)
		return;

	#Move towards the target
	var dir = to_target.normalized();
	velocity = dir * _move_speed;
	move_and_slide();
	
	#Check if facing new direction
	var new_dir = _direction_from_vector(dir);
	if new_dir != facing_dir:
		facing_dir = new_dir;
		_update_animation();
	
func _tick_attack(_delta: float) -> void:
	#No target, or target is dead, go back to idle
	if _target == null or not _is_target_alive():
		_set_state(State.IDLE);
		return;
	
	velocity = Vector2.ZERO;
	move_and_slide();
	
	#Only start attack once
	if _attack_in_progress:
		return;
		
	#Gate starting the attack
	if not _is_attack_ready:
		_set_state(State.CHASE);
		return;
		
	if not _is_target_in_attack_range():
		_set_state(State.CHASE);
		return;
	
	#Commit to attack now
	_attack_in_progress = true;
	#Get the correct facing direction
	var to_target := _target.global_position - global_position;
	facing_dir = _direction_from_vector(to_target.normalized());
	#FORCE update so ATTACK anim plays even if direction didn't change
	_update_animation();
		
	#Perform attack based on the ai_attack_profile
	match _ai_profile_id:
		"melee_fast":
			_do_melee_attack(0.90) #Slightly shorter windup
		"melee_slow":
			_do_melee_attack(1.40); #Slightly longer windup
		_:
			_do_melee_attack(1.0);
			
	return;
	
func _tick_hurt(delta: float) -> void:
	#Countdown hurt window
	if _hurt_timer > 0.0:
		_hurt_timer -= delta;
		if _hurt_timer < 0.0:
			#reset
			_hurt_timer = 0.0;
			
	#While hurt, movement is only knockback
	if _knockback_velocity.length() > 0.1:
		velocity = _knockback_velocity;
		_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, _knockback_damping * delta);
	else:
		velocity = Vector2.ZERO;
		
	move_and_slide();
	
	#When hurt window is over and knockback gone, resume AI
	if _hurt_timer <= 0.0 and _knockback_velocity.length() <= 1.0:
		if _target != null and is_instance_valid(_target) and _is_target_alive():
			_set_state(State.CHASE);
		else:
			_set_state(State.IDLE);
#endregion
#region State helpers
func _set_state(new_state: State) -> void:
	if _state == new_state:
		return;
	_state = new_state;
	if _state != State.ATTACK:
		_attack_in_progress = false;
	_update_animation();

func _direction_from_vector(v: Vector2) -> Vector2:
	#Select the dominate axis
	if abs(v.x) > abs(v.y):
		return DIR_RIGHT if v.x > 0 else DIR_LEFT;
	else:
		return DIR_DOWN if v.y > 0 else DIR_UP;
#endregion
#region Combat
func take_damage(amount: int,
	knockback_dir: Vector2 = Vector2.ZERO,
	knockback_force: float = 0.0
	) -> void:
	#If already dead, return
	if _state == State.DEAD:
		return;
		
	#Calculate and take damage
	var final_damage: int = max(1, amount - _defense);
	_hp -= final_damage;
	
	#Show damage number above enemy
	var hud = UIRouter.get_hud();
	if hud:
		hud.show_message(str(final_damage), 1.5, global_position, Color("#ff6b6b"));
	#Analytics
	Analytics.log_event("enemy_hit", {
		"enemy_id": enemy_id,
		"damage": final_damage,
		"hp_after": _hp,
		"scene": Analytics.get_scene_path(),
	})
	if _hp <= 0:
		_die();
		return;
	#Setup knockback velocity if requested
	if knockback_force > 0.0 and knockback_dir.length() > 0.0:
		_knockback_velocity = knockback_dir.normalized() * knockback_force;
	else:
		_knockback_velocity = Vector2.ZERO;
	#Enter hurt state and play anims
	_hurt_react();
	
#Melee attack based on profile
func _do_melee_attack(windup_multiplier: float = 1.0) -> void:
	#Play animation, wait a short windup, apply damage if target still in range, start cooldown
	_is_attack_ready = false;
	attack_cooldown_timer.start(_attack_cooldown_sec);
	
	var windup: float = 0.25 * windup_multiplier;
	if windup > 0.0:
		await get_tree().create_timer(windup).timeout;
	#Direction from enemy to player--calculate knockback
	var dir: Vector2 = Vector2.ZERO;
	if _target is Node2D:
		dir = (_target.global_position - global_position);
	#Tune this value to change how much knockback effect there is
	var knockback_force: float = 120.0;
	#Only apply damage if target still in range and such
	if _target != null and is_instance_valid(_target) and _is_target_in_attack_range() and _is_target_alive():
		if _target.has_method("take_damage"):
			_target.take_damage(_attack, dir, knockback_force);
			
	
func _die() -> void:
	if _state == State.DEAD:
		return;
	#Use _set_state to get death animation
	_set_state(State.DEAD);
	velocity = Vector2.ZERO;
	move_and_slide();
	
	_spawn_drops();
	#Allow the direct calls here as EnemySystems is not an autoload
	#Add xp as well
	var xp: int = EnemyDatabase.get_xp_reward(enemy_id);
	if xp > 0:
		LevelSystem.add_xp(xp);
	EncyclopediaSystem.record_kill(enemy_id);
	#Drop gold coins as a world pickup as well
	var gold_min: int = EnemyDatabase.get_gold_min(enemy_id);
	var gold_max: int = EnemyDatabase.get_gold_max(enemy_id);
	if gold_max > 0:
		var gold_amount: int = randi_range(gold_min, gold_max);
		if gold_amount > 0:
			WorldDrops.spawn_item_drop(
				"gold_coin",
				gold_amount,
				self,
				{
					"source_type": "enemy",
					"source_id": enemy_id,
				}
			);
			Analytics.log_event("enemy_gold_dropped", {
				"enemy_id": enemy_id,
				"amount": gold_amount,
			})
	Analytics.log_event("enemy_died", {
		"enemy_id": enemy_id,
		"scene": Analytics.get_scene_path(),
	})
	#Slightly shake the camera when enemy dies for the length of the death animation
	VisualFX.shake_camera(3.0, _death_linger_duration);
	#Let the single frame death animation pose breathe a bit
	await get_tree().create_timer(_death_linger_duration).timeout;
	#Safety: make sure it hasn't already been freed sonehow
	if not is_queued_for_deletion():
		queue_free();

#Get what drops should spawn from database
func _spawn_drops() -> void:
	var drops = EnemyDatabase.get_drops(enemy_id);
	if drops.is_empty():
		return;
	
	#Basic roll
	for d in drops:
		if typeof(d) != TYPE_DICTIONARY:
			continue;
		var item_id: String = String(d.get("item_id", ""));
		var chance: float = float(d.get("chance", 0.0));
		var min_amt: int = int(d.get("min", 1));
		var max_amt: int = int(d.get("max", 1));
		
		var luck: int = 0;
		var player = Game.get_player();
		if player and player.has_method("get_stats"):
			luck = player.get_stats().luck;
		var effective_chance: float = min(chance * (1.0 + luck * 0.01), 1.0);
		if randf() > effective_chance:
			continue;
			
		var amt: int = randi_range(min_amt, max_amt);
		#Call item drop spawn
		#Delegate to the shared world drop system
		WorldDrops.spawn_item_drop(
			item_id,
			amt,
			self,
			{
				"source_type": "enemy",
				"source_id": enemy_id
			}
		)

#Hurt reaction
func _hurt_react() -> void:
	#Don't enter hurt state if already flagged dead somehow
	if _state == State.DEAD:
		return;
	
	_hurt_timer = _hurt_duration;
	_set_state(State.HURT);
	#Add visualfx here (camera shake or something)
#endregion
#region Targeting/range checks
func _find_target() -> Node2D:
	var nodes = get_tree().get_nodes_in_group(String(target_group));
	for n in nodes:
		if n is Node2D:
			if n.has_method("is_alive") and not n.is_alive():
				continue;
			return n as Node2D;
	return null;
	
#Check if player is in aggro range
func _is_target_in_aggro() -> bool:
	if _target == null:
		return false;
	return global_position.distance_to(_target.global_position) <= _aggro_range;
	
#Check if player is in attack range
func _is_target_in_attack_range() -> bool:
	if _target == null:
		return false;
	return global_position.distance_to(_target.global_position) <= _attack_range;
	
func _on_attack_cooldown_timeout() -> void:
	_is_attack_ready = true;
	
#endregion
#region Animation helpers
#Get correct state name for animation
func _get_state_name(s: State) -> String:
	match s:
		State.IDLE:
			return "idle";
		State.CHASE:
			return "walk"; #name of animation
		State.ATTACK:
			return "attack";
		State.HURT:
			return "hurt";
		State.DEAD:
			return "death";
	#Otherwise, return idle
	return "idle";
	
#Correct direction for animation
func _get_direction_name(dir: Vector2) -> String:
	if dir == DIR_DOWN:
		return "down";
	if dir == DIR_UP:
		return "up";
	if dir == DIR_LEFT:
		return "left";
	if dir == DIR_RIGHT:
		return "right";
	#Fallback if something weird happens
	return "down";
#Play the correct animation depending on state and facing direction
func _update_animation() -> void:
	if anim == null:
		return;
	var dir_name: String = _get_direction_name(facing_dir);
	var anim_name: String = "";
	anim_name = _get_state_name(_state) + "_" + dir_name;
	#Something went wrong, no anim_name
	if anim_name.is_empty():
		return;
	#No sprite frames, error
	if anim.sprite_frames == null:
		return;
	

	#Only change animation if it's different to avoid restarting
	if anim.animation != anim_name:
		if anim.sprite_frames.has_animation(anim_name):
			anim.play(anim_name);
		else:
			#If specific anim is missing, do idle down
			if anim.sprite_frames.has_animation("idle_down"):
				anim.play("idle_down");
				
#Ensure animation has finished
func _on_anim_finished() -> void:
	if anim == null:
		return;
		
	#Only care about non-looping states
	if _state == State.ATTACK:
		#After attack anim finishes
		_attack_in_progress = false;
		if _target != null and is_instance_valid(_target) and _is_target_in_aggro():
			_set_state(State.CHASE);
		else:
			_set_state(State.IDLE);
	elif _state == State.HURT:
		#Same idea, resume after hurt
		if _target != null and is_instance_valid(_target) and _is_target_in_aggro():
			_set_state(State.CHASE);
		else:
			_set_state(State.IDLE);
	elif _state == State.DEAD:
		pass; #Handled in _die() with a short delay
#endregion
