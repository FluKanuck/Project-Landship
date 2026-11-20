class_name RaiderSim
extends RefCounted
## Alien light raider. Hover is fast over sand but burns energy, so raiders patrol, dash in,
## sting, and run home to the recharge node.

enum State { RECHARGE, PATROL, RAID, RETREAT, CHASE }

const PATROL_SPEED := 26.0
const DASH_SPEED := 40.0
const DRAIN := 1.0 / 1500.0
const CHARGE := 1.0 / 260.0
const SEE_DRONE := 1300.0
const GUN_RANGE := 700.0

var id := 0
var group := 0
var pad := 0
var state := State.RECHARGE
var pos := Vector3.ZERO
var vel := Vector3.ZERO
var heading := 0.0
var energy := 1.0
var target := Vector2.ZERO
var timer := 0.0
var fire_cd := 0.0
var shots: Array = [] # visual: [{from, to, t}]
var rng := RandomNumberGenerator.new()


func pos2() -> Vector2:
	return Vector2(pos.x, pos.z)


func _move(dt: float, sim: SimCore, spd: float) -> float:
	var to := target - pos2()
	var d := to.length()
	if d > 1.0:
		var want := atan2(to.x, -to.y)
		heading = wrapf(heading + clampf(wrapf(want - heading, -PI, PI), -1.6 * dt, 1.6 * dt), -PI, PI)
	var f := Vector2(sin(heading), -cos(heading))
	var step := minf(spd * dt, d + 2.0)
	var p := pos2() + f * step
	var y := sim.terrain.height_at(p.x, p.y) + 1.4
	var newpos := Vector3(p.x, lerpf(pos.y, y, clampf(dt * 4.0, 0.0, 1.0)) if dt < 1.0 else y, p.y)
	vel = (newpos - pos) / maxf(dt, 0.001)
	pos = newpos
	energy = maxf(0.0, energy - DRAIN * dt * (spd / PATROL_SPEED))
	return d


func step(dt: float, sim: SimCore) -> void:
	fire_cd = maxf(0.0, fire_cd - dt)
	timer -= dt
	var node: Vector2 = sim.pad_pos(pad)
	# opportunistic: chase a drone we can see, if we have the energy
	if state in [State.PATROL, State.RAID] and energy > 0.3:
		var d := sim.nearest_drone(pos2(), SEE_DRONE)
		if d:
			state = State.CHASE
			timer = 50.0
	match state:
		State.RECHARGE:
			target = node
			if pos2().distance_to(node) > 30.0:
				_move(dt, sim, PATROL_SPEED)
			else:
				vel = Vector3.ZERO
				energy = minf(1.0, energy + CHARGE * dt)
				if energy >= 1.0 and timer <= 0.0:
					_new_patrol(sim)
		State.PATROL:
			if _move(dt, sim, PATROL_SPEED) < 120.0:
				_new_patrol(sim)
			if energy < 0.28:
				state = State.RETREAT
		State.RAID:
			var c2: Vector2 = sim.carrier.pos2()
			var away := (pos2() - c2).normalized()
			target = c2 + away * 2100.0
			if _move(dt, sim, DASH_SPEED) < 150.0:
				timer = 25.0
				state = State.RETREAT
			if energy < 0.2:
				state = State.RETREAT
		State.CHASE:
			var d = sim.nearest_drone(pos2(), SEE_DRONE * 1.3)
			if d == null or timer <= 0.0 or energy < 0.2:
				state = State.RETREAT
			else:
				target = d.pos2()
				var dist := _move(dt, sim, DASH_SPEED)
				if dist < GUN_RANGE and fire_cd <= 0.0:
					fire_cd = 1.4
					shots.append({"from": pos + Vector3.UP * 1.5, "to": d.pos, "t": 0.0})
					var p_hit := 0.2 if d.current_roe() == DroneSim.Roe.FREE else 0.11
					if rng.randf() < p_hit * (1.0 - dist / GUN_RANGE * 0.5):
						d.take_hit(sim, pos2())
					else:
						d.under_fire = 6.0
					sim.drone_fired_on(d, pos2())
		State.RETREAT:
			target = node
			if _move(dt, sim, DASH_SPEED if energy > 0.15 else PATROL_SPEED) < 40.0:
				state = State.RECHARGE
				timer = rng.randf_range(60.0, 200.0)


func _new_patrol(sim: SimCore) -> void:
	state = State.PATROL
	var centre: Vector2 = sim.patrol_centre(group)
	var a := rng.randf() * TAU
	var r := rng.randf_range(600.0, 2200.0)
	target = centre + Vector2(cos(a), sin(a)) * r
	target = target.clamp(Vector2(-4500, -4500), Vector2(4500, 4500))


func start_raid() -> void:
	state = State.RAID
	energy = maxf(energy, 0.6)
