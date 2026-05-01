extends Node
#Serialises/deserialises game state to disk
#Uses FileAccess.store_var/get_var (Godot built-in binary variant serialisation)

#Save slots will be:
#user://save_0.dat
#user://save_1.dat etc.
const SAVE_PATH_TEMPLATE := "user://save_%d.dat";
#Optional separate settings file
const SETTINGS_PATH := "user://settings.dat";
const SAVE_VERSION: int = 1;
#How many slots the game supports
const MAX_SAVE_SLOTS: int = 3;

#region Public helpers
#Saves the game to a save slot
func save_to_slot(slot: int) -> bool:
	#Safety check
	if slot < 0:
		push_warning("SaveSystem: invalid slot %d" % slot);
		Analytics.log_event("save_failed", {
			"slot": slot,
			"reason": "invalid_slot",
		})
		return false;
		
	var path := SAVE_PATH_TEMPLATE % slot;
	var file := FileAccess.open(path, FileAccess.WRITE);
	if file == null:
		push_error("Failed to open save file for writing");
		Analytics.log_event("save_failed", {
			"slot": slot,
			"reason": "open_write_failed",
			"path": path
		})
		return false;
	#Gather data from all the systems
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"game_state": GameState.to_dict(),
		"inventory": InventorySystem.to_dict(),
		"quests": QuestSystem.to_dict(),
		"world_flags": WorldFlags.to_dict(),
		"settings": Settings.to_dict(), #optional, also saved separately
		"day_night": DayNightSystem.to_dict(),
		"level": LevelSystem.to_dict(),
		"crafting": CraftingSystem.to_dict(),
		"encyclopedia": EncyclopediaSystem.to_dict(),
		"decoration": DecorationSystem.to_dict(),
		"chest_storage": ChestStorageSystem.to_dict(),
	};
	#store_var serializes the dictionary automatically
	file.store_var(data);

	file.close();
	#Analytics: Log save file successful
	Analytics.log_event("save_successful", {
		"slot": slot,
		"path": path,
		"version": SAVE_VERSION,
	})
	return true;

#Loads the game from a save slot
func load_from_slot(slot: int) -> bool:
	#Safety check
	if slot < 0:
		push_warning("SaveSystem: invalid slot %d" % slot);
		Analytics.log_event("load_failed", {
			"slot": slot,
			"reason": "invalid_slot",
		})
		return false;
	#Returns true if successful, false if not
	var path := SAVE_PATH_TEMPLATE % slot;
	if not FileAccess.file_exists(path):
		Analytics.log_event("load_failed", {
			"slot": slot,
			"reason": "file_not_found",
			"path": path,
		})
		return false;
	var file := FileAccess.open(path, FileAccess.READ);
	if file == null:
		push_error("Failed to open save file for reading");
		Analytics.log_event("load_failed", {
			"slot": slot,
			"reason": "open_read_failed",
			"path": path,
		})
		return false;
	
	var raw = file.get_var();
	file.close();
	
	#Validate file contents
	if typeof(raw) != TYPE_DICTIONARY:
		push_warning("SaveSystem: Save file data was not a Dictionary: %s" % path);
		Analytics.log_event("load_failed", {
			"slot": slot,
			"reason": "bad_data_type",
			"path": path
		})
		return false;
	
	#Deserialize the stored data
	var data: Dictionary = raw;
	
	#Version handling for later updates
	var version: int = int(data.get("version", 0));
	if version <= 0:
		push_warning("SaveSystem: Save file has missing/invalid version: %s" % path);
		Analytics.log_event("load_failed", {
			"slot": slot,
			"reason": "missing_or_invalid_version",
			"path": path,
		})
		return false;
	
	#Migrate stuffs if different version
	if version != SAVE_VERSION:
		data = _migrate_save_data(data, version);
		if data.is_empty():
			push_warning("SaveSystem: Failed to migrate save data file for: %s" % path);
			Analytics.log_event("load_failed", {
				"slot": slot,
				"reason": "migration_failed",
				"from_version": version,
				"path": path,
			})
			return false;
	
	#Branch later what loads depending on version, don't need for now
	#Restore the data into each system
	#Each system is responsible for interpreting its own data
	GameState.from_dict(data.get("game_state", {}));
	InventorySystem.from_dict(data.get("inventory", {}));
	QuestSystem.from_dict(data.get("quests", {}));
	WorldFlags.from_dict(data.get("world_flags", {}));
	DayNightSystem.from_dict(data.get("day_night", {}));
	LevelSystem.from_dict(data.get("level", {}));
	CraftingSystem.from_dict(data.get("crafting", {}));
	EncyclopediaSystem.from_dict(data.get("encyclopedia", {}));
	DecorationSystem.from_dict(data.get("decoration", {}));
	ChestStorageSystem.from_dict(data.get("chest_storage", {}));
	#GameState.from_dict() has already restored player_uid from disk.
	#Pass it to the analytics plugin so all events in this session are
	#attributed to the correct player. The "" fallback handles saves that
	#predate this field — those sessions will appear as "unknown".
	if GameState.player_uid != "":
		Analytics.set_player_id(GameState.player_uid);
	#All safety checks passed, load game and log analytics
	Analytics.log_event("load_successful", {
		"slot": slot,
		"path": path,
		"version": version,
	})
	return true;
	
#Get the proper save path
func get_save_path(slot: int) -> String:
	return SAVE_PATH_TEMPLATE % slot;
	
#Public check if there is a save in that slot
func has_save_in_slot(slot: int) -> bool:
	if slot < 0 or slot >= MAX_SAVE_SLOTS:
		return false;
		
	#Safety checks passed
	var path = get_save_path(slot);
	return FileAccess.file_exists(path);
	
#Check if any saves exist
func has_any_saves() -> bool:
	for i in range(MAX_SAVE_SLOTS):
		if has_save_in_slot(i):
			return true;
	return false;
	
#Get the most recent save game
func get_latest_save_slot() -> int:
	var best_slot: int = -1;
	var best_time: int = -1;
	
	for i in range(MAX_SAVE_SLOTS):
		var path = get_save_path(i);
		if FileAccess.file_exists(path):
			var t = FileAccess.get_modified_time(path);
			if t > best_time:
				best_time = t;
				best_slot = i;
				
	return best_slot;
	
func _migrate_save_data(data: Dictionary, from_version: int) -> Dictionary:
	#For now, we only support exact version matches
	#Add migration steps later when it will actually matter
	# Example:
	# if from_version == 1:
	#     ... transform into version 2 dict ...
	#     data["version"] = 2
	#     from_version = 2
	#
	# if after steps from_version != SAVE_VERSION:
	#     return {}
	#
	# return data
	if from_version == SAVE_VERSION:
		return data;
	#No migrations implemeted yet
	return {};
	
func get_slot_metadata(slot: int) -> Dictionary:
	if slot < 0 or slot >= MAX_SAVE_SLOTS:
		return {};
	var path = get_save_path(slot);
	if not FileAccess.file_exists(path):
		return {};
	var file = FileAccess.open(path, FileAccess.READ);
	if file == null:
		return {};
	
	var raw = file.get_var();
	file.close();
	
	if typeof(raw) != TYPE_DICTIONARY:
		return {};
		
	var data: Dictionary = raw;
	var version: int = int(data.get("version", 0));
	if version <= 0:
		return {};
		
	#Future-proof when adding other versions later
	if version != SAVE_VERSION:
		data = _migrate_save_data(data, version);
		if data.is_empty():
			return {};
		
	#Safety checks passed
	var game_state: Dictionary = data.get("game_state", {});	
	var player_name: String = game_state.get("player_name", "");
	var scene_path: String = game_state.get("current_scene_path", "");
	var location_name: String = game_state.get("current_location_name", "");
	var playtime_sec: float = float(game_state.get("total_play_time_sec", 0.0));
	var modified_time: int = FileAccess.get_modified_time(path);
	
	return {
		"slot": slot,
		"player_name": player_name,
		"scene_path": scene_path,
		"location_name": location_name,
		"playtime_sec": playtime_sec,
		"modified_time": modified_time,
		"version": version,
	}
#endregion
#region Settings-only helpers
#Saves settings without touching game progress
#Useful for title screens or options menus
func save_settings_only() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE);
	if file == null:
		push_error("Failed to open settings file for writing");
		return;
	file.store_var(Settings.to_dict());
	file.close();
	
#Loads settings without loading a save slot
#Safe to call at game startup
#Good for sound and things in main menus
func load_settings_only() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return;
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ);
	if file == null:
		push_error("Failed to open settings file for reading");
		return;
	
	var raw = file.get_var();
	file.close();
	if typeof(raw) != TYPE_DICTIONARY:
		push_warning("SaveSystem: Settings file data was not a Dictionary");
		return;
	
	Settings.from_dict(raw);
#endregion
