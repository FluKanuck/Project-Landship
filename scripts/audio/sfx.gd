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
		var path := "res://assets/audio/vo_%s.ogg" % q.key
		var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
		if s == null:
			# no recorded line for this one: a squelch so the ear still catches it
			if ResourceLoader.exists("res://assets/audio/ui_beep.ogg"):
				_voice.stream = load("res://assets/audio/ui_beep.ogg")
				_voice.play()
			_gap = 0.4
		else:
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


func _v(data: Dictionary) -> String:
	var v: VehicleSim = data.get("veh")
	return v.callsign if v else "Crane"


func _site(data: Dictionary) -> String:
	var s = data.get("site")
	return s.name.capitalize() if s is SiteSim else "the site"


func _logistics(kind: String, data: Dictionary) -> bool:
	match kind:
		"site_found":
			var s: SiteSim = data.site
			say("site_found", "%sResource site %s, %s%s, bearing %03d." % ["Data burst: " if data.get("burst") else "", s.name.capitalize(),
				Logi.SITE_KIND_NAMES[s.kind].to_lower(), " (enemy held)" if s.owner == Logi.Owner.ALIEN else "", int(data.bearing)], 5, "sensors")
		"planted":
			var k: String = Logi.KIND_NAMES[data.kind].to_lower()
			if data.get("veh") == null:
				say("crane_planted", "Crane has the %s down%s." % [k, " at " + _site(data) if data.get("site") else ""], 4, "helm")
			else:
				say("planted", "%s: %s planted%s." % [_v(data), k, " at " + _site(data) if data.get("site") else ""], 4, "comms")
		"plant_failed":
			say("plant_failed", "Can't plant the %s: %s." % [Logi.KIND_NAMES[data.kind].to_lower(), data.why], 5, "helm")
			ui("err")
		"structure_online":
			var s: StructureSim = data.s
			match s.kind:
				Logi.Kind.RELAY: say("relay_online", "Relay online. Network extended%s." % (" (high ground)" if s.range_mult > 1.05 else ""), 5, "comms")
				Logi.Kind.SCANNER: say("scanner_online", "Scanner post online.", 5, "sensors")
				Logi.Kind.EXTRACTOR: say("extractor_online", "Extractor running at %s." % _site(data), 5, "comms")
				Logi.Kind.TURRET: say("turret_online", "Turret armed at %s." % _site(data), 4, "comms")
				Logi.Kind.PAD: say("pad_online", "Loading pad ready at %s." % _site(data), 4, "comms")
		"structure_attacked":
			var s: StructureSim = data.s
			say("hub_attack", "%s under attack!" % (_site(data) if data.get("site") else "Relay"), 8, "comms")
			sfx("sfx_burst", -10.0)
		"structure_lost":
			var s: StructureSim = data.s
			if s.kind == Logi.Kind.RELAY:
				say("relay_lost", "Relay lost. The network's cut.", 8, "comms")
			else:
				say("hub_part_lost", "We've lost the %s at %s." % [Logi.KIND_NAMES[s.kind].to_lower(), _site(data)], 8, "comms")
		"hub_dark":
			say("hub_dark", "%s has gone dark." % _site(data), 6, "comms")
		"hub_linked":
			say("hub_linked", "%s back on the net." % _site(data), 5, "comms")
		"hub_full":
			say("hub_full", "%s stockpile is full. Extraction stopped." % _site(data), 4, "comms")
		"hub_looted":
			if data.site.linked:
				say("hub_looted", "They're looting %s!" % _site(data), 8, "comms")
		"alien_settling":
			if data.get("seen", false):
				say("alien_settling", "Aliens are building at %s." % _site(data), 7, "sensors")
		"alien_outpost":
			if data.get("seen", false):
				say("alien_outpost", "Alien outpost established at %s." % _site(data), 7, "sensors")
		"site_cleared":
			say("site_cleared", "%s is clear. The site is ours to take." % _site(data), 7, "xo")
		"site_lootable":
			say("site_lootable", "Alien facility down at %s. Salvage on the ground." % _site(data), 6, "xo")
		"alien_structure_destroyed":
			var s: StructureSim = data.s
			if s.kind == Logi.Kind.ALIEN_NODE:
				say("node_destroyed", "The recharge node is down!", 9, "xo")
			else:
				say("outpost_destroyed", "Alien outpost destroyed.", 7, "xo")
		"raider_killed":
			if data.get("seen", false):
				say("raider_down", "Raider down.", 6, "sensors")
		"veh_deploy":
			say("veh_deploy", "%s deploying." % _v(data), 3, "flight")
		"veh_home":
			match data.get("why", ""):
				"bingo": say("veh_bingo", "%s, bingo fuel. Coming home." % _v(data), 5, "flight")
				"fuel": say("veh_dry", "%s is dry. Limping home on the reserve." % _v(data), 6, "flight")
				"evade": say("veh_home", "%s broke contact, coming home." % _v(data), 4, "flight")
		"veh_aboard":
			var txt := "%s aboard." % _v(data)
			if data.fuel + data.mat > 0.5:
				txt = "%s aboard, unloading %d fuel, %d materials." % [_v(data), int(data.fuel), int(data.mat)]
			say("veh_aboard", txt, 4, "helm")
		"veh_loaded":
			say("veh_loaded", "%s loaded at %s%s." % [_v(data), _site(data), " (part load)" if data.get("part") else ""], 3, "comms")
		"veh_looted":
			say("veh_looted", "%s has the salvage from %s." % [_v(data), _site(data)], 4, "comms")
		"veh_cannot":
			say("veh_cannot", "%s can't %s: %s." % [_v(data), data.what, data.why], 5, "comms")
		"veh_cannot_deploy":
			say("veh_cannot", "%s can't deploy: %s." % [_v(data), str(data.why).to_lower()], 5, "helm")
			ui("err")
		"veh_fire":
			say("veh_fire", "%s taking fire!" % _v(data), 8, "comms")
			sfx("sfx_burst", -10.0)
		"veh_breaking":
			say("veh_breaking", "%s under fire, breaking off." % _v(data), 8, "comms")
		"veh_damage":
			say("veh_damage", "%s hit." % _v(data), 7, "comms")
		"veh_lost":
			say("veh_lost", "%s lost%s." % [_v(data), " (out of fuel)" if data.get("why") == "fuel" else ""], 9, "comms")
		"veh_link_lost":
			say("veh_link_lost", "Lost the link to %s. Running last orders." % _v(data), 6, "comms")
		"veh_link_restored":
			say("veh_link_back", "%s back on the net." % _v(data), 5, "comms")
		"route_broken":
			say("route_broken", "%s: route broken, coming home." % _v(data), 6, "comms")
		"route_set":
			if data.on:
				say("route_set", "%s on a standing route." % _v(data), 3, "flight")
		"veh_refit":
			say("veh_refit", "%s refit: %s." % [_v(data), data.veh.fit_text().to_lower()], 3, "helm")
		"fab_done":
			say("fab_done", "Fabrication: %s complete." % str(data.name).to_lower(), 4, "xo")
		"fab_waiting":
			say("fab_waiting", "Fabricator waiting on materials. The %s needs %d." % [str(data.name).to_lower(), int(data.cost)], 6, "xo")
		"fab_refused":
			say("fab_refused", "Can't build the %s: %s." % [str(data.name).to_lower(), data.why], 5, "xo")
			ui("err")
		"refit_start":
			say("refit_start", "Refitting slot %d." % (int(data.slot) + 1), 4, "helm")
		"refit_done":
			if data.module != "":
				say("refit_done", "%s online." % Logi.MODULES[data.module].name.capitalize(), 5, "helm")
		"module_upgraded":
			say("module_upgraded", "%s fitted." % str(data.name).capitalize(), 5, "helm")
		"scanner_burst":
			say("burst", "Scanner data burst: %d contact report%s." % [data.burst, "" if data.burst == 1 else "s"], 6, "sensors")
		"objective":
			say("objective", "New objective: %s." % str(data.text).capitalize(), 6, "xo")
		_:
			return false
	return true


func _on_event(kind: String, data: Dictionary) -> void:
	if _logistics(kind, data):
		return
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
			say("rebuild", "Fabrication queued a replacement for %s (%d materials)." % [_cs(data), int(data.get("cost", 40))], 4)
		"drone_rebuilt":
			say("rebuilt", "Replacement %s on deck." % _cs(data), 5)
		"node_found":
			say("node_found", "Alien recharge node sighted, bearing %03d." % int(data.bearing), 9)
			sfx("sfx_contact", -4.0)
		"orders_locked":
			say("locked", "No link with %s. Orders locked." % (_v(data) if data.has("veh") else _cs(data)), 6)
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
