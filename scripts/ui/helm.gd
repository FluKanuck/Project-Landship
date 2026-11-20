class_name HelmPanel
extends Control
## Helm and time: plot-and-go throttle, fuel, the restart cost that grows while parked, and
## time compression (which drops to x1 on any new contact).

var throttle_btns: Array[Button] = []
var tc_btns: Array[Button] = []


func _ready() -> void:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 140)
	v.add_child(spacer)
	v.add_child(UiTheme.label("THROTTLE", 16, Pal.UI_DIM))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	v.add_child(h)
	for i in 4:
		var b := UiTheme.button(["STOP", "CRAWL", "CRUISE", "FLANK"][i], true, 96)
		b.pressed.connect(func(): Sim.set_throttle(i))
		h.add_child(b)
		throttle_btns.append(b)
	var clear := UiTheme.button("CLEAR COURSE", false, 0)
	clear.pressed.connect(func():
		var keep := Sim.selected
		Sim.selected = -1
		Sim.clear_orders()
		Sim.selected = keep)
	h.add_child(clear)
	v.add_child(UiTheme.label("TIME COMPRESSION", 16, Pal.UI_DIM))
	var t := HBoxContainer.new()
	t.add_theme_constant_override("separation", 6)
	v.add_child(t)
	for i in Sim.SCALES.size():
		var b := UiTheme.button("x%d" % Sim.SCALES[i], true, 84)
		b.pressed.connect(func(): Sim.set_scale_idx(i))
		t.add_child(b)
		tc_btns.append(b)


func frame_subtitle() -> String:
	return Sim.clock_text()


func _process(_d: float) -> void:
	for i in 4:
		throttle_btns[i].set_pressed_no_signal(Sim.carrier.throttle == i)
	for i in tc_btns.size():
		tc_btns[i].set_pressed_no_signal(Sim.scale_idx == i)
	queue_redraw()


func _draw() -> void:
	var f := UiTheme.font
	var hf := UiTheme.font_head
	var c := Sim.carrier
	var hdg := fposmod(rad_to_deg(c.heading), 360.0)
	draw_string(hf, Vector2(8, 46), "HDG %03d" % int(hdg), HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Pal.UI_HOT)
	draw_string(hf, Vector2(230, 46), "%.1f M/S" % c.speed, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Pal.UI_HOT)
	draw_string(f, Vector2(8, 78), CarrierSim.THROTTLE_NAMES[c.throttle] + "   SIGNATURE " + ["LOW", "LOW", "MED", "HIGH"][c.throttle], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Pal.UI_TEXT)
	# fuel bar
	var bx := Rect2(8, 92, minf(size.x - 16, 470), 22)
	draw_rect(bx, Pal.UI_DIM, false, 1.5)
	draw_rect(Rect2(bx.position, Vector2(bx.size.x * c.fuel, bx.size.y)), Color(Pal.UI_TEXT, 0.6))
	draw_string(f, bx.position + Vector2(6, 17), "FUEL %d%%" % int(c.fuel * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Pal.UI_BG if c.fuel > 0.2 else Pal.UI_ENEMY)
	var line := ""
	if c.throttle == 0:
		var hours := c.parked_time / 3600.0
		line = "PARKED %.1f H   RESTART COST %.1f%% FUEL" % [hours, c.restart_cost() * 100.0]
		if hours > 30.0:
			line += "   SAND IS TAKING HER"
	elif not c.course.is_empty():
		var d := c.pos2().distance_to(c.course[0])
		line = "NEXT POINT %.1f KM   ETA %s" % [d / 1000.0, Sim.age_text(d / maxf(c.speed, 0.1))]
	else:
		line = "NO COURSE: HOLDING HEADING"
	draw_string(f, Vector2(8, 138), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Pal.UI_WARN if c.throttle == 0 and c.parked_time > 86400.0 else Pal.UI_TEXT)
