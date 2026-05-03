# The Undoing of Ashvale

A Godot 4 RPG vertical slice built as part of an MSc dissertation exploring ADHD-informed accessibility design through autoethnographic methodology. The project demonstrates how signal-first, data-driven architecture can reduce both player cognitive load and developer friction when building accessible games.

Built entirely by a single developer using GDScript.

---

## Project Overview

The Undoing of Ashvale is a top-down 2D action RPG in which the player returns to their hometown to find its magical core shattered. Through five quests spanning approximately 20 minutes of gameplay, the player gathers resources, repairs buildings, crafts tools, and interacts with three NPCs to begin restoring the town. The vertical slice serves as a proof of concept for ADHD-informed design principles applied at the architectural level, not retrofitted as surface-level options.

### Key Features

- Five complete quests with data-driven progression (no hardcoded quest logic)
- Dialogue system with three-layer separation (system, database, UI) and a full dialogue log for attention lapse recovery
- Unified XP pool across quests, combat, and harvesting — every activity is progress
- Combined inventory checking across player inventory and chest storage, reducing working memory burden
- Crafting system with multiple unlock sources (level-up, shop, enemy drops, blueprints)
- Town building with shader-driven upgrade cinematics
- Action-driven day/night cycle (time advances through player actions, not real-time)
- Decoration mode with free camera placement and session rollback
- Full accessibility suite: text size presets, calm visual mode, camera shake toggle, guided mode with quest arrow, typewriter speed control
- Settings persistence independent of save slots — configured once, remembered forever
- Encyclopedia that passively tracks discoveries, harvests, kills, and all dialogue
- Analytics pipeline with buffered JSONL writes for playtesting data
- Localisation pipeline via CSV and `tr()` pattern

---

## Architecture

### Design Principles

The codebase is built on four architectural principles applied consistently across every system:

- **Signal-first communication:** Systems communicate through signals by default. Direct calls are used sparingly and only where signal indirection would add complexity without benefit (e.g., entity scripts calling `LevelSystem.add_xp()`).
- **Data-driven resources:** All game content (items, quests, dialogue, enemies, harvestables, NPCs, recipes) is authored as Godot `.tres` resource files in the Inspector. No content requires code changes to add.
- **Inspector-first scene design:** UI nodes are built in the scene editor. Scripts set textures and text at runtime but never create UI structure programmatically.
- **Uniform serialisation:** Every stateful system implements `to_dict()` and `from_dict()` with per-field defaults, enabling forward-compatible save files and a two-line addition to the save pipeline for any new system.

### Autoload Layers

Autoloads are organised into five layers:

| Layer | Autoloads | Responsibility |
|---|---|---|
| **Orchestration** | `Game` | Scene transitions, input lock stack, player lifecycle, game-level flow |
| **Systems** | `QuestSystem`, `InventorySystem`, `LevelSystem`, `CraftingSystem`, `DialogueSystem`, `DayNightSystem`, `ChestStorageSystem`, `DecorationSystem`, `EncyclopediaSystem`, `InteractionSystem`, `WorldFlags`, `WorldDrops` | Domain-specific state and logic, each with a clean public API |
| **UI** | `UIRouter`, `GlobalTooltip` | All screen/overlay instantiation and modal stack management |
| **Content** | `ItemDatabase`, `QuestDatabase`, `DialogueDatabase`, `EnemyDatabase`, `HarvestableDatabase`, `NPCDatabase`, `RecipeDatabase`, `UIStringsDatabase` | Runtime content indexing from preloaded registries |
| **Data** | `GameState`, `Settings` | Runtime state for serialisation and player preferences |
| **Effects** | `VisualFX`, `AudioManager`, `Analytics` | Visual feedback, audio, and telemetry |

### Content Pipeline

```
Author .tres in Inspector
        │
        ▼
Run BuildResourceRegistries.gd (Editor → File → Run)
        │
        ▼
Generated PreloadRegistry files (e.g., ItemPreloadRegistry.gd)
contain a typed ALL array with preload() calls
        │
        ▼
Database autoloads iterate ALL at startup,
index by ID into dictionaries
        │
        ▼
Any system queries content by name:
ItemDatabase.get_display_name("wood")
```

Adding new content (e.g., a new harvestable) requires creating a single `.tres` file, setting its exported fields in the Inspector, and re-running the registry builder. No code changes needed.

**To regenerate registries** after adding or removing any `.tres` file:

> Open `EditorTools/BuildResourceRegistries.gd` in the Godot editor and run via **File → Run**.

### Save/Load Architecture

Every stateful autoload implements `to_dict()` and `from_dict()`. SaveSystem orchestrates the full pipeline:

- **Save:** Calls `to_dict()` on each system, collects into a single dictionary, writes to disk via Godot's binary variant serialisation.
- **Load:** Reads dictionary from disk, passes each subsection to the owning system's `from_dict()`.
- **Settings:** Persisted separately in `settings.dat`, loaded before the first frame renders, independent of save slots.
- **Migration:** `SAVE_VERSION` is stamped into every save file. `_migrate_save_data()` is scaffolded for future version chains.

---

## File Structure

```
Autoloads/                           # System autoload scripts
├── Analytics.gd
├── AudioManager.gd
├── ChestStorageSystem.gd
├── CraftingSystem.gd
├── DayNightSystem.gd
├── DecorationSystem.gd
├── DialogueSystem.gd
├── EncyclopediaSystem.gd
├── Game.gd
├── GameState.gd
├── InventorySystem.gd
├── LevelSystem.gd
├── QuestSystem.gd
├── SaveSystem.gd
├── Settings.gd
├── VisualFX.gd
├── WorldDrops.gd
└── WorldFlags.gd

DataFiles/
├── Generated/                       # Auto-generated preload registries (do not edit)
│   ├── ItemPreloadRegistry.gd
│   ├── HarvestablePreloadRegistry.gd
│   ├── EnemyPreloadRegistry.gd
│   ├── DialoguePreloadRegistry.gd
│   ├── QuestPreloadRegistry.gd
│   ├── NPCPreloadRegistry.gd
│   └── RecipePreloadRegistry.gd
├── LocalisationCSVs/
│   ├── UIStringsText.csv            # Source for UIDatabaseStrings
│   └── *.csv                        # Content-specific localisation tables
└── TranslationFiles/                # Compiled .translation binaries

Entities/
├── Items/
│   ├── Resources/                   # ItemDataResource .tres files
│   └── Scripts/
│       └── ItemDatabase.gd
├── Harvestables/
│   ├── Resources/                   # HarvestableDataResource .tres files
│   └── Scripts/
│       └── HarvestableDatabase.gd
├── Enemies/
│   ├── Resources/                   # EnemyDataResource .tres files
│   └── Scripts/
│       ├── EnemyDatabase.gd
│       └── EnemySystems.gd
├── NPCs/
│   └── Resources/                   # NPCData .tres files
└── Player/
    └── Scripts/
        ├── Player.gd
        └── PlayerStats.gd

UI/
├── Resources/
│   ├── Dialogue/                    # DialogueResource .tres files
│   ├── Quests/                      # QuestDataResource .tres files
│   └── Crafting/                    # RecipeDataResource .tres files
└── Scripts/
    ├── UIRouter.gd
    ├── DialogueBox.gd
    ├── Quests/
    │   ├── QuestDatabase.gd
    │   └── QuestStepResource.gd
    └── Components/                  # Reusable UI components

EditorTools/
└── BuildResourceRegistries.gd       # Registry generator (@tool script)

World/
└── Scripts/
    ├── WorldScene.gd                # Base class for all world scenes
    ├── BuildingRoot.gd
    ├── SpawnPoint.gd
    └── TransitionArea.gd
```

---

## System Summaries

### Game.gd — Orchestration
Scene lifecycle manager, input router, and player ownership. Manages a 15-step async scene transition flow with input locking, fade transitions, player reparenting, world readiness polling, and progressive reveal. The input lock stack (`push_input_lock` / `pop_input_lock` with named sources) allows multiple systems to lock input simultaneously without conflicts.

### QuestSystem.gd — Quest Progression
Thin state machine (not_started → active → completed) driven by `notify_event()`. Any gameplay system calls `notify_event("event_type", {payload})`, and QuestDatabase finds matching steps. Auto-accepts quests on first step match, catches up inventory on accept, and checks combined player + chest inventory for delivery steps. Adding a new quest requires zero code changes.

### DialogueSystem.gd — Dialogue
Three-layer separation: DialogueSystem (state/logic), DialogueDatabase (content/scoring), DialogueBox (UI). Six signals, zero UI references. DialogueDatabase scores all dialogues for an NPC against current quest state and returns the best match. Two-stage advance input (first press completes typewriter, second advances) prevents accidental skips. All shown lines are logged to EncyclopediaSystem for attention lapse recovery.

### InventorySystem.gd — Inventory
Dual-layer model: `_items` dictionary (item_id → count) for quantities, `_layout` array for visual grid arrangement. Expandable rows unlocked via LevelSystem milestones. `first_time_item_acquired` signal drives three features (item-get cinematic, popup, encyclopedia discovery) through one-liner connections.

### ChestStorageSystem.gd — Combined Inventory
Three public helpers (`get_combined_amount`, `has_combined`, `try_remove_combined`) enable crafting and quest systems to check both player inventory and chest storage transparently. Draws from player inventory first, then chest storage. Emerged directly from autoethnographic playtesting.

### CraftingSystem.gd — Crafting
Recipe unlock sources declared on data resources (DEFAULT, LEVEL_UP, SHOP, ENEMY_DROP, BLUEPRINT). First-craft XP tracking rewards exploration without enabling grinding. Pin system provides an externalised working memory aid on the HUD.

### LevelSystem.gd — Progression
Unified XP pool fed by quests, combat, and harvesting. Computed XP table from two constants (`BASE_XP`, `RAMP_FACTOR`). `_on_level_up` raises stats, heals player, expands inventory at milestones, and emits `leveled_up` — which triggers recipe unlocks, UI banner, and stat display refresh across five systems with zero coupling.

### DayNightSystem.gd — Day/Night Cycle
Action-driven time: `advance_time(ticks)` is called by harvesting and crafting, not by a real-time clock. Players are never punished for pausing to think. End-of-day summary tracks items gained, gold earned, and quests completed. Sleeping heals to full and autosaves — a natural session boundary.

### EncyclopediaSystem.gd — Encyclopedia
Passive discovery system. Hooks into existing signals (first item acquired, recipe unlocked, dialogue line shown) and direct calls from harvestable/enemy death. Six categories rendered by a single generic `EncyclopediaGridPanel` driven by config dictionaries. Dialogue log records every line shown to the player for attention lapse recovery.

### DecorationSystem.gd — Town Building
Data/UI separation: the autoload manages unlock state, furniture inventory, and placement registry. DecorationModeUI handles camera, ghost placement, collision validation, and session rollback. Crafted furniture is silently routed from CraftingSystem via signal interception.

### SaveSystem.gd — Persistence
Pure orchestration with no state of its own. Calls `to_dict()` on 11 systems, writes one dictionary to disk. Settings persisted separately in `settings.dat`, loaded before the first frame. Save version stamped for future migration support.

### Settings.gd — Accessibility Configuration
Stores all player preferences: text size (3 presets), calm visual mode, camera shake toggle, guided mode, typewriter toggle and speed, audio volumes, fullscreen. `apply_settings_to_tree` recursively scales fonts from cached base sizes. Settings persist independently of save slots.

### VisualFX.gd — Effects Facade
Single entry point for camera shake, damage vignette, and building upgrade cinematics. Checks Settings at the call site (calm visual mode, reduce screen shake) so no caller needs accessibility awareness. Camera registration pattern means producers and consumers never reference each other directly.

### AudioManager.gd — Audio
Zone-based music with silence gaps between tracks. SFX pool of 8 pre-allocated players. Scene changes resolve to zone keys; same-zone transitions keep music playing. `process_mode = PROCESS_MODE_ALWAYS` ensures music continues during pause.

### WorldScene.gd — Scene Contract
Base script for all world scenes. Exports for actors and spawn points paths, automatic CameraDirector creation, spawn point lookup, and `world_ready_for_reveal` signal for scene transition handshake.

### WorldFlags.gd — Reactive World State
Flag store with `set_flag`, `get_flag`, `has_flag`, `clear_flag`, and a `flags_changed` signal. Used by BuildingRoot for harvestable persistence and building stage tracking.

### WorldDrops.gd — Item Drops
Stateless utility for spawning item pickups with configurable scatter, stacking, and source metadata. Half-circle scatter toward the player, sine-curve bounce animation, shader-driven idle bob with randomised parameters.

### Analytics.gd — Telemetry
Buffered JSONL writer. Events are queued in memory and flushed to disk at a configurable buffer limit or on application exit via `_notification(NOTIFICATION_WM_CLOSE_REQUEST)`. Each line is independently parseable for corruption resilience.

---

## Accessibility Features

Each feature maps to a specific ADHD-informed design principle:

| Feature | Design Principle | Implementation |
|---|---|---|
| Unified XP pool | Reduce decision paralysis | `LevelSystem` — one counter, every activity contributes |
| Combined inventory checking | Reduce working memory burden | `ChestStorageSystem` — crafting and quests check both pools |
| Action-driven day/night | Player autonomy, reduce time anxiety | `DayNightSystem` — time advances through actions, not a clock |
| Encyclopedia + dialogue log | Attention lapse recovery | `EncyclopediaSystem` — passive tracking, full conversation history |
| Two-stage dialogue advance | Impulsivity protection | `DialogueBox` — first press completes text, second advances |
| Quest auto-accept | Reduce interaction friction | `QuestSystem` — quests start when conditions are met, no accept button |
| Guided mode (quest arrow) | Task structure, reduce disorientation | `QuestArrow` — defaults on, points to next objective |
| Calm visual mode | Sensory management | `Settings` + `VisualFX` — suppresses floating text and damage vignette |
| Text size presets | Readability | `Settings` — three named presets (Small/Medium/Large), not a slider |
| Camera shake toggle | Sensory management | `Settings` + `VisualFX` — checked at the effect call site |
| Settings persistence | Reduce configuration anxiety | `SaveSystem` — `settings.dat` loads before first frame, survives across save slots |
| Tabbed menu | Reduce visual clutter | `TabbedMenu` — one tab visible at a time, five tabs total |
| Recipe pinning | Externalise working memory | `CraftingSystem` — pinned recipe with count shown on HUD |
| End-of-day summary | Natural session boundary | `DayNightSystem` — recap, heal, autosave on sleep |

---

## Assets

- **Sprites:** Franuka asset packs (tsTown, RPG Castles, RPG Icon Pack) from itch.io, with edits in Aseprite
- **Fonts:** m5x7 and m6x11 by Daniel Linssen
- **Audio:** Purchased/free sound effects and music (see Appendix A in thesis for full list)

---

## Technical Requirements

- **Engine:** Godot 4.x
- **Language:** GDScript
- **Platform:** Desktop (Windows/macOS/Linux)

---

## Academic Context

This project is submitted as part of an MSc dissertation at the University of Limerick. The thesis, titled *"The Undoing of Ashvale"*, uses autoethnographic methodology to explore how a developer with ADHD can design an RPG that addresses the specific accessibility challenges faced by neurodivergent players. All code was written by the developer; no AI-generated code was used in the implementation. Claude was used to write this readme and the make_pubic_copy.sh file only.
