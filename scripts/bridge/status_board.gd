class_name StatusBoard
extends Node
## The big status boards on the back wall: what a commander pacing the room glances at.

var viewport: SubViewport
var _c: Control


func _init() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(720, 340)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	_c = Control.new()
	_c.size = Vector2(viewport.size)
	_c.draw.connect(_draw_board)
	viewport.add_child(_c)


func _process(_d: float) -> void:
	_c.queue_redraw()


func _draw_board() -> void:
	var f := UiTheme.font
	var hf := UiTheme.font_head
	if f == null:
		UiTheme.get_theme()
		f = UiTheme.font
		hf = UiTheme.font_head
	var s := _c.size
	var red := Sim.alert
	var ink := Pal.UI_ENEMY if red else Pal.UI_TEXT
	_c.draw_rect(Rect2(Vector2.ZERO, s), Color(0.04, 0.03, 0.02))
	_c.draw_string(hf, Vector2(24, 52), Sim.clock_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, 46, Pal.UI_HOT)
	_c.draw_string(f, Vector2(s.x - 170, 50), "TIME x%d" % Sim.time_scale(), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Pal.UI_WARN if Sim.time_scale() > 1 else ink)
	_c.draw_line(Vector2(20, 70), Vector2(s.x - 20, 70), Pal.UI_LINE, 2)
	var live := 0
	var ghosts := 0
	for c in Sim.contacts.values():
		if c.live:
			live += 1
		else:
			ghosts += 1
	_c.draw_string(f, Vector2(24, 112), "CONTACTS  %d LIVE  %d GHOST" % [live, ghosts], HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Pal.UI_ENEMY if live > 0 else ink)
	var y := 156.0
	for d in Sim.drones:
		var col := Pal.UI_FRIEND if d.airborne() else Pal.UI_DIM
		if d.state == DroneSim.State.DESTROYED:
			col = Pal.UI_ENEMY
		var link := ""
		if d.airborne():
			link = ["", "  LINK WEAK", "  NO LINK"][d.link]
		_c.draw_string(f, Vector2(24, y), "%s  %s%s" % [d.callsign, d.status_text(), link], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, col)
		y += 38
	_c.draw_string(f, Vector2(24, y + 6), "LANDSHIP  %s  FUEL %d%%" % [CarrierSim.THROTTLE_NAMES[Sim.carrier.throttle], int(Sim.carrier.fuel * 100.0)], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, ink)
	var obj := "OBJECTIVE COMPLETE: RAIDER BASE LOCATED" if Sim.node_found else "OBJECTIVE: LOCATE THE RAIDER BASE"
	_c.draw_string(f, Vector2(24, s.y - 22), obj, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Pal.UI_FRIEND if Sim.node_found else Pal.UI_DIM)
