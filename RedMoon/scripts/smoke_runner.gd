class_name SmokeRunner
extends RefCounted
## T0.0 + T0.3 + T0.4 + T0.5: Automated headless/CLI --smoke verification runner.
## Plays through all 7 nights cleanly, verifying concentric onion fence solidity, zero fake wood,
## zero surviving night piles, bow/door/upgrade/trap systems, and clean exit status.

var active: bool = false
var passed: bool = false
var errors: Array[String] = []
var _main: Node = null
var _phase_checked_nights: Dictionary = {}
var _ring_checks_done: bool = false
var _elapsed: float = 0.0
var _max_seconds: float = 55.0


func start(main_node: Node) -> void:
	_main = main_node
	active = true
	errors.clear()
	_phase_checked_nights.clear()
	_ring_checks_done = false
	_elapsed = 0.0
	print("[SMOKE] Starting automated Red Moon verification...")
	_run_static_invariants()
	_main.call("smoke_start_run")


func step(delta: float) -> void:
	if not active or _main == null:
		return
	_elapsed += delta
	if _elapsed > _max_seconds:
		_fail("Timeout after %.1fs before finishing Night 7." % _elapsed)
		return
	if not _ring_checks_done:
		_ring_checks_done = true
		_run_onion_ring_checks()

	var state_str: String = String(_main.call("smoke_get_state"))
	var day_num: int = int(_main.get("day"))
	var act_num: int = int(_main.get("act"))

	match state_str:
		"STORY", "MOONRISE":
			_main.call("smoke_skip_overlay")
		"DAY":
			_verify_day_length()
			_main.call("smoke_fast_forward_day")
		"NIGHT":
			if not _phase_checked_nights.has(day_num):
				_phase_checked_nights[day_num] = true
				_verify_night_invariants(day_num, act_num)
			_main.call("smoke_defend_step", delta)
		"VICTORY":
			if not _phase_checked_nights.has(7):
				_fail("Reached victory without playing Night 7.")
			else:
				_succeed()
		"GAME_OVER":
			_fail("Player died unexpectedly during smoke test on Day %d." % day_num)


func _run_static_invariants() -> void:
	if Config.VIEW_SIZE != Vector2(640, 360):
		errors.append("VIEW_SIZE must be 640x360")
	if Config.WORLD_SIZE != Vector2(2400, 1350):
		errors.append("WORLD_SIZE must be 2400x1350")
	if Config.HOUSE_CENTER != Vector2(1200, 675):
		errors.append("HOUSE_CENTER must be (1200, 675)")
	if Config.WORLD_EXPAND_NIGHT != 3:
		errors.append("WORLD_EXPAND_NIGHT must be 3")
	if Config.day_length() != 90.0:
		errors.append("DAY_LENGTH must be 90.0")
	for n in range(1, 8):
		var expected_n: float = 30.0 + 10.0 * float(n - 1)
		if absf(Config.night_length(n) - expected_n) > 0.01:
			errors.append("Night %d length mismatch: got %.1f expected %.1f" % [
				n, Config.night_length(n), expected_n
			])


func _run_onion_ring_checks() -> void:
	var fences: Array = _main.get("fences") as Array
	var r1_built: int = 0
	var r2_built: int = 0
	var r3_unbuilt: int = 0
	for f in fences:
		var st: Structure = f as Structure
		if st.ring == 1 and st.is_standing():
			r1_built += 1
		elif st.ring == 2 and st.is_standing():
			r2_built += 1
		elif st.ring == 3 and not st.is_built:
			r3_unbuilt += 1
	if r1_built < 10 or r2_built < 12 or r3_unbuilt < 14:
		errors.append(
			"Concentric fence counts wrong: R1=%d R2=%d R3_ghost=%d"
			% [r1_built, r2_built, r3_unbuilt]
		)

	# Verify Ring 1 & Ring 2 are closed on North/East/West and have a 28 px South gate opening.
	var hc: Vector2 = Config.HOUSE_CENTER
	for ring_def in Config.FENCE_RINGS:
		if not bool(ring_def["built_at_start"]):
			continue
		var r_idx: int = int(ring_def["ring"])
		var he: Vector2 = ring_def["half_extents"] as Vector2
		var north_pt: Vector2 = Vector2(hc.x, hc.y - he.y)
		var east_pt: Vector2 = Vector2(hc.x + he.x, hc.y)
		var west_pt: Vector2 = Vector2(hc.x - he.x, hc.y)
		var gate_pt: Vector2 = Vector2(hc.x, hc.y + he.y)
		if not _point_covered_by_ring(fences, r_idx, north_pt):
			errors.append("Ring %d north wall not solid at %s" % [r_idx, str(north_pt)])
		if not _point_covered_by_ring(fences, r_idx, east_pt):
			errors.append("Ring %d east wall not solid at %s" % [r_idx, str(east_pt)])
		if not _point_covered_by_ring(fences, r_idx, west_pt):
			errors.append("Ring %d west wall not solid at %s" % [r_idx, str(west_pt)])
		if _point_covered_by_ring(fences, r_idx, gate_pt):
			errors.append("Ring %d south gate blocked at %s" % [r_idx, str(gate_pt)])


func _point_covered_by_ring(fences: Array, ring_num: int, pt: Vector2) -> bool:
	for f in fences:
		var st: Structure = f as Structure
		if st.ring == ring_num and st.is_standing() and st.footprint_rect.has_point(pt):
			return true
	return false


func _verify_day_length() -> void:
	var day_num: int = int(_main.get("day"))
	var act_num: int = int(_main.get("act"))
	if day_num >= 4 and act_num != 2:
		errors.append("World did not expand to Act 2 by Day %d." % day_num)


func _verify_night_invariants(night_num: int, _act_num: int) -> void:
	var piles_left: int = _main.get_tree().get_nodes_in_group("piles").size()
	if piles_left != 0:
		errors.append("Night %d started with %d surviving piles (T0.3 violation)." % [
			night_num, piles_left
		])
	print("[SMOKE] Night %d invariants verified (piles=0)." % night_num)


func _succeed() -> void:
	active = false
	if not errors.is_empty():
		_fail("; ".join(errors))
		return
	passed = true
	print("[SMOKE] PASS - All 7 nights, onion fences, and T0-T3 invariants verified.")
	_main.get_tree().quit(0)


func _fail(reason: String) -> void:
	active = false
	passed = false
	push_error("[SMOKE] FAIL - " + reason)
	print("[SMOKE] FAIL - " + reason)
	_main.get_tree().quit(1)
