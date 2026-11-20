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


func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		for k in ["master", "voice", "ambience", "sensitivity", "invert_y", "fov", "subtitles", "quality"]:
			set(k, cf.get_value("prefs", k, get(k)))
	apply_audio()


func set_value(k: String, v) -> void:
	set(k, v)
	apply_audio()
	changed.emit()
	var cf := ConfigFile.new()
	for key in ["master", "voice", "ambience", "sensitivity", "invert_y", "fov", "subtitles", "quality"]:
		cf.set_value("prefs", key, get(key))
	cf.save(PATH)


func apply_audio() -> void:
	_bus("Master", master)
	_bus("Voice", voice)
	_bus("Ambience", ambience)


func _bus(name: String, v: float) -> void:
	var i := AudioServer.get_bus_index(name)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
