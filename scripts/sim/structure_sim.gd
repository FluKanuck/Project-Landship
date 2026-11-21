class_name StructureSim
extends RefCounted
## Anything that stands on the sand: our hub parts (extractor, turret, pad), relays and
## scanner posts, and the aliens' recharge node and outposts. A planted kit starts at
## build 0 and is assembled (by the crane, an engineer, or by itself for relays and
## scanners) until it comes online.

var id := 0
var kind := Logi.Kind.RELAY
var owner := Logi.Owner.PLAYER
var pos := Vector2.ZERO
var site := -1
var hp := 1
var max_hp := 1
var build := 0.0 # 0..1
var dead := false
var linked := false
var range_mult := 1.0 # high-ground bonus for relays and scanners
var fire_cd := 0.0
var assist := 0.0 # assembly rate applied by a builder this tick (1/s fraction)
var shots: Array = [] # visual: [{from, to}]
var buffered := {} # scanner: raider id -> {pos, time} seen while unlinked
var died_at := -1.0
var _rng := RandomNumberGenerator.new()


func _init(k: int, o: int, p: Vector2, sim: SimCore) -> void:
	kind = k
	owner = o
	pos = p
	max_hp = Logi.STRUCT[k].hp
	hp = max_hp
	_rng.seed = hash(p)
	if k in [Logi.Kind.RELAY, Logi.Kind.SCANNER]:
		var rel := sim.terrain.relief_at(p)
		range_mult = 1.0 + clampf(rel / 10.0 * Logi.HIGH_GROUND_PER_10M, 0.0, Logi.HIGH_GROUND_CAP)


func online() -> bool:
	return build >= 1.0 and not dead


func name() -> String:
	return Logi.KIND_NAMES[kind]


func pos3(sim: SimCore) -> Vector3:
	return Vector3(pos.x, sim.terrain.height_at(pos.x, pos.y), pos.y)


func link_range() -> float:
	return Logi.STRUCT[Logi.Kind.RELAY].range * range_mult


func sensor_range() -> float:
	return Logi.STRUCT[Logi.Kind.SCANNER].sensor * range_mult


func is_alien() -> bool:
	return owner == Logi.Owner.ALIEN


func status_text() -> String:
	if dead:
		return "DESTROYED"
	if build < 1.0:
		return "BUILD %d%%" % int(build * 100.0)
	if hp < max_hp:
		return "DMG %d/%d" % [hp, max_hp]
	return "ONLINE"


func take_hit(sim: SimCore, by_alien: bool, dmg := 1) -> void:
	if dead:
		return
	hp -= dmg
	if site >= 0:
		sim.sites[site].under_attack = 90.0
	if hp <= 0:
		dead = true
		died_at = sim.game_time
		sim.structure_destroyed(self, by_alien)
	elif not is_alien():
		sim.structure_hit(self)


func step(dt: float, sim: SimCore) -> void:
	if dead:
		return
	fire_cd = maxf(0.0, fire_cd - dt)
	if build < 1.0:
		var rate := assist
		if Logi.STRUCT[kind].get("self_erect", false):
			rate = maxf(rate, 1.0 / Logi.STRUCT[kind].erect_time)
		if kind == Logi.Kind.ALIEN_OUTPOST:
			rate = assist
		assist = 0.0
		if rate > 0.0:
			build = minf(1.0, build + rate * dt)
			if build >= 1.0:
				sim.structure_online(self)
		return
	if kind == Logi.Kind.TURRET:
		_turret(sim)


func _turret(sim: SimCore) -> void:
	if fire_cd > 0.0:
		return
	var spec: Dictionary = Logi.STRUCT[kind]
	var best: RaiderSim = null
	var bd: float = spec.range
	for r in sim.raiders:
		if r.alive():
			var d := r.pos2().distance_to(pos)
			if d < bd:
				bd = d
				best = r
	if best == null:
		return
	fire_cd = spec.cd
	var from := pos3(sim) + Vector3.UP * 6.0
	shots.append({"from": from, "to": best.pos})
	if _rng.randf() < spec.hit * (1.0 - bd / spec.range * 0.4):
		best.take_hit(sim, pos)
	else:
		best.shot_at(sim, pos)
