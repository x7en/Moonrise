class_name SpriteData
extends RefCounted

# [frames, w, h] for horizontal sprite sheets
# had to measure these by hand since the pack strips have slightly different widths per dir
const ANIMATED := {
	"enemies/brute/attack_down": [8, 20, 25],
	"enemies/brute/attack_left": [8, 23, 23],
	"enemies/brute/attack_right": [8, 23, 23],
	"enemies/brute/attack_up": [8, 18, 24],
	"enemies/brute/death_left": [7, 29, 23],
	"enemies/brute/death_right": [7, 29, 23],
	"enemies/brute/walk_down": [8, 16, 24],
	"enemies/brute/walk_left": [8, 16, 24],
	"enemies/brute/walk_right": [8, 16, 24],
	"enemies/brute/walk_up": [8, 16, 24],

	"enemies/raider/attack_down": [7, 15, 21],
	"enemies/raider/attack_left": [7, 25, 19],
	"enemies/raider/attack_right": [7, 25, 19],
	"enemies/raider/attack_up": [7, 13, 25],
	"enemies/raider/death_left": [6, 27, 18],
	"enemies/raider/death_right": [6, 27, 18],
	"enemies/raider/walk_down": [8, 12, 20],
	"enemies/raider/walk_left": [8, 21, 19],
	"enemies/raider/walk_right": [8, 21, 19],
	"enemies/raider/walk_up": [8, 12, 23],

	"enemies/zombie/attack_down": [4, 13, 16],
	"enemies/zombie/attack_left": [4, 11, 14],
	"enemies/zombie/attack_right": [4, 11, 14],
	"enemies/zombie/attack_up": [4, 14, 15],
	"enemies/zombie/death_left": [6, 16, 14],
	"enemies/zombie/death_right": [6, 16, 14],
	"enemies/zombie/walk_down": [6, 12, 16],
	"enemies/zombie/walk_left": [6, 13, 15],
	"enemies/zombie/walk_right": [6, 13, 15],
	"enemies/zombie/walk_up": [6, 13, 16],

	"player/death_left": [6, 21, 16],
	"player/death_right": [6, 21, 16],
	"player/idle_down": [6, 13, 16],
	"player/idle_left": [6, 12, 16],
	"player/idle_right": [6, 12, 16],
	"player/idle_up": [6, 11, 16],
	"player/punch_down": [4, 12, 18],
	"player/punch_left": [4, 20, 18],
	"player/punch_right": [4, 20, 18],
	"player/punch_up": [4, 12, 17],
	"player/run_down": [6, 13, 17],
	"player/run_left": [6, 14, 17],
	"player/run_right": [6, 14, 17],
	"player/run_up": [6, 13, 17],
}

# static sprite sizes [w, h] so feet alignment doesnt have to peek every texture first
const STATIC := {
	"fences/iron/gate_h": [16, 15],
	"fences/iron/gate_v": [3, 23],
	"fences/iron/h": [16, 14],
	"fences/iron/post": [7, 10],
	"fences/iron/v": [8, 16],
	"fences/wood/gate_h": [16, 15],
	"fences/wood/gate_v": [3, 23],
	"fences/wood/h": [16, 14],
	"fences/wood/post": [7, 10],
	"fences/wood/v": [8, 16],

	"ground/crater_1": [32, 32],
	"ground/crater_2": [32, 32],
	"ground/crater_3": [32, 32],
	"ground/crater_4": [32, 32],
	"ground/crater_5": [32, 32],
	"ground/crater_6": [32, 32],
	"ground/dirt_0": [16, 16],
	"ground/dirt_1": [16, 16],
	"ground/dirt_2": [16, 16],
	"ground/dirt_3": [16, 16],
	"ground/grass_0": [16, 16],
	"ground/grass_1": [16, 16],
	"ground/grass_2": [16, 16],
	"ground/grass_3": [16, 16],

	"house/lv1": [160, 120],
	"house/lv1_open": [160, 120],
	"house/lv2": [160, 120],
	"house/lv2_open": [160, 120],
	"house/lv3": [160, 120],
	"house/lv3_open": [160, 120],

	"items/planks_1": [13, 14],
	"items/planks_2": [14, 10],

	"nature/birch_1": [39, 45],
	"nature/birch_2": [24, 36],
	"nature/bush_1": [15, 13],
	"nature/bush_2": [28, 13],
	"nature/oak": [24, 36],
	"nature/pine_big": [27, 49],
	"nature/rock": [13, 9],
	"nature/spruce_1": [16, 29],
	"nature/spruce_2": [16, 29],
	"nature/tree_1": [21, 30],
	"nature/tree_big": [34, 52],
	"nature/tuft": [16, 15],

	"props/barrel_blue": [12, 16],
	"props/barrel_red": [12, 16],
	"props/beam": [15, 5],
	"props/box": [11, 9],
	"props/car_blue": [25, 37],
	"props/car_red": [38, 19],
	"props/cart": [12, 16],
	"props/crate_gray": [41, 26],
	"props/crate_green": [41, 26],
	"props/crate_red": [41, 26],
	"props/dumpster": [29, 23],
	"props/metal": [23, 18],
	"props/rubble": [17, 15],
	"props/truck_scrap": [39, 20],
	"props/van_blue": [43, 27],

	"sky/blood_moon": [32, 32],
	"sky/clouds_1": [640, 86],
	"sky/clouds_2": [640, 86],
	"sky/clouds_3": [640, 86],
	"sky/moon": [32, 32],

	"traps/lure": [20, 24],
	"traps/lure_fire": [48, 16],
	"traps/snare": [24, 24],
	"traps/snare_sheet": [128, 32],
	"traps/spike": [32, 32],
	"traps/spike_sheet": [448, 32],

	"ui/bag": [16, 16],
	"ui/crosshair": [16, 16],
	"ui/cursor": [16, 16],
	"ui/danger": [16, 16],
	"ui/heart": [16, 16],
	"ui/house": [16, 16],
	"ui/panel": [48, 48],
	"ui/shock": [16, 16],
	"ui/slot": [16, 16],
	"ui/slot_active": [16, 16],
	"ui/trophy": [16, 16],

	"weapons/arrow": [16, 7],
	"weapons/arrow_pierce": [16, 7],
	"weapons/bow": [16, 16],
}


static func path(key: String) -> String:
	return "res://assets/%s.png" % key


static func is_animated(key: String) -> bool:
	return ANIMATED.has(key)
