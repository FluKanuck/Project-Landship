class_name SimCore
extends Node
## The war, as data. Runs the carrier, drones and raiders; owns sensors, contacts, ghost
## markers, the comms link, knowledge of the terrain and time compression. Everything the
## player sees on the bridge reads from here. Autoloaded as `Sim`.

signal event(kind: String, data: Dictionary)
signal knowledge_changed
signal scale_changed(scale: int)
signal selection_changed

const SCALES := [1, 4, 16, 64]
const KNOW_RES := 128
const LINK_OK := 4300.0
const LINK_MAX := 5000.0
const GHOST_FADE := 900.0 # seconds of game time until a ghost is gone
const START_CLOCK := 14 * 3600 + 20 * 60

var terrain: Terrain
var carrier: CarrierSim
var drones: Array[DroneSim] = []
var shadows := {} # drone id -> DroneSim predicted copy (only while the link is lost)
var raiders: Array[RaiderSim] = []
var contacts := {} # raider id -> Dictionary

var game_time := 0.0
var scale_idx := 0
var running := false
var selected := 0 # drone index, or -1 for the carrier
var tool_act := DroneSim.Act.MOVE
var tool_roe := DroneSim.Roe.RTRN
var node_found := false
var alert := false
var log_lines: Array[Dictionary] = []

var know := PackedFloat32Array()
var know_img: Image
var know_tex: ImageTexture
var height_tex: ImageTexture
var coarse_tex: ImageTexture
var feature_tex: ImageTexture

var _know_dirty := false
var _know_timer := 0.0
var _raid_timer := 420.0
var _raid_group := 0
var _new_burst := 0.0
var _new_count := 0
var _new_first := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	terrain = Terrain.new()
	height_tex = terrain.height_texture(256)
	coarse_tex = terrain.height_texture(20)
	feature_tex = terrain.feature_texture(256)
	know.resize(KNOW_RES * KNOW_RES)
	know.fill(0.0)
	know_img = Image.create(KNOW_RES, KNOW_RES, false, Image.FORMAT_L8)
	know_tex = ImageTexture.create_from_image(know_img)
	carrier = CarrierSim.new(terrain, Terrain.CARRIER_START)
	carrier.course.append(Terrain.CARRIER_START + Vector2(0, -2200))
	for i in 2:
		var d := DroneSim.new()
		d.id = i
		d.callsign = "SWIFT-%d" % (i + 1)
		d.spoken = "swift_%d" % (i + 1)
		drones.append(d)
		d.step(0.0, self)
	var groups := [[0, 0], [0, 1], [1, 2], [1, 0], [2, 1]] # [group, pad]
	for i in groups.size():
		var r := RaiderSim.new()
		r.id = i
		r.group = groups[i][0]
		r.pad = groups[i][1]
		r.rng.seed = 100 + i
		var p := pad_pos(r.pad) + Vector2(_rng.randf_range(-40, 40), _rng.randf_range(-40, 40))
		r.pos = Vector3(p.x, terrain.height_at(p.x, p.y) + 1.4, p.y)
		r.timer = 30.0 + i * 70.0
		r.energy = 1.0
		raiders.append(r)
	_stamp(carrier.pos2(), CarrierSim.SENSOR_RANGE)
	_upload_know()


# ------------------------------------------------------------------ public API

func time_scale() -> int:
	return SCALES[scale_idx]


func set_scale_idx(i: int) -> void:
	i = clampi(i, 0, SCALES.size() - 1)
	if i == scale_idx:
		return
	scale_idx = i
	scale_changed.emit(time_scale())
	emit_event("time_scale", {"scale": time_scale()})


func clock_text(t := -1.0) -> String:
	if t < 0.0:
		t = game_time
	var s := int(START_CLOCK + t)
	var day := s / 86400 + 1
	s = s % 86400
	return "D%d %02d:%02d:%02d" % [day, s / 3600, (s / 60) % 60, s % 60]


func age_text(seconds: float) -> String:
	var s := int(seconds)
	if s < 3600:
		return "%d:%02d" % [s / 60, s % 60]
	return "%dh%02d" % [s / 3600, (s / 60) % 60]


func emit_event(kind: String, data: Dictionary) -> void:
	event.emit(kind, data)


func add_log(who: String, text: String, warn := false) -> void:
	log_lines.append({"t": game_time, "who": who, "text": text, "warn": warn})
	if log_lines.size() > 60:
		log_lines.pop_front()


func select(i: int) -> void:
	selected = clampi(i, -1, drones.size() - 1)
	selection_changed.emit()


func selected_drone() -> DroneSim:
	if selected < 0 or selected >= drones.size():
		return null
	return drones[selected]


func orders_locked(d: DroneSim) -> bool:
	return d != null and d.airborne() and d.link == DroneSim.Link.LOST


## Add a waypoint for the selected unit. Returns false when the order could not be sent.
func order_point(p: Vector2) -> bool:
	if not terrain.in_bounds(p, 150.0):
		return false
	if selected == -1:
		carrier.course.append(p)
		emit_event("helm_course", {"count": carrier.course.size()})
		return true
	var d := selected_drone()
	if d == null or d.state in [DroneSim.State.DESTROYED, DroneSim.State.REBUILD]:
		return false
	if orders_locked(d):
		emit_event("orders_locked", {"drone": d})
		return false
	d.plan.append({"pos": p, "act": tool_act, "roe": tool_roe})
	d.set_plan_changed()
	emit_event("waypoint_added", {"drone": d})
	return true


func undo_point() -> void:
	if selected == -1:
		if not carrier.course.is_empty():
			carrier.course.pop_back()
		return
	var d := selected_drone()
	if d == null or orders_locked(d):
		if d:
			emit_event("orders_locked", {"drone": d})
		return
	if d.plan.size() > d.wp:
		d.plan.pop_back()


func clear_orders() -> void:
	if selected == -1:
		carrier.course.clear()
		emit_event("helm_course_clear", {})
		return
	var d := selected_drone()
	if d == null:
		return
	if orders_locked(d):
		emit_event("orders_locked", {"drone": d})
		return
	d.plan.resize(mini(d.wp, d.plan.size()))
	d.set_plan_changed()


func launch(i: int) -> void:
	var d := drones[i]
	if d.state != DroneSim.State.READY:
		emit_event("cannot_launch", {"drone": d})
		return
	d.launch(self)
	emit_event("launch", {"drone": d})


func rtb(i: int) -> void:
	var d := drones[i]
	if orders_locked(d):
		emit_event("orders_locked", {"drone": d})
		return
	d.start_rtb(self, "ordered")


func set_throttle(t: int) -> void:
	var was_stopped := carrier.throttle == 0
	if carrier.set_throttle(t):
		emit_event("helm_throttle", {"throttle": t, "restart": was_stopped and t > 0})


func set_alert(on: bool) -> void:
	if alert == on:
		return
	alert = on
	emit_event("alert", {"on": on})


func pad_pos(pad: int) -> Vector2:
	var a := deg_to_rad([60.0, 190.0, 300.0][pad % 3])
	# Blender pad sockets at (cos a, sin a) * 11 m -> Godot (x, -y)
	return Terrain.CAMP + Vector2(cos(a) * 11.0, -sin(a) * 11.0) * 1.0


func patrol_centre(group: int) -> Vector2:
	match group:
		0: return Vector2(-600.0, -2000.0)
		1: return Vector2(2000.0, -500.0)
		_: return Vector2(800.0, -2900.0)


func nearest_drone(p: Vector2, r: float) -> DroneSim:
	var best: DroneSim = null
	var bd := r
	for d in drones:
		if d.state in [DroneSim.State.ACTIVE, DroneSim.State.RTB, DroneSim.State.FINAL]:
			var dist := d.pos2().distance_to(p)
			if dist < bd:
				bd = dist
				best = d
	return best


func drone_fired_on(d: DroneSim, from: Vector2) -> void:
	var first: bool = d.under_fire <= 0.01 or not d.get_meta("warned", false)
	if d.state != DroneSim.State.ACTIVE:
		return
	if d.current_roe() == DroneSim.Roe.FLEE and d.mode != "evade":
		d.mode = "evade"
		d.mode_timer = 25.0
		d.evade_from = from
		emit_event("breaking_off", {"drone": d})
	elif first:
		d.set_meta("warned", true)
		emit_event("under_fire", {"drone": d})


# ------------------------------------------------------------------ main loop

func _physics_process(delta: float) -> void:
	if not running:
		return
	var total := delta * time_scale()
	var steps := int(ceil(total / 0.5))
	var dt := total / steps
	for i in steps:
		_step(dt)
	_know_timer -= delta
	if _know_dirty and _know_timer <= 0.0:
		_upload_know()
		_know_timer = 0.25


func _step(dt: float) -> void:
	game_time += dt
	carrier.step(dt, self)
	for d in drones:
		d.step(dt, self)
		if d.get_meta("warned", false) and d.under_fire <= 0.0:
			d.set_meta("warned", false)
	for d_id in shadows.keys():
		var s: DroneSim = shadows[d_id]
		s.step(dt, self)
	for r in raiders:
		r.step(dt, self)
	_update_links()
	_update_sensors(dt)
	_update_raids(dt)
	_update_losses()


func _update_links() -> void:
	var c := carrier.pos2()
	for d in drones:
		if not d.airborne():
			if d.link != DroneSim.Link.OK:
				d.link = DroneSim.Link.OK
				shadows.erase(d.id)
			continue
		var dist := d.pos2().distance_to(c)
		var old := d.link
		match d.link:
			DroneSim.Link.OK:
				if dist > LINK_OK:
					d.link = DroneSim.Link.WEAK
			DroneSim.Link.WEAK:
				if dist > LINK_MAX:
					d.link = DroneSim.Link.LOST
				elif dist < LINK_OK - 150.0:
					d.link = DroneSim.Link.OK
			DroneSim.Link.LOST:
				if dist < LINK_MAX - 200.0:
					d.link = DroneSim.Link.WEAK
		if old != d.link:
			if d.link == DroneSim.Link.LOST:
				shadows[d.id] = d.copy_for_shadow()
				emit_event("link_lost", {"drone": d})
			elif old == DroneSim.Link.LOST:
				shadows.erase(d.id)
				var n := d.buffered.size()
				for rid in d.buffered.keys():
					var b: Dictionary = d.buffered[rid]
					_report_contact(rid, b.pos, Vector3.ZERO, b.time, false, true)
				d.buffered.clear()
				emit_event("link_restored", {"drone": d, "burst": n})
				if d.get_meta("saw_node", false) and not node_found:
					node_found = true
					emit_event("node_found", {"drone": d, "bearing": Terrain.bearing_deg(c, Terrain.CAMP)})
			elif d.link == DroneSim.Link.WEAK and old == DroneSim.Link.OK:
				emit_event("link_weak", {"drone": d})


func _update_sensors(dt: float) -> void:
	_new_burst = maxf(0.0, _new_burst - dt)
	# terrain knowledge
	_stamp(carrier.pos2(), CarrierSim.SENSOR_RANGE)
	for d in drones:
		if d.state in [DroneSim.State.ACTIVE, DroneSim.State.RTB, DroneSim.State.FINAL]:
			_stamp(d.pos2(), d.sensor_range())
	# contacts
	var c := carrier.pos2()
	for r in raiders:
		var p := r.pos2()
		var live := p.distance_to(c) < CarrierSim.SENSOR_RANGE
		var seen_close := false
		for d in drones:
			if not (d.state in [DroneSim.State.ACTIVE, DroneSim.State.RTB, DroneSim.State.FINAL]):
				continue
			var dist := p.distance_to(d.pos2())
			if dist < d.sensor_range():
				if d.link == DroneSim.Link.LOST:
					d.buffered[r.id] = {"pos": r.pos, "time": game_time}
				else:
					live = true
					if dist < 800.0:
						seen_close = true
		if live:
			_report_contact(r.id, r.pos, r.vel, game_time, true, false, seen_close)
		elif contacts.has(r.id) and contacts[r.id].live and game_time - contacts[r.id].last > 2.0:
			contacts[r.id].live = false
			emit_event("contact_lost", {"id": r.id, "bearing": Terrain.bearing_deg(c, Vector2(contacts[r.id].pos.x, contacts[r.id].pos.z))})
	# the recharge node: reported live, or held in the drone's buffer until the link returns
	if not node_found:
		for d in drones:
			if d.airborne() and d.pos2().distance_to(Terrain.CAMP) < d.sensor_range() + 150.0:
				if d.link == DroneSim.Link.LOST:
					d.set_meta("saw_node", true)
				else:
					node_found = true
					emit_event("node_found", {"drone": d, "bearing": Terrain.bearing_deg(c, Terrain.CAMP)})
					break
	if _new_count > 0 and _new_burst <= 0.0:
		var data := _new_first.duplicate()
		data["count"] = _new_count
		emit_event("contact_new", data)
		if time_scale() > 1:
			set_scale_idx(0)
			emit_event("tc_drop", {})
		_new_count = 0


func _report_contact(rid: int, p: Vector3, v: Vector3, t: float, live: bool, from_burst: bool, close := false) -> void:
	var existed := contacts.has(rid)
	var fresh: bool = not existed or (live and not contacts[rid].live and game_time - contacts[rid].last > 60.0)
	if not existed:
		contacts[rid] = {"id": rid, "pos": p, "vel": v, "last": t, "live": live, "first": t, "class": "HOVER"}
	else:
		var c: Dictionary = contacts[rid]
		if t >= c.last:
			c.pos = p
			c.vel = v
			c.last = t
		if live:
			c.live = true
	if close and contacts[rid]["class"] == "HOVER":
		contacts[rid]["class"] = "RAIDER"
		emit_event("contact_class", {"id": rid})
	if live and fresh and not from_burst:
		if _new_count == 0:
			_new_first = {"id": rid, "bearing": Terrain.bearing_deg(carrier.pos2(), Vector2(p.x, p.z)),
				"range": carrier.pos2().distance_to(Vector2(p.x, p.z))}
		_new_count += 1
		_new_burst = 2.0


func _update_raids(dt: float) -> void:
	_raid_timer -= dt * carrier.SIGNATURE[carrier.throttle] / 0.45
	if _raid_timer > 0.0:
		return
	_raid_timer = _rng.randf_range(900.0, 1500.0)
	var picked := false
	for r in raiders:
		if r.group == _raid_group and r.energy > 0.5 and r.state in [RaiderSim.State.PATROL, RaiderSim.State.RECHARGE]:
			r.start_raid()
			picked = true
	_raid_group = (_raid_group + 1) % 3
	if not picked:
		_raid_timer = 120.0


func _update_losses() -> void:
	for d in drones:
		if d.state == DroneSim.State.DESTROYED:
			if not d.has_meta("lost_at"):
				d.set_meta("lost_at", game_time)
			elif game_time - d.get_meta("lost_at") > 30.0:
				d.remove_meta("lost_at")
				shadows.erase(d.id)
				d.begin_rebuild()
				emit_event("rebuild_start", {"drone": d})
	for rid in contacts.keys():
		var c: Dictionary = contacts[rid]
		if not c.live and game_time - c.last > GHOST_FADE:
			contacts.erase(rid)


# ------------------------------------------------------------------ knowledge grid

func _stamp(p: Vector2, r: float) -> void:
	var cell := Terrain.SIZE / KNOW_RES
	var cx := (p.x + Terrain.HALF) / cell
	var cz := (p.y + Terrain.HALF) / cell
	var rc := r / cell
	var x0 := maxi(0, int(cx - rc))
	var x1 := mini(KNOW_RES - 1, int(cx + rc))
	var z0 := maxi(0, int(cz - rc))
	var z1 := mini(KNOW_RES - 1, int(cz + rc))
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2(x + 0.5 - cx, z + 0.5 - cz).length() / rc
			if d < 1.0:
				var v := clampf((1.0 - d) * 3.0, 0.0, 1.0)
				var k := z * KNOW_RES + x
				if v > know[k]:
					know[k] = v
					_know_dirty = true


func _upload_know() -> void:
	var bytes := PackedByteArray()
	bytes.resize(KNOW_RES * KNOW_RES)
	for i in know.size():
		bytes[i] = int(know[i] * 255.0)
	know_img.set_data(KNOW_RES, KNOW_RES, false, Image.FORMAT_L8, bytes)
	know_tex.update(know_img)
	_know_dirty = false
	knowledge_changed.emit()


func known_at(p: Vector2) -> float:
	var cell := Terrain.SIZE / KNOW_RES
	var x := clampi(int((p.x + Terrain.HALF) / cell), 0, KNOW_RES - 1)
	var z := clampi(int((p.y + Terrain.HALF) / cell), 0, KNOW_RES - 1)
	return know[z * KNOW_RES + x]
