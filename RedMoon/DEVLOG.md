# Red Moon — Development Log (v2.0 Overnight Fix & Feature Build)

**Target Engine:** Godot 4.7 (GDScript 2.0, `GL Compatibility` renderer, Web-export safe — zero threads, zero GDExtension, zero external paths outside `res://` / `user://`).

> **Environment Note (Headless Godot Binary):**
> No `godot` binary was installed in the build sandbox, and outbound downloads redirecting to `objects.githubusercontent.com` are blocked by the sandbox network policy. Every file was instead verified rigorously with:
> - `gdparse` (26/26 GDScript files parsed cleanly)
> - `gdlint` (0 errors across all 26 scripts, every file <= 1000 lines)
> - Custom Godot 4.7 static semantic audit (verified zero `Config.*` accesses inside `static func`, zero 4.3→4.7 breaking APIs, zero deprecated `Image.create(`, zero integer-division warnings, 100% `res://` path resolution across all 102 static PNGs, 44 animated strips, and 3 fonts)
> - Cross-class signal arity & method-signature audit (0 mismatches)
> - Automated 2 px grid flood-fill & passability simulation over all 3 concentric onion fence rings (40,829 cells tested: 0 wall/corner leaks, 100% 28 px south-gate passability)
> - Wave spawn-rate & chew-timing verification across Nights 1–7.
>
> **To run the built-in automated smoke suite locally:**
> ```bash
> godot --headless --path RedMoon -- --smoke
> ```
> Exit code `0` confirms PASS; exit code `1` prints the exact invariant failure.

---

## Completed Tiers & Tasks

### Tier 0 — Foundations & Critical Fixes
- **T0.A (`sprite_data.gd`, `assets/moon/`, `assets/fonts/`, `assets/animals/`):** Installed `RedMoon_Assets_v2.zip` into `RedMoon/` and registered all 15 `32x32` moon/lunar PNGs (`moon/moon_00..03`, `moon/moon_00_white`, `moon/moon_00_red..03_red`, `moon/lunar_04..09`) in `SpriteData.STATIC`.
- **T0.B (`sprite_factory.gd`, `CREDITS.txt`):** Implemented the centralized 3-font retro pixel system (`PixelOperator8.ttf` body, `PixelOperator8-Bold.ttf` bold/buttons, `KiwiSoda.ttf` display headings) at strict integer multiples of `8/16/32`, nearest-neighbor filtering, hinting/antialiasing/subpixel-positioning disabled, 1 px dark outline + shadow, and updated `CREDITS.txt` (noting KiwiSoda license must be verified before any public/commercial release).
- **T0.0 (`smoke_runner.gd`, `main.gd`):** Added `--smoke` CLI auto-play harness verifying all 7 nights, onion-ring geometry, zero leaked night piles, Act 2 world expansion after Night 3, and clean process exit.
- **T0.1 (`project.godot`, `main.gd`, `settings_store.gd`):** Configured crisp 1080p/1440p/4K scaling (`stretch/mode="canvas_items"`, `aspect="keep"`, `scale_mode="fractional"`, `1280x720` default window override, `snap_2d_transforms_to_pixel=true`, `snap_2d_vertices_to_pixel=true`, `default_texture_filter=0`, `F11` and `Alt+Enter` fullscreen toggle persisted in `user://settings.cfg`).
- **T0.1b (`config.gd`, `world_builder.gd`, `hud.gd`, `story_card.gd`, `upgrade_ui.gd`):** Enlarged viewport to `640x360`, `ACT1_RECT` to `960x540` (`Rect2(720, 405, 960, 540)`), `WORLD_SIZE` to `2400x1350`, `HOUSE_CENTER` to `(1200, 675)`, `HOUSE_DOOR` to `(1200, 738)`, `WORLD_EXPAND_NIGHT = 3`, and removed legacy `480x270` / `1440x810` layout assumptions.
- **T0.2 (`story_card.gd`, `hud.gd`, `wave_spawner.gd`):** Added centered day/night header banners + persistent top-center objective strip while preserving the Blood Moon false-deadline twist (intro card 3 states *"The Blood Moon rises on Night 5."*, Act 1 counts down toward Night 5, Night 3 rises early, world expands after surviving Night 3, Act 2 counts down to the real Blood Moon on Night 7).
- **T0.3 (`world_builder.gd`, `main.gd`):**
  - *Root cause identified:* Previously `world_builder.gd::build_farmhouse_yard()` placed 24 decorative wood fence/post pieces via `_place_yard_piece()` directly into `Entities` with no collider, no HP, and no group; Act 2 swaps left orphaned pass-through wood blocks on screen.
  - *Fix:* Deleted `_place_yard_piece()` and `_act1_yard_fills` entirely; all perimeter wood pieces are now real solid `Structure` segments. Added night-start cleanup + debug assertion ensuring zero surviving `"piles"` nodes when night starts.
- **T0.4 (`config.gd`, `world_builder.gd`, `structure.gd`, `world_effects.gd`):** Replaced the 6 uncollided fences with concentric onion rings (`Config.FENCE_RINGS`):
  - **Ring 1** (`half_extents = 92x62`, 14 segments, built Day 1, 50 HP each, 28 px south gate)
  - **Ring 2** (`half_extents = 136x106`, 17 segments, built Day 1, 50 HP each, 28 px south gate)
  - **Ring 3** (`half_extents = 180x150`, 22 segments, unbuilt ghost foundations, buildable per-segment or ring-wide)
  - Every segment has a `StaticBody2D` on Layer 1 matching its exact tiled wood bounds with 10×10 corner overlap (zero diagonal corner leaks). Added `F8` debug collider overlay.
- **T0.5 (`config.gd`, `wave_spawner.gd`):** Constant `DAY_LENGTH = 90.0 s` across Act 1 and Act 2; growing nights (`30, 40, 50, 60, 70, 80, 90 s` via `NIGHT_BASE = 30`, `NIGHT_STEP = 10`, `NIGHT_MAX = 120`).
- **T0.6 (`enemy.gd`, `player.gd`, `world_effects.gd`):** Upgraded `Enemy` to `CharacterBody2D` on Layer 3 (`mask = 1 | 2`), soft enemy-enemy separation (`10 px`), generous `14x18` hurtbox, velocity knockback via `move_and_slide()`, white damage flash, blood/wood sparks, `0.04 s` hit-stop, and screen shake.

### Tier 1 — Core Gameplay & Atmosphere
- **T1.3 (`enemy.gd`):** Full AI state machine (`WALK_TO_TARGET`, `ATTACK_STRUCTURE`, `CHASE_PLAYER`, `ATTACK_PLAYER`, `WANDER`, `ROOTED`, `KNOCKBACK`, `DYING`, `DISSOLVING`). Zombies stay and chew fences (`4 dmg / 1.2 s` ≈ `15 s` per 50 HP fence), aggro onto nearby outside players (`56 px` zombie / `80 px` raider), leash back after `140 px` for `3 s`, and recover cleanly from obstacles.
- **T1.5 (`structure.gd`, `player.gd`, `main.gd`, `hud.gd`):** Interactive player-only House Door (`E` toggles open/closed; pressing `E` at doorstep enters indoor safe zone with `+1 HP / 2 s` healing and window bow firing); open-door intruder system (`3 HP/s` inside damage, `Space` clears intruders); floating world-space House HP bar with 4 s fade & color ramp; 75%/50%/25% cracks/smoke/flames; 3 s crumble animation into walkable rubble + hopeless state (NOT game over) + rebuild option. Game Over occurs strictly when `player.hp <= 0`.
- **T1.6 (`inventory.gd`, `upgrade_ui.gd`, `economy_controller.gd`):** Unified `Inventory` (`bag` cap `16`, unlimited `stockpile`), auto-deposit at house, `I` Inventory panel, structure hover highlight + tooltip, and keyboard/mouse context menus (`U` or click) for House Workshop, single-segment & ring-wide Fence repair/upgrade, and building Ring 3.
- **T1.2 (`arrow.gd`, `player.gd`):** Auto-aim Hunting Bow (`F` or LMB, `R` reload, `6` mag / `30` reserve, `150 px` range, `0.5 s` cadence, `2.2 s` reload) functional outdoors and from house windows while sheltered inside.
- **T1.1 (`moon_sky.gd`, `moonrise.gd`, `hud.gd`):** Removed old persistent HUD sky moon icon. Built reusable `MoonSky` (3-band sky, stars, owner `32x32` moon scaled 4×, 3-layer procedural Bayer-dithered parallax clouds that occlude the moon, horizon farmhouse silhouette) and ~7 s skippable `MoonriseCutscene` featuring Night 3's pale-white-to-blood-red crossfade.
- **T1.4 (`sprite_factory.gd`, `structure.gd`, `player.gd`, `enemy.gd`, `world_builder.gd`):** Volumetric 2D-shaded farmhouse texture (top-left light, right-wall shadow strip, roof overhang line, base AO, chimney with rising pixel smoke, inset windows, Level 2/3 reinforcements), time-of-day dynamic cast shadow, warm `PointLight2D` windows/porch/lantern + `LightOccluder2D`, and elliptical blob shadows under all characters, props, and pickups.
- **T1.7 (`settings_store.gd`, `story_card.gd`, `main.gd`):** Mandatory first-time opening story intro with `[Esc] Skip Intro` remembered in `user://settings.cfg` (`intro_seen`, `play_intro` toggleable in Settings).
- **T1.8 (`toast.gd`, `settings_store.gd`):** Non-blocking bottom-right achievement toast queue (`user://achievements.cfg`, 15 achievements) plus dramatic `"WORLD EXPANDED!"` transition card after surviving Night 3.

### Tier 2 — Progression & Strategy
- **T2.1 (`world_builder.gd`, `pile.gd`, `economy_controller.gd`):** Added `scrap` resource from 15 searchable POIs (hold `E` 1.5 s), loose mid/outer scrap piles, and meteor shards.
- **T2.2 (`upgrade_ui.gd`, `economy_controller.gd`, `watchtower.gd`, `player.gd`):** Integrated full workshop & defense tree: House Lv 2/3 (`160/240 HP`), Fence Lv 2/3 (`90/140 HP`), Spiked Fences, Bigger Quiver, Quick Hands, Barbed Arrows (pierce +1), Heavy Spear (2 melee dmg), Swift Boots (+15% speed), Quick Shockwave (-30% Q CD), Craft Arrows, and automated Watchtowers (max 2).
- **T2.3 (`trap.gd`, `economy_controller.gd`, `hud.gd`):** Implemented craftable/placeable Spike Traps (3 dmg × 5 triggers), Snares (3 s root), and Lure Posts (`140 px` attract radius, 25 HP) selectable with `1/2/3` and placed with `T` (max 12 active).

### Tier 3 — Exploration, Polish & Events
- **T3.1 (`world_builder.gd`, `wave_spawner.gd`, `hud.gd`):** 15 seeded searchable POIs across the `2400x1350` valley (4 inside `ACT1_RECT`, 11 in the outer Act 2 valley), Act 2 daytime wanderers (`3–6`), and off-screen `HOME >>` directional indicator when > `260 px` from the farmhouse.
- **T3.2a (`dog.gd`):** Implemented full asset-gated companion Dog system (stray -> hold `E` 2 s tame -> `G` Follow/Guard, max 2). `Dog.assets_available()` checks `res://assets/animals/` for `dog_idle_*.png` and `dog_run_*.png`; remains 100% dormant until real dog sprites are added (zero invented art).
- **T3.2b (`world_effects.gd`, `world_builder.gd`, `main.gd`):** Meteor Showers on Days 4 and 6 (plus `F7` debug trigger), dark shrinking ground telegraphs + glowing streaks, `moon/lunar_04..09` crater decals, meteor scrap shards, and `Meteor Survivor` achievement.
- **T3.3 & T3.4 (`hud.gd`, `upgrade_ui.gd`, `sfx.gd`):** Polished Main Menu reusing `MoonSky` live red moon & clouds with Play, Continue, Controls, Settings, Achievements, Credits, and Quit (hidden on Web); full Pause menu (`Esc`), custom pixel cursor, and 22 procedural 8-bit SFX.

---

## Tuning Tables (`RedMoon/scripts/config.gd`)

### Day & Night Schedule
| Night | Day Length | Night Length | Zombies | Raiders | Avg Spawn Rate | Special |
|---|---|---|---|---|---|---|
| 1 | 90 s | 30 s | 8 | 0 | 0.33 / s | Act 1 (false deadline: Night 5) |
| 2 | 90 s | 40 s | 13 | 0 | 0.38 / s | Act 1 |
| 3 | 90 s | 50 s | 18 | 0 | 0.41 / s | **Early Blood Moon** → World Expands! |
| 4 | 90 s | 60 s | 20 | 0 | 0.37 / s | Act 2 + Meteor Shower (22 meteors) |
| 5 | 90 s | 70 s | 22 | 4 | 0.41 / s | Act 2 + Raiders from East |
| 6 | 90 s | 80 s | 26 | 6 | 0.43 / s | Act 2 + Meteor Shower (12 meteors) |
| 7 | 90 s | 90 s | 32 | 8 | 0.48 / s | **Final Blood Moon** → Victory |

### Structure & Workshop Costs
| Item / Upgrade | Effect | Cost |
|---|---|---|
| Ring 3 Segment | Build 50 HP outer segment | 3 planks |
| Fence Lv 2 / Lv 3 | 90 HP / 140 HP metal | 3 planks / 3 planks + 2 scrap |
| Fence Spikes | Deals 1 recoil hit to chewing enemies | 3 planks + 1 scrap |
| House Lv 2 / Lv 3 | 160 HP / 240 HP fortress | 12P+4S / 20P+10S |
| Rebuild Fallen House | Restores house at 40% HP | 35P (Act 1) / 25P+8S (Act 2) |
| Craft +8 Arrows | Refills bow reserve | 1 plank |
| Bigger Quiver / Quick Hands / Barbed Arrows | Mag 12 & Res 50 / Reload 1.4 s / Pierce +1 | 6P+2S / 8P+3S / 8P+4S |
| Heavy Spear / Swift Boots / Quick Shockwave | Melee 2 dmg / +15% speed / -30% Q CD | 6P+2S / 5P+2S / 10P+4S |
| Watchtower (Max 2) | 40 HP auto-archer (120 px range) | 15 planks + 6 scrap |
| Spike / Snare / Lure Trap (Max 12) | 3 dmg ×5 / 3 s root / 140 px attract | 3P / 2P+1S / 2P |
