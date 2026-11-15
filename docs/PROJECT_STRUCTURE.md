# Moonrise — Project & Scene Structure

The Godot 4.7 project lives in `RedMoon/` (`RedMoon/project.godot`).
- **Main scene:** `res://scenes/main.tscn`
- **Autoload:** `Config` (`res://scripts/config.gd`) — balance constants, world/camera bounds, font paths, weapon & enemy tables.
- **Viewport:** `640×360` logical resolution (`canvas_items` stretch, `keep` aspect, nearest-neighbor pixel filtering).

---

## Main Scene Tree (`RedMoon/scenes/main.tscn`)

```text
Main (Node2D)                          [scripts/main.gd]
├── World (Node2D)                     Static world containers rebuilt per run
│   ├── GroundLayer (Node2D)           Procedural grass, paths, dirt, border colliders
│   └── DecalsLayer (Node2D)           Shadows, scorch marks, house decal overlays
├── Entities (Node2D, y_sort_enabled)  Y-sorted actors, structures, props, projectiles
│   └── Player                         [instance: scenes/player.tscn]
├── Effects (Node2D, z_index = 15)     [scripts/fx.gd] Sparks, rings, floating damage text
├── DayNightTint (CanvasModulate)      Day / dusk / night / Blood Moon color tint
├── Camera2D (Camera2D)                Follows Player (or House center while indoors)
├── Audio (Node)                       [scripts/sfx.gd]
│   ├── SfxPlayer_0 (AudioStreamPlayer)
│   ├── ...
│   └── SfxPlayer_9 (AudioStreamPlayer) 10-channel procedural synth SFX pool
├── UI (CanvasLayer, layer = 20)       [instance: scenes/hud.tscn]
├── Menus (CanvasLayer, layer = 30)    [instance: scenes/menus.tscn]
├── NightIntro (CanvasLayer, layer=40) [instance: scenes/night_intro.tscn]
├── IntroCards (CanvasLayer, layer=50) [instance: scenes/intro_cards.tscn]
└── Popups (CanvasLayer, layer = 50)   [instance: scenes/popups.tscn]
```

### Camera Behavior
`Camera2D` is a world-space child of `Main` (`enabled = true`, centered at `(1200, 729)` in the editor). At runtime, `main.gd:_update_camera()` locks onto `Config.HOUSE_CENTER` while the player is inside the farmhouse and follows `_player.position` outdoors (plus optional screen shake, rounded to pixels). `_apply_camera_limits()` clamps the camera to `Config.ACT1_RECT` (`720, 405` to `1680, 945`) during Act 1 and expands to `Config.WORLD_RECT` (`0, 0` to `2400, 1350`) in Act 2.

---

## Scene Reference (`RedMoon/scenes/`)

### Core & Player
| Scene | Root Type & Script | How It Is Loaded | Nodes & Responsibility |
| --- | --- | --- | --- |
| `main.tscn` | `Node2D` (`main.gd`) | `run/main_scene` in `project.godot` | Top-level game loop, world layers, `Entities` Y-sort container, `Effects`, `DayNightTint`, `Camera2D`, 10-player `Audio` pool, and all UI `CanvasLayer`s. |
| `player.tscn` | `CharacterBody2D` (`player.gd`) | Instanced under `Main/Entities/Player` | `CollisionShape2D` (8×8), `Shadow` (`Sprite2D`), `Sprite` (`AnimatedSprite2D`), `Spear` (`Sprite2D`), and `Lantern` (`PointLight2D`). Textures/frames are bound at `_ready()` via `Art`. |

### Spawnable Gameplay Scenes (`preload(...).instantiate()`)
Each spawnable scene is instantiated via `PackedScene.instantiate()` and configured with `setup(...)` before being added to `Entities`.

| Scene | Root Type & Script | Spawned From | Nodes & Responsibility |
| --- | --- | --- | --- |
| `enemy.tscn` | `CharacterBody2D` (`enemy.gd`) | `main.gd:_spawn_enemy()` | Zombies and raiders: `CollisionShape2D` (10×10), `Shadow`, `Sprite` (`AnimatedSprite2D`), and `HpBar` (`Node2D` + `Bg`/`Fill` `ColorRect`s). |
| `dog.tscn` | `CharacterBody2D` (`dog.gd`) | `waves.gd:spawn_dog_for()` | Stray/tamed companion dog: `CollisionShape2D` (8×6), `Shadow`, `Sprite` (`AnimatedSprite2D` scaled `0.5×`), and `HpBarBg`/`HpBarFill`. |
| `ghost.tscn` | `Node2D` (`ghost.gd`) | `waves.gd:spawn_ghost_for()` | Act 2 spectral enemies (`z_index = 2`): `Shadow`, `Sprite` (`AnimatedSprite2D` scaled `0.85×`), and `HpBar` (`Bg`/`Fill`). |
| `trap.tscn` | `Node2D` (`trap.gd`) | `shop.gd:spawn_trap_node()` | Spike, bear snare, and decoy lure traps: `Shadow`, `Sprite`, `AnimSprite` (`AnimatedSprite2D`), and `HpBar` (`ColorRect`). `setup()` toggles the active visual nodes per trap type. |
| `arrow.tscn` | `Node2D` (`arrow.gd`) | `main.gd:_spawn_arrow()` | Player and watchtower arrows: `Sprite` (`Sprite2D`) configured for normal or piercing arrow textures. |

### UI & Overlay Scenes
| Scene | Root Type & Script | Layer | Nodes & Responsibility |
| --- | --- | --- | --- |
| `hud.tscn` | `CanvasLayer` (`hud.gd`) | `20` | Contains three full-screen roots under `Root`: `HudLayer` (top bar, HP bar, house/bag/weapon/day readouts, 3-slot trap hotbar, announcement header banner, tame button, search progress bar, prompts, tooltips, home arrow), `TitleScreen` (`MenuSky`, title/subtitle, main menu buttons, version label), and `EndScreen` (dimmer, victory/defeat panel, Retry/New Run/Main Menu buttons). |
| `menus.tscn` | `CanvasLayer` (`menus.gd`) | `30` | Static modal shell (`Dimmer`, `Panel`, `VBox`, `TitleLabel`, `SubtitleLabel`, `Scroll/ListBox`, `FooterLabel`). Dynamic menu rows and buttons for Pause, Inventory, Crafting, Upgrades, Settings, Controls, Achievements, and Credits are populated into `ListBox` in code when each panel opens. |
| `night_intro.tscn` | `CanvasLayer` (`night_intro.gd`) | `40` | Moonrise / Blood Moon cutscene overlay (`Root/Sky` running `moon_sky.gd`, `TitleLabel`, `TextBand`, `NarrationLabel`, `SkipLabel`, `BloodFlash`). |
| `intro_cards.tscn` | `CanvasLayer` (`intro_cards.gd`) | `50` | Story and tutorial card viewer (`Background`, `CardFrame`, `ArtHolder`, `TitleLabel`, `BodyLabel`, `PromptLabel`, `SkipLabel`). Card illustrations are swapped inside `ArtHolder` in code. |
| `popups.tscn` | `CanvasLayer` (`popups.gd`) | `50` | Slide-in achievement toast (`ToastPanel` with `StyleBoxFlat`, `IconRect`, `TitleLabel`, `DescLabel`). Placed after `IntroCards` in `main.tscn` so toasts render above story cards. |

---

## Still Constructed in Code (Intentionally Kept Dynamic)

These parts remain code-generated because their node counts or shapes depend on procedural seeds, runtime state, or dynamic menu data:

- **Procedural world & map (`map_gen.gd`):** Ground tilemap composite, seeded trees/rocks/wrecks/stumps, Act 1 fog boundary strips, world border colliders, and harvestable resource props.
- **Farmhouse & fence rings (`structure.gd`):** Houses and variable-length fence/gate segments build different collider counts, tile sprites, window lights, occluders, crack lines, rubble, and smoke/flame particles depending on ring/orientation/state.
- **Dynamic menu rows (`menus.gd`):** Buttons, sliders/toggles, weapon lists, crafting recipes, upgrade cards, and achievement rows inside `Menus/Panel/VBox/Scroll/ListBox` are rebuilt dynamically every time a menu opens.
- **Procedural sky layers (`moon_sky.gd`):** The 52 seeded twinkling stars, scrolling cloud strips, animated moon layers, and horizon silhouettes inside `TitleScreen/MenuSky` and `NightIntro/Root/Sky`.
- **Card art & short-lived FX (`intro_cards.gd`, `fx.gd`):** Per-card `TextureRect` artwork inside `ArtHolder`, floating combat text `Label`s, and custom-drawn sparks/rings.
- **Secondary dynamic world entities (`boomerang.gd`, `watchtower.gd`, `pile.gd`):** Thrown boomerangs, buildable watchtowers, and variable-tier loot piles (planks/scrap/arrows) are still spawned via `.new()`.
- **Runtime art & audio resources (`art.gd`, `sfx.gd`):** `SpriteFrames` sliced from sprite strips, radial light / blob shadow textures, bitmap font styling, 9-patch `StyleBox`es, and synthesized `AudioStreamWAV` clips.
