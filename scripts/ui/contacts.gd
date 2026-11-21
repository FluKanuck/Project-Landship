class_name ContactsPanel
extends Control
## Sensor picture: every live contact and every ghost with its age, bearing and range from
## the carrier, plus the state of each sensor and the share of the map we actually know.

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func frame_subtitle() -> String:
	var k := 0.0
	for v in Sim.know:
		k += v
	return "TERRAIN KNOWN %d%%" % int(100.0 * k / Sim.know.size())


func _draw() -> void:
	var f := UiTheme.font
	var y := 30.0
	var c := Sim.carrier.pos2()
	# sensors
	draw_string(f, Vector2(8, y), "SENSORS", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Pal.UI_DIM)
	y += 26
	draw_string(f, Vector2(8, y), "LANDSHIP  SEARCH RADAR   %.1f KM  ACTIVE" % (Sim.carrier_sensor() / 1000.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Pal.UI_TEXT)
	y += 24
	for d in Sim.drones:
		var st := "ON DECK"
		var col := Pal.UI_DIM
		if d.airborne():
			match d.link:
				DroneSim.Link.OK:
					st = "%.1f KM  LIVE" % (d.sensor_range() / 1000.0)
					col = Pal.UI_FRIEND
				DroneSim.Link.WEAK:
					st = "%.1f KM  LINK WEAK" % (d.sensor_range() / 1000.0)
					col = Pal.UI_WARN
				DroneSim.Link.LOST:
					st = "NO LINK  %d BUFFERED" % d.buffered.size()
					col = Pal.UI_ENEMY
		elif d.state == DroneSim.State.DESTROYED:
			st = "LOST"
			col = Pal.UI_ENEMY
		draw_string(f, Vector2(8, y), "%-9s GIMBAL CAMERA    %s" % [d.callsign, st], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, col)
		y += 24
	y += 10
	draw_line(Vector2(0, y), Vector2(size.x, y), Pal.UI_DIM, 1)
	y += 24
	draw_string(f, Vector2(8, y), "ID     CLASS    BRG   RNG KM   STATUS", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Pal.UI_DIM)
	y += 26
	var rows := Sim.contacts.values()
	rows.sort_custom(func(a, b): return (1 if a.live else 0) > (1 if b.live else 0) or (a.live == b.live and a.last > b.last))
	if rows.is_empty():
		draw_string(f, Vector2(8, y + 10), "NO CONTACTS. SEND A SCOUT, WATCH THE GAPS.", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Pal.UI_DIM)
	for ct in rows:
		if y > size.y - (36 if Sim.node_found else 10):
			break
		var p := Vector2(ct.pos.x, ct.pos.z)
		var id := ("R-%d" if ct["class"] == "RAIDER" else "H-%d") % (ct.id + 1)
		var cls := "RAIDER" if ct["class"] == "RAIDER" else "HOVER?"
		var brg := int(Terrain.bearing_deg(c, p))
		var rng := c.distance_to(p) / 1000.0
		var col := Pal.UI_ENEMY
		var status := "LIVE"
		if not ct.live:
			var age: float = Sim.game_time - ct.last
			col = Color(Pal.UI_GHOST, clampf(1.0 - age / Sim.GHOST_FADE, 0.25, 0.8))
			status = "GHOST +" + Sim.age_text(age)
		elif fmod(_t, 1.0) < 0.5:
			draw_rect(Rect2(2, y - 18, 8, 22), Pal.UI_ENEMY)
		draw_string(f, Vector2(16, y), "%-6s %-8s %03d   %5.1f    %s" % [id, cls, brg, rng, status], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, col)
		y += 25
	if Sim.node_found:
		var np := Terrain.CAMP
		draw_string(f, Vector2(16, size.y - 14), "STRUCTURE  RECHARGE NODE  BRG %03d  RNG %.1f KM" % [int(Terrain.bearing_deg(c, np)), c.distance_to(np) / 1000.0], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Pal.UI_ENEMY)
