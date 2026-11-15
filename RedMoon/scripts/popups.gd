class_name Popups
extends CanvasLayer

const TOAST_WIDTH := 224.0
const TOAST_HEIGHT := 36.0
const HOLD_SECONDS := 3.4

var _queue: Array[Dictionary] = []
var _active_panel: PanelContainer
var _title_lbl: Label
var _desc_lbl: Label
var _icon_rect: TextureRect
var _timer: float = 0.0
var _showing: bool = false


func _ready() -> void:
	layer = 50
	_build_panel()


func enqueue(title: String, subtitle: String, icon_id: String = "trophy") -> void:
	_queue.append({"title": title, "desc": subtitle, "icon": icon_id})
	if not _showing:
		_pop_next()


func _process(delta: float) -> void:
	if not _showing or _active_panel == null:
		return

	_timer -= delta
	var target_x := Config.VIEW_SIZE.x - TOAST_WIDTH - 10.0
	var hidden_x := Config.VIEW_SIZE.x + 12.0

	if _timer > HOLD_SECONDS - 0.25:
		var t_in := clampf((HOLD_SECONDS - _timer) / 0.25, 0.0, 1.0)
		_active_panel.position.x = floorf(lerpf(hidden_x, target_x, t_in))
	elif _timer < 0.25:
		var t_out := clampf(_timer / 0.25, 0.0, 1.0)
		_active_panel.position.x = floorf(lerpf(hidden_x, target_x, t_out))
	else:
		_active_panel.position.x = target_x

	if _timer <= 0.0:
		_showing = false
		_active_panel.visible = false
		_pop_next()


func _pop_next() -> void:
	if _queue.is_empty():
		return

	var item = _queue.pop_front()
	_title_lbl.text = String(item["title"])
	_desc_lbl.text = String(item["desc"])
	_icon_rect.texture = Art.get_icon_texture(String(item.get("icon", "trophy")))

	_showing = true
	_timer = HOLD_SECONDS
	_active_panel.position = Vector2(Config.VIEW_SIZE.x + 12.0, 48.0)
	_active_panel.visible = true


func _build_panel() -> void:
	_active_panel = PanelContainer.new()
	_active_panel.size = Vector2(TOAST_WIDTH, TOAST_HEIGHT)
	_active_panel.position = Vector2(Config.VIEW_SIZE.x + 12.0, 48.0)
	_active_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_active_panel.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.08, 0.14, 0.94)
	style.border_color = Color(0.94, 0.72, 0.30, 1.0)
	style.set_border_width_all(1)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	_active_panel.add_theme_stylebox_override("panel", style)
	add_child(_active_panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	_active_panel.add_child(hbox)

	_icon_rect = TextureRect.new()
	_icon_rect.custom_minimum_size = Vector2(20.0, 20.0)
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hbox.add_child(_icon_rect)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(vbox)

	_title_lbl = Label.new()
	Art.style_label(_title_lbl, "bold", 8, Color(1.0, 0.88, 0.45))
	vbox.add_child(_title_lbl)

	_desc_lbl = Label.new()
	_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Art.style_label(_desc_lbl, "body", 8, Color(0.90, 0.90, 0.94))
	vbox.add_child(_desc_lbl)
