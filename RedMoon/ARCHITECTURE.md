# RED MOON (Bounce Back): Godot 4 Architecture & Build Spec

**Instructions to the AI reading this:** build the game described below as a **Godot 4 project (GDScript)** that a beginner can open in the Godot editor, run with F5, and edit afterwards. Do not ask questions; decide sensibly and list your decisions in a comment block at the top of `main.gd`. Return COMPLETE code for every file, with no "...rest of code" placeholders.

## 0. What already exists (do NOT output these again)

The user already has a Godot project folder containing these files and the whole `assets/` folder (section 11 shows the three code/config files verbatim, in case you cannot open the zip):

- `project.godot` (Godot 4.3+, GL Compatibility renderer, 480 x 270 viewport, integer stretch, nearest texture filter, autoload `Config`)
- `scenes/main.tscn` (root `Node2D` named Main with `res://scripts/main.gd` attached)
- `scripts/config.gd` (autoload `Config`, every tuning number)
- `scripts/sprite_data.gd` (`class_name SpriteData`, frame tables for every sprite)
- `assets/...` (the PNG sprites, already imported by Godot when the project is opened)

**You write everything else**, starting with `res://scripts/main.gd`. Never require changes to `project.godot` or `main.tscn`.

## 1. Output format

- Give each file in its own fenced code block, preceded by a heading line like `### res://scripts/player.gd`.
- Keep to this file list (merge files only if you must; fewer, longer files are fine):

```
scripts/main.gd            game controller: builds the scene tree, owns the phase state machine and the game state
scripts/sprite_factory.gd  class_name SpriteFactory: cached textures, SpriteFrames from strips, placeholders
scripts/player.gd          class_name Player (CharacterBody2D)
scripts/enemy.gd           class_name Enemy (Node2D): zombie, raider, brute from Config.ENEMY_TYPES
scripts/structure.gd       class_name Structure (Node2D) + House and Fence subclasses
scripts/pile.gd            class_name Pile (Node2D): plank pile pickup
scripts/world_builder.gd   class_name WorldBuilder: ground image, seeded scenery, colliders
scripts/hud.gd             class_name HUD (CanvasLayer): hearts, bars, counters, banner
scripts/story_card.gd      class_name StoryCard (CanvasLayer): title, story cards, game over, ending
scripts/sfx.gd             class_name Sfx: procedural sound effects (Tier 3)
```

- **Prefer building nodes in code (`_ready()`) over hand-written `.tscn` files**, because hand-written scene files are fragile. The only `.tscn` is the existing `main.tscn`. Expose useful tuning values with `@export` where it makes sense, and keep game-wide numbers in `Config`.
- Must also work in a Web export (no threads, no GDExtension, no external files).

**Godot 4 / GDScript 2.0 syntax rules (do not use Godot 3 syntax):** `@export`, `@onready`, `extends CharacterBody2D`, `velocity` + `move_and_slide()`, `signal x` + `x.emit()`, `some_signal.connect(callable)`, `await get_tree().create_timer(t).timeout` (no `yield`), `queue_free()`, `Vector2i`, typed variables (`var hp: int = 0`), `Engine.time_scale`, `Input.is_action_pressed()`, `randf_range()`, `Tween` via `create_tween()`. Initialize all variables; avoid name shadowing; no unused-signal spam in the Output panel.

## 2. Build priority (if output length forces cuts, cut from the bottom)

1. **Tier 1:** title, story cards, Act 1 complete (3 nights, planks, Bounce Back, early Blood Moon, lose and retry, win).
2. **Tier 2:** Act 2 (big map, camera, plank piles, fences, dawn repair, nights 4 to 7, final Blood Moon, ending, dusk snapshot retry).
3. **Tier 3:** raiders (night 5+), sound, scenery, polish. Within Tiers 2 and 3 cut in this order: raiders, dawn free repair, losing the bag at dusk, fences.

## 3. The game in one paragraph

Top-down 2D pixel survival. The king's army destroyed your home. You have three days to repair the house and defend it from zombies at night. The banner says "Blood Moon: night 5" so you think you have time, but on night 3 the Blood Moon rises early with a bigger wave. Your **Bounce Back** (teleport home and heal) is your escape. After night 3 the area is clear and the map opens. By day you explore and collect planks, at night the king's raiders and zombies smash your buildings, and each morning you rebuild before the final Blood Moon on night 7. One base camp (the house) sits at the center of a large explorable map. Only the HOUSE falling loses the game; the player's own death just triggers Bounce Back.

## 4. Scene tree, rendering, world

Built in `main.gd` `_ready()`:

```
Main (Node2D, main.gd)
|- CanvasModulate           light tint (Config.TINT_*), tweened over 2 s
|- Ground (Sprite2D)        one pre-rendered ImageTexture, centered = false
|- Decals (Node2D)          ruined fences, fence-slot marks, plank piles (drawn under everything)
|- Entities (Node2D)        y_sort_enabled = true: scenery, fences, house, player, enemies
|    each child's origin is its FEET position
|- Camera2D                 follows the player (position_smoothing off)
|- HUD (CanvasLayer)        not affected by CanvasModulate
|- StoryCard (CanvasLayer, layer 10)
```

- **Resolution:** the viewport is 480 x 270 (already set), so one world pixel = one art pixel. Never scale sprites. Use integer positions where possible.
- **One world coordinate system:** world is 1440 x 810 (3 x 3 screens), the house center is `Config.HOUSE_CENTER` (720, 405).
- **Act 1** uses only the center cell `Config.ACT1_RECT`: `Camera2D` limits set to that rect (limit_left=480, limit_right=960, limit_top=270, limit_bottom=540) and the player position clamped to it. **Act 2** sets the camera limits to `WORLD_RECT` and clamps the player to the world. This is how "the road opens" after night 3. Enemies are never clamped (they spawn just outside the visible area).
- **Ground:** build ONE `Image` (1440 x 810, RGBA8) once with `blit_rect` from the 16 x 16 tiles `terrain/grass_0..3` (mostly grass_0, the others sprinkled by a seeded hash of tile coordinates), then `ImageTexture.create_from_image`. Beyond 330 px from the house center use `terrain/wasteland_0..3` instead, so the far ring looks bleak. To `blit_rect` you need the tiles as `Image`s: use `texture.get_image()` (the textures are imported as regular Texture2D; this works).
- **Scenery** (seeded with a fixed seed): trees, bushes, rocks, grass tufts, plus a few containers, rusty cars and barrels in the middle and far rings, kept 120 px clear of the house. Trees, containers and cars are solid for the player: give each a `StaticBody2D` with a small `RectangleShape2D` at its base (collision layer 1). **Enemies ignore scenery** (no pathfinding). Act 1 should show a few trees and props around the cell border only.
- **Player collision:** `CharacterBody2D` with a small rectangle (about 8 x 6) at the feet, collision mask 1. The house is solid (a StaticBody2D rect). **Fences are NOT solid.**
- **Combat uses plain geometry** (`Rect2.intersects`, `distance_to`), not `Area2D` callbacks, to avoid physics-timing bugs. Enemy hurtbox is about `Rect2(pos.x - 5, pos.y - 14, 10, 14)`.
- **Light tint:** `CanvasModulate.color` tweened to `TINT_DAY`, `TINT_DUSK`, `TINT_NIGHT`, or `TINT_BLOOD` (Blood Moon nights).

## 5. Controls (create the InputMap actions in code in `main.gd`, using `InputMap.add_action` and `InputEventKey`)

| Action | Keys |
|---|---|
| `move_left/right/up/down` | arrows AND WASD |
| `swing` | Space |
| `bounce` | B |
| `repair` | E (Act 2: repair/rebuild the nearest structure within 40 px) |
| `confirm` | any key advances story cards; R or Enter retries after losing |
| `mute` | M |

Show the controls in one line at the bottom of the screen.

## 6. Entities and rules

Numbers are in `Config`; use them, never hard-code.

**Player** (`CharacterBody2D`). 50 HP, 4-direction facing (`down, up, left, right`; for diagonal movement face along the larger axis). Swing (Space): for 0.3 s a hitbox (`Config.SWING_BOX`, centered `SWING_OFFSET` px in front of the feet, a bit above the ground) hits each enemy at most once per swing. A hit on an enemy with more than 1 hit left: knockback 14 px over 0.15 s. Final hit: death animation 0.5 s, then `queue_free()`. Cooldown 0.4 s. An enemy touching the player: player -`player_dmg` HP, then 1 s invulnerability (blink by toggling `modulate.a`); the enemy keeps walking.

**Bounce Back.** One function `bounce_back()`, used two ways: action `bounce` (if off cooldown) and automatically when player HP reaches 0 (play the death animation 0.6 s first, ignore the cooldown). Effect: teleport to `Config.HOUSE_DOOR`, heal to full over 5 s, cannot swing for those 5 s (can still move), the house keeps taking hits. In Act 2 it also drops the bag into the stockpile. Each Bounce Back in a night makes the swing box 15% bigger for the rest of that night (max 3). Cooldown: 10 s in Act 1, 40 s in Act 2 (show a small cooldown bar). The player's death never ends the game.

**Enemy** (`Node2D`, group `enemies`). One class, `type` string picks numbers from `Config.ENEMY_TYPES` (`zombie` standard, `raider` = the axe sprites tinted via `modulate`, `brute` only if `Config.BRUTE_ENABLED`). It chooses a target ONCE at spawn: the nearest standing structure (HP > 0) to the spawn point. When that target falls, it picks the nearest standing structure to its current position. It walks straight at the target, no pathfinding. When within the structure's reach: the structure loses `struct_dmg`, the attack animation plays 0.3 s (optional), then the enemy disappears. Facing follows the larger velocity axis.

**Structure** (`Node2D`, group `structures`; fields `hp`, `max_hp`, `reach`). The **House** (100 HP, reach 40) is at the center and uses the sprite `structures/house` (96 x 90, top-left at `HOUSE_CENTER - (48, 45)`) with a dark-red overlay whose alpha is `(1 - hp/max_hp) * 0.4`; at HP 0 you lose. **Fences:** 6 fixed slots from `Config.FENCE_SLOTS` (offsets from the house center). A horizontal slot draws 3 `horizontal` sprites side by side, a vertical slot draws 2 `vertical` sprites stacked. Visual state by HP: `>= FENCE_REINFORCED_MIN_HP` uses `structures/fence_reinforced/...`, 1 to 19 uses `structures/fence_wood/...`, 0 is a ruin (`structures/ruins/gray-brick_debris` in Decals, plus faint corner marks so the empty slot is visible).

**Repair rule (everything uses it): 1 plank = +8 HP.** In Act 2, action `repair` near a structure or empty slot spends `min(stockpile, ceil((max_hp - hp) / 8.0))` planks, +8 HP each, capped at max. A ruined fence (0 HP) therefore costs 4 planks to bring back to 30. If the stockpile is empty show the banner "No planks". Only allowed in day and dusk phases.

**Planks and piles** (`Pile`, a `Node2D` with a distance check against the player, about 10 px).
- **Act 1:** each day, `ACT1_PLANKS_PER_DAY` single planks (sprite `pickups_planks/pallet_2`) lie randomly in the center cell (24 px margin, at least 80 px from the house center). Touching one puts it in the bag. Touching the house (player within the house rect expanded by 6 px) drops the bag off and heals the house immediately by 8 per plank (cap 100). Track `total_planks_dropped`.
- **Act 2:** at the start of each day scatter piles per `Config.PILES` (random angle and radius within the ring, clamped 24 px inside the world, not inside colliders). Sprites: near = `pallet_2`, middle = `pallet_1`, far = both drawn stacked. Touching a pile adds its planks to the bag. Touching the house drops the bag into the stockpile (start with `ACT2_START_STOCKPILE`).
- **Dusk (Act 2, the last `ACT2_DUSK_TIME` s of the day):** tint, banner "Dusk. Head home." When night starts, planks still in the bag are lost if `LOSE_BAG_AT_DUSK`.

## 7. Game flow (one state machine in `main.gd`, never separate scenes for day or night)

`enum Phase { TITLE, STORY, DAY, DUSK, NIGHT, DAWN, LOST, WON }`. Day, dusk, night and dawn all live in the SAME world; only the phase variable changes.

```
TITLE -> story cards 1,2,3 -> ACT 1
Act 1:  [day 20s] -> [night 1] -> [day] -> [night 2] -> [day] -> [night 3 EARLY BLOOD MOON]
        night 3 survived -> story card 4 -> ACT 2
Act 2:  dawn (3s banner, free repair, damage report, scatter piles) -> day 90s (dusk = last 15s)
        -> night 4..7 -> dawn ... -> night 7 FINAL BLOOD MOON survived -> ending card (story card 5) -> TITLE
```

- **Banners** (centered Label in HUD, fade out after 3 s): Day 1 and 2: "Day N. Blood Moon: night 5." Night 3 start: "The Blood Moon rises early!" and the tint goes red. Act 2 day: "Day N. Blood Moon: night 7. This time it's true." Before nights 5, 6, 7: "Raiders from the east!" (raiders spawn only along the east edge of the world, zombies along all edges). Dawn: damage report, e.g. "2 fences fell" (or "Nothing fell").
- **Spawning:** a Timer-like accumulator: spawn interval = night length / enemy count, +/-20% jitter. Act 1: spawn on the perimeter of the center cell just outside the camera view. Act 2: on the perimeter of the world.
- **Night end:** when the night timer hits 0, remaining enemies dissolve (fade, free) and the phase moves on. The win condition is simply: the house is alive at the end of the night.
- **Dawn (Act 2):** every standing structure gets `DAWN_FREE_REPAIR` HP free, then the damage report banner, then piles are scattered.
- **Lose:** house HP hits 0. Show "The house fell. Bounce back." with Retry (R or Enter). Retry restarts THAT night from the **dusk snapshot**, not the whole game.
- **Dusk snapshot** (taken the instant each night begins, after the bag is lost): `{night, house_hp, stockpile, fence_hps[6], total_planks_dropped}`. Act 1 snapshots house_hp and total_planks_dropped the same way. Retry restores it.
- **Enemy counts:** night 3 = 20 + floor(total_planks_dropped / 2) zombies. Night 7 = 30 zombies + 8 raiders + floor(stockpile_at_dusk / 2) extra zombies. (Hoarding must always be worse than spending.)
- **Story cards** (`StoryCard`): one reusable layer: black background, a small scene composed from the sprites with `TextureRect`s/`Sprite2D`s (house, trees, debris; card 1 bright and calm, card 2 red-tinted with debris, card 3 dusk-tinted ruins), one line of text, "press any key". Texts: 1 "Our village was quiet." 2 "Then the king's army came and burned it all." 3 "Only ruins are left. Night is coming." (then the title: RED MOON, Bounce Back) 4 "The zombies are gone. The silence is worse. The road out of the ruins is open." 5 "The house still stands. The king's castle is next." Title screen: "RED MOON / Bounce Back / Press any key to start", with the art credit line.

## 8. HUD (`HUD`, a CanvasLayer)

Top-left: player HP as hearts (`ui/heart_full`, `heart_half`, `heart_empty`; each heart = 10 HP, half = 5), and below it a house HP bar (two `ColorRect`s, red on dark, with the number). Top-right: "Day N / Night N", the phase timer, "Bag: n", "Stock: n" (Act 2), with a small pallet icon. Bottom-left: Bounce Back cooldown bar labeled "B". Bottom: the controls line. Center: the banner. Use the default font at size 8 with a 1 px shadow; a pixel font can be dropped in later.

## 9. Sprites and animation

- Each animated PNG is a **horizontal strip**. `SpriteData.ANIMATED[key] = [frames, frame_w, frame_h]`. Build a `SpriteFrames` at runtime: one animation per name (for example `walk_down`), each frame an `AtlasTexture` with `atlas = texture` and `region = Rect2(i * frame_w, 0, frame_w, frame_h)`. Set speed and loop per animation.
- Use `AnimatedSprite2D` with `centered = false` and set `offset = Vector2(-frame_w / 2.0, -frame_h)` **every time the animation changes**, so the feet sit at the node origin. Frame widths differ per direction and animation; always read them from `SpriteData`. If the body visibly jumps during the punch, shift x by half the width difference toward the facing side.
- Key naming: `player/<idle|run|punch>_<down|up|left|right>`, `player/death_<left|right>`, `enemies/<zombie|raider|brute>/<walk|attack|death>_<dir>`. Enemy and player **death** exists only for left and right; for up/down facing use the last horizontal facing (default right).
- Speeds: idle 6 fps, run and walk 10 fps (zombies 8 fps), punch = the 0.3 s swing time spread over its frames, death 10 fps.
- `SpriteFactory.tex(key)` loads `res://assets/<key>.png`, caches it, and if the file is missing returns a small colored placeholder `ImageTexture` so the game still runs.
- Static images: `Sprite2D` with `centered = false` and the same feet-origin offset for anything that sits on the ground.

## 10. Sound, debug, polish

- **Sfx (Tier 3):** generate tiny `AudioStreamWAV` blips in code (square wave / noise, 8-bit mono, 22050 Hz): swing, hit, structure hit, pickup, bounce, blood moon, fence rebuilt. Play through `AudioStreamPlayer`s. Mute with M.
- **Debug keys, only when `OS.is_debug_build()`:** F1 skip to the next phase, F2 toggle god mode (house takes no damage), F3 toggle `Engine.time_scale` between 1 and 4, F4 jump to Act 2, day of night 4 (with a few fences ruined, for testing).
- **Do not** read files from outside `res://`, do not use `OS.execute`, no threads.

## 11. Existing files, verbatim

`project.godot`:

```ini
; Engine configuration file.
config_version=5

[application]

config/name="Red Moon"
run/main_scene="res://scenes/main.tscn"
config/features=PackedStringArray("4.3", "GL Compatibility")

[autoload]

Config="*res://scripts/config.gd"

[display]

window/size/viewport_width=480
window/size/viewport_height=270
window/size/window_width_override=960
window/size/window_height_override=540
window/stretch/mode="viewport"
window/stretch/scale_mode="integer"

[rendering]

textures/canvas_textures/default_texture_filter=0
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
```

`scenes/main.tscn`:

```ini
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/main.gd" id="1_main"]

[node name="Main" type="Node2D"]
script = ExtResource("1_main")
```

`scripts/config.gd` (autoload `Config`):

```gdscript
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
```

`scripts/sprite_data.gd` (`class_name SpriteData`, read keys from here; it lists every sprite you may use):

```gdscript
class_name SpriteData
extends RefCounted
## Generated from the asset pack. [frames, frame_w, frame_h] per horizontal strip.
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
## [w, h] per single image.
const STATIC := {
	"nature/bush_1_green": [15, 13],
	"nature/bush_2_green": [28, 13],
	"nature/grass_1_green": [7, 5],
	"nature/grass_2_green": [12, 10],
	"nature/grass_3_green": [16, 15],
	"nature/grass_4_green": [16, 11],
	"nature/grass_5_green": [16, 14],
	"nature/rock-grass": [13, 9],
	"nature/tree-trunk_2_grass_green": [32, 12],
	"nature/tree_10_small-oak_green": [24, 36],
	"nature/tree_1_spruce_green": [16, 29],
	"nature/tree_2_spruce-sparse_green": [16, 29],
	"nature/tree_3_normal_green": [21, 30],
	"nature/tree_5_big_green": [34, 52],
	"nature/tree_6_pine_big_green": [27, 49],
	"nature/tree_7_birch_green": [39, 45],
	"nature/tree_8_birch_green": [24, 36],
	"nature/tree_9_small-oak_green": [39, 45],
	"pickups_planks/pallet_1": [13, 14],
	"pickups_planks/pallet_2": [14, 10],
	"props/barrel_blue_1": [12, 16],
	"props/barrel_red_1": [15, 16],
	"props/barrel_rust_blue_1": [12, 16],
	"props/barrel_rust_red_1": [12, 16],
	"props/cardboard_1": [11, 9],
	"props/cardboard_2": [12, 10],
	"props/container_11_green_horizontal": [41, 26],
	"props/container_1_gray_vertical": [24, 43],
	"props/container_3_gray_horizontal": [41, 26],
	"props/container_5_red_vertical": [24, 43],
	"props/container_7_red_horizontal": [41, 26],
	"props/container_9_green_vertical": [24, 43],
	"props/garbage-bin_1": [29, 23],
	"props/hydrant_1_red": [10, 15],
	"props/shopping-cart": [12, 16],
	"props/street-light_1_side": [23, 38],
	"props/tire_1": [15, 13],
	"props/traffic-cone": [9, 11],
	"props/trash-bag_1": [11, 11],
	"props/trash-can_1": [13, 13],
	"structures/fence_reinforced/gate_horizontal": [16, 15],
	"structures/fence_reinforced/gate_vertical": [3, 23],
	"structures/fence_reinforced/horizontal": [16, 14],
	"structures/fence_reinforced/left-side_right_down-connect": [12, 16],
	"structures/fence_reinforced/left-side_right_up-connect": [12, 16],
	"structures/fence_reinforced/middle_right_left_down-connect": [16, 16],
	"structures/fence_reinforced/right-side_left_down-connect": [12, 16],
	"structures/fence_reinforced/right-side_left_up-connect": [12, 16],
	"structures/fence_reinforced/vertical": [8, 16],
	"structures/fence_reinforced/vertical_for-gate": [7, 10],
	"structures/fence_wood/gate_horizontal": [16, 15],
	"structures/fence_wood/gate_vertical": [3, 23],
	"structures/fence_wood/horizontal": [16, 14],
	"structures/fence_wood/left-side_right_down-connect": [12, 16],
	"structures/fence_wood/left-side_right_up-connect": [12, 16],
	"structures/fence_wood/middle_right_left_down-connect": [16, 16],
	"structures/fence_wood/right-side_left_down-connect": [12, 16],
	"structures/fence_wood/right-side_left_up-connect": [12, 16],
	"structures/fence_wood/vertical": [8, 16],
	"structures/fence_wood/vertical_for-gate": [7, 10],
	"structures/house": [96, 90],
	"structures/ruins/gray-brick": [8, 10],
	"structures/ruins/gray-brick_debris": [17, 15],
	"structures/ruins/iron-beam": [15, 5],
	"structures/ruins/metal-plates": [23, 18],
	"terrain/grass_0": [16, 16],
	"terrain/grass_1": [16, 16],
	"terrain/grass_2": [16, 16],
	"terrain/grass_3": [16, 16],
	"terrain/wasteland_0": [16, 16],
	"terrain/wasteland_1": [16, 16],
	"terrain/wasteland_2": [16, 16],
	"terrain/wasteland_3": [16, 16],
	"ui/button_yes-sheet2": [20, 9],
	"ui/button_yes_not-pressed": [10, 9],
	"ui/button_yes_pressed": [10, 8],
	"ui/heart_empty": [13, 12],
	"ui/heart_full": [13, 12],
	"ui/heart_half": [13, 12],
	"ui/hp": [43, 4],
	"ui/hp-bar": [55, 12],
	"vehicles/car_1_rust_blue": [25, 37],
	"vehicles/car_2_rust_blue_upsidedown": [27, 37],
	"vehicles/car_3_rust_blue_van": [43, 27],
	"vehicles/car_4_rust_red": [38, 19],
	"vehicles/car_6_rust_green_scrap": [39, 20],
	"vehicles/car_7_rust_green_truck_": [59, 58],
}

static func path(key: String) -> String:
	return "res://assets/%s.png" % key

static func is_animated(key: String) -> bool:
	return ANIMATED.has(key)
```

Notes: `structures/fence_wood/horizontal` and `.../vertical` (and the same under `fence_reinforced`) are the pieces to use; corners and gates are optional. `structures/house` is a ready-made 96 x 90 house sprite. Scenery keys live under `nature/`, `props/`, `vehicles/`. `extras/` holds raw tilesets you may ignore. Art: Post-Apocalyptic Pixel Art Asset Pack by TheLazyStone: credit it on the title screen.

## 12. Acceptance checklist (the project is done when all are true)

- The project opens in Godot 4.3+ with no errors, and F5 runs the title screen; the Output panel shows no errors or warnings during a full playthrough.
- Act 1: planks can be picked up and dropped at the house (+8 HP each); zombies spawn at the edges, walk to the house, hurt it and vanish; two hits kill a zombie; night 3 turns red with a bigger wave; surviving it shows story card 4.
- Bounce Back works on B and on 0 HP, with the cooldown bar, the 5 s heal and the no-swing lock.
- Losing shows "The house fell. Bounce back." and Retry restores the dusk snapshot of that night only.
- Act 2: the camera follows the player across the whole 1440 x 810 map; three rings of piles appear each day; far piles take about 6 to 10 s to reach; the bag is lost when night starts; fences get chewed before the house; the repair key repairs and rebuilds; dawn gives free repair and the damage report; nights 4 to 7 run; raiders arrive from the east from night 5 with a warning banner; surviving night 7 shows the ending card.
- A good player wins night 3 with the house under a quarter health and wins night 7 after losing one or two fences (tune `Config` if not).
- 60 fps; dead enemies are freed; the ground is one pre-rendered texture.

## 13. Do NOT add

King boss fight, more than one resource, crafting or shops, several weapons, pathfinding, save-to-disk, touch controls, multiplayer, 3D, cutscene animation, dialogue trees, a second big map.
