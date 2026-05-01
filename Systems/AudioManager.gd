extends Node
#Simple dictionaries of IDs -> AudioStreams
var music_library: Dictionary = {
	"PlayerHouse": [
		preload("res://Sounds/Music/musHouse1.wav"),
		preload("res://Sounds/Music/musHouse2.wav"),
	],
	"Town": [
		preload("res://Sounds/Music/musTown1.wav"),
		preload("res://Sounds/Music/musTown2.wav"),
	],
	"Forest": [
		preload("res://Sounds/Music/musForest1.wav"),
		preload("res://Sounds/Music/musForest2.wav"),
	],
	"TitleScreen": [
		preload("res://Sounds/Music/musTitle.wav"),
	],
	"EndOfDaySummary": [
		preload("res://Sounds/Music/musEOD.wav"),
	],
};

var sfx_library: Dictionary = {
	"swing_sword": preload("res://Sounds/SFX/sndSwordSwing.wav"),
	"sword_hit": preload("res://Sounds/SFX/sndSwordHit.wav"),
	"open_menu": preload("res://Sounds/SFX/sndMenuOpen.wav"),
	"close_menu": preload("res://Sounds/SFX/sndMenuClose.wav"),
	"button_click": preload("res://Sounds/SFX/sndButtonClick.wav"),
	"door_open": preload("res://Sounds/SFX/sndDoorOpen.wav"),
	"door_close": preload("res://Sounds/SFX/sndDoorClose.wav"),
	"dialogue_tick": preload("res://Sounds/SFX/sndTypewriter.wav"),
	"chest_open": preload("res://Sounds/SFX/sndChestOpen.wav"),
	"chest_close": preload("res://Sounds/SFX/sndChestClose.wav"),
};

#Seconds of silence between tracks in the same zone
var silence_gap_sec: float = 60.0;
#Current active zone key
var _current_zone: String = "";
#Last played stream so we avoid immediate repeats
var _last_played_stream: AudioStream = null;
#Timer node for teh gap between tracks
var _silence_timer: Timer = null;

var _music_player: AudioStreamPlayer = null;
var _sfx_players: Array[AudioStreamPlayer] = []; #Pool of data so multiple sounds can play

#How many SFX players to keep in the pool
const MAX_SFX_PLAYERS: int = 8;

func _ready() -> void:
	#Music setup
	_music_player = AudioStreamPlayer.new();
	_music_player.bus = "Music";
	add_child(_music_player);
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS;
	
	#SFX pool setup
	for i in range(MAX_SFX_PLAYERS):
		var p = AudioStreamPlayer.new();
		p.bus = "SFX";
		add_child(p);
		_sfx_players.append(p);
	
	#Listen to Settings changes
	Settings.settings_changed.connect(_on_settings_changed);
	
	#Apply current values on startup
	_apply_settings();
	#Silence gap timer for music zones
	_silence_timer = Timer.new();
	_silence_timer.one_shot = true;
	_silence_timer.timeout.connect(_on_silence_timeout);
	add_child(_silence_timer);
	_silence_timer.process_mode = Node.PROCESS_MODE_ALWAYS;
	#Wire up music zone system
	_music_player.finished.connect(_on_music_finished);
	Game.scene_changed.connect(_on_scene_changed_music);
	
#region Music stuffs
#Manual play by ID (for one-off use like cutscenes)
func play_music(id: String) -> void:
	var stream: AudioStream = music_library.get(id, null);
	if stream == null:
		push_warning("Music id '%s' not found" % id);
		return;
	#Override the zone system so it doesn't restart after this track
	_current_zone = "";
	_silence_timer.stop();
	_music_player.stream = stream;
	_music_player.play();
	
func stop_music() -> void:
	_music_player.stop();
	_silence_timer.stop();
	_current_zone = "";
	
#Zone system: reacts to scene changes
func _on_scene_changed_music(scene_path: String) -> void:
	var zone: String = _resolve_zone(scene_path);
	#Same zone (like reentering same area) keep playing
	if zone == _current_zone:
		return;
	#New zone--stop all music and start fresh
	_current_zone = zone;
	_silence_timer.stop();
	_music_player.stop();
	if zone.is_empty():
		return;
	_play_random_from_zone(zone);
	
func _resolve_zone(scene_path: String) -> String:
	#Resolve UID paths to real file paths
	if scene_path.begins_with("uid://"):
		scene_path = ResourceUID.get_id_path(ResourceUID.text_to_id(scene_path));
	for key in music_library.keys():
		if scene_path.contains(key):
			return key;
	return "";
	
func _play_random_from_zone(zone: String) -> void:
	var pool: Array = music_library.get(zone, []);
	if pool.is_empty():
		return;
	var pick: AudioStream = _pick_random_track(pool);
	_last_played_stream = pick;
	_music_player.stream = pick;
	_music_player.play();
	
func _pick_random_track(pool: Array) -> AudioStream:
	#Single-track pool so no choice to make
	if pool.size() == 1:
		return pool[0];
	#Filter out the last played track to avoid immediate repeats
	var candidates: Array = pool.filter(func(s): return s != _last_played_stream);
	if candidates.is_empty():
		candidates = pool;
	return candidates[randi() % candidates.size()];
	
#Track ended naturally start the silence gap timer
func _on_music_finished() -> void:
	if _current_zone.is_empty():
		return;
	_silence_timer.start(silence_gap_sec);
	
#Silence gap elapsed, play next track
func _on_silence_timeout() -> void:
	if _current_zone.is_empty():
		return;
	_play_random_from_zone(_current_zone);
#endregion
#region SFX stuffs
#Public getter that grabs from the Dictionary up top
func play_sfx(id: String) -> void:
	var stream: AudioStream = sfx_library.get(id,null);
	if stream == null:
		push_warning("SFX id '%s' is not found" % id);
		return;
	play_sfx_stream(stream);
	
#Public getter if the sound is already declared elsewhere
func play_sfx_stream(stream: AudioStream) -> void:
	if stream == null:
		return;
	var audio_player = _get_available_sfx_player();
	if audio_player == null:
		#All players are busy, choose one or bail out
		audio_player = _sfx_players[0];
		
	audio_player.stop();
	audio_player.stream = stream;
	audio_player.play();
	
func _get_available_sfx_player() -> AudioStreamPlayer:
	#Returns and audio player that is not currently playing, or null if they are all busy
	for p in _sfx_players:
		if not p.playing:
			return p;
	return null;
#endregion
#Apply the settings
func _apply_settings() -> void:
	#Pull volume levels from the Settings autoload
	var master_vol_db: float = Settings.get_volume_db("master");
	var music_vol_db: float = Settings.get_volume_db("music");
	var sfx_vol_db: float = Settings.get_volume_db("sfx");
	
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), master_vol_db);
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), music_vol_db);
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), sfx_vol_db);

#Redo setting changes
func _on_settings_changed() -> void:
	_apply_settings();
