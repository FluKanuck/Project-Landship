class_name PanelFrame
extends Control
## One section of the command display: a header you can drag onto another section to swap
## them (snap-to-grid layout), and a content area.

signal drag_released(frame: PanelFrame, at: Vector2)

const HEAD := 38.0

var key := ""
var title := ""
var subtitle := ""
var content: Control
var _dragging := false
var _drag_at := Vector2.ZERO
var flash := 0.0


func _init(k: String, t: String, c: Control) -> void:
	key = k
	title = t
	content = c
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(c)
	c.position = Vector2(6, HEAD)


func _ready() -> void:
	resized.connect(_fit)
	_fit()


func _fit() -> void:
	content.position = Vector2(6, HEAD + 2)
	content.size = size - Vector2(12, HEAD + 8)


func _process(delta: float) -> void:
	flash = maxf(0.0, flash - delta)
	if content.has_method("frame_subtitle"):
		subtitle = content.frame_subtitle()
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Pal.UI_PANEL)
	var hc := Pal.UI_LINE
	if _dragging:
		hc = Pal.UI_HOT
	draw_rect(Rect2(0, 0, size.x, HEAD - 4), Color(1, 0.69, 0.0, 0.12 + flash * 0.4))
	draw_line(Vector2(0, HEAD - 4), Vector2(size.x, HEAD - 4), hc, 2)
	var f := UiTheme.font_head
	draw_string(f, Vector2(14, 26), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Pal.UI_HOT)
	if subtitle != "":
		draw_string(UiTheme.font, Vector2(14 + f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 18, 26),
			subtitle, HORIZONTAL_ALIGNMENT_LEFT, size.x - 260, 18, Pal.UI_DIM)
	# grip dots: drag here to move the section
	for i in 3:
		draw_rect(Rect2(size.x - 34 + i * 8, 15, 4, 4), Pal.UI_DIM)
	UiTheme.brackets(self, r.grow(-2), Pal.UI_LINE if not _dragging else Pal.UI_HOT, 18, 2)
	if _dragging:
		draw_rect(Rect2(_drag_at - Vector2(70, 14), Vector2(140, 28)), Color(Pal.UI_HOT, 0.25))
		draw_string(UiTheme.font, _drag_at + Vector2(-60, 6), "MOVE " + title.split(" ")[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Pal.UI_HOT)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed and ev.position.y < HEAD:
			_dragging = true
			_drag_at = ev.position
			accept_event()
		elif not ev.pressed and _dragging:
			_dragging = false
			drag_released.emit(self, global_position + ev.position)
			accept_event()
	elif ev is InputEventMouseMotion and _dragging:
		_drag_at = ev.position
