extends OSPlatform
class_name PlatformBazzite

const SESSION_SELECT_PATH := "/usr/bin/steamos-session-select"

# gamescope-session-plus resolves the "ogui-steam" session name (the one
# SDDM autologins into) through this exact user override, sourcing the
# stock Steam session file when it's just a passthrough. Same session
# name either way — only the launched CLIENTCMD changes. Deliberately NOT
# reusing `ujust configure-opengamepadui` here: its own "enable" branch
# does a bare `rm -f` on this path, which would wipe this custom-built
# YaguareteUI binary's own CLIENTCMD line (live-caught earlier this same
# session) rather than restoring it — that toggle is for Bazzite's own
# stock OGUI package, not this fork.
var OGUI_SESSION_OVERRIDE := "/".join([OS.get_environment("HOME"), ".config/gamescope-session-plus/sessions.d/ogui-steam"])
const STOCK_STEAM_SESSION_CONTENT := "#!/usr/bin/bash\n\nSTEAM_SESSION_FILE=/usr/share/gamescope-session-plus/sessions.d/steam\n[[ -f \"${STEAM_SESSION_FILE}\" ]] && . \"${STEAM_SESSION_FILE}\"\n"


func _init() -> void:
	logger.set_name("PlatformBazzite")
	logger.set_level(Log.LEVEL.INFO)


func ready(root: Window) -> void:
	if not _has_session_switcher():
		logger.info("No session switcher script detected")
		return
	_add_session_switcher(root)


## Add a button to the power menu to allow session switching
func _add_session_switcher(root: Window) -> void:
	# Get the power menu
	var power_menu := root.get_tree().get_first_node_in_group("power_menu")
	if not power_menu:
		logger.warn("No power menu was found. Unable to add session switcher.")
		return

	# Create a button that will perform the session switching
	var button_scene := load("res://core/ui/components/card_button.tscn") as PackedScene
	var switch_to_desktop := button_scene.instantiate() as CardButton
	switch_to_desktop.click_focuses = false
	switch_to_desktop.text = "Switch to Desktop"
	# The real script (/usr/libexec/os-session-select) only recognizes
	# "plasma"/"plasma-wayland"/"gamescope" — "desktop" was never a valid
	# argument, so this call silently failed every time (OS.execute here
	# doesn't capture stderr, hiding the "Unrecognized session" error).
	switch_to_desktop.pressed.connect(_switch_session.bind("plasma"))

	# Real Steam client for games no standalone/Goldberg path can run
	# (family-shared titles, real online features, strict DRM). Kept as a
	# separate gamescope session rather than bridged into this one — a
	# real Steam client running alongside this app's own gamescope session
	# was confirmed unstable this same session (steamwebhelper itself
	# crash-looping, 4/4 real-Steam launches failing 3 different ways).
	var switch_to_steam := button_scene.instantiate() as CardButton
	switch_to_steam.click_focuses = false
	switch_to_steam.text = "Switch to Steam"
	switch_to_steam.pressed.connect(_switch_to_steam_mode)

	# Add the buttons just above Cancel
	var cancel_button := power_menu.cancel_button as Control
	var container := cancel_button.get_parent()
	container.add_child(switch_to_desktop)
	container.move_child(switch_to_desktop, cancel_button.get_index())
	container.add_child(switch_to_steam)
	container.move_child(switch_to_steam, cancel_button.get_index())

	# Coerce the focus group to recalculate the focus neighbors
	var focus_group := power_menu.focus_group as FocusGroup
	focus_group.recalculate_focus()


## Returns true if we detect the session switching script
func _has_session_switcher() -> bool:
	return FileAccess.file_exists(SESSION_SELECT_PATH)


## Switch to the given session
func _switch_session(name: String) -> void:
	var out: Array = []
	# read_stderr=true — os-session-select prints its errors there, and a
	# blank "Unable to switch sessions: " with the argument mismatch that
	# broke this call cost real debugging time to track down.
	var code := OS.execute(SESSION_SELECT_PATH, [name], out, true)
	if code != OK:
		logger.error("Unable to switch sessions: " + out[0])


## Points the "ogui-steam" session override at the stock Steam session
## instead of this app's own binary, then restarts the session unit —
## this process is what's running under it, so the restart kills it and
## boots stock Steam. There is no button back to this app FROM Steam mode
## yet (needs a small Decky Loader plugin to run from inside Steam's own
## gamescope session); for now, restoring the override that points back
## at this build's CLIENTCMD has to happen from Desktop mode.
func _switch_to_steam_mode() -> void:
	var f := FileAccess.open(OGUI_SESSION_OVERRIDE, FileAccess.WRITE)
	if not f:
		logger.error("Unable to write Steam session override at " + OGUI_SESSION_OVERRIDE)
		return
	f.store_string(STOCK_STEAM_SESSION_CONTENT)
	f.close()
	OS.execute("chmod", ["+x", OGUI_SESSION_OVERRIDE])
	OS.execute("systemctl", ["--user", "restart", "gamescope-session-plus@ogui-steam.service"])
