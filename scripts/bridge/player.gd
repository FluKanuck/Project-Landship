class_name Player
extends Node3D
## The commander. Sits in the chair with the display around them; can stand, walk the room,
## lean over the holo table, or use the settings terminal. Hold ALT (or press TAB) for a
## cursor while the view stays put.

signal hint_changed(text: String)

enum Mode { SEATED, WALK, TABLE, TERMINAL }

const EYE := 1.65
const WALK_SPEED := 2.3
const RUN_SPEED := 4.2
const CHAIR := Vector3(0, 0.5, 5.4)
const TABLE := Vector3(0, 0, -0.8)
const TERMINAL_P := Vector3(7.6, 0, -5.2)

var bridge: Bridge
var cam: Camera3D
var mode := Mode.SEATED
var yaw := 0.0
var pitch := -0.08
var feet := Vector3(0, 0.5, 4.6)
var cursor_toggle := false
var alt_held := false
var _blend := 1.0
var _from := Transform3D()
var _hint := ""
var _drag_pan := false
var _last_uv := Vector2(-1, -1)
var _bob := 0.0
var _boot_lock := true


func _init(b: Bridge) -> void:
	bridge = b


func _ready() -> void:
	cam = Camera3D.new()
	cam.near = 0.05
	cam.far = 22000.0
	cam.fov = Prefs.fov
	cam.current = true
	add_child(cam)
	Prefs.changed.connect(func(): cam.fov = Prefs.fov if mode != Mode.TABLE else cam.fov)
	cam.transform = _seat_xform()


func cursor_active() -> bool:
	return mode in [Mode.TABLE, Mode.TERMINAL] or (mode == Mode.SEATED and (alt_held or cursor_toggle))


func release_boot() -> void:
	_boot_lock = false


# ------------------------------------------------------------------ poses

func _seat_xform() -> Transform3D:
	var eye := CHAIR + Vector3(0, 1.22, -0.02)
	return Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0)), eye)


func _walk_xform() -> Transform3D:
	var bob := sin(_bob) * 0.025
	return Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0)), feet + Vector3(0, EYE + bob, 0))


func _table_xform() -> Transform3D:
	var p := TABLE + Vector3(0, 2.45, 2.15)
	return Transform3D(Basis.from_euler(Vector3(deg_to_rad(-50), 0, 0)), p)


func _terminal_xform() -> Transform3D:
	var t := bridge.terminal.transform
	var p := t * Vector3(0, 1.45, 0.75)
	var look := t * Vector3(0, 1.3, 0.0)
	return Transform3D().looking_at(look - p, Vector3.UP).translated(p)


func _target_xform() -> Transform3D:
	match mode:
		Mode.SEATED: return _seat_xform()
		Mode.WALK: return _walk_xform()
		Mode.TABLE: return _table_xform()
		Mode.TERMINAL: return _terminal_xform()
	return Transform3D()


func _switch(m: int) -> void:
	_from = cam.transform
	_blend = 0.0
	mode = m
	cursor_toggle = false
	if m == Mode.WALK:
		Sfx.ui("button")
	_update_mouse_mode()


func _update_mouse_mode() -> void:
	var want := Input.MOUSE_MODE_VISIBLE if cursor_active() else Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != want:
		Input.mouse_mode = want


# ------------------------------------------------------------------ input

func _unhandled_input(ev: InputEvent) -> void:
	if _boot_lock:
		return
	if ev is InputEventMouseButton and ev.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not cursor_active():
		_update_mouse_mode()
	if ev.is_action_pressed("cursor_toggle") and mode == Mode.SEATED:
		cursor_toggle = not cursor_toggle
		_update_mouse_mode()
	if ev is InputEventKey and ev.keycode == KEY_ALT:
		alt_held = ev.pressed
		_update_mouse_mode()
	if ev.is_action_pressed("interact"):
		_interact()
	if ev.is_action_pressed("escape"):
		if mode in [Mode.TABLE, Mode.TERMINAL]:
			_leave_station()
		elif cursor_toggle:
			cursor_toggle = false
			_update_mouse_mode()
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if ev.is_action_pressed("time_up"):
		Sim.set_scale_idx(Sim.scale_idx + 1)
	if ev.is_action_pressed("time_down"):
		Sim.set_scale_idx(Sim.scale_idx - 1)
	for i in 3:
		if ev.is_action_pressed("select_%d" % (i + 1)):
			Sim.select(i if i < 2 else -1)
	if ev.is_action_pressed("select_vehicle"):
		# cycle the haulers and lifters
		var n := Sim.vehicles.size()
		var start := Sim.selected - Sim.VEH_SEL if Sim.selected >= Sim.VEH_SEL else -1
		for k in n:
			var i := (start + 1 + k) % n
			if Sim.vehicles[i].state != VehicleSim.State.DESTROYED:
				Sim.select(Sim.VEH_SEL + i)
				break
	if ev.is_action_pressed("preset_5"):
		bridge.projection.mfd.apply_preset("LOGISTICS")
	if ev.is_action_pressed("preset_6"):
		bridge.projection.mfd.apply_preset("FITTING")
	if mode in [Mode.SEATED, Mode.WALK]:
		for i in 4:
			if ev.is_action_pressed("preset_%d" % (i + 1)):
				_press(["btn_combat", "btn_recon", "btn_transit", "btn_alert"][i])

	# look
	if ev is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not cursor_active():
		var s := 0.0022 * Prefs.sensitivity
		yaw -= ev.relative.x * s
		pitch -= ev.relative.y * s * (-1.0 if Prefs.invert_y else 1.0)
		pitch = clampf(pitch, deg_to_rad(-75), deg_to_rad(75))
		if mode == Mode.SEATED:
			yaw = clampf(yaw, deg_to_rad(-115), deg_to_rad(115))
	# pointer work
	if cursor_active() and ev is InputEventMouse:
		_pointer(ev)


func _press(name: String) -> void:
	bridge.press(name)
	var mfd := bridge.projection.mfd
	match name:
		"btn_combat": mfd.apply_preset("COMBAT")
		"btn_recon": mfd.apply_preset("RECON")
		"btn_transit": mfd.apply_preset("TRANSIT")
		"btn_alert":
			Sim.set_alert(not Sim.alert)
			if Sim.alert:
				mfd.apply_preset("COMBAT")


func _pointer(ev: InputEventMouse) -> void:
	var o := cam.project_ray_origin(ev.position)
	var d := cam.project_ray_normal(ev.position)
	match mode:
		Mode.SEATED:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				var b := bridge.button_at(o, d)
				if b != "":
					_press(b)
					return
			var uv := bridge.projection.uv_at(o, d)
			if uv.x >= 0.0:
				bridge.projection.push_mouse(ev, uv)
				_last_uv = uv
			elif _last_uv.x >= 0.0 and ev is InputEventMouseButton and not ev.pressed:
				bridge.projection.push_mouse(ev, _last_uv) # finish drags that leave the display
		Mode.TERMINAL:
			var uv := RayScreen.uv_hit(bridge.terminal_screen, o, d)
			if uv.x >= 0.0:
				RayScreen.push_mouse(bridge.settings.viewport, ev, uv)
		Mode.TABLE:
			_table_input(ev, o, d)


func _table_input(ev: InputEventMouse, o: Vector3, d: Vector3) -> void:
	var holo := bridge.holo
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
			holo.zoom_by(0.85, holo.pick(o, d))
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			holo.zoom_by(1.0 / 0.85)
		elif ev.button_index == MOUSE_BUTTON_RIGHT:
			_drag_pan = ev.pressed
		elif ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			var w := holo.pick(o, d)
			if w != Vector2.INF:
				if not Sim.order_point(w):
					Sfx.ui("err")
	elif ev is InputEventMouseMotion and _drag_pan:
		holo.pan_by(ev.relative)


func _interact() -> void:
	match mode:
		Mode.SEATED:
			feet = Vector3(0, 0.5, 4.55)
			_switch(Mode.WALK)
		Mode.WALK:
			match _nearest():
				"chair":
					yaw = 0.0
					pitch = -0.08
					_switch(Mode.SEATED)
				"table":
					_switch(Mode.TABLE)
				"terminal":
					_switch(Mode.TERMINAL)
		Mode.TABLE, Mode.TERMINAL:
			_leave_station()


func _leave_station() -> void:
	if mode == Mode.TABLE:
		feet = Vector3(0, 0, 1.4)
		yaw = 0.0
		pitch = -0.5
	elif mode == Mode.TERMINAL:
		feet = TERMINAL_P + bridge.terminal.transform.basis * Vector3(0, 0, 1.1)
		feet.y = 0.0
		var to := TERMINAL_P - feet
		yaw = atan2(-to.x, -to.z)
	_switch(Mode.WALK)


func _nearest() -> String:
	var p := Vector2(feet.x, feet.z)
	if p.distance_to(Vector2(CHAIR.x, CHAIR.z)) < 1.4:
		return "chair"
	if p.distance_to(Vector2(TABLE.x, TABLE.z)) < 2.8:
		return "table"
	if p.distance_to(Vector2(TERMINAL_P.x, TERMINAL_P.z)) < 1.6:
		return "terminal"
	return ""


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	if mode == Mode.WALK and not _boot_lock:
		_walk(delta)
	var target := _target_xform()
	if _blend < 1.0:
		_blend = minf(1.0, _blend + delta * 1.8)
		var k := smoothstep(0.0, 1.0, _blend)
		cam.transform = _from.interpolate_with(target, k)
	else:
		cam.transform = target
	if mode == Mode.TABLE:
		cam.fov = lerpf(cam.fov, 60.0, delta * 3.0)
	else:
		cam.fov = lerpf(cam.fov, Prefs.fov, delta * 3.0)
	_update_hint()


func _walk(delta: float) -> void:
	var input := Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_forward", "move_back"))
	if input.length() > 1.0:
		input = input.normalized()
	var spd := RUN_SPEED if Input.is_action_pressed("run") else WALK_SPEED
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	var move := (right * input.x - fwd * input.y) * spd * delta
	if move.length() > 0.0001:
		_bob += delta * spd * 3.4
	var p := Vector2(feet.x, feet.z)
	var nx := Vector2(p.x + move.x, p.y)
	if _free(nx):
		p = nx
	var nz := Vector2(p.x, p.y + move.y)
	if _free(nz):
		p = nz
	feet.x = p.x
	feet.z = p.y
	feet.y = lerpf(feet.y, _floor(p), clampf(delta * 12.0, 0.0, 1.0))


func _floor(p: Vector2) -> float:
	if absf(p.x) < 2.4 and p.y > 4.2:
		return 0.5
	if absf(p.x) < 2.0 and p.y > 3.6:
		return 0.25
	return 0.0


func _free(p: Vector2) -> bool:
	if absf(p.x) > 8.2 or p.y < -6.15 or p.y > 6.65:
		return false
	if absf(p.x) > 3.0 and absf(p.x) < 6.8 and p.y > -4.0 and p.y < 2.8:
		return false # crew pits
	if p.distance_to(Vector2(TABLE.x, TABLE.z)) < 1.95:
		return false
	if p.distance_to(Vector2(CHAIR.x, CHAIR.z)) < 0.45:
		return false
	if absf(absf(p.x) - 2.35) < 0.15 and p.y > 4.25:
		return false # dais rails
	if p.distance_to(Vector2(TERMINAL_P.x, TERMINAL_P.z)) < 0.6:
		return false
	return true


func _update_hint() -> void:
	var h := ""
	match mode:
		Mode.SEATED:
			h = "[E] STAND UP     HOLD [ALT] / [TAB] CURSOR     [1-4] DISPLAY PRESETS     [,] [.] TIME"
			if cursor_active():
				h = "CURSOR: CLICK THE DISPLAY OR THE CHAIR BUTTONS.  DRAG A SECTION HEADER TO SWAP SECTIONS."
		Mode.WALK:
			match _nearest():
				"chair": h = "[E] SIT IN THE COMMAND CHAIR"
				"table": h = "[E] USE THE HOLO TABLE"
				"terminal": h = "[E] SETTINGS TERMINAL"
				_: h = "[WASD] WALK   [SHIFT] RUN"
		Mode.TABLE:
			h = "HOLO TABLE: [LMB] ORDER  [RMB DRAG] PAN  [WHEEL] ZOOM  [F1/F2/F3] UNIT  [E] STEP BACK"
		Mode.TERMINAL:
			h = "SETTINGS: CLICK TO ADJUST.  [E] / [ESC] STEP BACK"
	if h != _hint:
		_hint = h
		hint_changed.emit(h)
