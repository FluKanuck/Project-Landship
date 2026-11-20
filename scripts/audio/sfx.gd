extends Node
## The crew's voice. Turns Sim events into radio callouts, comms-log lines and subtitles,
## and runs the bridge ambience (hum, air, tracks, console blips, crew murmur).

signal subtitle(who: String, text: String)

const ROLE_NAMES := {"sensors": "SENSORS", "flight": "FLIGHT", "comms": "COMMS", "helm": "HELM", "xo": "XO"}
const PRIORITY := {"contact": 9, "fire": 8, "lost": 8, "alert": 9, "default": 5, "low": 2}

var lines := {}
var chatter := []
var _queue: Array[Dictionary] = []
var _voice: AudioStreamPlayer
var _ui: AudioStreamPlayer
var _sfx: AudioStreamPlayer
var _hum: AudioStreamPlayer
var _air: AudioStreamPlayer
var _tracks: AudioStreamPlayer
var _static: AudioStreamPlayer
var _chat_points: Array[AudioStreamPlayer3D] = []
var _chat_timer := 6.0
var _blip_timer := 3.0
var _lost_toggle := false
var _gap := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_make_buses()
	var f := FileAccess.open("res://assets/audio/lines.json", FileAccess.READ)
	if f:
		var meta: Dictionary = JSON.parse_string(f.get_as_text())
		lines = meta.get("lines", {})
		chatter = meta.get("chatter", [])
	_voice = _player("Voice")
	_ui = _player("UI")
	_sfx = _player("UI")
	_hum = _loop("amb_hum", "Ambience", -8.0)
	_air = _loop("amb_air", "Ambience", -14.0)
	_tracks = _loop("amb_tracks", "Ambience", -12.0)
	_static = _loop("sfx_static", "UI", -80.0)
	Sim.event.connect(_on_event)
	Prefs.apply_audio()


func _make_buses() -> void:
	for n in ["Voice", "Ambience", "UI"]:
		if AudioServer.get_bus_index(n) >= 0:
			continue
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, n)
		AudioServer.set_bus_send(i, "Master")
	var vi := AudioServer.get_bus_index("Voice")
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.25
	rev.wet = 0.08
	rev.dry = 1.0
	AudioServer.add_bus_effect(vi, rev)


func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func _loop(name: String, bus: String, db: float) -> AudioStreamPlayer:
	var p := _player(bus)
	var s := load("res://assets/audio/%s.ogg" % name) as AudioStreamOggVorbis
	if s:
		s.loop = true
		p.stream = s
	p.volume_db = db
	return p


func start_ambience() -> void:
	for p in [_hum, _air, _tracks, _static]:
		if p.stream and not p.playing:
			p.play()


## The bridge registers 3D points in the crew pits for the murmur.
func register_chatter_point(node: Node3D) -> void:
	var p := AudioStreamPlayer3D.new()
	p.bus = "Ambience"
	p.unit_size = 3.0
	p.max_db = -6.0
	p.volume_db = -9.0
	node.add_child(p)
	_chat_points.append(p)


func ui(name: String) -> void:
	var s := load("res://assets/audio/ui_%s.ogg" % name)
	if s:
		_ui.stream = s
		_ui.play()


func sfx(name: String, db := 0.0) -> void:
	var s := load("res://assets/audio/%s.ogg" % name)
	if s:
		var p := _player("UI")
		p.stream = s
		p.volume_db = db
		p.play()
		p.finished.connect(p.queue_free)


func set_static(level: float) -> void:
	_static.volume_db = linear_to_db(maxf(level, 0.0001)) - 14.0


## Queue a callout. `key` is a clip in lines.json; `text` overrides the log text.
func say(key: String, text := "", prio := 5, role := "") -> void:
	var meta: Dictionary = lines.get(key, {})
	if role == "":
		role = meta.get("role", "xo")
	if text == "":
		text = meta.get("text", key)
	var who: String = ROLE_NAMES.get(role, role.to_upper())
	Sim.add_log(who, text, prio >= 8)
	subtitle.emit(who, text)
	# drop stale low-priority lines so the voice never lags far behind events
	for q in _queue.duplicate():
		if q.key == key or (q.prio < prio and _queue.size() > 2):
			_queue.erase(q)
	_queue.append({"key": key, "prio": prio})
	_queue.sort_custom(func(a, b): return a.prio > b.prio)


func _process(delta: float) -> void:
	_gap = maxf(0.0, _gap - delta)
	if not _voice.playing and _gap <= 0.0 and not _queue.is_empty():
		var q: Dictionary = _queue.pop_front()
		var s := load("res://assets/audio/vo_%s.ogg" % q.key)
		if s:
			_voice.stream = s
			_voice.play()
			_gap = 0.25
	# ambience follows the carrier
	if _tracks.playing:
		var spd: float = Sim.carrier.speed
		_tracks.volume_db = lerpf(_tracks.volume_db, -30.0 + spd * 1.8, delta)
		_tracks.pitch_scale = 0.85 + spd * 0.025
	if not Sim.running:
		return
	_chat_timer -= delta
	if _chat_timer <= 0.0 and not _chat_points.is_empty() and chatter.size() > 0:
		_chat_timer = _rng.randf_range(3.5, 9.0)
		if not _voice.playing or _rng.randf() < 0.3:
			var p := _chat_points[_rng.randi() % _chat_points.size()]
			p.stream = load("res://assets/audio/chat_%02d.ogg" % (_rng.randi() % chatter.size()))
			p.pitch_scale = _rng.randf_range(0.96, 1.04)
			p.play()
	_blip_timer -= delta
	if _blip_timer <= 0.0 and not _chat_points.is_empty():
		_blip_timer = _rng.randf_range(1.5, 5.0)
		var p := _chat_points[_rng.randi() % _chat_points.size()]
		if not p.playing:
			p.stream = load("res://assets/audio/amb_blip_%d.ogg" % (_rng.randi() % 4))
			p.play()


func _n(data: Dictionary) -> int:
	var d: DroneSim = data.get("drone")
	return d.id + 1 if d else 1


func _cs(data: Dictionary) -> String:
	var d: DroneSim = data.get("drone")
	return d.callsign if d else "SWIFT"


func _on_event(kind: String, data: Dictionary) -> void:
	var n := _n(data)
	match kind:
		"boot":
			say("xo_boot", "", 6)
			say("xo_ready", "", 5)
			say("xo_objective", "", 4)
		"hint_launch":
			say("xo_hint_launch", "", 4)
		"hint_time":
			say("xo_hint_time", "", 4)
		"launch":
			say("launch_%d" % n, "%s launching." % _cs(data))
		"on_station":
			say("station_%d" % n, "%s on station." % _cs(data), 4)
		"loiter_start":
			say("loiter_%d" % n, "%s loitering." % _cs(data), 3)
		"scan_start":
			say("scan_%d" % n, "%s scanning." % _cs(data), 3)
		"contact_new":
			var b := int(round(data.bearing / 10.0)) * 10 % 360
			var many: bool = data.get("count", 1) > 1
			var key := ("multi_%03d" if many else "contact_%03d") % b
			var txt := "%s Bearing %03d, range %.1f km." % ["Multiple contacts." if many else "Contact.", int(round(data.bearing)) % 360, data.range / 1000.0]
			say(key, txt, 9)
			sfx("sfx_contact", -4.0)
		"contact_lost":
			_lost_toggle = not _lost_toggle
			say("contact_lost_a" if _lost_toggle else "contact_lost_b", "Contact lost, bearing %03d. Marking last known." % int(data.bearing), 3)
		"contact_class":
			say("contact_class", "", 6)
		"tc_drop":
			sfx("sfx_tc_drop", -2.0)
			Sim.add_log("XO", "Time compression disengaged.", true)
		"time_scale":
			if data.scale > 1:
				sfx("sfx_tc_up", -8.0)
		"link_weak":
			say("weak_%d" % n, "%s, signal weak." % _cs(data), 4)
		"link_lost":
			say("linklost_%d" % n, "Link lost with %s. Flying on last orders." % _cs(data), 7)
		"link_restored":
			say("linkback_%d" % n, "Link restored with %s." % _cs(data), 6)
			if data.get("burst", 0) > 0:
				say("burst", "Data burst from %s: %d contact report%s." % [_cs(data), data.burst, "" if data.burst == 1 else "s"], 6)
		"rtb":
			if data.get("why", "") == "bingo":
				say("bingo_%d" % n, "%s, bingo fuel. Returning." % _cs(data), 6)
			else:
				say("rtb_%d" % n, "%s returning to carrier." % _cs(data), 4)
		"recovered":
			say("recovered_%d" % n, "%s recovered. Refuelling." % _cs(data), 4)
		"drone_ready":
			say("ready_%d" % n, "%s ready on deck." % _cs(data), 3)
		"under_fire":
			say("fire_%d" % n, "%s taking fire!" % _cs(data), 8)
			sfx("sfx_burst", -10.0)
		"breaking_off":
			say("breaking_%d" % n, "%s under fire, breaking off (ROE: FLEE)." % _cs(data), 8)
			sfx("sfx_burst", -10.0)
		"damage":
			say("damage_%d" % n, "%s hit. Still flying." % _cs(data), 8)
		"drone_lost":
			say("lost_%d" % n, "%s lost%s." % [_cs(data), " (fuel exhausted)" if data.get("why") == "fuel" else ""], 9)
		"rebuild_start":
			say("rebuild", "Fabrication started a replacement for %s (20 min)." % _cs(data), 4)
		"drone_rebuilt":
			say("rebuilt", "Replacement %s on deck." % _cs(data), 5)
		"node_found":
			say("node_found", "Alien recharge node sighted, bearing %03d." % int(data.bearing), 9)
			say("xo_objective_done", "", 7)
			sfx("sfx_contact", -4.0)
		"orders_locked":
			say("locked", "No link with %s. Orders locked." % _cs(data), 6)
			ui("err")
		"cannot_launch":
			say("cannot_launch", "%s is not ready to launch." % _cs(data), 4)
			ui("err")
		"helm_throttle":
			say("helm_%d" % data.throttle, "", 5)
			if data.get("restart", false):
				say("helm_restart", "Breaking out of the sand: restart cost paid in fuel.", 4)
		"helm_course":
			if data.count == 1:
				say("helm_course", "", 3)
		"helm_course_done":
			say("helm_done", "", 3)
		"helm_limit":
			say("helm_limit", "", 7)
		"alert":
			if data.on:
				sfx("sfx_klaxon", -6.0)
				say("xo_alert_on", "", 9)
			else:
				say("xo_alert_off", "", 5)
		"waypoint_added":
			ui("beep")
