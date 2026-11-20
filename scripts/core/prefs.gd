extends Node
## Player settings, edited on the in-world settings terminal. Saved to user://prefs.cfg.

signal changed

const PATH := "user://prefs.cfg"

var master := 0.8
var voice := 0.9
var ambience := 0.7
var sensitivity := 1.0
var invert_y := false
var fov := 75.0
var subtitles := true
var quality := 1 # 0 low, 1 high (volumetric fog, shadows)

signal keys_changed

## Hotkeys. Each action has one rebindable key (physical, so it sits in the same place on
## any keyboard layout) plus fixed extras. ESC and the ALT cursor tap are not rebindable.
## Order and names here are the order and labels on the settings terminal.
const BINDABLE := [
	["move_forward", "WALK FORWARD", KEY_W], ["move_back", "WALK BACK", KEY_S],
	["move_left", "WALK LEFT", KEY_A], ["move_right", "WALK RIGHT", KEY_D],
	["run", "RUN", KEY_SHIFT], ["interact", "STAND / SIT / USE", KEY_E],
	["cursor_toggle", "CURSOR TOGGLE", KEY_TAB], ["help", "ALL KEYS CARD", KEY_H],
	["time_down", "TIME SLOWER", KEY_COMMA], ["time_up", "TIME FASTER", KEY_PERIOD],
	["select_1", "SELECT SWIFT-1", KEY_F1], ["select_2", "SELECT SWIFT-2", KEY_F2],
	["select_3", "SELECT LANDSHIP", KEY_F3],
	["preset_1", "LAYOUT COMBAT", KEY_1], ["preset_2", "LAYOUT RECON", KEY_2],
	["preset_3", "LAYOUT TRANSIT", KEY_3], ["preset_4", "ACTION STATIONS", KEY_4],
	["thermal", "FEED THERMAL", KEY_T], ["gimbal_auto", "FEED GIMBAL AUTO", KEY_G],
	["map_centre", "MAP CENTRE", KEY_C],
]
const EXTRA_KEYS := {
	"move_forward": [KEY_UP], "move_back": [KEY_DOWN], "move_left": [KEY_LEFT], "move_right": [KEY_RIGHT],
	"time_up": [KEY_EQUAL], "time_down": [KEY_MINUS], "help": [KEY_SLASH], "escape": [KEY_ESCAPE],
}
var keys := {} # action -> physical keycode
var capturing := "" # action waiting for a key on the settings terminal


func _ready() -> void:
	for b in BINDABLE:
		keys[b[0]] = b[2]
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		for k in ["master", "voice", "ambience", "sensitivity", "invert_y", "fov", "subtitles", "quality"]:
			set(k, cf.get_value("prefs", k, get(k)))
		for a in keys:
			keys[a] = int(cf.get_value("keys", a, keys[a]))
	apply_audio()
	apply_keys()


func set_value(k: String, v) -> void:
	set(k, v)
	apply_audio()
	changed.emit()
	_save()


func _save() -> void:
	var cf := ConfigFile.new()
	for key in ["master", "voice", "ambience", "sensitivity", "invert_y", "fov", "subtitles", "quality"]:
		cf.set_value("prefs", key, get(key))
	for a in keys:
		cf.set_value("keys", a, keys[a])
	cf.save(PATH)


## Rebuild the InputMap from the bindings.
func apply_keys() -> void:
	var all := keys.keys()
	for a in EXTRA_KEYS:
		if not all.has(a):
			all.append(a)
	for a in all:
		if InputMap.has_action(a):
			InputMap.action_erase_events(a)
		else:
			InputMap.add_action(a)
		var codes: Array = EXTRA_KEYS.get(a, []).duplicate()
		if keys.has(a):
			codes.push_front(keys[a])
		for k in codes:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(a, e)
	_names.clear()
	keys_changed.emit()


## Bind a key. If another action had it, that action takes this one's old key (a swap),
## so nothing is ever left without a key.
func bind(action: String, code: int) -> void:
	var old: int = keys[action]
	for a in keys:
		if a != action and keys[a] == code:
			keys[a] = old
	keys[action] = code
	apply_keys()
	_save()


func reset_keys() -> void:
	for b in BINDABLE:
		keys[b[0]] = b[2]
	apply_keys()
	_save()


## The label of an action's key as printed on this keyboard (layout aware where the
## platform can tell us; headless and web fall back to the QWERTY name). Cached.
var _names := {}


func key_name(action: String) -> String:
	if not keys.has(action):
		return "?"
	if _names.has(action):
		return _names[action]
	var code: int = keys[action]
	var label := KEY_NONE
	if DisplayServer.get_name() != "headless" and OS.get_name() in ["Windows", "macOS", "Linux", "FreeBSD"]:
		label = DisplayServer.keyboard_get_label_from_physical(code)
	var s := OS.get_keycode_string(label if label != KEY_NONE else code)
	_names[action] = s.to_upper() if s != "" else "?"
	return _names[action]


## Key capture for rebinding: the next key press goes to `capturing`. ESC cancels. Runs in
## _input so the press never reaches the game (no walking off, no leaving the terminal).
func _input(ev: InputEvent) -> void:
	if capturing == "" or not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	get_viewport().set_input_as_handled()
	var code: int = ev.physical_keycode
	var a := capturing
	capturing = ""
	if code == KEY_ESCAPE or code == KEY_ALT or code == KEY_NONE:
		keys_changed.emit() # cancelled: refresh the labels
		return
	bind(a, code)


func apply_audio() -> void:
	_bus("Master", master)
	_bus("Voice", voice)
	_bus("Ambience", ambience)


func _bus(name: String, v: float) -> void:
	var i := AudioServer.get_bus_index(name)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
