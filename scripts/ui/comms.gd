class_name CommsPanel
extends Control
## Comms log: every callout, stamped with game time, newest at the bottom.


func _process(_d: float) -> void:
	queue_redraw()


func frame_subtitle() -> String:
	var parts := []
	for d in Sim.drones:
		if d.airborne():
			parts.append("%s %s" % [d.callsign, ["OK", "WEAK", "LOST"][d.link]])
	return "  ".join(parts) if not parts.is_empty() else "NET QUIET"


func _wrap(f: Font, text: String, width: float, fs: int) -> PackedStringArray:
	var out := PackedStringArray()
	var line := ""
	for w in text.split(" "):
		var trial := w if line == "" else line + " " + w
		if f.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width and line != "":
			out.append(line)
			line = w
		else:
			line = trial
	if line != "":
		out.append(line)
	return out


func _draw() -> void:
	var f := UiTheme.font
	var lh := 22.0
	var fs := 18
	var narrow := size.x < 520.0
	var text_x := 8.0 if narrow else 182.0
	var width := size.x - text_x - 8.0
	# lay out newest-first from the bottom until the panel is full
	var y := size.y - 8.0
	var i := Sim.log_lines.size() - 1
	var shown := 0
	while i >= 0 and y > 20.0:
		var l: Dictionary = Sim.log_lines[i]
		var rows := _wrap(f, l.text, width, fs)
		var block := rows.size() * lh + (lh if narrow else 0.0)
		var top := y - block
		if top < 0.0:
			break
		var col: Color = Pal.UI_WARN if l.warn else Pal.UI_TEXT
		if shown >= 5:
			col.a *= 0.6
		var ts := Sim.clock_text(l.t).substr(3)
		var who_col := Pal.UI_FRIEND if l.who != "SENSORS" else Pal.UI_ENEMY.lerp(Pal.UI_TEXT, 0.4)
		var ry := top + lh - 5.0
		if narrow:
			draw_string(f, Vector2(8, ry), ts + "  " + l.who, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, who_col)
			ry += lh
		else:
			draw_string(f, Vector2(6, ry), ts, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Pal.UI_DIM)
			draw_string(f, Vector2(92, ry), l.who, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, who_col)
		for r in rows:
			draw_string(f, Vector2(text_x, ry), r, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			ry += lh
		y = top - 6.0
		i -= 1
		shown += 1
