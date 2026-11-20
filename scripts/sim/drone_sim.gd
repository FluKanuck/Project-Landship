class_name DroneSim
extends RefCounted
## A Swift scout. Flies a Carrier Command style waypoint chain: each waypoint has an action
## (MOVE / LOIT / SCAN) and rules of engagement (FREE / RTRN / FLEE).

enum State { READY, LAUNCH, ACTIVE, RTB, FINAL, REFUEL, DESTROYED, REBUILD }
enum Act { MOVE, LOIT, SCAN }
enum Roe { FREE, RTRN, FLEE }
enum Link { OK, WEAK, LOST }

const CRUISE := 42.0
const ORBIT_SPEED := 32.0
const ALT := 340.0
const SCAN_ALT := 240.0
const TURN := deg_to_rad(14.0)
const SENSOR := 1400.0
const SCAN_SENSOR := 1850.0
const ENDURANCE := 3600.0
const LOITER_TIME := 300.0
const SCAN_TIME := 240.0
const REFUEL_TIME := 180.0
const REBUILD_TIME := 1200.0

var id := 0
var callsign := "SWIFT-1"
var spoken := "swift_1"
var state := State.READY
var pos := Vector3.ZERO
var heading := 0.0
var speed := 0.0
var vspeed := 0.0
var bank := 0.0
var fuel := ENDURANCE
var hp := 3
var link := Link.OK
var plan: Array[Dictionary] = [] # {pos: Vector2, act: int, roe: int}
var wp := 0 # index of the waypoint being flown to
var mode := "" # "", "loiter", "scan", "hold", "evade"
var mode_timer := 0.0
var orbit_center := Vector2.ZERO
var orbit_r := 450.0
var orbit_dir := 1.0
var timer := 0.0
var under_fire := 0.0
var evade_from := Vector2.ZERO
var station_called := false
var buffered := {} # raider id -> {pos, time} seen while the link was down
var is_shadow := false # a predicted copy flown on the last orders we sent


func pos2() -> Vector2:
	return Vector2(pos.x, pos.z)


func airborne() -> bool:
	return state in [State.LAUNCH, State.ACTIVE, State.RTB, State.FINAL]


func sensor_range() -> float:
	return SCAN_SENSOR if mode == "scan" else SENSOR


func current_roe() -> int:
	if plan.is_empty():
		return Roe.RTRN
	return plan[clampi(wp, 0, plan.size() - 1)].roe


func status_text() -> String:
	match state:
		State.READY: return "READY"
		State.LAUNCH: return "LAUNCHING"
		State.ACTIVE:
			if mode == "loiter": return "LOITER"
			if mode == "scan": return "SCANNING"
			if mode == "hold": return "ON STATION"
			if mode == "evade": return "EVADING"
			return "EN ROUTE"
		State.RTB: return "RTB"
		State.FINAL: return "LANDING"
		State.REFUEL: return "REFUEL %d:%02d" % [int(timer) / 60, int(timer) % 60]
		State.DESTROYED: return "LOST"
		State.REBUILD: return "FAB %d:%02d" % [int(timer) / 60, int(timer) % 60]
	return "?"


func copy_for_shadow() -> DroneSim:
	var d := DroneSim.new()
	d.is_shadow = true
	d.id = id
	d.callsign = callsign
	d.state = state
	d.pos = pos
	d.heading = heading
	d.speed = speed
	d.plan = plan.duplicate(true)
	d.wp = wp
	d.mode = mode if mode != "evade" else ""
	d.mode_timer = mode_timer
	d.orbit_center = orbit_center
	d.orbit_r = orbit_r
	d.orbit_dir = orbit_dir
	d.fuel = fuel
	return d


# ------------------------------------------------------------------ flight

func step(dt: float, sim: SimCore) -> void:
	match state:
		State.READY:
			_park(sim)
		State.REFUEL:
			_park(sim)
			timer -= dt
			fuel = minf(ENDURANCE, fuel + ENDURANCE * dt / REFUEL_TIME)
			if timer <= 0.0:
				state = State.READY
				fuel = ENDURANCE
				hp = 3
				if not is_shadow:
					sim.emit_event("drone_ready", {"drone": self})
		State.REBUILD:
			timer -= dt
			if timer <= 0.0:
				state = State.READY
				fuel = ENDURANCE
				hp = 3
				plan.clear()
				_park(sim)
				sim.emit_event("drone_rebuilt", {"drone": self})
		State.DESTROYED:
			pos.y = maxf(pos.y - 60.0 * dt, sim.terrain.height_at(pos.x, pos.z))
		State.LAUNCH:
			_launch(dt, sim)
		State.ACTIVE:
			_active(dt, sim)
		State.RTB, State.FINAL:
			_rtb(dt, sim)
	if airborne() and not is_shadow:
		fuel -= dt
		if fuel <= 0.0:
			_destroy(sim, "fuel")
		elif state == State.ACTIVE:
			var home := pos2().distance_to(sim.carrier.pos2())
			if fuel < home / CRUISE + 300.0:
				start_rtb(sim, "bingo")


func _park(sim: SimCore) -> void:
	var c: CarrierSim = sim.carrier
	pos = c.to_world(CarrierSim.RECOVER_LOCAL + Vector3(-20.0 + id * 14.0, 0.0, 10.0))
	heading = c.heading
	speed = 0.0


func launch(sim: SimCore) -> void:
	state = State.LAUNCH
	timer = 0.0
	wp = 0
	mode = ""
	station_called = false
	var c: CarrierSim = sim.carrier
	pos = c.to_world(CarrierSim.LAUNCH_LOCAL)
	heading = c.heading
	speed = c.speed


func _launch(dt: float, sim: SimCore) -> void:
	var c: CarrierSim = sim.carrier
	timer += dt
	speed = minf(CRUISE, speed + 9.0 * dt)
	var f := Vector2(sin(heading), -cos(heading))
	var p := pos2() + f * speed * dt
	var deck := c.pos.y + 52.6
	var ground := sim.terrain.height_at(p.x, p.y)
	var climb := clampf((timer - 4.0) * 14.0, 0.0, 20.0)
	pos = Vector3(p.x, maxf(deck, pos.y + climb * dt), p.y)
	pos.y = maxf(pos.y, ground + 3.0)
	if pos.y - ground > 90.0:
		state = State.ACTIVE
		timer = 0.0


func _fly_to(target: Vector2, dt: float, sim: SimCore, alt: float, spd: float) -> float:
	var to := target - pos2()
	var want := atan2(to.x, -to.y)
	var diff := wrapf(want - heading, -PI, PI)
	var turn := clampf(diff, -TURN * dt, TURN * dt)
	heading = wrapf(heading + turn, -PI, PI)
	bank = lerpf(bank, clampf(diff * 1.4, -0.6, 0.6), clampf(dt * 2.0, 0.0, 1.0))
	speed = move_toward(speed, spd, 6.0 * dt)
	var f := Vector2(sin(heading), -cos(heading))
	var p := pos2() + f * speed * dt
	var ahead := p + f * 250.0
	var ground := maxf(sim.terrain.height_at(p.x, p.y), sim.terrain.height_at(ahead.x, ahead.y))
	var want_y := ground + alt
	vspeed = clampf((want_y - pos.y) * 0.25, -16.0, 22.0)
	pos = Vector3(p.x, maxf(pos.y + vspeed * dt, ground + 30.0), p.y)
	return to.length()


func _orbit(dt: float, sim: SimCore, alt: float) -> void:
	var rel := pos2() - orbit_center
	var ang := atan2(rel.y, rel.x) + orbit_dir * (ORBIT_SPEED / orbit_r) * dt * 1.6
	var target := orbit_center + Vector2(cos(ang), sin(ang)) * orbit_r
	_fly_to(target, dt, sim, alt, ORBIT_SPEED)


func _active(dt: float, sim: SimCore) -> void:
	under_fire = maxf(0.0, under_fire - dt)
	if mode == "evade":
		mode_timer -= dt
		var away := (pos2() - evade_from).normalized()
		_fly_to(pos2() + away * 1000.0, dt, sim, ALT + 80.0, CRUISE * 1.15)
		if mode_timer <= 0.0:
			mode = ""
			start_rtb(sim, "evade")
		return
	if mode == "loiter" or mode == "scan":
		mode_timer -= dt
		_orbit(dt, sim, SCAN_ALT if mode == "scan" else ALT)
		if mode_timer <= 0.0:
			mode = ""
			wp += 1
		return
	if mode == "hold" or wp >= plan.size():
		if mode != "hold":
			mode = "hold"
			orbit_center = plan[-1].pos if not plan.is_empty() else pos2()
			orbit_r = 500.0
			if not station_called and not is_shadow:
				station_called = true
				sim.emit_event("on_station", {"drone": self})
		_orbit(dt, sim, ALT)
		return
	var w: Dictionary = plan[wp]
	var d := _fly_to(w.pos, dt, sim, ALT, CRUISE)
	if d < 160.0:
		match w.act:
			Act.LOIT:
				mode = "loiter"
				mode_timer = LOITER_TIME
				orbit_center = w.pos
				orbit_r = 450.0
				if not is_shadow:
					sim.emit_event("loiter_start", {"drone": self})
			Act.SCAN:
				mode = "scan"
				mode_timer = SCAN_TIME
				orbit_center = w.pos
				orbit_r = 650.0
				if not is_shadow:
					sim.emit_event("scan_start", {"drone": self})
			_:
				wp += 1


func set_plan_changed() -> void:
	# new orders: leave holding/orbit modes and fly the chain from the first open point
	if state == State.ACTIVE and mode in ["hold", ""]:
		mode = ""
		station_called = false


func start_rtb(sim: SimCore, why := "") -> void:
	if not airborne():
		return
	state = State.RTB
	mode = ""
	if not is_shadow:
		sim.emit_event("rtb", {"drone": self, "why": why})


func _rtb(dt: float, sim: SimCore) -> void:
	var c: CarrierSim = sim.carrier
	var f := c.forward()
	var rec := c.to_world(CarrierSim.RECOVER_LOCAL)
	if state == State.RTB:
		var gate := Vector2(rec.x, rec.z) - f * 1400.0
		var d := _fly_to(gate, dt, sim, 180.0, CRUISE)
		if d < 220.0:
			state = State.FINAL
		return
	# final approach: line up behind the deck and descend onto it
	var target := Vector2(rec.x, rec.z)
	var to := target - pos2()
	var want := atan2(to.x, -to.y)
	heading = wrapf(heading + clampf(wrapf(want - heading, -PI, PI), -TURN * 1.5 * dt, TURN * 1.5 * dt), -PI, PI)
	bank = lerpf(bank, 0.0, clampf(dt * 2.0, 0.0, 1.0))
	speed = move_toward(speed, c.speed + 26.0, 5.0 * dt)
	var dir := Vector2(sin(heading), -cos(heading))
	var p := pos2() + dir * speed * dt
	var dist := to.length()
	var glide_y := rec.y + clampf(dist * 0.07, 0.0, 200.0)
	pos = Vector3(p.x, move_toward(pos.y, glide_y, 25.0 * dt), p.y)
	if dist < 40.0 or (to.dot(f) < 0.0 and dist < 120.0):
		if is_shadow:
			state = State.READY
			return
		state = State.REFUEL
		timer = REFUEL_TIME * (1.0 - fuel / ENDURANCE) + 30.0
		plan.clear()
		wp = 0
		mode = ""
		sim.emit_event("recovered", {"drone": self})


func take_hit(sim: SimCore, from: Vector2) -> void:
	hp -= 1
	under_fire = 6.0
	if hp <= 0:
		_destroy(sim, "shot")
		return
	sim.emit_event("damage", {"drone": self})


func _destroy(sim: SimCore, why: String) -> void:
	if is_shadow:
		return
	state = State.DESTROYED
	timer = 0.0
	sim.emit_event("drone_lost", {"drone": self, "why": why})


func begin_rebuild() -> void:
	state = State.REBUILD
	timer = REBUILD_TIME
