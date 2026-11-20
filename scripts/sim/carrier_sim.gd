class_name CarrierSim
extends RefCounted
## The landship. Plotted course, four throttle settings, fuel, and the restart cost that
## grows while it sits on the sand.

const SPEEDS := [0.0, 2.5, 6.0, 10.0] # m/s: stop, crawl, cruise, flank
const BURN := [0.0, 0.0000045, 0.000009, 0.000022] # fuel fraction per second
const SIGNATURE := [0.25, 0.45, 0.7, 1.0]
const THROTTLE_NAMES := ["ALL STOP", "SILENT CRAWL", "CRUISE", "FLANK"]
const TURN_RATE := deg_to_rad(0.9) # rad/s
const SENSOR_RANGE := 2600.0

# Local sockets (Godot coords, metres) from hum_carrier.glb
const LAUNCH_LOCAL := Vector3(8.0, 52.5, -120.0)
const RECOVER_LOCAL := Vector3(8.0, 52.5, 30.0)
const BOW_LOCAL := Vector3(8.0, 52.5, -182.0)
const BRIDGE_LOCAL := Vector3(0.0, 78.0, 95.0)

var pos := Vector3.ZERO
var heading := 0.0 # radians, 0 = north (-Z), clockwise
var speed := 0.0
var throttle := 1
var fuel := 0.86
var course: Array[Vector2] = []
var parked_time := 0.0
var pitch := 0.0
var roll := 0.0
var _terrain: Terrain


func _init(t: Terrain, start: Vector2) -> void:
	_terrain = t
	pos = Vector3(start.x, 0.0, start.y)
	heading = 0.0
	_settle(1.0)


func forward() -> Vector2:
	return Vector2(sin(heading), -cos(heading))


func basis() -> Basis:
	var b := Basis(Vector3.UP, -heading)
	b = b * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll)
	return b


func xform() -> Transform3D:
	return Transform3D(basis(), pos)


func to_world(local: Vector3) -> Vector3:
	return xform() * local


func pos2() -> Vector2:
	return Vector2(pos.x, pos.z)


func restart_cost() -> float:
	return 0.002 + (parked_time / 3600.0) * 0.006


func set_throttle(t: int) -> bool:
	t = clampi(t, 0, 3)
	if t == throttle:
		return false
	if throttle == 0 and t > 0:
		fuel = maxf(0.0, fuel - restart_cost())
		parked_time = 0.0
	throttle = t
	return true


func step(dt: float, sim: SimCore) -> void:
	if fuel <= 0.0:
		throttle = 0
	var target := float(SPEEDS[throttle])
	speed = move_toward(speed, target, dt * 0.08)
	fuel = maxf(0.0, fuel - BURN[throttle] * dt)
	if throttle == 0 and speed < 0.05:
		parked_time += dt
	# steer along the plotted course
	if course.size() > 0:
		var to := course[0] - pos2()
		if to.length() < 260.0:
			course.remove_at(0)
			sim.emit_event("helm_waypoint", {})
			if course.is_empty():
				# end of the plotted course: bring her to a stop rather than run on into the dunes
				throttle = 0
				sim.emit_event("helm_course_done", {})
		else:
			var want := atan2(to.x, -to.y)
			var diff := wrapf(want - heading, -PI, PI)
			heading = wrapf(heading + clampf(diff, -TURN_RATE * dt, TURN_RATE * dt), -PI, PI)
	var p2 := pos2() + forward() * speed * dt
	# survey limit: stop rather than drive off the map
	if not _terrain.in_bounds(p2, 700.0):
		if throttle > 0:
			throttle = 0
			sim.emit_event("helm_limit", {})
		p2 = pos2()
		speed = 0.0
	pos.x = p2.x
	pos.z = p2.y
	_settle(dt)


func _settle(dt: float) -> void:
	# sit on the sand: average height under the hull, pitch and roll from the ends
	var f := forward()
	var r := Vector2(-f.y, f.x)
	var c := pos2()
	var hb := _terrain.height_at(c.x + f.x * 150.0, c.y + f.y * 150.0)
	var ht := _terrain.height_at(c.x - f.x * 150.0, c.y - f.y * 150.0)
	var hl := _terrain.height_at(c.x - r.x * 45.0, c.y - r.y * 45.0)
	var hr := _terrain.height_at(c.x + r.x * 45.0, c.y + r.y * 45.0)
	var hc := _terrain.height_at(c.x, c.y)
	var base := maxf((hb + ht + hl + hr + hc) / 5.0, minf(hb, ht) + 4.0)
	var k := clampf(dt * 0.6, 0.0, 1.0)
	pos.y = lerpf(pos.y, base - 2.0, k) if dt < 1.0 else base - 2.0
	var want_pitch := clampf(atan2(hb - ht, 300.0), -0.07, 0.07)
	var want_roll := clampf(atan2(hr - hl, 90.0), -0.04, 0.04)
	pitch = lerpf(pitch, want_pitch, k)
	roll = lerpf(roll, want_roll, k)
