extends Resource;
class_name NPCData;
#region Exports for npc info
#Unique ID use in quests, save data, etc
@export var id: StringName;
#Display name for UI or dialogue
@export var display_name: String = "";
#Option portait or icon for dialogue windows
@export var portrait: Texture2D;
#Dafult dialogue to start when start to this particular NPC (set in each resource itself)
@export var default_dialogue_id: StringName;
#Tags like "shopkeeper", "quest_giver", etc
@export var tags: Array[StringName] = [];
#Optional paramaeters when sending quest events
#i.e., "npc_id" : "elder"
@export var base_event_payload: Dictionary = {};
#endregion
#region Animation stuffs
#Spriteframes for this NPC's AnimatedSprite2D
@export var sprite_frames: SpriteFrames;
#Default idle animation name
@export var idle_animation: StringName = &"idle";
#Talking animation--maybe set up later, we'll see
#@export var talk_animation: StringName = StringName();
#endregion
