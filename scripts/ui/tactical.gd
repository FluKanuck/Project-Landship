class_name TacticalPanel
extends Control
## Tactical screen: pick a unit, click the map to build its waypoint chain. Each new
## waypoint takes the action and rules of engagement last picked (design doc: Tactical).

var map: MapView
var unit_bar: HBoxContainer
var unit_btns: Array[Button] = []
var act_btns: Array[Button] = []
var roe_btns: Array[Button] = []
var launch_btn: Button
var rtb_btn: Button
var info: Label
var lock_label: Label


func _ready() -> void:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 6)
	add_child(v)

	unit_bar = HBoxContainer.new()
	unit_bar.add_theme_constant_override("separation", 6)
	v.add_child(unit_bar)
	for i in Sim.drones.size():
		var b := UiTheme.button(Sim.drones[i].callsign, true, 150)
		b.pressed.connect(func(): Sim.select(i))
		unit_bar.add_child(b)
		unit_btns.append(b)
	var cb := UiTheme.button("LANDSHIP", true, 140)
	cb.pressed.connect(func(): Sim.select(-1))
	unit_bar.add_child(cb)
	unit_btns.append(cb)
	info = UiTheme.label("", 18, Pal.UI_DIM)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.clip_text = true
	unit_bar.add_child(info)

	map = MapView.new()
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map.clicked_world.connect(_on_map_click)
	v.add_child(map)
	lock_label = UiTheme.label("LINK LOST: ORDERS LOCKED. SHE FLIES HER LAST ORDERS.", 22, Pal.UI_ENEMY)
	lock_label.visible = false
	lock_label.position = Vector2(18, 70)
	map.add_child(lock_label)

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	v.add_child(tools)
	launch_btn = UiTheme.button("LAUNCH", false, 96)
	launch_btn.pressed.connect(func(): if Sim.selected >= 0: Sim.launch(Sim.selected))
	tools.add_child(launch_btn)
	rtb_btn = UiTheme.button("RTB", false, 60)
	rtb_btn.pressed.connect(func(): if Sim.selected >= 0: Sim.rtb(Sim.selected))
	tools.add_child(rtb_btn)
	tools.add_child(_sep())
	for i in 3:
		var b := UiTheme.button(Pal.ACT_NAMES[i], true, 66)
		b.pressed.connect(func(): Sim.tool_act = i)
		b.tooltip_text = ["Fly to the point", "Orbit the point for 5 min", "Slow wide orbit, bigger sensor radius, 4 min"][i]
		tools.add_child(b)
		act_btns.append(b)
	tools.add_child(_sep())
	for i in 3:
		var b := UiTheme.button(Pal.ROE_NAMES[i], true, 66)
		b.add_theme_color_override("font_color", Pal.ROE_COLORS[i])
		b.pressed.connect(func(): Sim.tool_roe = i)
		b.tooltip_text = ["Weapons free: hold course under fire", "Return fire: evade but keep the plan", "Flee: break off and come home if shot at"][i]
		tools.add_child(b)
		roe_btns.append(b)
	tools.add_child(_sep())
	var undo := UiTheme.button("UNDO", false, 60)
	undo.pressed.connect(func(): Sim.undo_point())
	tools.add_child(undo)
	var clr := UiTheme.button("CLR", false, 54)
	clr.pressed.connect(func(): Sim.clear_orders())
	tools.add_child(clr)
	_compact(tools)


func _compact(row: HBoxContainer) -> void:
	for b in row.get_children():
		if b is Button:
			b.add_theme_font_size_override("font_size", 18)
			b.custom_minimum_size.x = 0
			for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
				b.add_theme_stylebox_override(st, _pad(b.get_theme_stylebox(st)))


func _pad(sb: StyleBox) -> StyleBox:
	var s := sb.duplicate() as StyleBox
	s.content_margin_left = 7
	s.content_margin_right = 7
	return s


func _sep() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(8, 0)
	return c


func frame_subtitle() -> String:
	var a := map.operational_area()
	return "OPS AREA %.1f x %.1f KM%s" % [a.size.x / 1000.0, a.size.y / 1000.0, "  ZOOM x%.1f" % map.zoom if map.zoom > 1.01 else ""]


func _on_map_click(p: Vector2, button: int) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		Sim.undo_point()
		return
	# a click on a unit selects it (18 px of slop at the current zoom)
	var u := Sim.unit_near(p, 18.0 * map.span / maxf(map.size.y, 1.0))
	if u != -2:
		if u != Sim.selected:
			Sim.select(u)
			Sfx.ui("button")
		return
	if not Sim.order_point(p):
		Sfx.ui("err")


func _process(_d: float) -> void:
	var sel := Sim.selected
	for i in unit_btns.size():
		var is_sel := (i == sel) or (i == unit_btns.size() - 1 and sel == -1)
		unit_btns[i].set_pressed_no_signal(is_sel)
		if i < Sim.drones.size():
			var d := Sim.drones[i]
			unit_btns[i].text = "%s %s %s" % [Prefs.key_name("select_%d" % (i + 1)), d.callsign, _short(d)]
		else:
			unit_btns[i].text = "%s LANDSHIP" % Prefs.key_name("select_3")
	var d := Sim.selected_drone()
	var drone_mode := d != null
	launch_btn.visible = drone_mode
	rtb_btn.visible = drone_mode
	for b in act_btns + roe_btns:
		b.disabled = not drone_mode
	for i in 3:
		act_btns[i].set_pressed_no_signal(Sim.tool_act == i)
		roe_btns[i].set_pressed_no_signal(Sim.tool_roe == i)
	if drone_mode:
		launch_btn.disabled = d.state != DroneSim.State.READY
		rtb_btn.disabled = not d.airborne() or Sim.orders_locked(d)
		var link: String = ["LINK OK", "LINK WEAK", "NO LINK"][d.link] if d.airborne() else "ON DECK"
		info.text = "%s  FUEL %d%%  HP %d/3  %s  ROE %s" % [d.status_text(), int(100.0 * d.fuel / DroneSim.ENDURANCE), d.hp, link, Pal.ROE_NAMES[d.current_roe()] if d.airborne() else "-"]
		lock_label.visible = Sim.orders_locked(d)
	else:
		info.text = "%s  %.1f M/S  HDG %03d  CLICK MAP TO PLOT COURSE" % [CarrierSim.THROTTLE_NAMES[Sim.carrier.throttle], Sim.carrier.speed, int(rad_to_deg(Sim.carrier.heading)) % 360 if Sim.carrier.heading >= 0 else int(rad_to_deg(Sim.carrier.heading) + 360.0)]
		lock_label.visible = false


func _short(d: DroneSim) -> String:
	match d.state:
		DroneSim.State.READY: return "RDY"
		DroneSim.State.REFUEL: return "FUEL"
		DroneSim.State.DESTROYED: return "LOST"
		DroneSim.State.REBUILD: return "FAB"
	if d.link == DroneSim.Link.LOST:
		return "NOLINK"
	return "AIR"
