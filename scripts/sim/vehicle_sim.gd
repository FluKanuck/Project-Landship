class_name VehicleSim
extends RefCounted
## A logistics vehicle: the HAULER (ground; cargo pod or engineer kit) or the LIFTER (air;
## cargo pod or sling). Both fly or drive a waypoint chain like the Swifts, with logistics
## actions, and either can run it as a standing route that repeats without the
## commander's attention. Either can carry a light gun.

enum State { STOWED, DEPLOY, ACTIVE, HOME, BOARDING, DESTROYED }
enum Act { MOVE, LOAD, BUILD, LOOT, HOME }
const ACT_NAMES := ["MOVE", "LOAD", "BUILD", "LOOT", "HOME"]
const STATE_NAMES := ["ABOARD", "DEPLOYING", "ACTIVE", "RETURNING", "BOARDING", "LOST"]

const TURN_GROUND := 0.45 # rad/s
const TURN_AIR := deg_to_rad(18.0)
const HAULER_TANK := 25.0
const LOAD_WAIT := 900.0 # longest a hauler waits at an empty pad before leaving with what it has
const TURNAROUND := 60.0
const DEPLOY_TIME := 25.0
const DECK_TIME := 20.0
# landship sockets (local, metres)
const STERN_LOCAL := Vector3(0.0, 0.0, 200.0)
const CRANE_LOCAL := Vector3(70.0, 0.0, 20.0)

var id := 0
var type := Logi.Veh.HAULER
var callsign := "DRAY-1"
var state := State.STOWED
var pos := Vector3.ZERO
var heading := 0.0
var speed := 0.0
var hp := 8
var max_hp := 8
var utility := "pod"
var gun := false
var cargo := [0.0, 0.0]
var kits: Array[int] = []
var fuel := HAULER_TANK
var plan: Array[Dictionary] = [] # {pos, act, roe, kit}
var wp := 0
var standing := false
var link := DroneSim.Link.OK
var timer := 0.0
var mode := "" # "", "load", "build", "loot", "hold", "wait"
var board_mode := "" # "ramp", "crane", "deck"
var under_fire := 0.0
var evade_from := Vector2.ZERO
var fire_cd := 0.0
var last_known := Vector2.ZERO
var last_known_t := 0.0
var shots: Array = []
var buffered := {} # raider id -> {pos, time} seen while out of the network
var refit := 0.0
var next_utility := ""
var next_gun := false
var turnaround := 0.0
var note := "" # one-line reason when waiting, for the displays
var trips := 0
var hauled := [0.0, 0.0]
var bay_slot := 0
var _wait := 0.0
var _rng := RandomNumberGenerator.new()


func _init(t: int, i: int, cs: String) -> void:
	type = t
	id = i
	callsign = cs
	max_hp = Logi.VEHICLE[t].hp
	hp = max_hp
	utility = "pod"
	fuel = HAULER_TANK if t == Logi.Veh.HAULER else Logi.VEHICLE[t].endurance
	_rng.seed = 900 + i


func pos2() -> Vector2:
	return Vector2(pos.x, pos.z)


func is_hauler() -> bool:
	return type == Logi.Veh.HAULER


func is_out() -> bool:
	return state in [State.DEPLOY, State.ACTIVE, State.HOME, State.BOARDING]


func airborne() -> bool:
	return not is_hauler() and state in [State.DEPLOY, State.ACTIVE, State.HOME]


func cargo_total() -> float:
	return cargo[0] + cargo[1]


func cargo_cap() -> float:
	return Logi.VEHICLE[type].cargo if utility == "pod" else 0.0


func max_kits() -> int:
	return Logi.VEHICLE[type].kits if utility in ["engineer", "sling"] else 0


func sensor_range() -> float:
	return Logi.VEHICLE[type].sensor


func current_roe() -> int:
	if plan.is_empty():
		return DroneSim.Roe.RTRN
	return plan[clampi(wp, 0, plan.size() - 1)].roe


func endurance(sim: SimCore) -> float:
	if is_hauler():
		return HAULER_TANK
	return Logi.VEHICLE[type].endurance * float(sim.fitting.stat("endurance_mult"))


func fit_text() -> String:
	return Logi.UTILITY[utility].name + (" + GUN" if gun else "")


func status_text() -> String:
	match state:
		State.STOWED:
			if refit > 0.0:
				return "REFIT %d:%02d" % [int(refit) / 60, int(refit) % 60]
			if turnaround > 0.0:
				return "TURNAROUND %d:%02d" % [int(turnaround) / 60, int(turnaround) % 60]
			return "ABOARD" if note == "" else note
		State.DEPLOY: return "DEPLOYING"
		State.ACTIVE:
			if note != "":
				return note
			match mode:
				"load": return "LOADING %d/%d" % [int(cargo_total()), int(cargo_cap())]
				"build": return "ASSEMBLING"
				"loot": return "LOOTING %d/%d" % [int(cargo_total()), int(cargo_cap())]
				"hold": return "HOLDING"
				"evade": return "EVADING"
			return "EN ROUTE"
		State.HOME: return note if note != "" else ("LIMPING HOME" if is_hauler() and fuel <= 0.0 else "RETURNING")
		State.BOARDING: return {"ramp": "UP THE RAMP", "crane": "CRANE LIFT", "deck": "LANDING"}.get(board_mode, "BOARDING")
		State.DESTROYED: return "LOST"
	return "?"


# ------------------------------------------------------------------ orders

## Leave the landship and run the plan. Returns false (with `note` set) if she can't go yet.
func try_deploy(sim: SimCore) -> bool:
	if state != State.STOWED or refit > 0.0:
		return false
	if plan.is_empty():
		note = "NO ORDERS"
		return false
	# take the kits the plan's BUILD points need
	for w in plan:
		if w.act == Act.BUILD and w.kit >= 0 and kits.count(w.kit) < _kits_needed(w.kit) and kits.size() < max_kits():
			if sim.take_kit(w.kit):
				kits.append(w.kit)
	if is_hauler():
		var how := sim.hauler_gate(self, true)
		if how == "":
			note = "AWAITING " + sim.gate_reason(true)
			return false
		board_mode = how
		if how == "crane":
			sim.crane_user = id
		timer = DEPLOY_TIME if how == "ramp" else float(sim.fitting.stat("crane_time")) * 0.5
	else:
		board_mode = "deck"
		timer = DECK_TIME
	state = State.DEPLOY
	note = ""
	wp = 0
	mode = ""
	_wait = 0.0
	sim.emit_event("veh_deploy", {"veh": self})
	return true


func _kits_needed(k: int) -> int:
	var n := 0
	for w in plan:
		if w.act == Act.BUILD and w.kit == k:
			n += 1
	return n


func go_home(sim: SimCore, why := "") -> void:
	if state in [State.ACTIVE, State.DEPLOY]:
		state = State.HOME
		mode = ""
		note = ""
		sim.emit_event("veh_home", {"veh": self, "why": why})


func set_plan_changed() -> void:
	if state == State.ACTIVE and mode == "hold":
		mode = ""


# ------------------------------------------------------------------ the tick

func step(dt: float, sim: SimCore) -> void:
	fire_cd = maxf(0.0, fire_cd - dt)
	under_fire = maxf(0.0, under_fire - dt)
	match state:
		State.STOWED:
			_stowed(dt, sim)
		State.DEPLOY:
			_deploy(dt, sim)
		State.ACTIVE:
			_active(dt, sim)
		State.HOME:
			_home(dt, sim)
		State.BOARDING:
			_boarding(dt, sim)
		State.DESTROYED:
			if not is_hauler():
				pos.y = maxf(pos.y - 40.0 * dt, sim.terrain.height_at(pos.x, pos.z))
			return
	if state in [State.ACTIVE, State.HOME]:
		_gun(sim)
		if is_hauler():
			fuel -= speed * dt / 1000.0 * Logi.VEHICLE[type].fuel_per_km
		else:
			fuel -= dt
		if fuel <= 0.0:
			if is_hauler():
				fuel = 0.0
				if state == State.ACTIVE:
					standing = false
					go_home(sim, "fuel")
			else:
				destroy(sim, "fuel")
		elif state == State.ACTIVE and not is_hauler():
			var home := pos2().distance_to(sim.carrier.pos2())
			if fuel < home / Logi.VEHICLE[type].speed + 240.0:
				go_home(sim, "bingo")


func _park(sim: SimCore) -> void:
	var c: CarrierSim = sim.carrier
	if is_hauler():
		pos = c.to_world(Vector3(-24.0 + bay_slot * 16.0, 8.0, 150.0))
	else:
		pos = c.to_world(CarrierSim.RECOVER_LOCAL + Vector3(18.0 + bay_slot * 12.0, 0.0, -40.0))
	heading = c.heading
	speed = 0.0


func _stowed(dt: float, sim: SimCore) -> void:
	_park(sim)
	# refuel and repair from the holds
	var full := endurance(sim)
	if fuel < full:
		var per_u := 1.0 if is_hauler() else 3600.0 / (Logi.DRONE_FUEL_PER_HOUR * 1.5)
		var want := minf(full - fuel, dt * full / 120.0)
		var got := sim.stores.take(Logi.Res.FUEL, want / per_u)
		fuel += got * per_u
	if hp < max_hp and sim.stores.has(Logi.Res.MAT, 1.0):
		timer -= dt
		if timer <= 0.0:
			sim.stores.take(Logi.Res.MAT, 2.0)
			hp += 1
			timer = 60.0
	if refit > 0.0:
		refit -= dt
		if refit <= 0.0:
			refit = 0.0
			utility = next_utility
			gun = next_gun
			for k in kits:
				sim.return_kit(k)
			kits.clear()
			sim.emit_event("veh_refit", {"veh": self})
		return
	if turnaround > 0.0:
		turnaround -= dt
		if turnaround <= 0.0 and standing:
			try_deploy(sim)
		return
	if note.begins_with("AWAITING") and not plan.is_empty():
		try_deploy(sim)


func _deploy(dt: float, sim: SimCore) -> void:
	timer -= dt
	var c: CarrierSim = sim.carrier
	if is_hauler():
		var p := c.to_world(STERN_LOCAL if board_mode == "ramp" else CRANE_LOCAL)
		pos = Vector3(p.x, sim.terrain.height_at(p.x, p.z), p.z)
		heading = c.heading + (PI if board_mode == "ramp" else PI * 0.5)
		speed = c.speed
	else:
		var p := c.to_world(CarrierSim.RECOVER_LOCAL)
		pos = Vector3(p.x, p.y + (DECK_TIME - timer) * 4.0, p.z)
		heading = c.heading
	if timer <= 0.0:
		state = State.ACTIVE
		if board_mode == "crane" and sim.crane_user == id:
			sim.crane_user = -1


func _active(dt: float, sim: SimCore) -> void:
	note = ""
	if mode == "evade":
		timer -= dt
		_move_to(pos2() + (pos2() - evade_from).normalized() * 800.0, dt, sim)
		if timer <= 0.0:
			go_home(sim, "evade")
		return
	if wp >= plan.size():
		if standing and plan.size() > 0:
			wp = 0
		else:
			mode = "hold"
			speed = move_toward(speed, 0.0, 2.0 * dt) if is_hauler() else speed
			if not is_hauler():
				_move_to(pos2() + Vector2(sin(heading + 0.6), -cos(heading + 0.6)) * 300.0, dt, sim)
			return
	var w: Dictionary = plan[wp]
	if w.act == Act.HOME:
		go_home(sim)
		return
	var d := _move_to(w.pos, dt, sim) if mode == "" else pos2().distance_to(w.pos)
	if mode == "" and d > (45.0 if is_hauler() else 90.0):
		return
	speed = 0.0 if is_hauler() else move_toward(speed, 0.0, 8.0 * dt)
	match w.act:
		Act.MOVE:
			wp += 1
		Act.LOAD:
			_load(dt, sim, w)
		Act.BUILD:
			_build(dt, sim, w)
		Act.LOOT:
			_loot(dt, sim, w)


func _next() -> void:
	mode = ""
	_wait = 0.0
	wp += 1


func _load(dt: float, sim: SimCore, w: Dictionary) -> void:
	var s := sim.site_at(w.pos, Logi.SITE_RADIUS + 120.0)
	if mode != "load":
		mode = "load"
		_wait = 0.0
		if s == null or s.owner != Logi.Owner.PLAYER or s.find(sim, Logi.Kind.PAD) == null:
			sim.emit_event("veh_cannot", {"veh": self, "what": "load", "why": "no pad"})
			_route_broken(sim)
			return
		if not s.linked:
			sim.emit_event("veh_cannot", {"veh": self, "what": "load", "why": "hub dark"})
			_next()
			return
		if s.find(sim, Logi.Kind.EXTRACTOR) == null and s.stock[0] + s.stock[1] < 1.0:
			sim.emit_event("veh_cannot", {"veh": self, "what": "load", "why": "nothing to load"})
			_next()
			return
	if s == null or s.find(sim, Logi.Kind.PAD) == null or not s.linked:
		_next()
		return
	_wait += dt
	var room := cargo_cap() - cargo_total()
	var rate := Logi.LOAD_RATE * dt
	var moved := 0.0
	for r in 2:
		var n := minf(minf(rate, s.stock[r]), room - moved)
		if n > 0.0:
			s.stock[r] -= n
			cargo[r] += n
			moved += n
	var empty: bool = s.stock[0] + s.stock[1] < 0.5
	if cargo_total() >= cargo_cap() - 0.5:
		sim.emit_event("veh_loaded", {"veh": self, "site": s})
		_next()
	elif empty and (_wait > LOAD_WAIT or (cargo_total() >= cargo_cap() * 0.5 and _wait > 120.0)):
		sim.emit_event("veh_loaded", {"veh": self, "site": s, "part": true})
		_next()


## A standing route that can't work any more (pad gone, site lost) is dropped, not looped.
func _route_broken(sim: SimCore) -> void:
	if standing:
		standing = false
		sim.emit_event("route_broken", {"veh": self})
		go_home(sim, "route")
	else:
		_next()


func _build(dt: float, sim: SimCore, w: Dictionary) -> void:
	if utility == "pod":
		if mode != "build":
			sim.emit_event("veh_cannot", {"veh": self, "what": "build", "why": "no kit fitted"})
		_next()
		return
	if mode != "build":
		mode = "build"
		if w.kit >= 0:
			if kits.has(w.kit):
				var st := sim.plant(w.kit, w.pos, self)
				if st:
					kits.erase(w.kit)
			else:
				sim.emit_event("veh_cannot", {"veh": self, "what": "build", "why": "no %s kit" % Logi.KIND_SHORT[w.kit]})
		if utility == "sling":
			_next()
			return
	# engineer: assemble everything unfinished nearby, then move on
	var busy := false
	for s in sim.structures:
		if not s.dead and s.build < 1.0 and s.owner == Logi.Owner.PLAYER and s.pos.distance_to(w.pos) < 320.0:
			if not Logi.STRUCT[s.kind].get("self_erect", false):
				s.assist = maxf(s.assist, 1.0 / Logi.ASSEMBLE_TIME)
				busy = true
	if not busy:
		_next()


func _loot(dt: float, sim: SimCore, w: Dictionary) -> void:
	var s := sim.site_at(w.pos, Logi.SITE_RADIUS + 150.0)
	if mode != "loot":
		mode = "loot"
		if s == null or s.lootable() <= 0.0:
			sim.emit_event("veh_cannot", {"veh": self, "what": "loot", "why": "nothing to take"})
			_next()
			return
	if s == null:
		_next()
		return
	for st in s.structures(sim):
		if st.is_alien():
			note = "SITE HOSTILE"
			return
	var room := cargo_cap() - cargo_total()
	var rate := Logi.LOAD_RATE * 2.0 * dt
	var moved := 0.0
	for r in 2:
		var n := minf(minf(rate, s.stock[r]), room - moved)
		if n > 0.0:
			s.stock[r] -= n
			cargo[r] += n
			moved += n
	var n2 := minf(minf(rate, s.salvage), room - moved)
	if n2 > 0.0:
		s.salvage -= n2
		cargo[1] += n2
		moved += n2
	if s.owner == Logi.Owner.ALIEN and s.lootable() <= 0.01:
		sim.site_cleared(s)
	if cargo_total() >= cargo_cap() - 0.5 or s.lootable() <= 0.01:
		sim.emit_event("veh_looted", {"veh": self, "site": s})
		_next()


func _home(dt: float, sim: SimCore) -> void:
	var c: CarrierSim = sim.carrier
	if not is_hauler():
		var rec := c.to_world(CarrierSim.RECOVER_LOCAL)
		var d := _move_to(Vector2(rec.x, rec.z), dt, sim, maxf(c.speed + 10.0, 14.0) if pos2().distance_to(Vector2(rec.x, rec.z)) < 400.0 else -1.0)
		if d < 60.0:
			state = State.BOARDING
			board_mode = "deck"
			timer = DECK_TIME
		return
	var how := sim.hauler_gate(self, false)
	note = ""
	if how == "":
		note = "AWAITING " + sim.gate_reason(false)
		# keep station astern until a way aboard opens
		var wait := c.to_world(STERN_LOCAL + Vector3(0, 0, 220))
		_move_to(Vector2(wait.x, wait.z), dt, sim, c.speed if pos2().distance_to(Vector2(wait.x, wait.z)) < 80.0 else -1.0)
		return
	var tgt := c.to_world(STERN_LOCAL if how == "ramp" else CRANE_LOCAL + Vector3(30, 0, 0))
	var d := _move_to(Vector2(tgt.x, tgt.z), dt, sim, c.speed + 1.5 if pos2().distance_to(Vector2(tgt.x, tgt.z)) < 150.0 else -1.0)
	if d < 40.0:
		state = State.BOARDING
		board_mode = how
		if how == "crane":
			sim.crane_user = id
			timer = float(sim.fitting.stat("crane_time"))
		else:
			timer = float(sim.fitting.stat("ramp_time"))


func _boarding(dt: float, sim: SimCore) -> void:
	var c: CarrierSim = sim.carrier
	timer -= dt
	var k := clampf(1.0 - timer / 30.0, 0.0, 1.0)
	match board_mode:
		"ramp":
			var a := c.to_world(STERN_LOCAL)
			var b := c.to_world(Vector3(0, 8, 150))
			pos = a.lerp(b, k)
			pos.y = maxf(pos.y, sim.terrain.height_at(pos.x, pos.z))
			heading = c.heading
		"crane":
			var a := c.to_world(CRANE_LOCAL + Vector3(30, 0, 0))
			a.y = sim.terrain.height_at(a.x, a.z)
			pos = a + Vector3.UP * k * 55.0
		"deck":
			var rec := c.to_world(CarrierSim.RECOVER_LOCAL)
			pos = pos.lerp(rec, clampf(dt * 0.5, 0.0, 1.0))
			heading = c.heading
	if timer <= 0.0:
		if board_mode == "crane" and sim.crane_user == id:
			sim.crane_user = -1
		_arrive(sim)


func _arrive(sim: SimCore) -> void:
	state = State.STOWED
	mode = ""
	note = ""
	var got := [0.0, 0.0]
	for r in 2:
		got[r] = sim.stores.put(r, cargo[r])
		cargo[r] -= got[r]
		hauled[r] += got[r]
	trips += 1
	sim.emit_event("veh_aboard", {"veh": self, "fuel": got[0], "mat": got[1]})
	if standing and not plan.is_empty():
		turnaround = TURNAROUND
	else:
		plan.clear()
	wp = 0


# ------------------------------------------------------------------ movement

func _move_to(target: Vector2, dt: float, sim: SimCore, spd := -1.0) -> float:
	var to := target - pos2()
	var dist := to.length()
	var want := atan2(to.x, -to.y)
	var diff := wrapf(want - heading, -PI, PI)
	var turn := TURN_GROUND if is_hauler() else TURN_AIR
	heading = wrapf(heading + clampf(diff, -turn * dt, turn * dt), -PI, PI)
	var f := Vector2(sin(heading), -cos(heading))
	if is_hauler():
		var top: float = Logi.VEHICLE[type].speed
		var sl := sim.terrain.slope_at(pos.x + f.x * 30.0, pos.z + f.y * 30.0)
		if sl > 0.16:
			top = Logi.VEHICLE[type].rough_speed
		if sl > 0.35:
			top *= 0.5
		if spd >= 0.0:
			top = minf(top, spd)
		if absf(diff) > 1.2:
			top = minf(top, 3.0)
		if fuel <= 0.0:
			top = minf(top, 2.0) # limping home on the reserve cell
		speed = move_toward(speed, top, 1.5 * dt)
		var step := minf(speed * dt, dist + 1.0)
		var p := pos2() + f * step
		pos = Vector3(p.x, sim.terrain.height_at(p.x, p.y), p.y)
	else:
		var top: float = Logi.VEHICLE[type].speed if spd < 0.0 else spd
		speed = move_toward(speed, top, 5.0 * dt)
		var p := pos2() + f * minf(speed * dt, dist + 1.0)
		var ahead := p + f * 200.0
		var ground := maxf(sim.terrain.height_at(p.x, p.y), sim.terrain.height_at(ahead.x, ahead.y))
		var alt: float = Logi.VEHICLE[type].alt
		if dist < 300.0 and state == State.ACTIVE:
			alt = lerpf(40.0, alt, dist / 300.0)
		pos = Vector3(p.x, move_toward(pos.y, ground + alt, 12.0 * dt), p.y)
		pos.y = maxf(pos.y, ground + 20.0)
	return dist


# ------------------------------------------------------------------ fighting

func _gun(sim: SimCore) -> void:
	if not gun or fire_cd > 0.0:
		return
	var roe := current_roe()
	var target_pos := Vector3.INF
	var best := Logi.GUN_RANGE
	var rt: RaiderSim = null
	for r in sim.raiders:
		if r.alive():
			var d := r.pos2().distance_to(pos2())
			if d < best:
				best = d
				rt = r
	var st: StructureSim = null
	if rt == null and roe == DroneSim.Roe.FREE:
		for s in sim.structures:
			if s.is_alien() and not s.dead and s.pos.distance_to(pos2()) < Logi.GUN_RANGE:
				st = s
				break
	if rt == null and st == null:
		return
	fire_cd = Logi.GUN_CD
	if rt:
		shots.append({"from": pos + Vector3.UP * 3.0, "to": rt.pos})
		if _rng.randf() < Logi.GUN_HIT * (1.0 - best / Logi.GUN_RANGE * 0.5):
			rt.take_hit(sim, pos2())
		else:
			rt.shot_at(sim, pos2())
	else:
		shots.append({"from": pos + Vector3.UP * 3.0, "to": st.pos3(sim) + Vector3.UP * 4.0})
		if _rng.randf() < 0.5:
			st.take_hit(sim, false)


func take_hit(sim: SimCore, from: Vector2) -> void:
	hp -= 1
	fired_on(sim, from)
	if hp <= 0:
		destroy(sim, "shot")
	else:
		sim.emit_event("veh_damage", {"veh": self})


func fired_on(sim: SimCore, from: Vector2) -> void:
	var first := under_fire <= 0.01
	under_fire = 6.0
	if state != State.ACTIVE and state != State.HOME:
		return
	if current_roe() == DroneSim.Roe.FLEE and mode != "evade" and state == State.ACTIVE:
		mode = "evade"
		timer = 30.0
		evade_from = from
		sim.emit_event("veh_breaking", {"veh": self})
	elif first:
		sim.emit_event("veh_fire", {"veh": self})


func destroy(sim: SimCore, why: String) -> void:
	if state == State.DESTROYED:
		return
	if sim.crane_user == id:
		sim.crane_user = -1
	state = State.DESTROYED
	plan.clear()
	standing = false
	# what she carried spills onto the sand where she died
	var s := sim.site_at(pos2(), 400.0)
	if s:
		s.salvage += cargo[1] * 0.5
	cargo = [0.0, 0.0]
	kits.clear()
	sim.emit_event("veh_lost", {"veh": self, "why": why})
