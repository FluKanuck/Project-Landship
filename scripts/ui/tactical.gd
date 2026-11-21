class_name TacticalPanel
extends Control
## Tactical screen: pick a unit, click the map to build its waypoint chain. Each new
## waypoint takes the action and rules of engagement last picked (design doc: Tactical).
## Swifts fly MOVE / LOIT / SCAN; haulers and lifters run MOVE / LOAD / BUILD / LOOT /
## HOME and can loop the chain as a standing route; the landship plots a course or plants
## a kit with her crane.

var map: MapView
var unit_bar: HBoxContainer
var unit_btns: Array[Button] = []
var unit_ids: Array[int] = []
var info: Label
var lock_label: Label
# drone tools
var drone_row: HBoxContainer
var act_btns: Array[Button] = []
var roe_btns: Array[Button] = []
var launch_btn: Button
var rtb_btn: Button
# vehicle tools
var veh_box: VBoxContainer
var vact_btns: Array[Button] = []
var vroe_btns: Array[Button] = []
var kit_btn: Button
var deploy_btn: Button
var recall_btn: Button
var loop_btn: Button
# landship tools
var ship_row: HBoxContainer
var plant_btn: Button
var plant_kit_btn: Button
var plant_on := false
var plant_kind := Logi.Kind.EXTRACTOR
var _veh_count := -1

const KIT_CYCLE := [Logi.Kind.EXTRACTOR, Logi.Kind.TURRET, Logi.Kind.PAD, Logi.Kind.RELAY, Logi.Kind.SCANNER, -1]


func _ready() -> void:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 6)
	add_child(v)

	unit_bar = HBoxContainer.new()
	unit_bar.add_theme_constant_override("separation", 4)
	v.add_child(unit_bar)
	info = UiTheme.label("", 16, Pal.UI_DIM)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.clip_text = true
	v.add_child(info)
	_rebuild_units()

	map = MapView.new()
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map.clicked_world.connect(_on_map_click)
	v.add_child(map)
	lock_label = UiTheme.label("LINK LOST: ORDERS LOCKED. SHE FLIES HER LAST ORDERS.", 22, Pal.UI_ENEMY)
	lock_label.visible = false
	lock_label.position = Vector2(18, 70)
	map.add_child(lock_label)

	# --- Swifts
	drone_row = HBoxContainer.new()
	drone_row.add_theme_constant_override("separation", 6)
	v.add_child(drone_row)
	launch_btn = UiTheme.button("LAUNCH", false, 96)
	launch_btn.pressed.connect(func(): if Sim.selected_drone(): Sim.launch(Sim.selected))
	drone_row.add_child(launch_btn)
	rtb_btn = UiTheme.button("RTB", false, 60)
	rtb_btn.pressed.connect(func(): if Sim.selected_drone(): Sim.rtb(Sim.selected))
	drone_row.add_child(rtb_btn)
	drone_row.add_child(_sep())
	for i in 3:
		var b := UiTheme.button(Pal.ACT_NAMES[i], true, 66)
		b.pressed.connect(func(): Sim.tool_act = i)
		b.tooltip_text = ["Fly to the point", "Orbit the point for 5 min", "Slow wide orbit, bigger sensor radius, 4 min"][i]
		drone_row.add_child(b)
		act_btns.append(b)
	drone_row.add_child(_sep())
	_roe_buttons(drone_row, roe_btns)
	drone_row.add_child(_sep())
	_undo_clear(drone_row)
	_compact(drone_row)

	# --- haulers and lifters
	veh_box = VBoxContainer.new()
	veh_box.add_theme_constant_override("separation", 4)
	v.add_child(veh_box)
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 5)
	veh_box.add_child(r1)
	deploy_btn = UiTheme.button("DEPLOY", false, 0)
	deploy_btn.pressed.connect(func():
		var vv := Sim.selected_vehicle()
		if vv and not Sim.deploy_vehicle(vv):
			Sfx.ui("err"))
	r1.add_child(deploy_btn)
	recall_btn = UiTheme.button("RECALL", false, 0)
	recall_btn.pressed.connect(func():
		var vv := Sim.selected_vehicle()
		if vv:
			Sim.recall_vehicle(vv))
	r1.add_child(recall_btn)
	r1.add_child(_sep())
	var tips := ["Drive or fly to the point", "Load from the hub's pad (needs a linked hub)",
		"Plant the chosen kit here (engineer: also assembles; sling: drops)", "Take whatever is lootable at a cleared site",
		"Come back aboard and unload"]
	for i in 5:
		var b := UiTheme.button(VehicleSim.ACT_NAMES[i], true, 0)
		b.pressed.connect(func(): Sim.tool_vact = i)
		b.tooltip_text = tips[i]
		r1.add_child(b)
		vact_btns.append(b)
	kit_btn = UiTheme.button("KIT RLY", false, 0)
	kit_btn.tooltip_text = "Kit the next BUILD point plants (click to cycle)"
	kit_btn.pressed.connect(func(): Sim.tool_kit = _cycle(Sim.tool_kit, false))
	r1.add_child(kit_btn)
	_compact(r1)
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 5)
	veh_box.add_child(r2)
	_roe_buttons(r2, vroe_btns)
	r2.add_child(_sep())
	loop_btn = UiTheme.button("STANDING ROUTE", true, 0)
	loop_btn.tooltip_text = "Repeat the chain until told otherwise: a supply run that needs no attention"
	loop_btn.pressed.connect(func():
		var vv := Sim.selected_vehicle()
		if vv:
			vv.standing = loop_btn.button_pressed
			Sim.emit_event("route_set", {"veh": vv, "on": vv.standing}))
	r2.add_child(loop_btn)
	r2.add_child(_sep())
	_undo_clear(r2)
	_compact(r2)

	# --- landship
	ship_row = HBoxContainer.new()
	ship_row.add_theme_constant_override("separation", 6)
	v.add_child(ship_row)
	ship_row.add_child(UiTheme.label("CLICK MAP: PLOT COURSE", 17, Pal.UI_DIM))
	ship_row.add_child(_sep())
	plant_btn = UiTheme.button("CRANE PLANT", true, 0)
	plant_btn.tooltip_text = "Set a kit down beside the hull with the crane (crawl or stop)"
	plant_btn.pressed.connect(func(): plant_on = plant_btn.button_pressed)
	ship_row.add_child(plant_btn)
	plant_kit_btn = UiTheme.button("EXT", false, 0)
	plant_kit_btn.pressed.connect(func(): plant_kind = _cycle(plant_kind, true))
	ship_row.add_child(plant_kit_btn)
	ship_row.add_child(_sep())
	_undo_clear(ship_row)
	_compact(ship_row)


func _roe_buttons(row: HBoxContainer, into: Array[Button]) -> void:
	for i in 3:
		var b := UiTheme.button(Pal.ROE_NAMES[i], true, 66)
		b.add_theme_color_override("font_color", Pal.ROE_COLORS[i])
		b.pressed.connect(func(): Sim.tool_roe = i)
		b.tooltip_text = ["Weapons free: hold course under fire", "Return fire: evade but keep the plan", "Flee: break off and come home if shot at"][i]
		row.add_child(b)
		into.append(b)


func _undo_clear(row: HBoxContainer) -> void:
	var undo := UiTheme.button("UNDO", false, 60)
	undo.pressed.connect(func(): Sim.undo_point())
	row.add_child(undo)
	var clr := UiTheme.button("CLR", false, 54)
	clr.pressed.connect(func(): Sim.clear_orders())
	row.add_child(clr)


func _cycle(cur: int, skip_none: bool) -> int:
	var i := KIT_CYCLE.find(cur)
	for n in KIT_CYCLE.size():
		i = (i + 1) % KIT_CYCLE.size()
		if KIT_CYCLE[i] == -1 and skip_none:
			continue
		return KIT_CYCLE[i]
	return cur


func _rebuild_units() -> void:
	for b in unit_btns:
		b.queue_free()
	unit_btns.clear()
	unit_ids.clear()
	var ids: Array[int] = []
	for i in Sim.drones.size():
		ids.append(i)
	ids.append(-1)
	for v in Sim.vehicles:
		if v.state != VehicleSim.State.DESTROYED:
			ids.append(Sim.VEH_SEL + v.id)
	for id in ids:
		var b := UiTheme.button("", true, 0)
		b.add_theme_font_size_override("font_size", 16)
		b.custom_minimum_size.y = 34
		b.pressed.connect(func(): Sim.select(id))
		unit_bar.add_child(b)
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var sb := UiTheme.get_theme().get_stylebox(st, "Button")
			b.add_theme_stylebox_override(st, _pad(sb))
		unit_btns.append(b)
		unit_ids.append(id)
	_veh_count = _live_vehicles()


func _live_vehicles() -> int:
	var n := 0
	for v in Sim.vehicles:
		if v.state != VehicleSim.State.DESTROYED:
			n += 1
	return n


func _compact(row: HBoxContainer) -> void:
	for b in row.get_children():
		if b is Button:
			b.add_theme_font_size_override("font_size", 17)
			b.custom_minimum_size.x = 0
			for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
				b.add_theme_stylebox_override(st, _pad(b.get_theme_stylebox(st)))


func _pad(sb: StyleBox) -> StyleBox:
	var s := sb.duplicate() as StyleBox
	s.content_margin_left = 6
	s.content_margin_right = 6
	return s


func _sep() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(6, 0)
	return c


func frame_subtitle() -> String:
	var a := map.operational_area()
	return "OPS AREA %.1f x %.1f KM%s" % [a.size.x / 1000.0, a.size.y / 1000.0, "  ZOOM x%.1f" % map.zoom if map.zoom > 1.01 else ""]


func _on_map_click(p: Vector2, button: int) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		if plant_on and Sim.selected == -1:
			plant_on = false
			return
		Sim.undo_point()
		return
	if plant_on and Sim.selected == -1:
		if Sim.crane_plant(plant_kind, p):
			Sfx.ui("ok")
			if Sim.kit_bay.get(plant_kind, 0) <= 0:
				plant_on = false
		else:
			Sfx.ui("err")
		return
	if not Sim.order_point(p):
		Sfx.ui("err")


func _process(_d: float) -> void:
	if _live_vehicles() != _veh_count:
		_rebuild_units()
	var sel := Sim.selected
	for i in unit_btns.size():
		var id := unit_ids[i]
		unit_btns[i].set_pressed_no_signal(id == sel)
		if id == -1:
			unit_btns[i].text = "LANDSHIP"
		elif id >= Sim.VEH_SEL:
			var vv: VehicleSim = Sim.vehicles[id - Sim.VEH_SEL]
			unit_btns[i].text = "%s %s" % [vv.callsign, _vshort(vv)]
		else:
			var d := Sim.drones[id]
			unit_btns[i].text = "%s %s" % [d.callsign, _short(d)]
	var d := Sim.selected_drone()
	var v := Sim.selected_vehicle()
	drone_row.visible = d != null
	veh_box.visible = v != null
	ship_row.visible = sel == -1
	if sel != -1:
		plant_on = false
	plant_btn.set_pressed_no_signal(plant_on)
	map.plant_kind = plant_kind if plant_on else -1
	plant_kit_btn.text = "%s x%d" % [Logi.KIND_SHORT[plant_kind], Sim.kit_bay.get(plant_kind, 0)]
	for i in 3:
		act_btns[i].set_pressed_no_signal(Sim.tool_act == i)
		roe_btns[i].set_pressed_no_signal(Sim.tool_roe == i)
		vroe_btns[i].set_pressed_no_signal(Sim.tool_roe == i)
	for i in 5:
		vact_btns[i].set_pressed_no_signal(Sim.tool_vact == i)
	kit_btn.text = "KIT %s" % ("ASSEMBLE" if Sim.tool_kit < 0 else "%s x%d" % [Logi.KIND_SHORT[Sim.tool_kit], Sim.kit_bay.get(Sim.tool_kit, 0)])
	kit_btn.visible = Sim.tool_vact == VehicleSim.Act.BUILD
	lock_label.visible = false
	if d:
		launch_btn.disabled = d.state != DroneSim.State.READY
		rtb_btn.disabled = not d.airborne() or Sim.orders_locked(d)
		var link: String = ["LINK OK", "LINK WEAK", "NO LINK"][d.link] if d.airborne() else "ON DECK"
		info.text = "%s  FUEL %d%%  HP %d/3  %s  ROE %s" % [d.status_text(), int(100.0 * d.fuel / DroneSim.ENDURANCE), d.hp, link, Pal.ROE_NAMES[d.current_roe()] if d.airborne() else "-"]
		lock_label.visible = Sim.orders_locked(d)
	elif v:
		deploy_btn.disabled = v.state != VehicleSim.State.STOWED
		recall_btn.disabled = not v.is_out()
		loop_btn.set_pressed_no_signal(v.standing)
		var link: String = ["LINK OK", "LINK WEAK", "NO LINK"][v.link] if v.is_out() else "ABOARD"
		var fuel := "FUEL %d%%" % int(100.0 * v.fuel / v.endurance(Sim))
		info.text = "%s  %s  %s  HP %d/%d  %s%s" % [v.status_text(), v.fit_text(), fuel, v.hp, v.max_hp, link,
			"  CARGO F%d M%d" % [int(v.cargo[0]), int(v.cargo[1])] if v.cargo_total() > 0.5 else ("  KITS " + " ".join(v.kits.map(func(k): return Logi.KIND_SHORT[k])) if not v.kits.is_empty() else "")]
		lock_label.visible = Sim.orders_locked(v)
		lock_label.text = "LINK LOST: ORDERS LOCKED. %s RUNS HER LAST ORDERS." % v.callsign
	else:
		var hdg := fposmod(rad_to_deg(Sim.carrier.heading), 360.0)
		info.text = "%s  %.1f M/S  HDG %03d  KITS ABOARD %d" % [CarrierSim.THROTTLE_NAMES[Sim.carrier.throttle], Sim.carrier.speed, int(hdg), Sim.kits_total()]
	if d:
		lock_label.text = "LINK LOST: ORDERS LOCKED. SHE FLIES HER LAST ORDERS."


func _short(d: DroneSim) -> String:
	match d.state:
		DroneSim.State.READY: return "RDY"
		DroneSim.State.REFUEL: return "FUEL"
		DroneSim.State.DESTROYED: return "LOST"
		DroneSim.State.REBUILD: return "FAB"
	if d.link == DroneSim.Link.LOST:
		return "NOLINK"
	return "AIR"


func _vshort(v: VehicleSim) -> String:
	match v.state:
		VehicleSim.State.STOWED: return "LOOP" if v.standing else "BAY"
		VehicleSim.State.DESTROYED: return "LOST"
	if v.link == DroneSim.Link.LOST:
		return "NOLINK"
	return "LOOP" if v.standing else "OUT"
