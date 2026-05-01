extends Node
#Flags throughout the world 
#Bridge built, door unlocked, etc
signal flags_changed(key: StringName);

var _flags: Dictionary = {} # key: StringName -> Variant

#Set a flag in the world
func set_flag(key: StringName, value: Variant = true) -> void:
	_flags[key] = value;
	flags_changed.emit(key);

#Get the flag in the world
func get_flag(key: StringName, default: Variant = false) -> Variant:
	#Returns flag value or default if missing
	return _flags.get(key, default);
	
#Check if something has a flag
func has_flag(key: StringName) -> bool:
	return _flags.has(key);
	
#Clear the flag (relock door, etc)
func clear_flag(key: StringName) -> void:
	if _flags.erase(key):
		flags_changed.emit(key);

#Reset all the flags (new save data)
func reset() -> void:
	#Clears all flags
	_flags.clear();
	flags_changed.emit(&"__reset__");
	
#Saving logic
func to_dict() -> Dictionary:
	return {
		"flags": _flags.duplicate(true),
	}
#Loading logic
func from_dict(data: Dictionary) -> void:
	#Restore from saved data safely
	var loaded = data.get("flags", {});
	_flags = loaded.duplicate(true) if loaded is Dictionary else {};
	#Optional: emit reset so listeners refresh
	flags_changed.emit(&"__reset__");
