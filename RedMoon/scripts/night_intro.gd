class_name NightIntro
extends CanvasLayer

signal finished()

const TOTAL_DURATION := 7.0

var active: bool = false

var _root: Control
var _sky: MoonSky
var _title_label: Label
var _narration_label: Label
var _skip_label: Label
var _flash: ColorRect

var _elapsed: float = 0.0
var _night_num: int = 1
var _is_blood: bool = false
var _is_early_blood_twist: bool = false


func _ready() -> void:
	layer = 40
	visible = false

	_root = Control.new()
	_root.position = Vector2.ZERO
	_root.size = Config.VIEW_SIZE
	_root.theme = Art.get_game_theme()
	add_child(_root)

	_sky = MoonSky.new()
	_root.add_child(_sky)
	_sky.build(Config.VIEW_SIZE)

	_title_label = Label.new()
	_title_label.position = Vector2(0.0, 12.0)
	_title_label.size = Vector2(Config.VIEW_SIZE.x, 32.0)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Art.style_label(_title_label, "display", 16, Color(0.96, 0.94, 0.90))
	_root.add_child(_title_label)

	var text_band := ColorRect.new()
	text_band.position = Vector2(0.0, Config.VIEW_SIZE.y - 54.0)
	text_band.size = Vector2(Config.VIEW_SIZE.x, 54.0)
	text_band.color = Color(0.05, 0.04, 0.08, 0.80)
	_root.add_child(text_band)

	_narration_label = Label.new()
	_narration_label.position = Vector2(40.0, Config.VIEW_SIZE.y - 46.0)
	_narration_label.size = Vector2(Config.VIEW_SIZE.x - 80.0, 26.0)
	_narration_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_narration_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Art.style_label(_narration_label, "bold", 8, Color(0.95, 0.90, 0.86))
	_root.add_child(_narration_label)

	_skip_label = Label.new()
	_skip_label.position = Vector2(Config.VIEW_SIZE.x - 190.0, Config.VIEW_SIZE.y - 16.0)
	_skip_label.size = Vector2(182.0, 12.0)
	_skip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skip_label.text = "[Space / Enter / Esc] Skip"
	Art.style_label(_skip_label, "body", 8, Color(0.72, 0.70, 0.78))
	_root.add_child(_skip_label)

	_flash = ColorRect.new()
	_flash.position = Vector2.ZERO
	_flash.size = Config.VIEW_SIZE
	_flash.color = Color(0.92, 0.14, 0.14, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)


func start_moonrise(
	night_num: int,
	is_blood: bool,
	instant_skip: bool = false,
	is_even: bool = false
) -> void:
	_night_num = night_num
	_is_blood = is_blood
	_is_early_blood_twist = (night_num == Config.WORLD_EXPAND_NIGHT and is_blood)
	_elapsed = 0.0
	active = true
	visible = true

	_sky.configure_for_night(night_num, is_blood, _is_early_blood_twist, is_even)
	_sky.moon_progress = 0.0
	_sky.red_blend = 1.0 if (is_blood and not _is_early_blood_twist) else 0.0
	_flash.color.a = 0.0

	if _is_early_blood_twist:
		_title_label.text = "NIGHT 3"
		_narration_label.text = "Two nights early... WAIT. The moon is turning red!"
		Art.style_label(_title_label, "display", 16, Color(0.98, 0.94, 0.90))
	elif night_num == 7 and is_blood:
		_title_label.text = "NIGHT 7 - THE FINAL BLOOD MOON"
		_narration_label.text = "The sky burns red. Hold the line until dawn."
		Art.style_label(_title_label, "display", 16, Color(1.0, 0.36, 0.24))
	elif is_blood:
		_title_label.text = "NIGHT %d - BLOOD MOON" % night_num
		_narration_label.text = "The Blood Moon rises. They are coming from every side."
		Art.style_label(_title_label, "display", 16, Color(1.0, 0.36, 0.24))
	elif is_even:
		_title_label.text = "NIGHT %d - EVEN MOON" % night_num
		_narration_label.text = "The crimson Even Moon rises over the valley. Stand ready."
		Art.style_label(_title_label, "display", 16, Config.EVEN_MOON_BANNER)
	else:
		_title_label.text = "NIGHT %d" % night_num
		_narration_label.text = "Night falls over the valley. Close the door and stand ready."
		Art.style_label(_title_label, "display", 16, Color(0.92, 0.94, 1.0))

	if instant_skip:
		skip_now()


func skip_now() -> void:
	if not active:
		return
	active = false
	visible = false
	finished.emit()


func _process(delta: float) -> void:
	if not active:
		return

	_elapsed += delta
	_sky.moon_progress = clampf(_elapsed / 4.2, 0.0, 1.0)

	# night 3 fakeout: starts normal white then turns crimson halfway up
	if _is_early_blood_twist:
		if _elapsed > 2.2:
			var t_red := clampf((_elapsed - 2.2) / 2.8, 0.0, 1.0)
			_sky.red_blend = t_red

			if t_red > 0.35:
				_title_label.text = "NIGHT 3 - BLOOD MOON!"
				Art.style_label(_title_label, "display", 16, Color(1.0, 0.30, 0.28))
				_narration_label.text = "The Blood Moon came early! Brace the walls!"

			if _elapsed > 2.4 and _elapsed < 3.1:
				_flash.color.a = sin(((_elapsed - 2.4) / 0.7) * PI) * 0.35
			else:
				_flash.color.a = 0.0

	_sky.update_sky(delta)

	if _elapsed >= TOTAL_DURATION:
		skip_now()


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return

	if event is InputEventKey:
		var ke = event
		if ke.pressed and not ke.echo:
			if ke.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
				get_viewport().set_input_as_handled()
				skip_now()
	elif event is InputEventMouseButton:
		var mb = event
		if mb.pressed:
			get_viewport().set_input_as_handled()
			skip_now()
