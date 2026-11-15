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


# player & melee (PLAYER_SPEED intentionally kept unchanged)
const PLAYER_SPEED := 82.0
const PLAYER_HP := 40
const SWING_TIME := 0.30
const SWING_COOLDOWN := 0.55
const SWING_BOX := Vector2(32, 22)
const SWING_OFFSET := 18.0
const KNOCKBACK := 14.0
const CONTACT_INVULN := 0.75

const BOUNCE_STUN := 5.0
const BOUNCE_CD_ACT1 := 18.0
const BOUNCE_CD_ACT2 := 45.0
const SWING_GROWTH_PER_BOUNCE := 0.15
const MAX_BOUNCE_BONUSES := 3
const INSIDE_HEAL_INTERVAL := 3.0
const RECALL_HEAL_DURATION := 4.0
const RECALL_HEAL_INTERVAL := 0.8
const RECALL_HEAL_TICK := 2


# bow
const BOW_RANGE := 220.0
const BOW_FIRE_INTERVAL := 1.5
const BOW_MAG := 5
const BOW_RELOAD := 2.6
const BOW_RESERVE_MAX := 30
const BOW_DAMAGE := 1
const ARROW_SPEED := 220.0

# boomerang (reusable bounce-back weapon)
const BOOMERANG_RANGE := 175.0
const BOOMERANG_SPEED := 230.0
const BOOMERANG_RETURN_SPEED := 265.0
const BOOMERANG_DAMAGE := 2
const BOOMERANG_COOLDOWN := 1.8
const BOOMERANG_HIT_RADIUS := 10.0
const BOOMERANG_SPIN_SPEED := 18.0

# extensible weapon registry (data-driven for future weapons)
const WEAPON_DEFS := {
	"bow": {
		"id": "bow",
		"label": "Hunting Bow",
		"short_label": "Bow",
		"kind": "ranged",
		"icon": "bow",
		"desc": "Auto-aim ranged shots (1.5s CD, uses arrows).",
	},
	"spear": {
		"id": "spear",
		"label": "Iron-Tipped Spear",
		"short_label": "Spear",
		"kind": "melee",
		"icon": "spear",
		"desc": "Close-range thrust with knockback (no ammo).",
	},
	"boomerang": {
		"id": "boomerang",
		"label": "Boomerang",
		"short_label": "Boomerang",
		"kind": "thrown",
		"icon": "boomerang",
		"desc": "Auto-aim throw; bounces back & hits both ways (1.8s CD).",
	},
}
const DEFAULT_WEAPONS: Array[String] = ["bow", "spear", "boomerang"]

# enemies (TODO: maybe nerf raider speed if night 5 feels too brutal)
const ENEMY_TYPES := {
	"zombie": {
		"hits": 3,
		"speed": 33.0,
		"struct_dmg": 5,
		"attack_interval": 1.2,
		"player_dmg": 12,
		"aggro_radius": 56.0,
		"tint": Color(1, 1, 1),
	},
	"raider": {
		"hits": 2,
		"speed": 50.0,
		"struct_dmg": 8,
		"attack_interval": 1.0,
		"player_dmg": 13,
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
		"damage": 2,
		"cooldown": 0.7,
		"max_triggers": 5,
		"radius": 13.0,
	},
	"trap_snare": {
		"label": "Bear Trap",
		"cost": {"plank": 2},
		"damage": 1,
		"root_time": 2.5,
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

const CRAFT_RECIPES: Array[Dictionary] = [
	{
		"action": "craft_trap",
		"item": "trap_snare",
		"label": "Bear Traps (+2)",
		"amount": 2,
		"cost": {"plank": 2},
		"desc": "Deals 1 dmg & immobilizes a zombie for 2.5s (single-use).",
	},
	{
		"action": "craft_trap",
		"item": "trap_spike",
		"label": "Spike Traps (+2)",
		"amount": 2,
		"cost": {"plank": 2},
		"desc": "Floor spikes dealing 2 dmg per trigger (5 uses).",
	},
	{
		"action": "craft_trap",
		"item": "trap_lure",
		"label": "Decoy Lure (+1)",
		"amount": 1,
		"cost": {"plank": 2},
		"desc": "Draws zombies within 150px away from fences (30 HP).",
	},
	{
		"action": "buy_arrows",
		"item": "arrows",
		"label": "Arrows (+10)",
		"amount": 10,
		"cost": {"plank": 1},
		"desc": "Restock bow quiver reserve.",
	},
]


# day/night timers & wave sizes
const DAY_LENGTH := 90.0
const ACT1_DUSK_TIME := 12.0
const ACT2_DUSK_TIME := 15.0
const NIGHT_BASE := 30.0
const NIGHT_STEP := 5.0
const NIGHT_STEP_EVERY := 2
const NIGHT_MAX := 60.0

# base tracker: only shown when player is within 50m (50 * 16px = 800px) of base
const BASE_TRACKER_MIN_PX := 80.0
const BASE_TRACKER_MAX_METERS := 50.0
const BASE_TRACKER_MAX_PX := 800.0

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
const CHOP_HOLD_TIME := 1.2

const DOG_TAME_RANGE := 40.0
const DOG_TAMEABLE_CHANCE := 0.55
const DOG_MAX := 3
const DOG_MAX_TAMED := 2
const DOG_HP := 15
const DOG_ENEMY_DMG := 5
const DOG_DAMAGE := 1
const DOG_GUARD_RANGE := 84.0
const DOG_HUNT_RANGE := 160.0
const DOG_ATTACK_INTERVAL := 1.6
const DOG_SPEED_FOLLOW := 56.0
const DOG_SPEED_CATCHUP_MAX := 78.0
const DOG_SPEED_CHASE := 66.0

# zombie ghosts (Act 2 / Day 4+ only; never in Act 1)
const GHOST_MIN_DAY := 4
const GHOST_MAX_ALIVE := 2
const GHOST_HP := 2
const GHOST_DAMAGE := 4
const GHOST_DAMAGE_COOLDOWN := 2.2
const GHOST_SPEED_SCYTHE := 42.0
const GHOST_SPEED_LUNGE := 50.0
const GHOST_DAY_INTERVAL_MIN := 22.0
const GHOST_DAY_INTERVAL_MAX := 38.0
const GHOST_NIGHT_INTERVAL_MIN := 16.0
const GHOST_NIGHT_INTERVAL_MAX := 28.0
const GHOST_SPAWN_MIN_DIST := 175.0
const GHOST_SPAWN_MAX_DIST := 260.0
const GHOST_LIFETIME := 18.0
const GHOST_SCALE := 0.85

const METEOR_DAYS := []
const METEOR_COUNT_DAY4 := 22
const METEOR_COUNT_DAY6 := 12
const METEOR_TELEGRAPH_TIME := 1.4
const METEOR_RADIUS := 22.0
const METEOR_PLAYER_DMG := 15
const METEOR_STRUCT_DMG := 20


# day/night tint colors & moon palette
const TINT_DAY := Color(1.0, 1.0, 1.0)
const TINT_DUSK := Color(0.86, 0.67, 0.59)
const TINT_NIGHT := Color(0.24, 0.28, 0.52)
const TINT_EVEN_MOON := Color(0.44, 0.22, 0.36)
const TINT_BLOOD := Color(0.84, 0.16, 0.18)
const TINT_HOPELESS := Color(0.58, 0.64, 0.74)

# secondary moon ("Even Moon") deep wine-crimson vs bright scarlet Blood/Red Moon
const EVEN_MOON_COLOR := Color(0.72, 0.12, 0.34, 1.0)
const EVEN_MOON_GLOW := Color(0.74, 0.14, 0.38, 0.24)
const EVEN_MOON_BANNER := Color(0.90, 0.36, 0.56, 1.0)


func day_length() -> float:
	return DAY_LENGTH


func night_length(night_num: int) -> float:
	var steps := floori(float(maxi(0, night_num - 1)) / float(NIGHT_STEP_EVERY))
	return minf(NIGHT_BASE + NIGHT_STEP * float(steps), NIGHT_MAX)
