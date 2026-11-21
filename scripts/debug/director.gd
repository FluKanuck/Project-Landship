extends Node
## Test director: scripted scenarios that drive the game and save screenshots.
## godot --path . -- --scenario=tour --out=/tmp/shots

var main: Node
var out := "/tmp/shots"
var scenario := "tour"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a.begins_with("--scenario="):
			scenario = a.substr(11)
	DirAccess.make_dir_recursive_absolute(out)
	call_deferred("_run")


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func shot(name: String) -> void:
	await _frames(3)
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
	print("[shot] ", name)


func _run() -> void:
	main = get_parent()
	await _wait(0.5)
	if scenario == "quick":
		await shot("q0_title")
	main._start()
	await _wait(4.5)
	var p: Player = main.player
	call(scenario)


func mfd_shot(name: String) -> void:
	await _frames(3)
	var img: Image = main.bridge.projection.viewport.get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
	print("[shot] ", name)


func simtest() -> void:
	# Headless soak test: hours of game time with scripted orders. Prints every event.
	Sim.event.connect(func(k, data): print("  %s %-16s %s" % [Sim.clock_text(), k, _brief(data)]))
	Sim.running = false
	Sim.select(0)
	Sim.tool_roe = DroneSim.Roe.FLEE
	Sim.tool_act = DroneSim.Act.SCAN
	Sim.order_point(Vector2(1500, 0))
	Sim.tool_act = DroneSim.Act.MOVE
	Sim.order_point(Vector2(2700, -2600)) # near the camp: should be fired on and flee
	Sim.launch(0)
	Sim.select(1)
	Sim.tool_roe = DroneSim.Roe.FREE
	Sim.tool_act = DroneSim.Act.LOIT
	Sim.order_point(Vector2(-2500, -900)) # the oasis, beyond link range
	Sim.order_point(Vector2(-3200, -2600))
	Sim.launch(1)
	Sim.set_throttle(2)
	Sim.select(-1)
	Sim.order_point(Vector2(800, 1500))
	for i in 7200 * 6:
		Sim._step(0.5)
		if i % 1200 == 0:
			var s := []
			for dd in Sim.drones:
				s.append("%s %s fuel%d hp%d link%d" % [dd.callsign, dd.status_text(), int(dd.fuel), dd.hp, dd.link])
			print("[t] ", Sim.clock_text(), " carrier ", Sim.carrier.pos2().round(), " fuel %.3f " % Sim.carrier.fuel, " | ".join(s))
	var live := 0
	for c in Sim.contacts.values():
		live += 1 if c.live else 0
	print("[simtest] done contacts ", Sim.contacts.size(), " live ", live, " node_found ", Sim.node_found)
	get_tree().quit()


func logitest() -> void:
	# Headless soak of the supply war: crane-plant a hub at the mine, run a standing hauler
	# route, sling a relay and a scanner out, then let the aliens find the network.
	Sim.event.connect(func(k, data):
		if not k in ["contact_new", "contact_lost", "contact_class", "waypoint_added", "helm_waypoint"]:
			print("  %s %-24s %s" % [Sim.clock_text(), k, _brief(data)]))
	Sim.running = false
	var mine: SiteSim = Sim.site_at(Terrain.MINE, 50.0)
	Sim.set_throttle(2)
	Sim.carrier.course.clear()
	Sim.carrier.course.append(Vector2(1820, 1300))
	_run_for(1500.0)
	print("[logi] at mine: carrier ", Sim.carrier.pos2().round(), " dist ", int(Sim.carrier.pos2().distance_to(mine.pos)))
	for k in [[Logi.Kind.EXTRACTOR, Vector2(0, 0)], [Logi.Kind.TURRET, Vector2(-70, 60)], [Logi.Kind.PAD, Vector2(60, 70)]]:
		var ok := Sim.crane_plant(k[0], mine.pos + k[1])
		print("[logi] crane plant ", Logi.KIND_NAMES[k[0]], " ", ok)
	Sim.queue_build("kit_relay")
	Sim.queue_build("kit_turret")
	_run_for(600.0)
	# hauler: standing route mine -> landship
	var h: VehicleSim = Sim.vehicles[0]
	Sim.select(Sim.VEH_SEL + h.id)
	Sim.tool_roe = DroneSim.Roe.FLEE
	Sim.tool_vact = VehicleSim.Act.LOAD
	Sim.order_point(mine.pos)
	Sim.tool_vact = VehicleSim.Act.HOME
	Sim.order_point(mine.pos)
	h.standing = true
	print("[logi] hauler deploy ", Sim.deploy_vehicle(h), " ", h.note)
	# lifter: sling the relay out north-west towards the oasis, then come home
	var l: VehicleSim = Sim.vehicles[1]
	Sim.select(Sim.VEH_SEL + l.id)
	Sim.tool_vact = VehicleSim.Act.BUILD
	Sim.tool_kit = Logi.Kind.RELAY
	Sim.order_point(Vector2(-900, 600))
	Sim.tool_kit = Logi.Kind.SCANNER
	Sim.order_point(Vector2(-2000, -300))
	Sim.tool_vact = VehicleSim.Act.HOME
	Sim.order_point(Vector2.ZERO)
	print("[logi] lifter deploy ", Sim.deploy_vehicle(l), " kits ", l.kits)
	Sim.set_throttle(1)
	Sim.carrier.course.append(Vector2(800, 1200))
	for hour in 14:
		_run_for(3600.0)
		_logi_report()
		if hour == 2:
			# a second hub at the oasis by engineer hauler once kits are ready
			Sim.queue_build("kit_extractor")
			Sim.queue_build("kit_pad")
		if hour == 3:
			Sim.queue_build("hauler")
		if hour == 4 and Sim.vehicles.size() > 2:
			# the new hauler takes an engineer kit and builds a hub at the oasis
			var e: VehicleSim = Sim.vehicles[2]
			print("[logi] refit ", e.callsign, " ", Sim.refit_vehicle(e, "engineer", true))
			_run_for(70.0)
			var oasis: SiteSim = Sim.site_at(Terrain.OASIS, 50.0)
			print("[logi] oasis site ", oasis.label(), " linked ", Sim.net.covers(oasis.pos))
			Sim.select(Sim.VEH_SEL + e.id)
			Sim.tool_roe = DroneSim.Roe.RTRN
			Sim.tool_vact = VehicleSim.Act.BUILD
			Sim.tool_kit = Logi.Kind.EXTRACTOR
			Sim.order_point(oasis.pos + Vector2(-40, 0))
			Sim.tool_kit = Logi.Kind.PAD
			Sim.order_point(oasis.pos + Vector2(60, 40))
			Sim.tool_vact = VehicleSim.Act.HOME
			Sim.order_point(oasis.pos)
			print("[logi] engineer deploy ", Sim.deploy_vehicle(e), " kits ", e.kits)
		if hour == 7:
			# the oasis hauler: second standing route
			var l2: VehicleSim = Sim.vehicles[1]
			l2.plan.clear()
			Sim.refit_vehicle(l2, "pod", false)
			_run_for(70.0)
			var oasis: SiteSim = Sim.site_at(Terrain.OASIS, 50.0)
			Sim.select(Sim.VEH_SEL + l2.id)
			Sim.tool_vact = VehicleSim.Act.LOAD
			Sim.order_point(oasis.pos)
			Sim.tool_vact = VehicleSim.Act.HOME
			Sim.order_point(oasis.pos)
			l2.standing = true
			print("[logi] lifter route deploy ", Sim.deploy_vehicle(l2))
	print("[logitest] done kills ", Sim.kills, " alien stock %.0f" % Sim.alien_stock, " built ", Sim.fab.built)
	get_tree().quit()


func _run_for(sec: float) -> void:
	var n := int(sec / 0.5)
	for i in n:
		Sim._step(0.5)


func _logi_report() -> void:
	var st := Sim.stores
	print("[t] %s FUEL %.0f/%.0f MAT %.0f/%.0f  delivered F%.0f M%.0f  fab %s  kits %s" % [Sim.clock_text(), st.fuel, st.cap(0), st.mat, st.cap(1),
		st.delivered[0], st.delivered[1], ",".join(Sim.fab.queue.map(func(i): return i.name)), str(Sim.kit_bay)])
	for s in Sim.sites:
		if s.owner != Logi.Owner.NONE or s.discovered:
			var parts := []
			for x in s.structures(Sim):
				parts.append("%s(%s)" % [Logi.KIND_SHORT[x.kind], x.status_text()])
			if s.owner == Logi.Owner.PLAYER or s.owner == Logi.Owner.ALIEN:
				print("     site %-10s %s owner %d linked %s stock F%.0f M%.0f salv %.0f  %s" % [s.name, Logi.SITE_KIND_SHORT[s.kind], s.owner, s.linked, s.stock[0], s.stock[1], s.salvage, " ".join(parts)])
	for v in Sim.vehicles:
		print("     %s %s %s cargo F%.0f M%.0f trips %d hauled F%.0f M%.0f hp %d fuel %.0f link %d" % [v.callsign, v.fit_text(), v.status_text(), v.cargo[0], v.cargo[1], v.trips, v.hauled[0], v.hauled[1], v.hp, v.fuel, v.link])
	for x in Sim.structures:
		if x.site < 0:
			print("     %s at %s %s linked %s x%.2f" % [x.name(), x.pos.round(), x.status_text(), x.linked, x.range_mult])
	var rs := []
	for r in Sim.raiders:
		rs.append("%d:%s e%.2f" % [r.id, RaiderSim.STATE_NAMES[r.state], r.energy])
	print("     raiders ", " ".join(rs), "  alien stock %.0f" % Sim.alien_stock, "  net nodes ", Sim.net.nodes.size())


func _brief(d: Dictionary) -> String:
	var out := []
	for k in d:
		var v = d[k]
		if v is DroneSim:
			out.append(v.callsign)
		elif v is VehicleSim:
			out.append(v.callsign)
		elif v is SiteSim:
			out.append("site=" + v.name)
		elif v is StructureSim:
			out.append("%s#%d" % [Logi.KIND_SHORT[v.kind], v.id])
		elif v is float:
			out.append("%s=%.0f" % [k, v])
		else:
			out.append("%s=%s" % [k, str(v)])
	return " ".join(out)


## Click a Control inside the projected display, through the 3D projection, like a player.
func click_mfd(ctrl: Control, offset := Vector2(0.5, 0.5), button := MOUSE_BUTTON_LEFT) -> void:
	var proj: CmdProjection = main.bridge.projection
	var px := ctrl.get_global_rect().position + ctrl.get_global_rect().size * offset
	var uv := px / Vector2(CmdProjection.RES)
	var local := Vector3((uv.x - 0.5) * CmdProjection.SIZE.x, (0.5 - uv.y) * CmdProjection.SIZE.y, 0.0)
	var world := proj.screen.global_transform * local
	var cam: Camera3D = main.player.cam
	var sp := cam.unproject_position(world)
	var mm := InputEventMouseMotion.new()
	mm.position = sp
	Input.parse_input_event(mm)
	await _frames(2)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.position = sp
		e.button_index = button
		e.pressed = pressed
		Input.parse_input_event(e)
		await _frames(2)


func interact() -> void:
	# drive the game only through the projected display, the way a player would
	var p: Player = main.player
	var ev := InputEventKey.new()
	ev.keycode = KEY_TAB
	ev.physical_keycode = KEY_TAB
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(3)
	ev = ev.duplicate()
	ev.pressed = false
	Input.parse_input_event(ev)
	await _frames(3)
	print("cursor active: ", p.cursor_active())
	var mfd: MFD = main.bridge.projection.mfd
	var tac: TacticalPanel = mfd.frames["tactical"].content
	await click_mfd(tac.unit_btns[1])
	print("selected after click: ", Sim.selected)
	await click_mfd(tac.act_btns[2])
	await click_mfd(tac.roe_btns[2])
	print("tool act/roe: ", Sim.tool_act, " ", Sim.tool_roe)
	await click_mfd(tac.map, Vector2(0.62, 0.3))
	await click_mfd(tac.map, Vector2(0.75, 0.55))
	print("swift-2 plan: ", Sim.drones[1].plan.size())
	await click_mfd(tac.launch_btn)
	await _wait(1.0)
	print("swift-2 state: ", Sim.drones[1].status_text())
	await shot("i1_after_clicks")
	await mfd_shot("i2_mfd")
	# drag the feed header onto the contacts section to swap them
	var feed: PanelFrame = mfd.frames["feed"]
	var cont: PanelFrame = mfd.frames["contacts"]
	print("feed rect before ", feed.position)
	var proj: CmdProjection = main.bridge.projection
	var cam: Camera3D = p.cam
	var a := feed.get_global_rect().position + Vector2(80, 16)
	var b := cont.get_global_rect().get_center()
	var pts := []
	for k in 6:
		var px := a.lerp(b, k / 5.0)
		var uv := px / Vector2(CmdProjection.RES)
		pts.append(cam.unproject_position(proj.screen.global_transform * Vector3((uv.x - 0.5) * CmdProjection.SIZE.x, (0.5 - uv.y) * CmdProjection.SIZE.y, 0)))
	var down := InputEventMouseButton.new()
	down.position = pts[0]
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(2)
	for k in range(1, 6):
		var mm := InputEventMouseMotion.new()
		mm.position = pts[k]
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(mm)
		await _frames(2)
	var up := down.duplicate()
	up.pressed = false
	up.position = pts[5]
	Input.parse_input_event(up)
	await _wait(0.6)
	print("feed rect after ", feed.position, " layout ", mfd.preset)
	await mfd_shot("i3_swapped")
	get_tree().quit()


func events() -> void:
	# lost link with a predicted track, action stations, ghosts with ages
	Sim.select(1)
	Sim.tool_roe = DroneSim.Roe.FLEE
	Sim.tool_act = DroneSim.Act.MOVE
	Sim.order_point(Vector2(-1500, 600))
	Sim.tool_act = DroneSim.Act.LOIT
	Sim.order_point(Vector2(-2500, -900))
	Sim.launch(1)
	Sim.select(0)
	Sim.tool_act = DroneSim.Act.SCAN
	Sim.tool_roe = DroneSim.Roe.RTRN
	Sim.order_point(Vector2(1600, 400))
	Sim.launch(0)
	var t0 := Sim.game_time
	while Sim.game_time - t0 < 420.0:
		for k in 120:
			Sim._step(0.5)
		await get_tree().process_frame
	await _wait(1.0)
	await mfd_shot("e1_mfd_linklost")
	main.player._press("btn_alert")
	await _wait(2.0)
	await shot("e2_alert_seated")
	await mfd_shot("e3_alert_mfd")
	main.player._switch(Player.Mode.TABLE)
	main.player._blend = 1.0
	await _wait(1.0)
	await shot("e4_alert_table")
	get_tree().quit()


func dronetest() -> void:
	Sim.select(1)
	Sim.tool_act = DroneSim.Act.MOVE
	Sim.order_point(Vector2(-1500, 600))
	Sim.tool_act = DroneSim.Act.LOIT
	Sim.order_point(Vector2(-2500, -900))
	Sim.launch(1)
	var d: DroneSim = Sim.drones[1]
	for i in 900:
		Sim._step(0.5)
		if i % 40 == 0:
			print("t=%d %s pos=%s alt=%.0f wp=%d mode=%s link=%d spd=%.1f" % [int(Sim.game_time), d.status_text(), str(d.pos2().round()), d.pos.y - Sim.terrain.height_at(d.pos.x, d.pos.z), d.wp, d.mode, d.link, d.speed])
	get_tree().quit()


func look() -> void:
	var p: Player = main.player
	p.feet = Vector3(-2.0, 0.0, -4.2)
	p.yaw = deg_to_rad(-10)
	p.pitch = deg_to_rad(-10)
	p._switch(Player.Mode.WALK)
	p._blend = 1.0
	await _wait(0.6)
	await shot("l1_window")
	p.feet = Vector3(-6.0, 0.0, -5.0)
	p.yaw = deg_to_rad(35)
	p.pitch = deg_to_rad(2)
	await _wait(0.6)
	await shot("l1b_window_west")
	var c := Camera3D.new()
	main.world.add_child(c)
	c.far = 20000.0
	c.current = true
	var cx: Transform3D = main.world.carrier_xform()
	c.global_position = cx * Vector3(-300, 110, -520)
	c.look_at(cx * Vector3(0, 40, 0), Vector3.UP)
	await _wait(0.8)
	await shot("l2_carrier_front")
	c.global_position = cx * Vector3(250, 160, 300)
	c.look_at(cx * Vector3(-2000, 300, 0), Vector3.UP)
	await _wait(0.8)
	await shot("l2b_storm")
	c.global_position = cx * Vector3(400, 30, 100)
	c.look_at(cx * Vector3(0, 30, 0), Vector3.UP)
	await _wait(0.8)
	await shot("l3_carrier_side_low")
	var o := Terrain.OASIS
	var h := Sim.terrain.height_at(o.x, o.y)
	c.global_position = Vector3(o.x + 500, h + 120, o.y + 500)
	c.look_at(Vector3(o.x, h, o.y), Vector3.UP)
	await _wait(0.8)
	await shot("l4_oasis")
	get_tree().quit()


func logishots() -> void:
	# the logistics screens, with a hub at the mine and a hauler on a standing route
	var mine: SiteSim = Sim.site_at(Terrain.MINE, 50.0)
	Sim.carrier.course.clear()
	Sim.carrier.course.append(Vector2(1820, 1300))
	Sim.set_throttle(2)
	for i in 3000:
		Sim._step(0.5)
	for k in [[Logi.Kind.EXTRACTOR, Vector2(0, 0)], [Logi.Kind.TURRET, Vector2(-70, 60)], [Logi.Kind.PAD, Vector2(60, 70)]]:
		Sim.crane_plant(k[0], mine.pos + k[1])
	Sim.queue_build("kit_relay")
	Sim.queue_build("kit_scanner")
	Sim.queue_module(9, "baffles", 0)
	for i in 1200:
		Sim._step(0.5)
	var h: VehicleSim = Sim.vehicles[0]
	Sim.select(Sim.VEH_SEL + h.id)
	Sim.tool_vact = VehicleSim.Act.LOAD
	Sim.order_point(mine.pos)
	Sim.tool_vact = VehicleSim.Act.HOME
	Sim.order_point(mine.pos)
	h.standing = true
	Sim.deploy_vehicle(h)
	var l: VehicleSim = Sim.vehicles[1]
	Sim.select(Sim.VEH_SEL + l.id)
	Sim.tool_vact = VehicleSim.Act.BUILD
	Sim.tool_kit = Logi.Kind.RELAY
	Sim.order_point(Vector2(-900, 600))
	Sim.tool_vact = VehicleSim.Act.HOME
	Sim.order_point(Vector2.ZERO)
	Sim.deploy_vehicle(l)
	Sim.select(0)
	Sim.tool_act = DroneSim.Act.SCAN
	Sim.order_point(Vector2(-2500, -900))
	Sim.launch(0)
	Sim.set_throttle(1)
	for i in 4200:
		Sim._step(0.5)
	Sim.select(Sim.VEH_SEL + h.id)
	var mfd: MFD = main.bridge.projection.mfd
	mfd.apply_preset("LOGISTICS", false)
	await _wait(1.5)
	await mfd_shot("g1_logistics")
	mfd.apply_preset("FITTING", false)
	(mfd.frames["fitting"].content as FittingPanel).sel_slot = 3
	await _wait(1.5)
	await mfd_shot("g2_fitting")
	Sim.select(-1)
	mfd.apply_preset("COMBAT", false)
	var tac: TacticalPanel = mfd.frames["tactical"].content
	tac.plant_on = true
	tac.plant_kind = Logi.Kind.RELAY
	tac.map.hover = tac.map.w2p(Sim.carrier.pos2() + Vector2(250, 120))
	await _wait(1.5)
	await mfd_shot("g3_combat_plant")
	print("[director] logistics F%.0f M%.0f delivered %s" % [Sim.stores.fuel, Sim.stores.mat, str(Sim.stores.delivered)])
	main.player._switch(Player.Mode.TABLE)
	main.player._blend = 1.0
	await _wait(1.0)
	await shot("g4_holo")
	get_tree().quit()


func quick() -> void:
	var p: Player = main.player
	Sim.select(0)
	Sim.tool_act = DroneSim.Act.MOVE
	Sim.tool_roe = DroneSim.Roe.RTRN
	Sim.order_point(Vector2(800, 1800))
	Sim.tool_act = DroneSim.Act.SCAN
	Sim.order_point(Vector2(1900, 1000))
	Sim.tool_act = DroneSim.Act.LOIT
	Sim.tool_roe = DroneSim.Roe.FLEE
	Sim.order_point(Vector2(1200, -600))
	Sim.launch(0)
	Sim.set_scale_idx(3)
	await _wait(10.0)
	Sim.set_scale_idx(0)
	await _wait(1.0)
	await shot("q1_seated")
	await mfd_shot("q2_mfd_combat")
	main.bridge.projection.mfd.apply_preset("TRANSIT", false)
	await _wait(1.0)
	await mfd_shot("q3_mfd_transit")
	main.bridge.projection.mfd.apply_preset("COMBAT", false)
	p.feet = Vector3(3.0, 0.0, 3.6)
	p.yaw = deg_to_rad(15)
	p.pitch = deg_to_rad(-6)
	p._switch(Player.Mode.WALK)
	p._blend = 1.0
	await _wait(0.6)
	await shot("q4_room")
	p.feet = Vector3(-3.0, 0.0, 2.2)
	p.yaw = deg_to_rad(160)
	p.pitch = deg_to_rad(4)
	await _wait(0.6)
	await shot("q4b_back_wall")
	var c := Camera3D.new()
	main.world.add_child(c)
	var cx: Transform3D = main.world.carrier_xform()
	c.global_position = cx * Vector3(-300, 120, 420)
	c.look_at(cx * Vector3(0, 40, -40), Vector3.UP)
	c.far = 20000.0
	c.current = true
	await _wait(1.0)
	await shot("q5_exterior")
	get_tree().quit()


func tour() -> void:
	var p: Player = main.player
	await shot("01_seated_boot")
	# orders for Swift-1: scan out to the south-east, loiter, flee if shot at
	Sim.select(0)
	Sim.tool_act = DroneSim.Act.MOVE
	Sim.tool_roe = DroneSim.Roe.RTRN
	Sim.order_point(Vector2(800, 1800))
	Sim.tool_act = DroneSim.Act.SCAN
	Sim.order_point(Vector2(1900, 1000))
	Sim.tool_act = DroneSim.Act.LOIT
	Sim.tool_roe = DroneSim.Roe.FLEE
	Sim.order_point(Vector2(1200, -600))
	Sim.launch(0)
	await _wait(6.0)
	await shot("02_seated_launch")
	Sim.set_scale_idx(3)
	await _wait(14.0)
	Sim.set_scale_idx(0)
	await shot("03_seated_after_tc")
	p.yaw = deg_to_rad(60)
	p.pitch = deg_to_rad(-15)
	await _wait(0.5)
	await shot("04_seated_look_left")
	p.yaw = 0.0
	p.pitch = -0.08
	main.bridge.projection.mfd.apply_preset("RECON", false)
	await _wait(1.0)
	await shot("05_recon_layout")
	main.bridge.projection.mfd.apply_preset("TRANSIT", false)
	await _wait(1.0)
	await shot("06_transit_layout")
	main.bridge.projection.mfd.apply_preset("COMBAT", false)
	p.feet = Vector3(-1.5, 0.0, 3.2)
	p.yaw = deg_to_rad(-15)
	p.pitch = deg_to_rad(-12)
	p._switch(Player.Mode.WALK)
	p._blend = 1.0
	await _wait(0.6)
	await shot("07_standing_room")
	p.feet = Vector3(4.0, 0.0, 5.0)
	p.yaw = deg_to_rad(20)
	p.pitch = deg_to_rad(5)
	await _wait(0.6)
	await shot("08_standing_window")
	p._switch(Player.Mode.TABLE)
	p._blend = 1.0
	await _wait(0.8)
	await shot("09_holo_table")
	p._switch(Player.Mode.TERMINAL)
	p._blend = 1.0
	await _wait(0.8)
	await shot("10_terminal")
	# exterior: free camera near the carrier
	var c := Camera3D.new()
	main.world.add_child(c)
	var cx: Transform3D = main.world.carrier_xform()
	c.global_transform = Transform3D().looking_at(Vector3(0, -0.25, -1), Vector3.UP)
	c.global_position = cx * Vector3(-260, 140, 380)
	c.look_at(cx * Vector3(0, 40, -40), Vector3.UP)
	c.far = 20000.0
	c.current = true
	await _wait(1.0)
	await shot("11_exterior_carrier")
	var d: DroneSim = Sim.drones[0]
	c.global_position = d.pos + Vector3(-25, 8, 30)
	c.look_at(d.pos, Vector3.UP)
	await _wait(0.5)
	await shot("12_exterior_drone")
	var r: RaiderSim = Sim.raiders[0]
	c.global_position = r.pos + Vector3(-14, 6, 18)
	c.look_at(r.pos + Vector3(0, 1, 0), Vector3.UP)
	await _wait(0.6)
	await shot("13_exterior_raider")
	var n := Terrain.CAMP
	var h := Sim.terrain.height_at(n.x, n.y)
	c.global_position = Vector3(n.x - 90, h + 40, n.y + 110)
	c.look_at(Vector3(n.x, h + 8, n.y), Vector3.UP)
	await _wait(0.6)
	await shot("14_exterior_node")
	print("[director] done. game time ", Sim.clock_text(), " log lines ", Sim.log_lines.size())
	for l in Sim.log_lines:
		print("   ", Sim.clock_text(l.t), " ", l.who, ": ", l.text)
	get_tree().quit()
