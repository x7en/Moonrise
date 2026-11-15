extends Node

# dump of all balance numbers and sizes so i dont have to hunt across 10 files to tweak stuff

# world & camera
const VIEW_SIZE := Vector2(640, 360)
const WORLD_SIZE := Vector2(2400, 1350)
const WORLD_RECT := Rect2(0, 0, 2400, 1350)
const HOUSE_CENTER := Vector2(1200, 675)
const HOUSE_DOOR := Vector2(1200, 729)  # porch stones right outside the front door
const HOUSE_DOOR_STEP := Vector2(1200, 720)  # doorstep collider line
const ACT1_RECT := Rect2(720, 405, 960, 540)  # smaller starter zone before night 3
const WORLD_EXPAND_NIGHT := 3

const FONT_BODY_PATH := "res://assets/fonts/PixelOperator8.ttf"
const FONT_BOLD_PATH := "res://assets/fonts/PixelOperator8-Bold.ttf"
const FONT_DISPLAY_PATH := "res://assets/fonts/KiwiSoda.ttf"


# player & melee
const PLAYER_SPEED := 82.0
const PLAYER_HP := 50
const SWING_TIME := 0.30
const SWING_COOLDOWN := 0.38
const SWING_BOX := Vector2(32, 22)
const SWING_OFFSET := 18.0
const KNOCKBACK := 18.0
const CONTACT_INVULN := 1.0

const BOUNCE_STUN := 5.0
const BOUNCE_CD_ACT1 := 10.0
const BOUNCE_CD_ACT2 := 40.0
const SWING_GROWTH_PER_BOUNCE := 0.15
const MAX_BOUNCE_BONUSES := 3
const INSIDE_HEAL_INTERVAL := 2.0
const RECALL_HEAL_DURATION := 6.0
const RECALL_HEAL_INTERVAL := 0.5
const RECALL_HEAL_TICK := 2


# bow
const BOW_RANGE := 220.0
const BOW_FIRE_INTERVAL := 1.5
const BOW_MAG := 6
const BOW_RELOAD := 2.2
const BOW_RESERVE_MAX := 30
const BOW_DAMAGE := 1
const ARROW_SPEED := 220.0


# enemies (TODO: maybe nerf raider speed if night 5 feels too brutal)
const ENEMY_TYPES := {
	"zombie": {
		"hits": 2,
		"speed": 33.0,
		"struct_dmg": 4,
		"attack_interval": 1.2,
		"player_dmg": 10,
		"aggro_radius": 56.0,
		"tint": Color(1, 1, 1),
	},
	"raider": {
		"hits": 1,
		"speed": 50.0,
		"struct_dmg": 7,
		"attack_interval": 1.0,
		"player_dmg": 10,
		"aggro_radius": 80.0,
		"tint": Color(1.0, 0.6, 0.55),
	},
}

const ENEMY_LEASH_RADIUS := 140.0
const ENEMY_LEASH_TIME := 3.0
const ENEMY_PLAYER_WINDUP := 0.35
const ENEMY_PLAYER_COOLDOWN := 1.0
const ENEMY_SEPARATION_RADIUS := 10.0
const RAIDER_SIDE := "east"

const WAVE_GROUP_MIN := 2
const WAVE_GROUP_MAX := 3
const WAVE_MEMBER_DELAY := 0.55


# house & fence rings
const HOUSE_HP := 100
const HOUSE_LEVEL_HP := [100, 160, 240]
const FENCE_HP := 50
const FENCE_LEVEL_HP := [50, 90, 140]
const PLANK_HEAL := 8
const DAWN_FREE_REPAIR := 10

const HOUSE_REACH := 56.0
const FENCE_REACH := 20.0
const STRUCTURE_MENU_REACH := 80.0
const DOOR_INTERACT_REACH := 28.0

const INTRUDER_HOUSE_DPS := 3.0
const INTRUDER_PLAYER_DMG := 10
const INTRUDER_PLAYER_INTERVAL := 1.2

# ring 1 starts built, rings 2 & 3 unlock later - bumped ring 1 size up to fit the 160x120 cottage
const FENCE_GATE_WIDTH := 30.0
const FENCE_RINGS := [
	{"ring": 1, "half_extents": Vector2(114.0, 78.0), "gate_offset_x": 0.0, "built_at_start": true},
	{"ring": 2, "half_extents": Vector2(160.0, 122.0), "gate_offset_x": 0.0, "built_at_start": false},
	{"ring": 3, "half_extents": Vector2(206.0, 166.0), "gate_offset_x": 0.0, "built_at_start": false},
]


# inventory & crafting costs
const BAG_CAPACITY := 16
const ACT1_START_STOCKPILE := 4
const ACT2_START_STOCKPILE := 8
const START_BEAR_TRAPS := 3
const START_SPIKE_TRAPS := 2
const LOSE_BAG_AT_DUSK_ACT2 := true

const COST_UNLOCK_RING2 := {"plank": 12}
const COST_UNLOCK_RING3 := {"plank": 18, "scrap": 4}
const COST_RING_LV2 := {
	1: {"plank": 10},
	2: {"plank": 14},
	3: {"plank": 18},
}
const COST_RING_LV3 := {
	1: {"plank": 12, "scrap": 4},
	2: {"plank": 16, "scrap": 6},
	3: {"plank": 20, "scrap": 8},
}
const COST_RING_SPIKES := {
	1: {"plank": 6, "scrap": 2},
	2: {"plank": 8, "scrap": 3},
	3: {"plank": 10, "scrap": 4},
}

const COST_HOUSE_LV2 := {"plank": 12, "scrap": 4}
const COST_HOUSE_LV3 := {"plank": 20, "scrap": 10}
const COST_HOUSE_REBUILD := {"plank": 25, "scrap": 8}
const COST_HOUSE_REBUILD_ACT1 := {"plank": 35}
const COST_GEAR_TIER2 := {"plank": 8, "scrap": 2}
const COST_GEAR_TIER3 := {"plank": 14, "scrap": 6}
const COST_BUY_ARROWS := {"plank": 1}
const COST_WATCHTOWER := {"plank": 14, "scrap": 5}

const BUY_ARROWS_AMOUNT := 10
const WATCHTOWER_MAX := 2
const WATCHTOWER_HP := 40
const WATCHTOWER_RANGE := 120.0
const WATCHTOWER_FIRE_INTERVAL := 1.2


# traps
const MAX_TRAPS := 16
const TRAP_MIN_SPACING := 14.0
const TRAP_PLACE_RANGE := 96.0

const TRAPS := {
	"trap_spike": {
		"label": "Spike Trap",
		"cost": {"plank": 2},
		"damage": 3,
		"cooldown": 0.7,
		"max_triggers": 5,
		"radius": 13.0,
	},
	"trap_snare": {
		"label": "Bear Trap",
		"cost": {"plank": 2},
		"damage": 1,
		"root_time": 3.0,
		"max_triggers": 1,
		"radius": 14.0,
	},
	"trap_lure": {
		"label": "Decoy Lure",
		"cost": {"plank": 2},
		"hp": 30,
		"attract_radius": 150.0,
		"radius": 15.0,
	},
}


# day/night timers & wave sizes
const DAY_LENGTH := 90.0
const ACT1_DUSK_TIME := 12.0
const ACT2_DUSK_TIME := 15.0
const NIGHT_BASE := 30.0
const NIGHT_STEP := 10.0
const NIGHT_MAX := 120.0

const ACT1_PLANKS_PER_DAY := 14
const PILES := [
	{"count": 9, "planks": 2, "r_min": 225.0, "r_max": 390.0},
	{"count": 8, "planks": 3, "r_min": 420.0, "r_max": 740.0},
	{"count": 7, "planks": 6, "r_min": 780.0, "r_max": 1080.0},
]

const NIGHTS := {
	1: {"zombies": 8, "raiders": 0},
	2: {"zombies": 13, "raiders": 0},
	3: {"zombies": 18, "raiders": 0},
	4: {"zombies": 20, "raiders": 0},
	5: {"zombies": 22, "raiders": 4},
	6: {"zombies": 26, "raiders": 6},
	7: {"zombies": 32, "raiders": 8},
}


# daytime wanderers, dog, meteors
const DAY_WANDERER_MIN := 3
const DAY_WANDERER_MAX := 6
const DAY_WANDERER_AGGRO := 50.0
const SEARCH_HOLD_TIME := 1.5

const DOG_TAME_TIME := 2.0
const DOG_MAX := 2
const DOG_HP := 20
const DOG_GUARD_RANGE := 60.0
const DOG_ATTACK_INTERVAL := 0.8

const METEOR_DAYS := []
const METEOR_COUNT_DAY4 := 22
const METEOR_COUNT_DAY6 := 12
const METEOR_TELEGRAPH_TIME := 1.4
const METEOR_RADIUS := 22.0
const METEOR_PLAYER_DMG := 15
const METEOR_STRUCT_DMG := 20


# day/night tint colors
const TINT_DAY := Color(1.0, 1.0, 1.0)
const TINT_DUSK := Color(0.86, 0.67, 0.59)
const TINT_NIGHT := Color(0.24, 0.28, 0.52)
const TINT_BLOOD := Color(0.84, 0.16, 0.18)
const TINT_HOPELESS := Color(0.58, 0.64, 0.74)


func day_length() -> float:
	return DAY_LENGTH


func night_length(night_num: int) -> float:
	return minf(NIGHT_BASE + NIGHT_STEP * float(maxi(0, night_num - 1)), NIGHT_MAX)
