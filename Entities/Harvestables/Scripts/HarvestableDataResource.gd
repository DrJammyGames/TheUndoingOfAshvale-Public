extends Resource  
class_name HarvestableDataResource

#Enum for tool required to harvest
enum RequiredTool {
	NONE,
	AXE,
	HOE,
	PICKAXE,
	SWORD,
	WATERING_CAN
}

#Core data
@export var harvest_id: String = "";
@export var max_hits: int = 1;

@export var drop_item: ItemDataResource = null; #direct reference to the item resource
@export var drop_amount_min: int = 1;
@export var drop_amount_max: int = 1;
@export var xp_reward: int = 0;
@export var required_tool: RequiredTool = RequiredTool.NONE;

@export var location_hint: LocationData.Location = LocationData.Location.FOREST;
#Presentation
@export var world_sprites: Array[Texture2D] = []; #for any harvestables that have a few options
@export var encyclopedia_icon: Texture2D = null;
@export var hit_sfx: AudioStream = null;
@export var break_sfx: AudioStream = null;

#Sizes
enum NodeSize {
	SMALL,
	MEDIUM,
	LARGE
}
@export var node_size: NodeSize = NodeSize.MEDIUM;

#Auto generate localisation keys
func get_name_key() -> String:
	if harvest_id.is_empty():
		return "";
	return "harvestable.%s.name" % harvest_id;
	
func get_description_key() -> String:
	if harvest_id.is_empty():
		return "";
	return "harvestable.%s.description" % harvest_id;
	
#If there are multiple sprite options, select a random one
func get_random_sprite() -> Texture2D:
	if world_sprites.is_empty():
		return null;
	#If there's only one, just get that one
	if world_sprites.size() == 1:
		return world_sprites[0];
	#Randomly select one of the options if there is more than one
	return world_sprites[randi() % world_sprites.size()];

#Get the localised location hint
func get_location_key() -> String:
	if harvest_id.is_empty():
		return "";
	var location_str: String = LocationData.Location.keys()[location_hint].to_lower();
	return "location.%s" % location_str;
