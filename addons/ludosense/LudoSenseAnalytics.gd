## LudoSenseAnalytics.gd
## Autoload singleton for the LudoSense analytics platform.
##
## INSTALLATION
## ------------
## 1. Copy the addons/ludosense/ folder into your Godot project.
## 2. In Project Settings → Plugins, enable "LudoSense Analytics".
## 3. In Project Settings → Autoload, confirm LudoSenseAnalytics is listed.
##    Godot adds it automatically when you enable the plugin, but it is
##    worth checking the name matches what you call in code.
## 4. Set your API key and URL before any events are sent:
##
##      LudoSenseAnalytics.api_key = "your-api-key-here"
##      LudoSenseAnalytics.api_url = "http://localhost:8000"  # local dev
##
##    The best place to do this is your main scene's _ready() function,
##    or wherever you initialise global state.
##
## USAGE
## -----
## Call log_event() from anywhere in your game — same as before:
##
##   LudoSenseAnalytics.log_event("quest_started", {"quest_id": "q_intro"})
##   LudoSenseAnalytics.log_event("enemy_killed", {"enemy_type": "goblin"})
##
## The plugin batches events and flushes them to the API automatically.
## If a flush fails (e.g. no network), events are held in memory and
## retried on the next flush cycle.
extends Node
# ---------------------------------------------------------------------------
# Configuration — set these before your first log_event() call
# ---------------------------------------------------------------------------

## Your game's API key from the LudoSense dashboard.
## Events sent without a valid key will be rejected with 401.
var api_key: String = ""

## Base URL of the LudoSense API — no trailing slash.
## For local development: "http://localhost:8000"
## For production:        "https://api.ludosenseanalytics.com"  (once deployed in Session 10)
var api_url: String = "https://api.ludosenseanalytics.com"

## Game version string. Override this to match your release version.
## Used in the dashboard for version-by-version comparisons.
## Tip: set this from your SaveSystem or project settings at startup.
var game_version: String = "0.1.0"

## Player identifier. Set this once you know who the player is
## (e.g. after loading a save file or completing account login).
## Until set, all events are attributed to "unknown".
var player_id: String = "unknown"

## How many events to accumulate before automatically flushing to the API.
## Lower values mean more frequent HTTP requests but smaller payloads.
## Higher values mean fewer requests but more data lost if the game crashes.
## 30 is a reasonable default for most games.
const FLUSH_THRESHOLD: int = 30

# ---------------------------------------------------------------------------
# Runtime state — do not set these directly
# ---------------------------------------------------------------------------

## Unique identifier for this play session, generated at startup.
## Format matches the thesis game: "2026-04-02T15-34-31_076414"
var _session_id: String = ""

## In-memory event buffer. Events accumulate here until flushed.
var _buffer: Array = []

## Kill switch. Set to false to stop all event recording instantly,
## for example when the player opts out of analytics.
var _is_enabled: bool = true

## Guards against double-initialisation if _ready() is called twice.
var _is_initialized: bool = false

## We do not keep a single shared HTTPRequest node, because Godot's
## HTTPRequest can only process one request at a time — attempting a second
## while one is in flight returns ERR_BUSY. Instead, we create a fresh node
## per event and free it automatically once the request completes.

## Events that failed to send and are waiting for a retry.
## On every successful flush, we attempt to drain this retry queue first.
var _retry_buffer: Array = []

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_ensure_initialized()

	## Emit the session start event immediately.
	## This is the anchor event that the ETL pipeline uses to open a session
	## row in the silver layer. Without it, the session will have no start
	## timestamp and duration calculations will fail.
	log_event("session_start", {
		"game_version": game_version
	})

func _notification(what: int) -> void:
	## Flush remaining events when the game is closing or this node is freed.
	## This is the same pattern as the thesis Analytics.gd — we hook into
	## Godot's notification system rather than relying on _exit_tree() alone,
	## because NOTIFICATION_WM_CLOSE_REQUEST fires before the scene tree tears
	## down, giving us the best chance of getting events out.
	if what == NOTIFICATION_WM_CLOSE_REQUEST \
	or what == NOTIFICATION_EXIT_TREE \
	or what == NOTIFICATION_PREDELETE:
		_flush_to_api()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Set the player identifier once it is known (e.g. after loading a save).
## Also logs an identification event so the dashboard can link this session
## to a specific player from the point of identification onward.
func set_player_id(new_player_id: String) -> void:
	player_id = new_player_id
	log_event("player_identified", {"player_id": player_id})

## Override the game version — call this early in your main scene's _ready()
## if you manage version strings in code rather than using the default above.
func set_game_version(version: String) -> void:
	game_version = version

## Enable or disable all event recording.
## Useful for honouring a player's opt-out preference.
## When disabled, log_event() is a silent no-op.
func set_enabled(enabled: bool) -> void:
	_is_enabled = enabled

## Convenience helper — returns the current scene's file path.
## Saves callers from repeating the null-safe ternary everywhere:
##   LudoSenseAnalytics.log_event("scene_entered", {
##       "scene": LudoSenseAnalytics.get_scene_path()
##   })
func get_scene_path() -> String:
	var scene = get_tree().current_scene if get_tree() else null
	return scene.scene_file_path if scene else ""

## Record a single analytics event.
##
## event_name  — a short, stable string identifying what happened.
##               Use underscores, keep it lowercase. Avoid changing names
##               mid-development — the dashboard groups by this string, so
##               a rename splits historical data.
##               Examples: "enemy_killed", "quest_completed", "chest_opened"
##
## properties  — any extra data relevant to this event. Free-form dict.
##               Examples: {"enemy_type": "goblin"}, {"quest_id": "q_intro"}
##
## This is the only function most games need to call.
func log_event(event_name: String, properties: Dictionary = {}) -> void:
	if not _is_enabled:
		return

	## Build the core event payload.
	## These fields are required by the LudoSense ingest schema (EventIngestRequest).
	## The api_key is not included here — it is added at flush time so that
	## it is never stored inside individual event dicts in the buffer.
	var event: Dictionary = {
		"event_name":   event_name,
		"session_id":   _session_id,
		"player_id":    player_id,
		"game_version": game_version,
		## ts_iso is optional in the schema but we always send it.
		## This lets the backend use client-side timestamps rather than
		## server arrival time, which is more accurate for session duration.
		"ts_iso":       Time.get_datetime_string_from_system(true),
		## payload is the free-form dict the schema expects.
		## We pass the caller's properties dict through as-is.
		"payload":      properties,
	}

	_buffer.append(event)

	## Auto-flush once the buffer reaches the threshold.
	if _buffer.size() >= FLUSH_THRESHOLD:
		_flush_to_api()

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _ensure_initialized() -> void:
	if _is_initialized:
		return

	## Generate a session ID in the same format as the thesis game.
	## Example output: "2026-04-13T10-22-05_483921"
	## We use a timestamp prefix so session IDs sort chronologically,
	## and a random suffix to avoid collisions if the game is launched
	## twice in the same second.
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	var ts_str := "%04d-%02d-%02dT%02d-%02d-%02d" % [
		dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second
	]
	var rand_part := randi() % 1_000_000
	_session_id = "%s_%06d" % [ts_str, rand_part]

	_is_initialized = true

func _flush_to_api() -> void:
	## Nothing to do if the buffer is empty and the retry queue is empty.
	if _buffer.is_empty() and _retry_buffer.is_empty():
		return

	if not _is_enabled:
		_buffer.clear()
		return

	if api_key.is_empty():
		push_warning("[LudoSense] api_key is not set. Events will not be sent. " +
			"Set LudoSenseAnalytics.api_key before calling log_event().")
		return

	## Drain the retry buffer first — older failed events take priority.
	## Then append the current buffer so everything is sent in order.
	var events_to_send: Array = _retry_buffer + _buffer
	_retry_buffer.clear()
	_buffer.clear()

	## Send each event as a separate HTTP POST.
	## The LudoSense ingest endpoint accepts one event per request
	## (matching the schema in ludosense/schemas/event.py).
	## For MVP this is fine — batching can be added in a future version.
	for event in events_to_send:
		_send_event(event)

func _send_event(event: Dictionary) -> void:
	## Build the full request body.
	## We add api_key here rather than storing it in each event dict —
	## the key is a credential, not event data, and keeping it separate
	## means we never accidentally log it alongside event content.
	var body: Dictionary = {
		"api_key":      api_key,
		"player_id":    event["player_id"],
		"session_id":   event["session_id"],
		"event_name":   event["event_name"],
		"game_version": event["game_version"],
		"ts_iso":       event["ts_iso"],
		"payload":      event["payload"],
	}

	var json_body: String = JSON.stringify(body)

	var headers: PackedStringArray = [
		"Content-Type: application/json"
	]

	var endpoint: String = api_url + "/v1/ingest/events"

	## Create a fresh HTTPRequest node for each event.
	## A single shared node can only handle one request at a time — if a
	## second request is fired before the first completes, Godot returns
	## ERR_BUSY and drops it. One node per request avoids this entirely.
	## We connect a lambda that frees the node after the request completes,
	## so we don't accumulate orphaned nodes over a long session.
	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)

	## Capture the event dict in the lambda so we can retry it on failure.
	http.request_completed.connect(
		func(result: int, response_code: int, _headers: PackedStringArray, body_bytes: PackedByteArray) -> void:
			_on_request_completed(result, response_code, _headers, body_bytes, event)
			http.queue_free()
	)

	var err: int = http.request(
		endpoint,
		headers,
		HTTPClient.METHOD_POST,
		json_body
	)

	if err != OK:
		## The request couldn't even be queued (e.g. invalid URL, no network).
		## Push the event onto the retry buffer so it is attempted next flush.
		## Note: the format string is one expression here to avoid GDScript's
		## % operator only binding to the rightmost string literal.
		push_warning("[LudoSense] Failed to queue HTTP request (error %d). Event will be retried next flush." % err)
		_retry_buffer.append(event)
		http.queue_free()

func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	event: Dictionary
) -> void:
	## result is Godot's transport-level result code (not HTTP status).
	## RESULT_SUCCESS (0) means the request completed at the network level —
	## it does not mean the server accepted the event.
	if result != HTTPRequest.RESULT_SUCCESS:
		push_warning("[LudoSense] HTTP request failed at transport level (result code %d). Event will be retried next flush." % result)
		## Put the event back in the retry buffer — it will be resent on the next flush.
		_retry_buffer.append(event)
		return

	## 202 Accepted is the expected success response from /v1/ingest/events.
	if response_code == 202:
		## Optionally parse the response to check the over_quota flag.
		## If over_quota is true, the event was stored but will not appear
		## in dashboard analytics — the developer needs to upgrade their plan.
		var response_text: String = body.get_string_from_utf8()
		var parsed = JSON.parse_string(response_text)
		if parsed and parsed.get("over_quota", false):
			push_warning("[LudoSense] Event accepted but player is over quota. " +
				"Upgrade your plan at ludosense.com to capture all players.")
		return

	## Any other status code is unexpected. Log it so the developer can debug.
	push_warning("[LudoSense] Unexpected response from API: HTTP %d. " +
		"Body: %s" % [response_code, body.get_string_from_utf8()])
