extends WorldScene;
class_name Forest;

#Tree generation
#Percentage of valud tree cells to populate
const TREE_FILL_PERCENT: float = 0.2;
#Tree types available in the forest
const TREE_HARVEST_IDS: Array[String] = [
	"small_tree",
	"medium_tree",
]

#Ore generation
#Range for how many ore nodes to spawn per day
const ORE_MIN: int = 8;
const ORE_MAX: int = 12;
#Ore types available in the forest
enum OreType { COAL, STONE, IRON };
const ORE_HARVEST_IDS: Array[String] = [
	"medium_coal_node",
	"medium_stone_node",
	"medium_iron_node",
]

#Enemy generation
#Range for how many enemies to spawn per day
const ENEMY_MIN: int = 4;
const ENEMY_MAX: int = 8;
const FOREST_ENEMY_IDS: Array[String] = [
	"slime_green_small",
]

@export var harvestable_scene: PackedScene;
@export var enemy_scene: PackedScene;

@onready var _harvestables_root: Node2D = %HarvestablesRoot;
@onready var _tree_tilemap: TileMapLayer = %HarvestableTrees;
@onready var _ore_tilemap: TileMapLayer = %HarvestableOre;

func _ready() -> void:
	super._ready();
	call_deferred("_try_generate");
	
func _try_generate() -> void:
	if GameState.forest_last_generated_day == GameState.current_day:
		#Already generated today, restore the layout
		_restore_layout();
		return;
	#New day, clear any nodes leftover from previous day and regenerate
	_clear_spawned_harvestables();
	_clear_spawned_enemies();
	#Enemies claim cells first, then trees fill in gaps
	var occupied_cells: Dictionary = {};
	_generate_enemies(occupied_cells);
	_generate_trees(occupied_cells);
	_generate_ore();
	#Save the layout to be reloaded if the player exits and returns
	_save_layout();
	_connect_layout_tracking();
	GameState.forest_last_generated_day = GameState.current_day;
	Analytics.log_event("forest_generated", {
		"day": GameState.current_day,
	})
	
#Remove any leftover instances from the previous day
func _clear_spawned_harvestables() -> void:
	for child in _harvestables_root.get_children():
		if child != null and child is HarvestableNode:
			child.queue_free();
			
#Clear any previously spawned enemies
func _clear_spawned_enemies() -> void:
	if actors == null:
		return;
	for child in actors.get_children():
		#Only remove enemies, never the player
		if child.is_in_group("enemies"):
			child.queue_free();
			
#Generate the enemies in the forest as well
func _generate_enemies(occupied_cells: Dictionary) -> void:
	var cells: Array = _tree_tilemap.get_used_cells();
	if cells.is_empty():
		return;
	#Shuffle so the selection is random each day
	cells.shuffle();
	var count: int = randi_range(ENEMY_MIN, ENEMY_MAX);
	count = min(count, cells.size());
	for i in range(count):
		var cell: Vector2i = cells[i];
		var enemy_id: String = FOREST_ENEMY_IDS[randi() % FOREST_ENEMY_IDS.size()];
		_spawn_enemy(cell,enemy_id);
		#Mark cells as occupied so trees won't spawn here
		occupied_cells[cell] = true;
		
#Generate the trees in the HarvestableTrees TileMapLayer
func _generate_trees(occupied_cells: Dictionary) -> void:
	var cells: Array = _tree_tilemap.get_used_cells();
	if cells.is_empty():
		return;
	#Remove any cell already claimed by an enemy
	var available: Array = cells.filter(func(c): return not occupied_cells.has(c));
	#Shuffle so the selection is random each day
	available.shuffle();
	var count: int = int(ceil(cells.size() * TREE_FILL_PERCENT));
	count = min(count, cells.size());
	for i in range(count):
		var harvest_id: String = TREE_HARVEST_IDS[randi() % TREE_HARVEST_IDS.size()];
		_spawn_harvestable(available[i], _tree_tilemap, harvest_id);
		
#Generate the ore in the HarvestableOre TileMapLayer
func _generate_ore() -> void:
	var cells: Array = _ore_tilemap.get_used_cells();
	if cells.is_empty():
		return;
	cells.shuffle();
	var count: int = randi_range(ORE_MIN, ORE_MAX);
	count = min(count, cells.size());
	for i in range(count):
		var harvest_id: String = ORE_HARVEST_IDS[randi() % ORE_HARVEST_IDS.size()];
		_spawn_harvestable(cells[i], _ore_tilemap, harvest_id);
		
#Actually spawn those selected harvestables
func _spawn_harvestable(cell: Vector2i, tilemap: TileMapLayer, harvest_id: String) -> void:
	var node: HarvestableNode = harvestable_scene.instantiate();
	node.harvest_id = harvest_id;
	#map_to_local gives the centre of the tile in the tilemap's local space
	node.position = tilemap.map_to_local(cell);
	_harvestables_root.add_child(node);
	
#Spawn the enemies
func _spawn_enemy(cell: Vector2i, enemy_id: String) -> void:
	if actors == null:
		push_warning("Forest: No Actors node, cannot spawn enemies.");
		return;
		
	var node: CharacterBody2D = enemy_scene.instantiate();
	node.set("enemy_id", enemy_id);
	#Position relative to Actors, converting from tilemap local space to global
	node.global_position = _tree_tilemap.to_global(_tree_tilemap.map_to_local(cell));
	actors.add_child(node);

#Serialise current spawned state into GameState
func _save_layout() -> void:
	var harvestables: Array = [];
	for child in _harvestables_root.get_children():
		var node = child as HarvestableNode;
		if node == null:
			continue;
		harvestables.append({
			"harvest_id": node.harvest_id,
			"position": node.position,
			"depleted": false,
		});
	var enemies: Array = [];
	for child in actors.get_children():
		if not child.is_in_group("enemies"):
			continue;
		enemies.append({
			"enemy_id": child.get("enemy_id"),
			"global_position": child.global_position,
		});
	GameState.forest_layout = {
		"harvestables": harvestables,
		"enemies": enemies,
	}
#Restore a previously saved layout, skipping depleted resources
func _restore_layout() -> void:
	if GameState.forest_layout.is_empty():
		#No layout saved, fall back to fresh generation
		_clear_spawned_harvestables();
		_clear_spawned_enemies();
		var occupied_cells: Dictionary = {};
		_generate_enemies(occupied_cells);
		_generate_trees(occupied_cells);
		_generate_ore();
		_save_layout();
		return;
	#Otherwise, we're good to reload what was saved
	for entry in GameState.forest_layout.get("harvestables", []):
		if entry.get("depleted", false):
			continue;
		var node: HarvestableNode = harvestable_scene.instantiate();
		node.harvest_id = entry["harvest_id"];
		node.position = entry["position"];
		_harvestables_root.add_child(node);
		node.destroyed.connect(func(_id: String): _on_harvestable_destroyed(node));
	#Reload enemies in proper location if they weren't already killed
	var enemies_data: Array = GameState.forest_layout.get("enemies", []);
	for entry in range(enemies_data.size()):
		var enemy: Dictionary = enemies_data[entry];
		if enemy.get("dead", false):
			continue;
		var node: CharacterBody2D = enemy_scene.instantiate();
		node.set("enemy_id", enemy["enemy_id"]);
		node.global_position = enemy["global_position"];
		actors.add_child(node);
		node.tree_exiting.connect(_on_enemy_killed.bind(entry));
	
#Mark a harvestable as depleted in the save layout
func _on_harvestable_destroyed(node: HarvestableNode) -> void:
	for entry in GameState.forest_layout.get("harvestables", []):
		#Looks for the location of the destroyed node and set it's depleted value to true
		#so it won't respawn
		if entry["position"].is_equal_approx(node.position):
			entry["depleted"] = true;
			return;
			
#Connect tree_exiting signals for freshly generated enemies
#Called after _save_layout() so the layout array indices exist
func _connect_layout_tracking() -> void:
	var enemies_data: Array = GameState.forest_layout.get("enemies", []);
	var index: int = 0;
	for child in actors.get_children():
		if child.is_in_group("enemies"):
			if index < enemies_data.size():
				child.tree_exiting.connect(_on_enemy_killed.bind(index));
			index += 1;
	#Also connect harvestable signals for first-generation visits
	var harvestables_data: Array = GameState.forest_layout.get("harvestables", []);
	var h_index: int = 0;
	for child in _harvestables_root.get_children():
		if child is HarvestableNode:
			if h_index < harvestables_data.size():
				child.destroyed.connect(func(_id: String): _on_harvestable_destroyed(child));
			h_index += 1;
			
#Mark an enemy as dead in the saved layout so it doesn't respawn on entry
func _on_enemy_killed(index: int) -> void:
	#Don't mark enemies when the whole scene is unloading
	if is_queued_for_deletion():
		return;
	var enemies: Array = GameState.forest_layout.get("enemies", []);
	if index >= 0 and index < enemies.size():
		enemies[index]["dead"] = true;
