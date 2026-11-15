class_name SaveData
extends RefCounted

const SETTINGS_PATH := "user://settings.cfg"
const ACHIEVEMENTS_PATH := "user://achievements.cfg"

const ACHIEVEMENT_DEFS := {
	"first_plank": {
		"title": "First Plank",
		"desc": "Gather your first wooden plank.",
		"icon": "trophy",
	},
	"first_night": {
		"title": "First Night Survived",
		"desc": "Live through the first dark night.",
		"icon": "moon",
	},
	"blood_moon_survivor": {
		"title": "Blood Moon Survivor",
		"desc": "Survive the early Blood Moon on Night 3.",
		"icon": "moon",
	},
	"world_expanded": {
		"title": "World Expanded!",
		"desc": "The road out of the ruins is open.",
		"icon": "world",
	},
	"first_bow_kill": {
		"title": "First Bow Kill",
		"desc": "Drop a zombie with your hunting bow.",
		"icon": "trophy",
	},
	"fence_upgraded": {
		"title": "Reinforced Line",
		"desc": "Upgrade a fence segment to Level 2.",
		"icon": "trophy",
	},
	"metal_fences": {
		"title": "Metal Fences",
		"desc": "Upgrade a fence segment to Metal (Level 3).",
		"icon": "trophy",
	},
	"house_level_3": {
		"title": "Fortress Home",
		"desc": "Upgrade the farmhouse to Level 3.",
		"icon": "trophy",
	},
	"intruder_alert": {
		"title": "Intruder Alert",
		"desc": "Survive a night after an enemy entered the house.",
		"icon": "trophy",
	},
	"perfect_night": {
		"title": "Perfect Night",
		"desc": "Survive a night with zero house or fence damage.",
		"icon": "moon",
	},
	"meteor_survivor": {
		"title": "Meteor Survivor",
		"desc": "Weather a meteor shower without falling.",
		"icon": "world",
	},
	"house_fell": {
		"title": "The House Fell",
		"desc": "Watch the shelter crumble and keep standing.",
		"icon": "moon",
	},
	"homeless_survivor": {
		"title": "Homeless Survivor",
		"desc": "Survive the final Blood Moon with no shelter.",
		"icon": "moon",
	},
	"final_blood_moon": {
		"title": "Final Blood Moon Survivor",
		"desc": "Outlast Night 7 and keep fighting.",
		"icon": "moon",
	},
	"tamed_dog": {
		"title": "Tamed a Dog",
		"desc": "Earn the loyalty of a stray companion.",
		"icon": "trophy",
	},
}

var intro_seen: bool = false
var play_intro: bool = true
var fullscreen: bool = false
var master_volume: float = 1.0
var screen_shake: bool = true
var unlocked: Dictionary = {}


func load_all() -> void:
	_load_settings()
	_load_achievements()


func save_settings() -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("story", "intro_seen", intro_seen)
	cfg.set_value("story", "play_intro", play_intro)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("gameplay", "screen_shake", screen_shake)
	cfg.save(SETTINGS_PATH)


func mark_intro_completed() -> void:
	intro_seen = true
	play_intro = false
	save_settings()


func apply_display_and_audio() -> void:
	var target_mode: DisplayServer.WindowMode = (
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(target_mode)
	var bus_idx = AudioServer.get_bus_index("Master")
	if bus_idx >= 0:
		var clamped_vol = clampf(master_volume, 0.0, 1.0)
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(maxf(0.0001, clamped_vol)))
		AudioServer.set_bus_mute(bus_idx, clamped_vol <= 0.001)


func unlock(ach_id: String) -> Dictionary:
	if not ACHIEVEMENT_DEFS.has(ach_id) or bool(unlocked.get(ach_id, false)):
		return {}
	unlocked[ach_id] = true
	_save_achievements()
	return ACHIEVEMENT_DEFS[ach_id] as Dictionary


func is_unlocked(ach_id: String) -> bool:
	return bool(unlocked.get(ach_id, false))


func get_unlocked_count() -> int:
	var total = 0
	for key in ACHIEVEMENT_DEFS.keys():
		if is_unlocked(String(key)):
			total += 1
	return total


func _load_settings() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	intro_seen = bool(cfg.get_value("story", "intro_seen", false))
	play_intro = bool(cfg.get_value("story", "play_intro", not intro_seen))
	fullscreen = bool(cfg.get_value("display", "fullscreen", false))
	master_volume = clampf(float(cfg.get_value("audio", "master_volume", 1.0)), 0.0, 1.0)
	screen_shake = bool(cfg.get_value("gameplay", "screen_shake", true))


func _load_achievements() -> void:
	unlocked.clear()
	var cfg = ConfigFile.new()
	if cfg.load(ACHIEVEMENTS_PATH) != OK:
		return
	for key in ACHIEVEMENT_DEFS.keys():
		var k = String(key)
		unlocked[k] = bool(cfg.get_value("unlocked", k, false))


func _save_achievements() -> void:
	var cfg = ConfigFile.new()
	for key in unlocked.keys():
		cfg.set_value("unlocked", String(key), bool(unlocked[key]))
	cfg.save(ACHIEVEMENTS_PATH)
