class_name RaiderSim
extends RefCounted
## Alien light raider. Hover is fast over sand but burns energy, so raiders patrol, dash in,
## sting, and run home to recharge. Home is the recharge node or any outpost they have
## planted. Against our network they assault a hub (turret first), loot its stockpile,
## wreck what is left and settle the site with an outpost of their own. With no home left
## to recharge at they are stranded.

enum State { RECHARGE, PATROL, RAID, RETREAT, CHASE, ASSAULT, LOOT, SETTLE, STRANDED, DEAD }
const STATE_NAMES := ["RECHARGE", "PATROL", "RAID", "RETREAT", "CHASE", "ASSAULT", "LOOT", "SETTLE", "STRANDED", "DEAD"]

const PATROL_SPEED := 26.0
const DASH_SPEED := 40.0
const DRAIN := 1.0 / 1500.0
const CHARGE := 1.0 / 260.0
const SEE_DRONE := 1300.0
const GUN_RANGE := 700.0
const STRUCT_RANGE := 600.0

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
var hp := Logi.RAIDER_HP
var home := -1 # structure id of the node or outpost it recharges at
var loot := [0.0, 0.0]
var target_site := -1
var target_struct := -1
var died_at := -1.0
var hit_flash := 0.0


func pos2() -> Vector2:
	return Vector2(pos.x, pos.z)


func alive() -> bool:
	return state != State.DEAD


func home_struct(sim: SimCore) -> StructureSim:
	var h := sim.structure_by_id(home)
	if h == null or h.dead or not h.online():
		h = sim.nearest_alien_home(pos2())
		home = h.id if h else -1
	return h


func home_pos(sim: SimCore) -> Vector2:
	var h := home_struct(sim)
	if h == null:
		return Vector2.INF
	var a := deg_to_rad([60.0, 190.0, 300.0][pad % 3])
	var r := 11.0 if h.kind == Logi.Kind.ALIEN_NODE else 30.0
	return h.pos + Vector2(cos(a) * r, -sin(a) * r)


func _move(dt: float, sim: SimCore, spd: float) -> float:
	var to := target - pos2()
	var d := to.length()
	if d > 1.0:
		var want := atan2(to.x, -to.y)
		heading = wrapf(heading + clampf(wrapf(want - heading, -PI, PI), -1.6 * dt, 1.6 * dt), -PI, PI)
	if energy <= 0.0:
		spd = 3.0
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
	if state == State.DEAD:
		vel = Vector3.ZERO
		return
	fire_cd = maxf(0.0, fire_cd - dt)
	hit_flash = maxf(0.0, hit_flash - dt)
	timer -= dt
	var node := home_pos(sim)
	if node == Vector2.INF and state != State.STRANDED and state not in [State.ASSAULT, State.LOOT, State.SETTLE]:
		state = State.STRANDED
		sim.emit_event("raider_stranded", {"id": id})
	# opportunistic: chase a drone or vehicle we can see, if we have the energy
	if state in [State.PATROL, State.RAID] and energy > 0.3:
		var d = sim.nearest_prey(pos2(), SEE_DRONE)
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
			var d = sim.nearest_prey(pos2(), SEE_DRONE * 1.3)
			if d == null or timer <= 0.0 or energy < 0.2:
				state = State.RETREAT
			else:
				target = d.pos2()
				var dist := _move(dt, sim, DASH_SPEED)
				_shoot_prey(sim, d, dist)
		State.RETREAT:
			target = node
			if _move(dt, sim, DASH_SPEED if energy > 0.15 else PATROL_SPEED) < 40.0:
				state = State.RECHARGE
				timer = rng.randf_range(60.0, 200.0)
				if loot[0] + loot[1] > 0.0:
					sim.alien_stock += loot[0] + loot[1]
					sim.emit_event("alien_loot_home", {"id": id, "amount": loot[0] + loot[1]})
					loot = [0.0, 0.0]
		State.ASSAULT:
			_assault(dt, sim)
		State.LOOT:
			_loot(dt, sim)
		State.SETTLE:
			_settle(dt, sim)
		State.STRANDED:
			vel = Vector3.ZERO
			energy = maxf(0.0, energy - DRAIN * dt * 0.2)
			if node != Vector2.INF:
				state = State.RETREAT


func _shoot_prey(sim: SimCore, d, dist: float) -> void:
	if dist < GUN_RANGE and fire_cd <= 0.0:
		fire_cd = 1.4
		var dpos: Vector3 = d.pos
		shots.append({"from": pos + Vector3.UP * 1.5, "to": dpos, "t": 0.0})
		var roe_free: bool = d.current_roe() == DroneSim.Roe.FREE
		var p_hit := 0.2 if roe_free else 0.11
		if d is VehicleSim and d.is_hauler():
			p_hit = 0.3
		if rng.randf() < p_hit * (1.0 - dist / GUN_RANGE * 0.5):
			d.take_hit(sim, pos2())
		elif d is DroneSim:
			d.under_fire = 6.0
		if d is DroneSim:
			sim.drone_fired_on(d, pos2())
		elif d is VehicleSim and d.state != VehicleSim.State.DESTROYED:
			d.fired_on(sim, pos2())


func _pick_struct(sim: SimCore) -> StructureSim:
	if target_struct >= 0:
		var s := sim.structure_by_id(target_struct)
		if s and not s.dead:
			return s
		target_struct = -1
		if target_site < 0:
			return null
	if target_site < 0:
		return null
	var best: StructureSim = null
	var best_rank := 99
	for s in sim.sites[target_site].structures(sim):
		if s.is_alien():
			continue
		var rank: int = {Logi.Kind.TURRET: 0, Logi.Kind.PAD: 2, Logi.Kind.EXTRACTOR: 3}.get(s.kind, 4)
		if rank < best_rank:
			best_rank = rank
			best = s
	return best


func _assault(dt: float, sim: SimCore) -> void:
	var s := _pick_struct(sim)
	var site: SiteSim = sim.sites[target_site] if target_site >= 0 else null
	if s == null:
		if site and site.stock[0] + site.stock[1] > 1.0 and loot[0] + loot[1] < Logi.RAIDER_CARRY:
			state = State.LOOT
			return
		if site and site.owner != Logi.Owner.ALIEN and sim.can_settle(site, self):
			state = State.SETTLE
			return
		_go_home()
		return
	# defenders first: a living turret is shot before anything else; loot once it is gone
	if site and s.kind != Logi.Kind.TURRET and site.stock[0] + site.stock[1] > 1.0 and loot[0] + loot[1] < Logi.RAIDER_CARRY * 0.99:
		state = State.LOOT
		return
	var dist := pos2().distance_to(s.pos)
	if dist > STRUCT_RANGE * 0.85:
		target = s.pos
		_move(dt, sim, DASH_SPEED)
	else:
		# circle while firing so a turret has a moving target
		var rel := pos2() - s.pos
		var ang := atan2(rel.y, rel.x) + dt * 0.05
		target = s.pos + Vector2(cos(ang), sin(ang)) * STRUCT_RANGE * 0.7
		_move(dt, sim, PATROL_SPEED)
		if fire_cd <= 0.0:
			fire_cd = 1.6
			shots.append({"from": pos + Vector3.UP * 1.5, "to": s.pos3(sim) + Vector3.UP * 4.0, "t": 0.0})
			if rng.randf() < 0.45:
				s.take_hit(sim, true)
	# vehicles that come to help get shot
	var v = sim.nearest_prey(pos2(), GUN_RANGE)
	if v and fire_cd <= 0.0:
		_shoot_prey(sim, v, pos2().distance_to(v.pos2()))
	if energy < 0.12:
		_go_home()


func _loot(dt: float, sim: SimCore) -> void:
	var site: SiteSim = sim.sites[target_site]
	target = site.pos + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30))
	if pos2().distance_to(site.pos) > 80.0:
		_move(dt, sim, DASH_SPEED)
		return
	vel = Vector3.ZERO
	var rate := 0.5 * dt
	var took := false
	for r in 2:
		var n := minf(minf(rate, site.stock[r]), Logi.RAIDER_CARRY - loot[r])
		if n > 0.0:
			site.stock[r] -= n
			loot[r] += n
			took = true
	if not took:
		sim.emit_event("hub_looted", {"site": site, "by": id})
		state = State.ASSAULT


func _settle(dt: float, sim: SimCore) -> void:
	var site: SiteSim = sim.sites[target_site]
	var op := sim.settle(site, self)
	if op == null:
		_go_home()
		return
	target = op.pos + Vector2(20, 20)
	if pos2().distance_to(target) > 40.0:
		_move(dt, sim, PATROL_SPEED)
		return
	vel = Vector3.ZERO
	op.assist = maxf(op.assist, 1.0 / Logi.STRUCT[Logi.Kind.ALIEN_OUTPOST].build_time)
	energy = maxf(0.0, energy - DRAIN * dt * 0.3)
	if op.online():
		home = op.id
		target_site = -1
		state = State.RECHARGE
	elif energy < 0.1:
		_go_home()


func _go_home() -> void:
	target_site = -1
	target_struct = -1
	state = State.RETREAT


func _new_patrol(sim: SimCore) -> void:
	state = State.PATROL
	var centre: Vector2 = sim.patrol_centre(group)
	var h := home_struct(sim)
	if h and h.kind == Logi.Kind.ALIEN_OUTPOST:
		centre = centre.lerp(h.pos, 0.6)
	var a := rng.randf() * TAU
	var r := rng.randf_range(600.0, 2200.0)
	target = centre + Vector2(cos(a), sin(a)) * r
	var lim := Terrain.HALF - 500.0
	target = target.clamp(Vector2(-lim, -lim), Vector2(lim, lim))


func start_raid() -> void:
	state = State.RAID
	energy = maxf(energy, 0.6)


func start_assault(site: int, structure := -1) -> void:
	state = State.ASSAULT
	target_site = site
	target_struct = structure
	energy = maxf(energy, 0.7)


func shot_at(_sim: SimCore, _from: Vector2) -> void:
	hit_flash = 0.3


func take_hit(sim: SimCore, _from: Vector2) -> void:
	if state == State.DEAD:
		return
	hp -= 1
	hit_flash = 0.6
	if hp <= 0:
		state = State.DEAD
		died_at = sim.game_time
		vel = Vector3.ZERO
		sim.raider_killed(self)
	elif state in [State.PATROL, State.RECHARGE]:
		state = State.RETREAT


func respawn(sim: SimCore, h: StructureSim) -> void:
	state = State.RECHARGE
	hp = Logi.RAIDER_HP
	home = h.id
	energy = 0.5
	loot = [0.0, 0.0]
	target_site = -1
	target_struct = -1
	var p := home_pos(sim)
	pos = Vector3(p.x, sim.terrain.height_at(p.x, p.y) + 1.4, p.y)
	timer = 120.0
