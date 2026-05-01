extends Node
#region Config
#Where to store logs (inside user data folder)
const LOG_DIR: String = "user://analytics"

#How many events to buffer before writing to disk
const BUFFER_LIMIT: int = 30;

#Can set this from code or leave as default
var game_version: String = "0.1.0"

#Optional: set when player profile is known
var player_id: String = "unknown"
#endregion

#region Runtime state stuffs
var _session_id: String = ""
var _log_file_path: String = ""
var _buffer: Array = []
var _is_enabled: bool = true  #easy kill switch if needed
var _is_initialized: bool = false;

func _ready() -> void:
	#Make sure logging is ready even if someone calls log_event before _ready
	_ensure_initialized();
	
	
	#Write a "session started" event right away
	log_event("analytics_session_started", {
		"session_id": _session_id,
		"game_version": game_version
	});
	print("Analytics log path: ", _log_file_path);
#endregion
#region Public helpers
func set_player_id(new_player_id: String) -> void:
	player_id = new_player_id
	#Log that we associated a player with this session
	log_event("analytics_player_identified", {
		"player_id": player_id
	})
#Call to set a specific game version--probably in SaveSystem
func set_game_version(version: String) -> void:
	game_version = version

func set_enabled(enabled: bool) -> void:
	_is_enabled = enabled
	
#Public helper so callers don't repeat the ternary everywhere
func get_scene_path() -> String:
	var scene = get_tree().current_scene if get_tree() else null
	return scene.scene_file_path if scene else ""
	
func log_event(event_name: String, properties: Dictionary = {}) -> void:
	#This is the main function you’ll call from the rest of your game:
	#Analytics.log_event("quest_started", {"quest_id": "q_intro"})
	if not _is_enabled:
		return

	#Build the full event payload
	var event: Dictionary = {
		"event_name": event_name,
		#Unix timestamp in seconds 
		"ts_unix": Time.get_unix_time_from_system(),
		#ISO string as well so it's also readable by humans
		"ts_iso": Time.get_datetime_string_from_system(true),
		"session_id": _session_id,
		"player_id": player_id,
		"game_version": game_version
	}
	
	#Merge custom properties
	for key in properties.keys():
		event[key] = properties[key]
		
	_buffer.append(event)
	
	#Flush if we hit the buffer limit
	if _buffer.size() >= BUFFER_LIMIT:
		_flush_to_disk()
#endregion

#region Internal helpers
func _ensure_initialized() -> void:
	if _is_initialized:
		return;
		
	#Generate a fairly unique session id
	#Example: "2026-02-23T19-45-12_123456"
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	var ts_str := "%04d-%02d-%02dT%02d-%02d-%02d" % [
		dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second
	]
	var rand_part := randi() % 1_000_000
	_session_id = "%s_%06d" % [ts_str, rand_part]

	#Ensure directory exists
	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("[Analytics] Could not open user:// directory.")
		_is_enabled = false
		return

	if not dir.dir_exists("analytics"):
		var err = dir.make_dir("analytics")
		if err != OK:
			push_error("[Analytics] Failed to create analytics directory: %s" % str(err))
			_is_enabled = false
			return

	_log_file_path = "%s/session_%s.jsonl" % [LOG_DIR, _session_id]
	_is_initialized = true;
	
func _flush_to_disk() -> void:
	if _buffer.is_empty():
		return
	if not _is_enabled:
		_buffer.clear()
		return
		
	var file: FileAccess = null;
	#If the file already exists, open for read/write and seek to the end
	if FileAccess.file_exists(_log_file_path):
		file = FileAccess.open(_log_file_path, FileAccess.READ_WRITE)
		if file == null:
			var err = FileAccess.get_open_error()
			push_error("[Analytics] Failed to open log file '%s': %s" % [_log_file_path, str(err)])
			return;
		file.seek_end();
	else:
		#First time: create the file with thw WRITE mode
		file = FileAccess.open(_log_file_path, FileAccess.WRITE);
		if file == null:
			var err_new = FileAccess.get_open_error();
			push_error("[Analytics] Failed to create log file '%s':  %s"
				%[_log_file_path, str(err_new)]);
			return;
			#No need to seek_end, it's a fresh file
	
	for event in _buffer:
		var line := JSON.stringify(event)
		file.store_line(line)
		
	file.flush()
	file.close()
	
	_buffer.clear()

func _notification(what: int) -> void:
	#Try to flush pending events when the app closes or node is about to be freed
	if what == NOTIFICATION_WM_CLOSE_REQUEST \
	or what == NOTIFICATION_EXIT_TREE \
	or what == NOTIFICATION_PREDELETE:
		_flush_to_disk()
#endregion
