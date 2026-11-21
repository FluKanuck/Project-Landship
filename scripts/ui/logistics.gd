class_name LogisticsPanel
extends Control
## Logistics: the holds (fuel and materials, with their trend), every hub with its
## stockpile and whether we can hear it, every hauler and lifter with its route and load,
## and the fabricator: what it is building, what is queued, and buttons to queue more.

var board: Control
var queue_view: Control
var build_btns := {}
var cancel_btn: Button


func _ready() -> void:
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.add_theme_constant_override("separation", 10)
	add_child(h)
	board = Control.new()
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.clip_contents = true
	board.draw.connect(_draw_board)
	h.add_child(board)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(300, 0)
	right.add_theme_constant_override("separation", 4)
	h.add_child(right)
	right.add_child(UiTheme.label("FABRICATE", 16, Pal.UI_DIM))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	right.add_child(grid)
	for k in Logi.FAB_ORDER:
		if k == "swift":
			continue
		var b := UiTheme.button("", false, 146)
		b.add_theme_font_size_override("font_size", 15)
		b.custom_minimum_size.y = 32
		b.pressed.connect(func():
			if not Sim.queue_build(k):
				Sfx.ui("err"))
		b.tooltip_text = "%s: %d materials, %d min at fabricator speed 1" % [Logi.FAB[k].name, Logi.FAB[k].cost, int(Logi.FAB[k].time / 60.0)]
		grid.add_child(b)
		build_btns[k] = b
	queue_view = Control.new()
	queue_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	queue_view.draw.connect(_draw_queue)
	right.add_child(queue_view)
	cancel_btn = UiTheme.button("CANCEL LAST", false, 0)
	cancel_btn.add_theme_font_size_override("font_size", 15)
	cancel_btn.custom_minimum_size.y = 32
	cancel_btn.pressed.connect(func():
		if not Sim.fab.queue.is_empty():
			var it: Dictionary = Sim.fab.queue[-1]
			if it.kind != "swift":
				Sim.fab.cancel(it.uid, Sim.stores))
	right.add_child(cancel_btn)


func frame_subtitle() -> String:
	return "HUBS %d   VEHICLES %d   KITS ABOARD %d" % [Sim.hubs().size(), Sim.vehicles.filter(func(v): return v.state != VehicleSim.State.DESTROYED).size(), Sim.kits_total()]


func _process(_d: float) -> void:
	for k in build_btns:
		var b: Button = build_btns[k]
		var short: String = Logi.FAB[k].name.replace(" KIT", "")
		b.text = "+%s  %d" % [short, Logi.FAB[k].cost]
		b.disabled = false
	cancel_btn.disabled = Sim.fab.queue.is_empty()
	board.queue_redraw()
	queue_view.queue_redraw()


func _bar(ci: CanvasItem, r: Rect2, frac: float, col: Color, text: String) -> void:
	ci.draw_rect(r, Pal.UI_DIM, false, 1.5)
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), Color(col, 0.55))
	ci.draw_string(UiTheme.font, r.position + Vector2(6, r.size.y - 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Pal.UI_HOT)


func _draw_board() -> void:
	var f := UiTheme.font
	var ci := board
	var w := ci.size.x
	var st := Sim.stores
	var y := 4.0
	for r in 2:
		var tr := st.trend(r)
		var txt := "%s %d / %d   %s%d/H" % [Logi.RES_NAMES[r], int(st.amount(r)), int(st.cap(r)), "+" if tr >= 0 else "", int(tr)]
		var col := Pal.UI_TEXT if st.frac(r) > 0.2 else Pal.UI_ENEMY
		_bar(ci, Rect2(4, y, minf(w - 8, 520), 22), st.frac(r), col, txt)
		y += 28
	ci.draw_string(f, Vector2(4, y + 14), "DELIVERED F%d M%d   SPENT F%d M%d   CRANE %s" % [int(st.delivered[0]), int(st.delivered[1]), int(st.spent[0]), int(st.spent[1]),
		"BUSY" if Sim.crane_user >= 0 else ("FREE" if Sim.fitting.has("crane") else "NOT FITTED")], HORIZONTAL_ALIGNMENT_LEFT, w - 8, 15, Pal.UI_DIM)
	y += 30
	ci.draw_line(Vector2(0, y), Vector2(w, y), Pal.UI_DIM, 1)
	y += 20
	ci.draw_string(f, Vector2(4, y), "HUB         KIND  LINK  STOCK F / M   PARTS", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Pal.UI_DIM)
	y += 22
	var hubs := Sim.hubs()
	# sites we lost but still remember as ours show as dark until re-seen
	if hubs.is_empty():
		ci.draw_string(f, Vector2(4, y), "NO HUBS. FIND A SITE, PLANT AN EXTRACTOR, A TURRET AND A PAD.", HORIZONTAL_ALIGNMENT_LEFT, w - 8, 16, Pal.UI_DIM)
		y += 22
	for s in hubs:
		var linked := s.linked
		var stock: Array = s.stock if linked else s.known_stock
		var col := Pal.UI_FRIEND if linked else Color(Pal.UI_FRIEND, 0.5)
		if linked and s.under_attack > 0.0:
			col = Pal.UI_ENEMY
		var link := "OK" if linked else "DARK"
		var parts := s.known_parts
		ci.draw_string(f, Vector2(4, y), "%-11s %-5s %-5s %4d / %-4d   %s" % [s.name, Logi.SITE_KIND_SHORT[s.kind], link, int(stock[0]), int(stock[1]), parts], HORIZONTAL_ALIGNMENT_LEFT, w - 8, 16, col)
		y += 21
		if y > ci.size.y * 0.58:
			break
	y += 6
	ci.draw_line(Vector2(0, y), Vector2(w, y), Pal.UI_DIM, 1)
	y += 20
	ci.draw_string(f, Vector2(4, y), "VEHICLE  FIT              STATUS               CARGO   TRIPS", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Pal.UI_DIM)
	y += 22
	for v in Sim.vehicles:
		if v.state == VehicleSim.State.DESTROYED:
			continue
		var col := Pal.UI_FRIEND if v.is_out() else Pal.UI_TEXT
		if v.under_fire > 0.0:
			col = Pal.UI_ENEMY
		if v.link == DroneSim.Link.LOST and v.is_out():
			col = Color(Pal.UI_FRIEND, 0.5)
		var cargo := "F%d M%d" % [int(v.cargo[0]), int(v.cargo[1])] if v.cargo_total() > 0.5 else "-"
		var fit := ("POD" if v.utility == "pod" else ("ENG" if v.utility == "engineer" else "SLING")) + ("+GUN" if v.gun else "")
		ci.draw_string(f, Vector2(4, y), "%-8s %-9s %s%-20s %-7s %d" % [v.callsign, fit, "@" if v.standing else " ", v.status_text().left(20), cargo, v.trips], HORIZONTAL_ALIGNMENT_LEFT, w - 8, 16, col)
		y += 21
		if y > ci.size.y - 6:
			break


func _draw_queue() -> void:
	var ci := queue_view
	var f := UiTheme.font
	var y := 16.0
	var speed: float = Sim.fitting.stat("fab_speed")
	ci.draw_string(f, Vector2(0, y), "QUEUE  x%.1f SPEED" % speed, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Pal.UI_DIM)
	y += 20
	if Sim.fab.queue.is_empty():
		ci.draw_string(f, Vector2(0, y), "IDLE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Pal.UI_DIM)
	for i in Sim.fab.queue.size():
		var it: Dictionary = Sim.fab.queue[i]
		var col := Pal.UI_HOT if i == 0 else Pal.UI_TEXT
		var txt: String = it.name
		if i == 0:
			if not it.paid:
				txt += "  WAIT %d MAT" % int(it.cost)
				col = Pal.UI_WARN
			else:
				txt += "  %s" % Sim.age_text((it.total - it.progress) / maxf(speed, 0.01))
			ci.draw_rect(Rect2(0, y + 4, ci.size.x * it.progress / it.total, 3), Pal.UI_HOT)
		ci.draw_string(f, Vector2(0, y), txt, HORIZONTAL_ALIGNMENT_LEFT, ci.size.x, 15, col)
		y += 22
		if y > ci.size.y - 30:
			break
	var kits := []
	for k in Sim.kit_bay:
		if Sim.kit_bay[k] > 0:
			kits.append("%s x%d" % [Logi.KIND_SHORT[k], Sim.kit_bay[k]])
	ci.draw_string(f, Vector2(0, ci.size.y - 6), "KIT BAY: " + (" ".join(kits) if not kits.is_empty() else "EMPTY"), HORIZONTAL_ALIGNMENT_LEFT, ci.size.x, 15, Pal.UI_TEXT)
