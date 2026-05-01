# LudoSense Analytics — Godot Plugin

Real-time game analytics for Godot 4. Send gameplay events to the LudoSense platform with one line of code.

> **Note:** This plugin is GDScript-only. A C# SDK is planned and will support both Godot C# and Unity projects.

---

## Installation

1. Copy the `addons/ludosense/` folder into your Godot project's `addons/` directory.
2. Open **Project Settings → Plugins** and enable **LudoSense Analytics**.
3. The plugin registers `LudoSenseAnalytics` as an autoload automatically — no manual setup needed. You can verify it appears under **Project Settings → Autoload**.

---

## Setup

Set your API key and API URL early in your main scene's `_ready()`:

```gdscript
func _ready() -> void:
	LudoSenseAnalytics.api_key = "your-api-key-here"    # from the LudoSense dashboard
	LudoSenseAnalytics.api_url = "http://localhost:8000" # or your production URL
	LudoSenseAnalytics.set_game_version("1.0.0")
```

Get your API key by registering at [ludosense.com](https://ludosense.com) and creating a game.

---

## Recording events

Call `log_event()` from anywhere in your project:

```gdscript
# Minimal — just an event name
LudoSenseAnalytics.log_event("level_started")

# With extra data
LudoSenseAnalytics.log_event("enemy_killed", {
	"enemy_type": "goblin",
	"weapon": "sword",
	"scene": LudoSenseAnalytics.get_scene_path()
})

LudoSenseAnalytics.log_event("quest_completed", {
	"quest_id": "q_intro",
	"time_taken_seconds": 142
})
```

---

## Setting the player ID

The player ID must be unique per player, not per save slot — if you use the
slot number alone, every player who uses slot 1 will be merged together in
the dashboard.

The recommended pattern is to generate a random ID when a new save file is
created, persist it in the save data, and load it back on every subsequent
launch:

```gdscript
# When creating a new save file — generate and store a unique ID:
var player_uid: String = "%s_%06d" % [
	Time.get_datetime_string_from_system(true).replace(":", "-"),
	randi() % 1_000_000
]
save_data["player_uid"] = player_uid

# When loading a save file — pass the stored ID to the plugin:
LudoSenseAnalytics.set_player_id(save_data["player_uid"])
```

This ensures every save file has a stable, unique identity across all sessions.

Calling `set_player_id()` also logs a `player_identified` event automatically,
so the dashboard can link the session to a specific player from that point onward.

---

## Opting out

To respect a player's analytics opt-out preference:

```gdscript
LudoSenseAnalytics.set_enabled(false)
```

All subsequent `log_event()` calls are silent no-ops until you call `set_enabled(true)` again.

---

## How it works

- Events are buffered in memory and flushed to the API every 30 events or when the game closes — whichever comes first.
- Each flush sends individual HTTP POSTs to `/v1/ingest/events`. A per-request `HTTPRequest` node is created for each event and freed on completion, avoiding Godot's `ERR_BUSY` limitation on concurrent requests.
- If a request fails (no network, server down), the event is held in a retry buffer and retried on the next flush. Events are never silently dropped.
- A `session_start` event is sent automatically when the plugin initialises. You do not need to call this yourself.

---

## API reference

| Method | Description |
|---|---|
| `log_event(event_name, properties)` | Record an analytics event. `properties` is an optional dictionary. |
| `set_player_id(id)` | Set the player identity and log a `player_identified` event. |
| `set_game_version(version)` | Override the game version string used in all subsequent events. |
| `set_enabled(enabled)` | Enable or disable event recording (for player opt-out). |
| `get_scene_path()` | Returns the current scene's file path (null-safe convenience helper). |

---

## Requirements

- Godot 4.x
- A LudoSense account and API key
