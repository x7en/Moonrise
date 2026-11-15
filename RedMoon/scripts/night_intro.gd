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

	_root = get_node("Root") as Control
	_root.theme = Art.get_game_theme()

	_sky = get_node("Root/Sky") as MoonSky
	_sky.build(Config.VIEW_SIZE)

	_title_label = get_node("Root/TitleLabel") as Label
	Art.style_label(_title_label, "display", 16, Color(0.96, 0.94, 0.90))

	_narration_label = get_node("Root/NarrationLabel") as Label
	Art.style_label(_narration_label, "bold", 8, Color(0.95, 0.90, 0.86))

	_skip_label = get_node("Root/SkipLabel") as Label
	Art.style_label(_skip_label, "body", 8, Color(0.72, 0.70, 0.78))

	_flash = get_node("Root/BloodFlash") as ColorRect


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


func _input(event: InputEvent) -> void:
	if not active:
		return

	if event is InputEventKey:
		var ke: InputEventKey = event as InputEventKey
		if ke.pressed and not ke.echo:
			if ke.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
				get_viewport().set_input_as_handled()
				skip_now()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
			skip_now()
	elif event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event as InputEventScreenTouch
		if st.pressed:
			get_viewport().set_input_as_handled()
			skip_now()
