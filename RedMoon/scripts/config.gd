extends Node
## Autoload "Config". Every tuning number lives here. Tune by playing.

const VIEW_SIZE := Vector2(480, 270)
const WORLD_SIZE := Vector2(1440, 810)
const WORLD_RECT := Rect2(0, 0, 1440, 810)
const ACT1_RECT := Rect2(480, 270, 480, 270)  # center cell of the 3x3 world
const HOUSE_CENTER := Vector2(720, 405)
const HOUSE_DOOR := Vector2(720, 460)  # Bounce Back arrival point

# --- Player ---
const PLAYER_SPEED := 60.0
const PLAYER_HP := 50
const SWING_TIME := 0.3
const SWING_COOLDOWN := 0.4
const SWING_BOX := Vector2(22, 18)  # hitbox size in front of the player
const SWING_OFFSET := 8.0  # distance from feet to box center along facing
const KNOCKBACK := 14.0
const CONTACT_INVULN := 1.0
const BOUNCE_STUN := 5.0
const BOUNCE_CD_ACT1 := 10.0
const BOUNCE_CD_ACT2 := 40.0
const SWING_GROWTH_PER_BOUNCE := 0.15
const MAX_BOUNCE_BONUSES := 3

# --- Enemies (one Enemy class, different numbers) ---
const ENEMY_TYPES := {
	"zombie": {"hits": 2, "speed": 33.0, "struct_dmg": 10, "player_dmg": 10, "tint": Color(1, 1, 1)},
	"raider": {"hits": 1, "speed": 51.0, "struct_dmg": 20, "player_dmg": 10, "tint": Color(1.0, 0.6, 0.55)},
	"brute": {"hits": 6, "speed": 20.0, "struct_dmg": 25, "player_dmg": 15, "tint": Color(1, 1, 1)},
}
const BRUTE_ENABLED := false
const RAIDER_SIDE := "east"

# --- Structures ---
const HOUSE_HP := 100
const FENCE_HP := 30
const PLANK_HEAL := 8  # 1 plank = +8 HP on anything
const DAWN_FREE_REPAIR := 10
const FENCE_REINFORCED_MIN_HP := 20  # >= this looks reinforced, 1..19 looks wooden, 0 = ruin
const HOUSE_REACH := 40.0
const FENCE_REACH := 22.0
const FENCE_SLOTS := [
	{"offset": Vector2(-70, -62), "horizontal": true},
	{"offset": Vector2(70, -62), "horizontal": true},
	{"offset": Vector2(-70, 62), "horizontal": true},
	{"offset": Vector2(70, 62), "horizontal": true},
	{"offset": Vector2(-92, 0), "horizontal": false},
	{"offset": Vector2(92, 0), "horizontal": false},
]

# --- Days ---
const ACT1_DAY_TIME := 20.0
const ACT1_PLANKS_PER_DAY := 8
const ACT2_DAY_TIME := 90.0
const ACT2_DUSK_TIME := 15.0  # last seconds of the day
const ACT2_START_STOCKPILE := 8
const LOSE_BAG_AT_DUSK := true
const PILES := [
	{"count": 6, "planks": 2, "r_min": 110.0, "r_max": 170.0},  # near
	{"count": 4, "planks": 3, "r_min": 180.0, "r_max": 280.0},  # middle
	{"count": 3, "planks": 6, "r_min": 330.0, "r_max": 400.0},  # far
]

# --- Nights: length in seconds, enemy counts ---
# Night 3 = early Blood Moon: +1 zombie per 2 planks dropped off in total.
# Night 7 = final Blood Moon: +1 zombie per 2 planks left in the stockpile at dusk.
const NIGHTS := {
	1: {"len": 45.0, "zombies": 8, "raiders": 0},
	2: {"len": 50.0, "zombies": 14, "raiders": 0},
	3: {"len": 60.0, "zombies": 20, "raiders": 0},
	4: {"len": 55.0, "zombies": 20, "raiders": 0},
	5: {"len": 60.0, "zombies": 22, "raiders": 4},
	6: {"len": 60.0, "zombies": 24, "raiders": 6},
	7: {"len": 75.0, "zombies": 30, "raiders": 8},
}

# --- Light tints (CanvasModulate colors) ---
const TINT_DAY := Color(1, 1, 1)
const TINT_DUSK := Color(0.86, 0.67, 0.59)
const TINT_NIGHT := Color(0.27, 0.31, 0.55)
const TINT_BLOOD := Color(0.78, 0.24, 0.24)
