extends Node
## Builds the wedge: the desert, the carrier, the bridge inside it, the commander, and runs
## the short power-up sequence.

var world: WorldView
var bridge: Bridge
var player: Player
var hud: Hud
var _hinted_launch := false
var _hinted_time := false
var _started := false


func _ready() -> void:
	_inputs()
	world = WorldView.new()
	add_child(world)
	bridge = Bridge.new()
	bridge.position = CarrierSim.BRIDGE_LOCAL
	world.carrier_node.add_child(bridge)
	bridge.projection.mfd.setup(world)
	player = Player.new(bridge)
	bridge.add_child(player)
	hud = Hud.new(player)
	add_child(hud)
	Sim.event.connect(_on_event)
	bridge.set_power(0.0)
	bridge.projection.set_boot(0.0)
	bridge.holo.boot = 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scenario="):
			var dir: Node = load("res://scripts/debug/director.gd").new()
			add_child(dir)
	if "--autostart" in OS.get_cmdline_user_args():
		_start()


func _unhandled_input(ev: InputEvent) -> void:
	if not _started and (ev is InputEventMouseButton or ev is InputEventKey) and ev.is_pressed():
		_start()


func _start() -> void:
	if _started:
		return
	_started = true
	Sfx.start_ambience()
	var tw := create_tween()
	tw.tween_property(hud.title, "modulate:a", 0.0, 0.6)
	tw.parallel().tween_property(hud.title.get_meta("sub"), "modulate:a", 0.0, 0.6)
	tw.parallel().tween_property(hud.fade, "color:a", 0.0, 2.2)
	tw.parallel().tween_method(bridge.set_power, 0.0, 1.0, 3.0).set_delay(0.3)
	tw.parallel().tween_method(bridge.projection.set_boot, 0.0, 1.0, 1.6).set_delay(1.6)
	tw.parallel().tween_property(bridge.holo, "boot", 1.0, 1.2).set_delay(2.4)
	tw.tween_callback(func():
		player.release_boot()
		player._update_mouse_mode()
		Sim.running = true
		Sim.emit_event("boot", {}))


func _process(_d: float) -> void:
	if not Sim.running:
		return
	if not _hinted_launch and Sim.game_time > 25.0:
		_hinted_launch = true
		var any := false
		for d in Sim.drones:
			if d.state != DroneSim.State.READY:
				any = true
		if not any:
			Sim.emit_event("hint_launch", {})
	if not _hinted_time and Sim.game_time > 90.0 and Sim.time_scale() == 1:
		for d in Sim.drones:
			if d.state == DroneSim.State.ACTIVE:
				_hinted_time = true
				Sim.emit_event("hint_time", {})
				break


func _on_event(kind: String, data: Dictionary) -> void:
	if kind == "alert":
		bridge.set_alert(data.on)


func _inputs() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN], "move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT], "run": [KEY_SHIFT], "interact": [KEY_E], "cursor_toggle": [KEY_TAB],
		"escape": [KEY_ESCAPE], "time_up": [KEY_PERIOD, KEY_EQUAL], "time_down": [KEY_COMMA, KEY_MINUS],
		"preset_1": [KEY_1], "preset_2": [KEY_2], "preset_3": [KEY_3], "preset_4": [KEY_4],
		"select_1": [KEY_F1], "select_2": [KEY_F2], "select_3": [KEY_F3], "help": [KEY_H],
		"select_vehicle": [KEY_F4], "preset_5": [KEY_5], "preset_6": [KEY_6],
	}
	for a in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		for k in keys[a]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(a, e)
