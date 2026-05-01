@tool
extends EditorPlugin

## Plugin lifecycle script — registers the LudoSenseAnalytics autoload
## when the developer enables "LudoSense Analytics" in Project Settings → Plugins.
##
## This script does NOT contain analytics logic. It exists solely to wire up
## the autoload singleton so that LudoSenseAnalytics.log_event() works
## globally from any scene.
##
## Why _enable_plugin / _disable_plugin instead of _enter_tree / _exit_tree?
## _enter_tree runs every editor startup, which would re-add the autoload
## entry each time and risk duplicates. _enable_plugin runs only when the
## developer explicitly toggles the plugin on — once — and _disable_plugin
## cleans it up on toggle-off.

const AUTOLOAD_NAME = "Analytics"

func _enable_plugin():
	add_autoload_singleton(
		AUTOLOAD_NAME,
		"res://addons/ludosense/LudoSenseAnalytics.gd"
	)

func _disable_plugin():
	remove_autoload_singleton(AUTOLOAD_NAME)
