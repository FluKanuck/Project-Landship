class_name SimCore
extends Node
## The war, as data. Runs the carrier, drones, logistics vehicles, structures and raiders;
## owns sensors, contacts, ghost markers, the data link network, the stores, the
## fabricator, the fit, the resource sites, the enemy economy, knowledge of the terrain and
## time compression. Everything the player sees on the bridge reads from here. Autoloaded
## as `Sim`.

signal event(kind: String, data: Dictionary)
signal knowledge_changed
signal scale_changed(scale: int)
signal selection_changed

const SCALES := [1, 4, 16, 64]
const KNOW_RES := 128
const GHOST_FADE := 900.0 # seconds of game time until a ghost is gone
const START_CLOCK := 14 * 3600 + 20 * 60
const VEH_SEL := 100 # selection index of vehicle i is VEH_SEL + i
const HUB_RAID_START := 3.0 * 3600.0 # the aliens take this long to notice our network
const PD_CD := 2.0
const PD_HIT := 0.12
const CRANE_PLANT_RANGE := 450.0

var terrain: Terrain
var carrier: CarrierSim
var drones: Array[DroneSim] = []
var shadows := {} # drone id -> DroneSim predicted copy (only while the link is lost)
var raiders: Array[RaiderSim] = []
var contacts := {} # raider id -> Dictionary

var fitting: Fitting
var stores: Stores
var fab: Fabricator
var net := LinkNet.new()
var sites: Array[SiteSim] = []
var structures: Array[StructureSim] = []
var vehicles: Array[VehicleSim] = []
var kit_bay := {} # Logi.Kind -> count of finished kits aboard
var crane_user := -1 # vehicle id on the crane, -1 when free
var alien_stock := Logi.ALIEN_START_STOCK
var pd_shots: Array = []
var kills := 0

var game_time := 0.0
var scale_idx := 0
var running := false
var selected := 0 # drone index, -1 for the carrier, VEH_SEL + i for vehicle i
var tool_act := DroneSim.Act.MOVE
var tool_roe := DroneSim.Roe.RTRN
var tool_vact := VehicleSim.Act.MOVE
var tool_kit := Logi.Kind.RELAY
var node_found := false
var first_hub := false
var first_delivery := false
var node_destroyed := false
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
var _hub_raid_timer := HUB_RAID_START
var _new_burst := 0.0
var _new_count := 0
var _new_first := {}
var _rng := RandomNumberGenerator.new()
var _struct_uid := 0
var _pd_cd := 0.0
var _respawn_timer := Logi.RAIDER_RESPAWN
var _hauler_n := 0
var _lifter_n := 0


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
	fitting = Fitting.new(Logi.LANDSHIP_SLOTS, Logi.START_FIT)
	stores = Stores.new(fitting)
	fab = Fabricator.new()
	carrier = CarrierSim.new(terrain, Terrain.CARRIER_START)
	carrier.stores = stores
	carrier.course.append(Terrain.CARRIER_START + Vector2(0, -2200))
	for i in 2:
		var d := DroneSim.new()
		d.id = i
		d.callsign = "SWIFT-%d" % (i + 1)
		d.spoken = "swift_%d" % (i + 1)
		drones.append(d)
		d.step(0.0, self)
	_build_sites()
	var hauler := add_vehicle(Logi.Veh.HAULER)
	hauler.utility = "pod"
	var lifter := add_vehicle(Logi.Veh.LIFTER)
	lifter.utility = "sling"
	kit_bay = {Logi.Kind.EXTRACTOR: 1, Logi.Kind.TURRET: 1, Logi.Kind.PAD: 1, Logi.Kind.RELAY: 1, Logi.Kind.SCANNER: 1}
	var node := structure_at_site(Logi.Kind.ALIEN_NODE, Logi.Owner.ALIEN, Terrain.CAMP)
	node.build = 1.0
	var groups := [[0, 0], [0, 1], [1, 2], [1, 0], [2, 1]] # [group, pad]
	for i in groups.size():
		var r := RaiderSim.new()
		r.id = i
		r.group = groups[i][0]
		r.pad = groups[i][1]
		r.rng.seed = 100 + i
		r.home = node.id
		var p := r.home_pos(self) + Vector2(_rng.randf_range(-40, 40), _rng.randf_range(-40, 40))
		r.pos = Vector3(p.x, terrain.height_at(p.x, p.y) + 1.4, p.y)
		r.timer = 30.0 + i * 70.0
		r.energy = 1.0
		raiders.append(r)
	net.rebuild(self)
	_stamp(carrier.pos2(), carrier_sensor())
	_upload_know()


func _build_sites() -> void:
	var seeds := [
		{"pos": Terrain.MINE, "kind": Logi.SiteKind.MAT, "name": "MINE", "richness": 1.25},
		{"pos": Terrain.OASIS, "kind": Logi.SiteKind.FUEL, "name": "OASIS", "richness": 1.2},
		{"pos": Terrain.CAMP, "kind": Logi.SiteKind.MIXED, "name": "CAMP", "owner": Logi.Owner.ALIEN, "richness": 1.5},
	]
	var names := ["WRECK A", "WRECK B", "WRECK C", "WRECK D"]
	for i in Terrain.WRECKS.size():
		seeds.append({"pos": Terrain.WRECKS[i], "kind": Logi.SiteKind.MAT, "name": names[i], "richness": 0.6, "salvage": 35.0})
	var t := terrain
	var valid := func(p: Vector2) -> bool:
		if not t.in_bounds(p, 600.0):
			return false
		if p.distance_to(Terrain.OASIS) < 700.0:
			return false
		return t.slope_at(p.x, p.y) < 0.3
	var gen := SiteGen.generate(Terrain.HALF, Terrain.CARRIER_START, Terrain.CAMP, seeds, valid)
	for i in gen.size():
		var g: Dictionary = gen[i]
		var s := SiteSim.new()
		s.id = i
		s.pos = g.pos
		s.kind = g.kind
		s.name = g.name
		s.richness = g.richness
		s.owner = g.owner
		s.salvage = g.salvage
		sites.append(s)
		if s.owner == Logi.Owner.ALIEN and s.name != "CAMP":
			var op := structure_at_site(Logi.Kind.ALIEN_OUTPOST, Logi.Owner.ALIEN, s.pos + Vector2(25, -15))
			op.build = 1.0
			s.stock = [20.0, 20.0]


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


func carrier_sensor() -> float:
	return float(fitting.stat("sensor_range"))


func link_range() -> float:
	return float(fitting.stat("link_range"))


## 0..1 signal quality at a point (1 well inside the network, 0 outside it).
func link_quality(p: Vector2) -> float:
	return clampf(net.margin(p) / LinkNet.WEAK_MARGIN, 0.0, 1.0)


var _last_objective := ""


func _objective_check() -> void:
	var o := objective()
	if o != _last_objective:
		_last_objective = o
		emit_event("objective", {"text": o})


func objective() -> String:
	if not node_found:
		return "LOCATE THE RAIDER BASE"
	if not first_hub:
		return "ESTABLISH AN EXTRACTION HUB"
	if not first_delivery:
		return "RUN A SUPPLY LOAD TO THE LANDSHIP"
	if not node_destroyed:
		return "DESTROY THE RECHARGE NODE"
	return "ALL OBJECTIVES COMPLETE"


func select(i: int) -> void:
	if i >= VEH_SEL:
		i = clampi(i, VEH_SEL, VEH_SEL + vehicles.size() - 1)
	else:
		i = clampi(i, -1, drones.size() - 1)
	selected = i
	selection_changed.emit()


func selected_drone() -> DroneSim:
	if selected < 0 or selected >= drones.size():
		return null
	return drones[selected]


func selected_vehicle() -> VehicleSim:
	var i := selected - VEH_SEL
	if i < 0 or i >= vehicles.size():
		return null
	return vehicles[i]


func selected_name() -> String:
	if selected == -1:
		return "LANDSHIP"
	var v := selected_vehicle()
	if v:
		return v.callsign
	var d := selected_drone()
	return d.callsign if d else "-"


func orders_locked(d) -> bool:
	if d is VehicleSim:
		return d.is_out() and d.link == DroneSim.Link.LOST
	return d != null and d.airborne() and d.link == DroneSim.Link.LOST


## Add a waypoint for the selected unit. Returns false when the order could not be sent.
func order_point(p: Vector2) -> bool:
	if not terrain.in_bounds(p, 150.0):
		return false
	if selected == -1:
		carrier.course.append(p)
		emit_event("helm_course", {"count": carrier.course.size()})
		return true
	var v := selected_vehicle()
	if v:
		if v.state == VehicleSim.State.DESTROYED:
			return false
		if orders_locked(v):
			emit_event("orders_locked", {"veh": v})
			return false
		var q := p
		if tool_vact in [VehicleSim.Act.LOAD, VehicleSim.Act.LOOT]:
			var s := site_at(p, 500.0)
			if s:
				q = s.pos
		v.plan.append({"pos": q, "act": tool_vact, "roe": tool_roe, "kit": tool_kit if tool_vact == VehicleSim.Act.BUILD else -1})
		v.set_plan_changed()
		emit_event("waypoint_added", {"veh": v})
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
	var v := selected_vehicle()
	if v:
		if orders_locked(v):
			emit_event("orders_locked", {"veh": v})
		elif v.plan.size() > (v.wp if v.is_out() else 0):
			v.plan.pop_back()
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
	var v := selected_vehicle()
	if v:
		if orders_locked(v):
			emit_event("orders_locked", {"veh": v})
			return
		v.plan.resize(mini(v.wp, v.plan.size()) if v.is_out() else 0)
		v.standing = false
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


func deploy_vehicle(v: VehicleSim) -> bool:
	if v.state != VehicleSim.State.STOWED:
		return false
	var ok := v.try_deploy(self)
	if not ok:
		emit_event("veh_cannot_deploy", {"veh": v, "why": v.note})
	return ok


func recall_vehicle(v: VehicleSim) -> void:
	if orders_locked(v):
		emit_event("orders_locked", {"veh": v})
		return
	v.standing = false
	v.go_home(self, "ordered")


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


## Nearest drone or vehicle a raider can see and shoot at.
func nearest_prey(p: Vector2, r: float):
	var best = null
	var bd := r
	for d in drones:
		if d.state in [DroneSim.State.ACTIVE, DroneSim.State.RTB, DroneSim.State.FINAL]:
			var dist := d.pos2().distance_to(p)
			if dist < bd:
				bd = dist
				best = d
	for v in vehicles:
		if v.state in [VehicleSim.State.ACTIVE, VehicleSim.State.HOME]:
			var dist := v.pos2().distance_to(p)
			if dist < bd:
				bd = dist
				best = v
	return best


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


# ------------------------------------------------------------------ logistics API

func add_vehicle(type: int) -> VehicleSim:
	var cs := ""
	if type == Logi.Veh.HAULER:
		_hauler_n += 1
		cs = "DRAY-%d" % _hauler_n
	else:
		_lifter_n += 1
		cs = "KITE-%d" % _lifter_n
	var v := VehicleSim.new(type, vehicles.size(), cs)
	v.bay_slot = _count_type(type) % 4
	vehicles.append(v)
	v.step(0.0, self)
	return v


func _count_type(type: int) -> int:
	var n := 0
	for v in vehicles:
		if v.type == type and v.state != VehicleSim.State.DESTROYED:
			n += 1
	return n


func air_count() -> int:
	var n := 0
	for d in drones:
		n += 1
	for v in vehicles:
		if v.type == Logi.Veh.LIFTER and v.state != VehicleSim.State.DESTROYED:
			n += 1
	return n


func hauler_bay() -> int:
	return 2 + fitting.tier_of("ramp") + 1


func air_room() -> bool:
	return air_count() < int(fitting.stat("air_capacity"))


func ground_room() -> bool:
	return _count_type(Logi.Veh.HAULER) < hauler_bay()


## Queue something in the fabricator. Returns false if it can't be built (no room aboard).
func queue_build(kind: String) -> bool:
	if kind == "lifter" and air_count() + fab.count("lifter") >= int(fitting.stat("air_capacity")):
		emit_event("fab_refused", {"name": "LIFTER", "why": "hangar full"})
		return false
	if kind == "hauler" and _count_type(Logi.Veh.HAULER) + fab.count("hauler") >= hauler_bay():
		emit_event("fab_refused", {"name": "HAULER", "why": "vehicle bay full"})
		return false
	if kind == "swift":
		emit_event("fab_refused", {"name": "SWIFT", "why": "replacements are built automatically"})
		return false
	fab.add(kind)
	emit_event("fab_queued", {"name": Logi.FAB[kind].name})
	return true


## Fabricate a module (tier 0) for an empty or occupied slot, or the next tier of what's there.
func queue_module(slot: int, module: String, tier: int) -> bool:
	if not fitting.can_fit(slot, module):
		emit_event("fab_refused", {"name": Logi.MODULES[module].name, "why": "too big for that slot"})
		return false
	for it in fab.queue:
		if it.kind == "module" and it.data.slot == slot:
			emit_event("fab_refused", {"name": Logi.MODULES[module].name, "why": "slot already has work queued"})
			return false
	fab.add("module", {"slot": slot, "module": module, "tier": tier})
	emit_event("fab_queued", {"name": "%s %s" % [Logi.MODULES[module].name, Logi.tier_name(tier)]})
	return true


func remove_module(slot: int) -> void:
	var s: Dictionary = fitting.slots[slot]
	if s.module == "" or s.refit > 0.0:
		return
	var m: Dictionary = Logi.MODULES[s.module]
	var refund := 0.0
	for t in s.tier + 1:
		refund += m.cost[t]
	stores.put(Logi.Res.MAT, refund * Logi.REMOVE_REFUND)
	stores.delivered[Logi.Res.MAT] -= refund * Logi.REMOVE_REFUND
	fitting.begin_refit(slot, "", 0)
	emit_event("refit_start", {"slot": slot, "module": ""})


func refit_vehicle(v: VehicleSim, utility: String, gun: bool) -> bool:
	if v.state != VehicleSim.State.STOWED or not Logi.UTILITY[utility]["for"].has(v.type):
		return false
	if gun and not v.gun:
		if not stores.has(Logi.Res.MAT, Logi.GUN_COST):
			emit_event("fab_refused", {"name": "LIGHT GUN", "why": "not enough materials"})
			return false
		stores.take(Logi.Res.MAT, Logi.GUN_COST)
	v.next_utility = utility
	v.next_gun = gun
	v.refit = Logi.VEH_REFIT_TIME
	return true


func fab_done(it: Dictionary) -> void:
	match it.kind:
		"module":
			var slot: int = it.data.slot
			var s: Dictionary = fitting.slots[slot]
			if s.module == it.data.module and it.data.tier > 0:
				fitting.set_tier(slot, it.data.tier)
				emit_event("module_upgraded", {"name": it.name})
			else:
				fitting.begin_refit(slot, it.data.module, it.data.tier)
				emit_event("refit_start", {"slot": slot, "module": it.data.module})
		"swift":
			var d: DroneSim = drones[it.data.drone]
			d.finish_rebuild(self)
		"hauler", "lifter":
			var v := add_vehicle(Logi.Veh.HAULER if it.kind == "hauler" else Logi.Veh.LIFTER)
			if it.kind == "lifter":
				v.utility = "pod"
			emit_event("fab_done", {"name": v.callsign})
		_:
			var k: int = Logi.FAB[it.kind].kind
			kit_bay[k] = kit_bay.get(k, 0) + 1
			emit_event("fab_done", {"name": it.name})


func take_kit(k: int) -> bool:
	if kit_bay.get(k, 0) > 0:
		kit_bay[k] -= 1
		return true
	return false


func return_kit(k: int) -> void:
	kit_bay[k] = kit_bay.get(k, 0) + 1


func kits_total() -> int:
	var n := 0
	for k in kit_bay:
		n += kit_bay[k]
	return n


func site_at(p: Vector2, r := Logi.SITE_RADIUS) -> SiteSim:
	var best: SiteSim = null
	var bd := r
	for s in sites:
		var d := s.pos.distance_to(p)
		if d < bd:
			bd = d
			best = s
	return best


func structure_by_id(i: int) -> StructureSim:
	if i < 0:
		return null
	for s in structures:
		if s.id == i:
			return s
	return null


func structure_at_site(k: int, owner: int, p: Vector2) -> StructureSim:
	var s := StructureSim.new(k, owner, p, self)
	s.id = _struct_uid
	_struct_uid += 1
	var site := site_at(p, Logi.SITE_RADIUS + 60.0)
	if site:
		s.site = site.id
	structures.append(s)
	return s


## Why a kit can't go down at `p`, or "" if it can.
func plant_problem(k: int, p: Vector2) -> String:
	if not terrain.in_bounds(p, 300.0):
		return "outside the survey"
	for s in structures:
		if not s.dead and s.pos.distance_to(p) < 45.0:
			return "too close to another structure"
	if Logi.STRUCT[k].get("on_site", false):
		var site := site_at(p)
		if site == null:
			return "hub parts need a resource site"
		if site.owner == Logi.Owner.ALIEN:
			return "site is held by the enemy"
		if k == Logi.Kind.EXTRACTOR and site.find(self, Logi.Kind.EXTRACTOR, false):
			return "site already has an extractor"
	if terrain.slope_at(p.x, p.y) > 0.45:
		return "ground too steep"
	return ""


## Put a kit down at `p` (by a vehicle, or by the crane when `by` is null).
func plant(k: int, p: Vector2, by: VehicleSim) -> StructureSim:
	var why := plant_problem(k, p)
	if why != "":
		emit_event("plant_failed", {"veh": by, "kind": k, "why": why})
		return null
	var s := structure_at_site(k, Logi.Owner.PLAYER, p)
	if s.site >= 0:
		sites[s.site].owner = Logi.Owner.PLAYER
	emit_event("planted", {"veh": by, "kind": k, "site": sites[s.site] if s.site >= 0 else null})
	return s


## Landship crane: plant a kit from the bay within reach of the hull, at crawl or stopped.
func crane_plant(k: int, p: Vector2) -> bool:
	if not fitting.has("crane"):
		emit_event("plant_failed", {"kind": k, "why": "no crane rig fitted"})
		return false
	if carrier.speed > CarrierSim.SPEEDS[1] + 0.3:
		emit_event("plant_failed", {"kind": k, "why": "too fast: crawl or stop to use the crane"})
		return false
	if p.distance_to(carrier.pos2()) > CRANE_PLANT_RANGE:
		emit_event("plant_failed", {"kind": k, "why": "out of crane reach"})
		return false
	if kit_bay.get(k, 0) <= 0:
		emit_event("plant_failed", {"kind": k, "why": "no %s kit aboard" % Logi.KIND_NAMES[k]})
		return false
	var s := plant(k, p, null)
	if s == null:
		return false
	take_kit(k)
	s.set_meta("crane", true)
	return true


## Which way a hauler can leave or come aboard right now: "ramp", "crane" or "".
func hauler_gate(v: VehicleSim, deploying: bool) -> String:
	var spd := carrier.speed
	var stern := carrier.to_world(VehicleSim.STERN_LOCAL)
	if fitting.has("ramp") and spd <= CarrierSim.SPEEDS[1] + 0.3 and terrain.good_ground(stern.x, stern.z):
		return "ramp"
	if fitting.has("crane") and spd <= CarrierSim.SPEEDS[2] + 0.3 and (crane_user == -1 or crane_user == v.id):
		return "crane"
	return ""


func gate_reason(deploying: bool) -> String:
	if not fitting.has("ramp") and not fitting.has("crane"):
		return "RAMP OR CRANE"
	if carrier.speed > CarrierSim.SPEEDS[2] + 0.3:
		return "CRANE (TOO FAST)"
	if crane_user != -1:
		return "CRANE (BUSY)"
	return "RAMP (GROUND)" if fitting.has("ramp") else "CRANE"


func nearest_alien_home(p: Vector2) -> StructureSim:
	var best: StructureSim = null
	var bd := INF
	for s in structures:
		if s.is_alien() and s.online() and s.kind in [Logi.Kind.ALIEN_NODE, Logi.Kind.ALIEN_OUTPOST]:
			var d := s.pos.distance_to(p)
			if d < bd:
				bd = d
				best = s
	return best


func can_settle(site: SiteSim, _r: RaiderSim) -> bool:
	for s in site.structures(self):
		if not s.is_alien():
			return false
	return site.owner != Logi.Owner.ALIEN


## The outpost under construction at a site (planted by the first raider that settles it).
func settle(site: SiteSim, r: RaiderSim) -> StructureSim:
	for s in site.structures(self):
		if s.kind == Logi.Kind.ALIEN_OUTPOST:
			return s
		if not s.is_alien():
			return null
	var op := structure_at_site(Logi.Kind.ALIEN_OUTPOST, Logi.Owner.ALIEN, site.pos + Vector2(25, -15))
	emit_event("alien_settling", {"site": site, "seen": site.linked})
	return op


func site_cleared(site: SiteSim) -> void:
	if site.owner == Logi.Owner.ALIEN:
		site.owner = Logi.Owner.NONE
		emit_event("site_cleared", {"site": site})


func structure_online(s: StructureSim) -> void:
	if s.is_alien():
		if s.kind == Logi.Kind.ALIEN_OUTPOST and s.site >= 0:
			sites[s.site].owner = Logi.Owner.ALIEN
			emit_event("alien_outpost", {"site": sites[s.site], "seen": net.covers(s.pos)})
		return
	emit_event("structure_online", {"s": s, "site": sites[s.site] if s.site >= 0 else null})
	if s.kind == Logi.Kind.EXTRACTOR and not first_hub:
		first_hub = true
		_objective_check()


func structure_hit(s: StructureSim) -> void:
	if s.linked and not s.has_meta("hit_called"):
		s.set_meta("hit_called", true)
		emit_event("structure_attacked", {"s": s, "site": sites[s.site] if s.site >= 0 else null})


func structure_destroyed(s: StructureSim, by_alien: bool) -> void:
	var site: SiteSim = sites[s.site] if s.site >= 0 else null
	if s.is_alien():
		if site:
			site.salvage += Logi.SALVAGE_FACILITY
			if s.kind == Logi.Kind.ALIEN_NODE:
				site.salvage += 60.0
				site.stock[1] += alien_stock * 0.3
				alien_stock *= 0.7
				node_destroyed = true
		emit_event("alien_structure_destroyed", {"s": s, "site": site})
		if site and site.owner == Logi.Owner.ALIEN:
			var any := false
			for o in site.structures(self):
				if o.is_alien():
					any = true
			if not any:
				site.owner = Logi.Owner.NONE if site.lootable() <= 0.01 else Logi.Owner.ALIEN
				emit_event("site_cleared" if site.owner == Logi.Owner.NONE else "site_lootable", {"site": site})
		return
	# ours: tell the bridge if we can hear it, otherwise it is found out later
	if s.linked or s.kind == Logi.Kind.RELAY:
		emit_event("structure_lost", {"s": s, "site": site})
	if site:
		var any := false
		for o in site.structures(self):
			if not o.is_alien():
				any = true
		if not any and site.owner == Logi.Owner.PLAYER:
			site.owner = Logi.Owner.NONE
			site.salvage += 10.0


func raider_killed(r: RaiderSim) -> void:
	kills += 1
	var s := site_at(r.pos2(), 600.0)
	if s:
		s.salvage += 6.0 + r.loot[0] * 0.5 + r.loot[1] * 0.5
	emit_event("raider_killed", {"id": r.id, "seen": net.covers(r.pos2())})
	if contacts.has(r.id):
		contacts.erase(r.id)


func hubs() -> Array[SiteSim]:
	var out: Array[SiteSim] = []
	for s in sites:
		if s.owner == Logi.Owner.PLAYER:
			out.append(s)
	return out


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
	fitting.step(dt, self)
	fab.step(dt, self)
	stores.step(dt)
	net.rebuild(self)
	for d in drones:
		d.step(dt, self)
		if d.get_meta("warned", false) and d.under_fire <= 0.0:
			d.set_meta("warned", false)
	for d_id in shadows.keys():
		var s: DroneSim = shadows[d_id]
		s.step(dt, self)
	for v in vehicles:
		v.step(dt, self)
	for s in structures:
		s.step(dt, self)
	for r in raiders:
		r.step(dt, self)
	_update_links()
	_update_sites(dt)
	_update_sensors(dt)
	_point_defence(dt)
	_update_raids(dt)
	_update_hub_raids(dt)
	_alien_economy(dt)
	_update_losses()


func _link_state(cur: int, m: float) -> int:
	match cur:
		DroneSim.Link.OK:
			if m < LinkNet.WEAK_MARGIN:
				return DroneSim.Link.WEAK
		DroneSim.Link.WEAK:
			if m < 0.0:
				return DroneSim.Link.LOST
			elif m > LinkNet.WEAK_MARGIN + 150.0:
				return DroneSim.Link.OK
		DroneSim.Link.LOST:
			if m > 200.0:
				return DroneSim.Link.WEAK
	return cur


func _update_links() -> void:
	var c := carrier.pos2()
	for d in drones:
		if not d.airborne():
			if d.link != DroneSim.Link.OK:
				d.link = DroneSim.Link.OK
				shadows.erase(d.id)
			continue
		var old := d.link
		d.link = _link_state(d.link, net.margin(d.pos2()))
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
				var found: Array = d.get_meta("sites", [])
				for sid in found:
					_discover(sites[sid], true)
				d.set_meta("sites", [])
				emit_event("link_restored", {"drone": d, "burst": n})
				if d.get_meta("saw_node", false) and not node_found:
					node_found = true
					emit_event("node_found", {"drone": d, "bearing": Terrain.bearing_deg(c, Terrain.CAMP)})
					_objective_check()
			elif d.link == DroneSim.Link.WEAK and old == DroneSim.Link.OK:
				emit_event("link_weak", {"drone": d})
	for v in vehicles:
		if not v.is_out():
			v.link = DroneSim.Link.OK
			continue
		var old := v.link
		v.link = _link_state(v.link, net.margin(v.pos2()))
		if v.link != DroneSim.Link.LOST:
			v.last_known = v.pos2()
			v.last_known_t = game_time
		if old != v.link:
			if v.link == DroneSim.Link.LOST:
				emit_event("veh_link_lost", {"veh": v})
			elif old == DroneSim.Link.LOST:
				for rid in v.buffered.keys():
					_report_contact(rid, v.buffered[rid].pos, Vector3.ZERO, v.buffered[rid].time, false, true)
				emit_event("veh_link_restored", {"veh": v, "burst": v.buffered.size()})
				v.buffered.clear()
	# scanners that come back into the network dump what they saw while dark
	for s in structures:
		if s.kind == Logi.Kind.SCANNER and s.online() and s.linked and not s.buffered.is_empty():
			var n := s.buffered.size()
			for rid in s.buffered.keys():
				var b: Dictionary = s.buffered[rid]
				_report_contact(rid, b.pos, Vector3.ZERO, b.time, false, true)
			s.buffered.clear()
			emit_event("scanner_burst", {"s": s, "burst": n})


func _update_sites(dt: float) -> void:
	for s in sites:
		s.under_attack = maxf(0.0, s.under_attack - dt)
		if s.owner == Logi.Owner.PLAYER:
			var ext := s.find(self, Logi.Kind.EXTRACTOR)
			if ext:
				for r in 2:
					s.stock[r] = minf(Logi.STOCK_CAP, s.stock[r] + s.yield_per_s(r) * dt)
			var was := s.linked
			s.linked = net.covers(s.pos)
			if s.linked:
				s.observe(self)
				if not was and s.known_time >= 0.0 and s.has_meta("was_linked"):
					emit_event("hub_linked", {"site": s})
			elif was:
				emit_event("hub_dark", {"site": s})
			if s.linked:
				s.set_meta("was_linked", true)
			if ext and s.stock[0] + s.stock[1] >= Logi.STOCK_CAP * (1.0 if s.kind != Logi.SiteKind.MIXED else 1.6) - 0.1 and not s.get_meta("full_called", false):
				s.set_meta("full_called", true)
				if s.linked:
					emit_event("hub_full", {"site": s})
			elif s.stock[0] + s.stock[1] < Logi.STOCK_CAP * 0.5:
				s.set_meta("full_called", false)
		else:
			s.linked = false
		# crane-planted kits are assembled while the hull is alongside
		for st in s.structures(self):
			if st.has_meta("crane") and st.build < 1.0 and st.pos.distance_to(carrier.pos2()) < CRANE_PLANT_RANGE + 80.0 and fitting.has("crane"):
				st.assist = maxf(st.assist, 1.0 / (float(fitting.stat("crane_time")) * 2.0))
	for st in structures:
		if st.site < 0 and st.has_meta("crane") and st.build < 1.0 and st.pos.distance_to(carrier.pos2()) < CRANE_PLANT_RANGE + 80.0 and fitting.has("crane"):
			st.assist = maxf(st.assist, 1.0 / (float(fitting.stat("crane_time")) * 2.0))


func _sensors() -> Array:
	# [pos, range, linked, owner object]
	var out := [[carrier.pos2(), carrier_sensor(), true, carrier]]
	for d in drones:
		if d.state in [DroneSim.State.ACTIVE, DroneSim.State.RTB, DroneSim.State.FINAL]:
			out.append([d.pos2(), d.sensor_range(), d.link != DroneSim.Link.LOST, d])
	for v in vehicles:
		if v.state in [VehicleSim.State.ACTIVE, VehicleSim.State.HOME]:
			out.append([v.pos2(), v.sensor_range(), v.link != DroneSim.Link.LOST, v])
	for s in structures:
		if s.kind == Logi.Kind.SCANNER and s.online() and not s.is_alien():
			out.append([s.pos, s.sensor_range(), s.linked, s])
	return out


func _discover(s: SiteSim, from_burst := false) -> void:
	if s.discovered:
		return
	s.discovered = true
	s.observe(self)
	emit_event("site_found", {"site": s, "burst": from_burst, "bearing": Terrain.bearing_deg(carrier.pos2(), s.pos)})


func _update_sensors(dt: float) -> void:
	_new_burst = maxf(0.0, _new_burst - dt)
	var sens := _sensors()
	# terrain knowledge
	for sn in sens:
		_stamp(sn[0], sn[1])
	# sites: discovered and observed under linked coverage; dark sensors remember for later
	for s in sites:
		for sn in sens:
			if s.pos.distance_to(sn[0]) < sn[1] + 150.0:
				if sn[2]:
					_discover(s)
					if s.owner != Logi.Owner.PLAYER:
						s.observe(self)
				elif sn[3] is DroneSim:
					var l: Array = sn[3].get_meta("sites", [])
					if not l.has(s.id):
						l.append(s.id)
						sn[3].set_meta("sites", l)
	# contacts
	var c := carrier.pos2()
	for r in raiders:
		if not r.alive():
			continue
		var p := r.pos2()
		var live := false
		var seen_close := false
		for sn in sens:
			var dist := p.distance_to(sn[0])
			if dist < sn[1]:
				if not sn[2]:
					sn[3].buffered[r.id] = {"pos": r.pos, "time": game_time}
				else:
					live = true
					if dist < 800.0 and not (sn[3] is CarrierSim):
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
					_objective_check()
					break
		for sn in sens:
			if sn[2] and not node_found and sn[0].distance_to(Terrain.CAMP) < sn[1] + 150.0:
				node_found = true
				emit_event("node_found", {"drone": null, "bearing": Terrain.bearing_deg(c, Terrain.CAMP)})
				_objective_check()
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


func _point_defence(dt: float) -> void:
	_pd_cd = maxf(0.0, _pd_cd - dt)
	var rng_m: float = fitting.stat("pd_range")
	if rng_m <= 0.0 or _pd_cd > 0.0:
		return
	var c := carrier.pos2()
	var best: RaiderSim = null
	var bd := rng_m
	for r in raiders:
		if r.alive() and r.pos2().distance_to(c) < bd:
			bd = r.pos2().distance_to(c)
			best = r
	var from := carrier.to_world(Vector3(0, 60, -40))
	var tier := fitting.tier_of("pd")
	if best:
		_pd_cd = PD_CD / (1.0 + tier * 0.3)
		pd_shots.append({"from": from, "to": best.pos})
		if _rng.randf() < PD_HIT * (1.0 - bd / rng_m * 0.4):
			best.take_hit(self, c)
		return
	for s in structures:
		if s.is_alien() and not s.dead and s.pos.distance_to(c) < rng_m:
			_pd_cd = PD_CD * 1.5
			pd_shots.append({"from": from, "to": s.pos3(self) + Vector3.UP * 5.0})
			if _rng.randf() < 0.6:
				s.take_hit(self, false)
			return


func _update_raids(dt: float) -> void:
	_raid_timer -= dt * carrier.SIGNATURE[carrier.throttle] / 0.45 * float(fitting.stat("signature_mult"))
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


## The aliens go after the network: rich or weakly defended hubs, and the relays that
## hold it together.
func _update_hub_raids(dt: float) -> void:
	if not first_hub:
		return
	_hub_raid_timer -= dt
	if _hub_raid_timer > 0.0:
		return
	_hub_raid_timer = _rng.randf_range(1800.0, 3000.0)
	var best_score := -INF
	var best_site := -1
	var best_struct := -1
	for s in sites:
		if s.owner != Logi.Owner.PLAYER:
			continue
		var h := nearest_alien_home(s.pos)
		if h == null:
			continue
		var score: float = s.stock[0] + s.stock[1] - h.pos.distance_to(s.pos) / 120.0
		if s.find(self, Logi.Kind.TURRET, false) == null:
			score += 60.0
		score += _rng.randf_range(0.0, 30.0)
		if score > best_score:
			best_score = score
			best_site = s.id
			best_struct = -1
	for st in structures:
		if st.kind == Logi.Kind.RELAY and st.online() and not st.is_alien():
			var h := nearest_alien_home(st.pos)
			if h == null:
				continue
			var score: float = 40.0 - h.pos.distance_to(st.pos) / 120.0 + _rng.randf_range(0.0, 40.0)
			if score > best_score:
				best_score = score
				best_site = st.site
				best_struct = st.id
	if best_site < 0 and best_struct < 0:
		return
	var sent := 0
	for r in raiders:
		if sent >= 3:
			break
		if r.alive() and r.energy > 0.55 and r.state in [RaiderSim.State.PATROL, RaiderSim.State.RECHARGE]:
			r.start_assault(best_site, best_struct)
			sent += 1
	if sent == 0:
		_hub_raid_timer = 300.0
	else:
		emit_event("alien_assault", {"site": sites[best_site] if best_site >= 0 else null, "count": sent})


func _alien_economy(dt: float) -> void:
	for s in structures:
		if s.is_alien() and s.online() and s.kind == Logi.Kind.ALIEN_NODE:
			alien_stock += Logi.NODE_YIELD / 3600.0 * dt
		if s.is_alien() and s.online() and s.kind == Logi.Kind.ALIEN_OUTPOST:
			var y := Logi.OUTPOST_YIELD / 3600.0 * dt
			alien_stock += y * 0.6
			if s.site >= 0:
				var site: SiteSim = sites[s.site]
				site.stock[1] = minf(60.0, site.stock[1] + y * 0.4)
	_respawn_timer -= dt
	if _respawn_timer > 0.0:
		return
	_respawn_timer = Logi.RAIDER_RESPAWN
	for r in raiders:
		if not r.alive() and game_time - r.died_at > 600.0 and alien_stock >= Logi.RAIDER_COST:
			var h := nearest_alien_home(r.pos2())
			if h:
				alien_stock -= Logi.RAIDER_COST
				r.respawn(self, h)
				emit_event("raider_respawn", {"id": r.id})
				return


func _update_losses() -> void:
	for d in drones:
		if d.state == DroneSim.State.DESTROYED:
			if not d.has_meta("lost_at"):
				d.set_meta("lost_at", game_time)
			elif game_time - d.get_meta("lost_at") > 30.0:
				d.remove_meta("lost_at")
				shadows.erase(d.id)
				d.begin_rebuild()
				var it := fab.add("swift", {"drone": d.id})
				fab.promote(it.uid)
				d.set_meta("fab_uid", it.uid)
				emit_event("rebuild_start", {"drone": d, "cost": it.cost})
		elif d.state == DroneSim.State.REBUILD and d.has_meta("fab_uid"):
			var uid: int = d.get_meta("fab_uid")
			var head := fab.head()
			if not head.is_empty() and head.uid == uid and not head.paid:
				d.timer = -1.0
			else:
				d.timer = fab.eta(uid, float(fitting.stat("fab_speed")))
	for rid in contacts.keys():
		var c: Dictionary = contacts[rid]
		if not c.live and game_time - c.last > GHOST_FADE:
			contacts.erase(rid)
	# bookkeeping for the first delivery objective
	if not first_delivery:
		for v in vehicles:
			if v.hauled[0] + v.hauled[1] > 0.0:
				first_delivery = true
				break
	_objective_check()


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
