extends Node
## Autoload "Config". Every tuning number lives here so you can tweak the game in one place.

# --- World, Viewport & Expansion (T0.1 / T0.1b) ---
const VIEW_SIZE := Vector2(640, 360)
const WORLD_SIZE := Vector2(2400, 1350)
const WORLD_RECT := Rect2(0, 0, 2400, 1350)
const HOUSE_CENTER := Vector2(1200, 675)
const HOUSE_DOOR := Vector2(1200, 729)  # Stepping-stone porch area outside the front door
const HOUSE_DOOR_STEP := Vector2(1200, 720)  # Threshold directly on the south cabin facade
const ACT1_RECT := Rect2(720, 405, 960, 540)  # 960x540 playable area centered on HOUSE_CENTER
const WORLD_EXPAND_NIGHT := 3  # World expands after surviving this night (early Blood Moon)

# --- Fonts (T0.B) ---
const FONT_BODY_PATH := "res://assets/fonts/PixelOperator8.ttf"
const FONT_BOLD_PATH := "res://assets/fonts/PixelOperator8-Bold.ttf"
const FONT_DISPLAY_PATH := "res://assets/fonts/KiwiSoda.ttf"

# --- Debug ---
const DEBUG_COLLIDERS := false

# --- Player & Spear Melee ---
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
const INSIDE_HEAL_INTERVAL := 2.0  # +1 HP every 2 s while sheltered indoors

# --- Weapons & Bow (T1.2) ---
const BOW_RANGE := 150.0
const BOW_FIRE_INTERVAL := 0.50
const BOW_MAG := 6
const BOW_RELOAD := 2.2
const BOW_RESERVE_MAX := 30
const BOW_DAMAGE := 1
const ARROW_SPEED := 220.0
const WEAPONS := {
	"bow": {
		"name": "Hunting Bow",
		"range": BOW_RANGE,
		"fire_interval": BOW_FIRE_INTERVAL,
		"mag_size": BOW_MAG,
		"reload_time": BOW_RELOAD,
		"reserve_max": BOW_RESERVE_MAX,
		"damage": BOW_DAMAGE,
		"projectile_speed": ARROW_SPEED,
		"pierce": 0,
	},
}

# --- Enemies (T0.6 / T1.3) ---
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
	"brute": {
		"hits": 6,
		"speed": 20.0,
		"struct_dmg": 12,
		"attack_interval": 1.5,
		"player_dmg": 15,
		"aggro_radius": 70.0,
		"tint": Color(1, 1, 1),
	},
}
const ENEMY_LEASH_RADIUS := 140.0
const ENEMY_LEASH_TIME := 3.0
const ENEMY_PLAYER_WINDUP := 0.35
const ENEMY_PLAYER_COOLDOWN := 1.0
const ENEMY_SEPARATION_RADIUS := 10.0
const BRUTE_ENABLED := false
const RAIDER_SIDE := "east"

const WAVE_GROUP_MIN := 2
const WAVE_GROUP_MAX := 3
const WAVE_MEMBER_DELAY := 0.55

# --- Structures, Onion Fence Rings & House Door (T0.4 / T1.5) ---
const HOUSE_HP := 100
const HOUSE_LEVEL_HP := [100, 160, 240]
const FENCE_HP := 50
const FENCE_LEVEL_HP := [50, 90, 140]
const PLANK_HEAL := 8
const DAWN_FREE_REPAIR := 10
const FENCE_REINFORCED_MIN_HP := 20
const HOUSE_REACH := 56.0
const FENCE_REACH := 20.0
const STRUCTURE_MENU_REACH := 80.0
const DOOR_INTERACT_REACH := 28.0
const INTRUDER_HOUSE_DPS := 3.0
const INTRUDER_PLAYER_DMG := 10
const INTRUDER_PLAYER_INTERVAL := 1.2

# Concentric onion fence rings around HOUSE_CENTER.
# Ring 1 is the starter perimeter with a closable gate; Rings 2 & 3 are player-unlocked layers.
const FENCE_GATE_WIDTH := 30.0
const FENCE_RINGS := [
	{"ring": 1, "half_extents": Vector2(114.0, 78.0), "gate_offset_x": 0.0, "built_at_start": true},
	{"ring": 2, "half_extents": Vector2(160.0, 122.0), "gate_offset_x": 0.0, "built_at_start": false},
	{"ring": 3, "half_extents": Vector2(206.0, 166.0), "gate_offset_x": 0.0, "built_at_start": false},
]

# --- Inventory & Economy (T1.6 / T2.1 / T2.2) ---
const BAG_CAPACITY := 16
const ACT1_START_STOCKPILE := 4
const ACT2_START_STOCKPILE := 8
const START_SPIKE_TRAPS := 2
const LOSE_BAG_AT_DUSK_ACT1 := false
const LOSE_BAG_AT_DUSK_ACT2 := true

# Whole-ring fence layer unlock, upgrade, and spike costs (no per-segment upgrades).
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

# --- Traps (T2.3) ---
const MAX_TRAPS := 16
const TRAP_MIN_SPACING := 14.0
const TRAP_PLACE_RANGE := 72.0
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
		"label": "Bear Snare",
		"cost": {"plank": 2, "scrap": 1},
		"damage": 1,
		"root_time": 3.5,
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

# --- Days & Nights (T0.5) ---
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

# Enemy counts tuned so average spawn rate stays <= 0.55/s (N1-5) and <= 0.70/s (N6-7).
const NIGHTS := {
	1: {"zombies": 8, "raiders": 0},
	2: {"zombies": 13, "raiders": 0},
	3: {"zombies": 18, "raiders": 0},
	4: {"zombies": 20, "raiders": 0},
	5: {"zombies": 22, "raiders": 4},
	6: {"zombies": 26, "raiders": 6},
	7: {"zombies": 32, "raiders": 8},
}

# --- Exploration, Dogs & Meteors (T3.1 / T3.2a / T3.2b) ---
const DAY_WANDERER_MIN := 3
const DAY_WANDERER_MAX := 6
const DAY_WANDERER_AGGRO := 50.0
const SEARCH_HOLD_TIME := 1.5
const DOG_TAME_TIME := 2.0
const DOG_MAX := 2
const DOG_HP := 20
const DOG_GUARD_RANGE := 60.0
const DOG_ATTACK_INTERVAL := 0.8
const METEOR_DAYS := [4, 6]
const METEOR_COUNT_DAY4 := 22
const METEOR_COUNT_DAY6 := 12
const METEOR_TELEGRAPH_TIME := 1.4
const METEOR_RADIUS := 22.0
const METEOR_PLAYER_DMG := 15
const METEOR_STRUCT_DMG := 20

# --- Light tints (CanvasModulate colors) ---
const TINT_DAY := Color(1.0, 1.0, 1.0)
const TINT_DUSK := Color(0.86, 0.67, 0.59)
const TINT_NIGHT := Color(0.24, 0.28, 0.52)
const TINT_BLOOD := Color(0.76, 0.22, 0.22)
const TINT_HOPELESS := Color(0.58, 0.64, 0.74)


## Returns the constant day duration (90 s) shared across Act 1 and Act 2.
func day_length() -> float:
	return DAY_LENGTH


## Returns the night duration in seconds: 30, 40, 50, 60, 70, 80, 90 s (capped at NIGHT_MAX).
func night_length(night_num: int) -> float:
	return minf(NIGHT_BASE + NIGHT_STEP * float(maxi(0, night_num - 1)), NIGHT_MAX)
