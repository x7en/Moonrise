extends Node
## Autoload "Config". Every tuning number lives here so you can tweak the game in one place.

# --- World & Camera ---
const VIEW_SIZE := Vector2(480, 270)
const WORLD_SIZE := Vector2(1440, 810)
const WORLD_RECT := Rect2(0, 0, 1440, 810)
const ACT1_RECT := Rect2(480, 270, 480, 270)  # Center cell of the 3x3 world
const HOUSE_CENTER := Vector2(720, 405)
const HOUSE_DOOR := Vector2(720, 468)  # Center of the farmhouse yard front door gap

# --- Retro Pixel Font ---
# Drop your .ttf font (such as Kiwi Soda or Pixel Dogica) at this path.
const PIXEL_FONT_PATH := "res://assets/fonts/pixel_font.ttf"

# --- Player & Spear Melee ---
const PLAYER_SPEED := 85.0  # Snappy movement speed for exploring and kiting
const PLAYER_HP := 50
const SWING_TIME := 0.3
const SWING_COOLDOWN := 0.38
const SWING_BOX := Vector2(32, 22)  # Spear hitbox: 32 px forward reach, 22 px wide
const SWING_OFFSET := 18.0  # Thrust distance in front of the player
const KNOCKBACK := 16.0
const CONTACT_INVULN := 1.0
const BOUNCE_STUN := 5.0
const BOUNCE_CD_ACT1 := 10.0
const BOUNCE_CD_ACT2 := 40.0
const SWING_GROWTH_PER_BOUNCE := 0.15
const MAX_BOUNCE_BONUSES := 3

# --- Enemies (one Enemy class driven by these stats) ---
const ENEMY_TYPES := {
	"zombie": {
		"hits": 2,
		"speed": 33.0,
		"struct_dmg": 10,
		"player_dmg": 10,
		"tint": Color(1, 1, 1),
	},
	"raider": {
		"hits": 1,
		"speed": 50.0,
		"struct_dmg": 20,
		"player_dmg": 10,
		"tint": Color(1.0, 0.6, 0.55),
	},
	"brute": {
		"hits": 6,
		"speed": 20.0,
		"struct_dmg": 25,
		"player_dmg": 15,
		"tint": Color(1, 1, 1),
	},
}
const BRUTE_ENABLED := false
const RAIDER_SIDE := "east"

# Wave group pacing: enemies arrive in small bursts instead of a constant wall.
const WAVE_GROUP_MIN := 2
const WAVE_GROUP_MAX := 3
const WAVE_MEMBER_DELAY := 0.55

# --- Structures & Farmhouse Perimeter ---
const HOUSE_HP := 100
const FENCE_HP := 30
const PLANK_HEAL := 8  # 1 plank = +8 HP on any structure
const DAWN_FREE_REPAIR := 10
const FENCE_REINFORCED_MIN_HP := 20  # >= 20 reinforced, 1..19 wooden, 0 = ruin
const HOUSE_REACH := 56.0  # Keeps enemies outside the 96x90 house sprite (half-width 48 + 8 px)
const FENCE_REACH := 22.0
const FENCE_SLOTS := [
	{"offset": Vector2(-70, -62), "horizontal": true},
	{"offset": Vector2(70, -62), "horizontal": true},
	{"offset": Vector2(-70, 62), "horizontal": true},
	{"offset": Vector2(70, 62), "horizontal": true},
	{"offset": Vector2(-92, 0), "horizontal": false},
	{"offset": Vector2(92, 0), "horizontal": false},
]

# --- Days & Loot Piles ---
const ACT1_DAY_TIME := 60.0  # Generous daytime window in Act 1
const ACT1_PLANKS_PER_DAY := 10
const ACT2_DAY_TIME := 100.0  # Extra breathing room for exploring the full map
const ACT2_DUSK_TIME := 15.0  # Last seconds of the day
const ACT2_START_STOCKPILE := 8
const LOSE_BAG_AT_DUSK := true

# Three loot rings across the 1440x810 map.
# At 85 px/s, far piles (490..680 px away) take roughly 6 to 10 seconds to reach.
const PILES := [
	{"count": 7, "planks": 2, "r_min": 130.0, "r_max": 240.0},  # Near ring
	{"count": 6, "planks": 3, "r_min": 250.0, "r_max": 440.0},  # Middle ring
	{"count": 5, "planks": 6, "r_min": 490.0, "r_max": 680.0},  # Far wasteland ring
]

# --- Nights: length in seconds and re-tuned (~30% lower) enemy counts ---
# Night 3 = early Blood Moon: +1 zombie per 3 planks dropped off in total.
# Night 7 = final Blood Moon: +1 zombie per 3 planks left in the stockpile at dusk.
const NIGHTS := {
	1: {"len": 45.0, "zombies": 6, "raiders": 0},
	2: {"len": 50.0, "zombies": 10, "raiders": 0},
	3: {"len": 60.0, "zombies": 14, "raiders": 0},
	4: {"len": 55.0, "zombies": 14, "raiders": 0},
	5: {"len": 60.0, "zombies": 15, "raiders": 3},
	6: {"len": 60.0, "zombies": 17, "raiders": 5},
	7: {"len": 75.0, "zombies": 21, "raiders": 6},
}

# --- Light tints (CanvasModulate colors) ---
const TINT_DAY := Color(1, 1, 1)
const TINT_DUSK := Color(0.86, 0.67, 0.59)
const TINT_NIGHT := Color(0.27, 0.31, 0.55)
const TINT_BLOOD := Color(0.78, 0.24, 0.24)
