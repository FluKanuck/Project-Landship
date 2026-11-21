class_name FittingPanel
extends Control
## Fitting: the landship's slots (each with a size limit) and what is in them. Pick a slot
## to upgrade its module a tier, pull it out, or fabricate a different module for it. Below,
## the refit bay for the selected hauler or lifter while she is aboard.

var slot_btns: Array[Button] = []
var sel_slot := 0
var detail: Control
var opt_box: VBoxContainer
var opt_btns: Array[Button] = []
var upgrade_btn: Button
var remove_btn: Button
var veh_row: HBoxContainer
var veh_label: Label
var util_btns := {}
var gun_btn: Button
var _built_for := ""


func _ready() -> void:
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.add_theme_constant_override("separation", 10)
	add_child(h)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(290, 0)
	left.add_theme_constant_override("separation", 3)
	h.add_child(left)
	for i in Sim.fitting.slots.size():
		var b := UiTheme.button("", true, 0)
		b.add_theme_font_size_override("font_size", 15)
		b.custom_minimum_size.y = 27
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.pressed.connect(func(): sel_slot = i)
		left.add_child(b)
		slot_btns.append(b)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	h.add_child(right)
	detail = Control.new()
	detail.custom_minimum_size = Vector2(0, 92)
	detail.draw.connect(_draw_detail)
	right.add_child(detail)
	var act := HBoxContainer.new()
	act.add_theme_constant_override("separation", 6)
	right.add_child(act)
	upgrade_btn = UiTheme.button("UPGRADE", false, 0)
	upgrade_btn.add_theme_font_size_override("font_size", 15)
	upgrade_btn.pressed.connect(_upgrade)
	act.add_child(upgrade_btn)
	remove_btn = UiTheme.button("REMOVE", false, 0)
	remove_btn.add_theme_font_size_override("font_size", 15)
	remove_btn.pressed.connect(func(): Sim.remove_module(sel_slot))
	act.add_child(remove_btn)
	right.add_child(UiTheme.label("FABRICATE FOR THIS SLOT (REPLACES WHAT IS THERE)", 14, Pal.UI_DIM))
	opt_box = VBoxContainer.new()
	opt_box.add_theme_constant_override("separation", 3)
	opt_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(opt_box)
	veh_label = UiTheme.label("", 15, Pal.UI_DIM)
	right.add_child(veh_label)
	veh_row = HBoxContainer.new()
	veh_row.add_theme_constant_override("separation", 5)
	right.add_child(veh_row)
	for u in Logi.UTILITY:
		var b := UiTheme.button(Logi.UTILITY[u].name, false, 0)
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func():
			var v := Sim.selected_vehicle()
			if v and not Sim.refit_vehicle(v, u, v.gun):
				Sfx.ui("err"))
		veh_row.add_child(b)
		util_btns[u] = b
	gun_btn = UiTheme.button("LIGHT GUN", true, 0)
	gun_btn.add_theme_font_size_override("font_size", 14)
	gun_btn.pressed.connect(func():
		var v := Sim.selected_vehicle()
		if v and not Sim.refit_vehicle(v, v.utility, not v.gun):
			Sfx.ui("err"))
	veh_row.add_child(gun_btn)


func frame_subtitle() -> String:
	var used := 0
	for s in Sim.fitting.slots:
		if s.module != "" or s.refit > 0.0:
			used += 1
	return "%d / %d SLOTS FITTED" % [used, Sim.fitting.slots.size()]


func _upgrade() -> void:
	var s: Dictionary = Sim.fitting.slots[sel_slot]
	if s.module == "" or s.tier >= 2 or s.refit > 0.0:
		Sfx.ui("err")
		return
	if not Sim.queue_module(sel_slot, s.module, s.tier + 1):
		Sfx.ui("err")


func _rebuild_options() -> void:
	for b in opt_btns:
		b.queue_free()
	opt_btns.clear()
	var slot: Dictionary = Sim.fitting.slots[sel_slot]
	var row: HBoxContainer = null
	var n := 0
	for id in Logi.MODULES:
		var m: Dictionary = Logi.MODULES[id]
		if not Logi.fits(m.size, slot.size) or id == slot.module:
			continue
		if n % 2 == 0:
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			opt_box.add_child(row)
		var b := UiTheme.button("%s [%s] %d" % [m.name, Logi.SIZE_NAMES[m.size], m.cost[0]], false, 0)
		b.add_theme_font_size_override("font_size", 14)
		b.custom_minimum_size.y = 28
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = m.desc
		b.pressed.connect(func():
			if not Sim.queue_module(sel_slot, id, 0):
				Sfx.ui("err"))
		row.add_child(b)
		opt_btns.append(b)
		n += 1
	for c in opt_box.get_children():
		if c.get_child_count() == 0:
			c.queue_free()
	_built_for = "%d:%s" % [sel_slot, slot.module]


func _process(_d: float) -> void:
	var fit := Sim.fitting
	for i in slot_btns.size():
		var s: Dictionary = fit.slots[i]
		slot_btns[i].text = "%s%d  %s" % [Logi.SIZE_NAMES[s.size], i + 1, fit.slot_text(i)]
		slot_btns[i].set_pressed_no_signal(i == sel_slot)
	if _built_for != "%d:%s" % [sel_slot, fit.slots[sel_slot].module]:
		for c in opt_box.get_children():
			c.queue_free()
		_rebuild_options()
	var s: Dictionary = fit.slots[sel_slot]
	upgrade_btn.disabled = s.module == "" or s.tier >= 2 or s.refit > 0.0
	if s.module != "" and s.tier < 2:
		upgrade_btn.text = "UPGRADE TO %s  %d MAT" % [Logi.tier_name(s.tier + 1), Logi.MODULES[s.module].cost[s.tier + 1]]
	else:
		upgrade_btn.text = "UPGRADE"
	remove_btn.disabled = s.module == "" or s.refit > 0.0
	var v := Sim.selected_vehicle()
	var ok := v != null and v.state == VehicleSim.State.STOWED and v.refit <= 0.0
	veh_row.visible = v != null
	if v == null:
		veh_label.text = "SELECT A HAULER OR LIFTER TO REFIT IT (ABOARD ONLY)"
	else:
		veh_label.text = "REFIT %s  (%s)  NOW: %s%s" % [v.callsign, Logi.VEH_NAMES[v.type], v.fit_text(), "" if ok else "  - MUST BE ABOARD"]
		for u in util_btns:
			var b: Button = util_btns[u]
			b.visible = Logi.UTILITY[u]["for"].has(v.type)
			b.disabled = not ok or v.utility == u
		gun_btn.disabled = not ok
		gun_btn.set_pressed_no_signal(v.gun)
		gun_btn.text = "LIGHT GUN" + ("" if v.gun else " %d" % Logi.GUN_COST)
	detail.queue_redraw()


func _draw_detail() -> void:
	var f := UiTheme.font
	var hf := UiTheme.font_head
	var s: Dictionary = Sim.fitting.slots[sel_slot]
	detail.draw_string(hf, Vector2(0, 24), "SLOT %s%d   %s" % [Logi.SIZE_NAMES[s.size], sel_slot + 1, Sim.fitting.slot_text(sel_slot)], HORIZONTAL_ALIGNMENT_LEFT, detail.size.x, 22, Pal.UI_HOT)
	if s.module == "":
		detail.draw_string(f, Vector2(0, 52), "EMPTY. TAKES ANY MODULE SIZE %s OR SMALLER." % Logi.SIZE_NAMES[s.size], HORIZONTAL_ALIGNMENT_LEFT, detail.size.x, 16, Pal.UI_DIM)
		return
	var m: Dictionary = Logi.MODULES[s.module]
	detail.draw_string(f, Vector2(0, 50), m.desc.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, detail.size.x, 16, Pal.UI_TEXT)
	var vals := []
	for t in 3:
		var val = m.tiers[t]
		var txt := str(val) if val is int else ("%.2f" % val if val < 10.0 else "%d" % int(val))
		vals.append(("[%s %s]" if t == s.tier else "%s %s") % [Logi.tier_name(t), txt])
	detail.draw_string(f, Vector2(0, 74), "%s:  %s" % [m.stat.to_upper().replace("_", " "), "   ".join(vals)], HORIZONTAL_ALIGNMENT_LEFT, detail.size.x, 16, Pal.UI_TEXT)
