extends Node;

#harvest_id -> HarvestableDataResource
var _harvestables_by_id: Dictionary = {};

func _ready() -> void:
	for resource in HarvestablePreloadRegistry.ALL:
		if resource is HarvestableDataResource:
			var h: HarvestableDataResource = resource;
			if h.harvest_id.is_empty():
				push_warning("HarvestableDataResource missing harvest_id: %s" % resource.resource_path);
			elif _harvestables_by_id.has(h.harvest_id):
				push_warning("Duplicate HarvestableDataResource id: '%s'" % h.harvest_id);
			else:
				_harvestables_by_id[h.harvest_id] = h;
		else:
			push_warning("HarvestablePreloadRegistry: Non-HarvestableDataResource entry: %s" % resource.resource_path);
	
#region Public helpers
func has_harvestable(harvest_id: String) -> bool:
	return _harvestables_by_id.has(harvest_id);
	
func get_resource(harvest_id: String) -> HarvestableDataResource:
	return _harvestables_by_id.get(harvest_id, null);

func get_display_name(harvest_id: String) -> String:
	var h = get_resource(harvest_id);
	if h == null:
		return harvest_id.capitalize();
	return tr(h.get_name_key());
	
func get_location(harvest_id: String) -> String:
	var h = get_resource(harvest_id);
	if h == null:
		return "";
	return tr(h.get_location_key());
	
func get_description(harvest_id: String) -> String:
	var h = get_resource(harvest_id);
	if h == null:
		return harvest_id.capitalize();
	return tr(h.get_description_key());
	
func get_max_hits(harvest_id: String) -> int:
	var h = get_resource(harvest_id);
	if h:
		return h.max_hits;
	return 1;
	
func get_drop_item_id(harvest_id: String) -> String:
	var h = get_resource(harvest_id);
	if h and h.drop_item != null:
		return h.drop_item.item_id;
	return "";
	
func get_drop_amount_range(harvest_id: String) -> Vector2i:
	var h = get_resource(harvest_id);
	if h == null:
		return Vector2i(1, 1);
	var min_amt: int = h.drop_amount_min;
	var max_amt: int = h.drop_amount_max;
	if max_amt < min_amt:
		max_amt = min_amt;
	return Vector2i(min_amt, max_amt);
	
func get_all_harvestables() -> Array[HarvestableDataResource]:
	var result: Array[HarvestableDataResource] = [];
	for h in _harvestables_by_id.values():
		result.append(h);
	return result;
	
func get_xp_reward(harvest_id: String) -> int:
	var h = get_resource(harvest_id);
	if h == null:
		return 0;
	return h.xp_reward;
	
func get_world_sprite_texture(harvest_id: String) -> Texture2D:
	var h = get_resource(harvest_id);
	if h == null:
		return null;
	var tex = h.get_random_sprite();
	if tex == null:
		push_warning("HarvestableDatabase: No world_sprites set for %s" % harvest_id);
	return tex;
	
func get_icon(harvest_id: String) -> Texture2D:
	var h = get_resource(harvest_id);
	if h == null:
		return null;
	return h.icon;
	
func get_hit_sfx(harvest_id: String) -> AudioStream:
	var h = get_resource(harvest_id);
	if h:
		return h.hit_sfx;
	return null;
	
func get_break_sfx(harvest_id: String) -> AudioStream:
	var h = get_resource(harvest_id);
	if h:
		return h.break_sfx;
	return null;
	
#Returning an int because it's loading an enum
func get_required_tool(harvest_id: String) -> int:
	var h = get_resource(harvest_id);
	if h == null:
		return HarvestableDataResource.RequiredTool.NONE;
	return h.required_tool;
	
#Return the time cost multiplier
func get_size_multiplier(harvest_id: String) -> float:
	var h = get_resource(harvest_id);
	if h == null:
		return 1.0;
	match h.node_size:
		HarvestableDataResource.NodeSize.SMALL:
			return 0.5;
		HarvestableDataResource.NodeSize.LARGE:
			return 1.5;
		_:
			return 1.0; #Medium is the safe default
#endregion
#region Internal helpers
func _make_fallback_harvestable(harvest_id: String) -> Dictionary:
	return {
		"harvest_id": harvest_id,
		"max_hits": 1,
		"drop_item_id": "",
		"drop_amount_min": 1,
		"drop_amount_max": 1,
		"required_tool": HarvestableDataResource.RequiredTool.NONE,
	};
#endregion
