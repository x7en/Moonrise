# Red Moon — Architecture & Controls

## Engine & Export Target
- **Godot 4.7** (`config_version=5`, `GL Compatibility` renderer)
- **Viewport & Scaling:** Virtual `640×360` pixel canvas (`1280×720` default window, `stretch/mode="canvas_items"`, `aspect="keep"`, `scale_mode="fractional"`, nearest texture filtering, pixel transform & vertex snapping).
- **Web-Export Safe:** Zero threads, zero GDExtension, zero file access outside `res://` and `user://`, procedural 8-bit `AudioStreamWAV` audio.

## World Geometry & Collision Layers
- **Full Valley (`WORLD_SIZE`):** `2400 × 1350` px (`HOUSE_CENTER = (1200, 675)`).
- **Act 1 Playable Area (`ACT1_RECT`):** `960 × 540` px centered on the farmhouse (`Rect2(720, 405, 960, 540)`). Expands to full `WORLD_RECT` after surviving `WORLD_EXPAND_NIGHT = 3`.
- **Concentric Onion Fence Rings (`Config.FENCE_RINGS`):**
  - Ring 1: half-extents `(92, 62)` — 14 built segments (50 HP), 28 px south gate.
  - Ring 2: half-extents `(136, 106)` — 17 built segments (50 HP), 28 px south gate.
  - Ring 3: half-extents `(180, 150)` — 22 unbuilt ghost foundations, buildable per segment or ring-wide.
- **Physics Layers:**
  - **Layer 1 (bit `1`):** Solid static obstacles (house, house door when closed, standing fence segments, watchtowers, trees, POI props, world border).
  - **Layer 2 (bit `2`):** Player (`CharacterBody2D`, mask `1 | 4`, disabled while sheltered inside house) and Dogs (`mask 1`).
  - **Layer 3 (bit `4`):** Enemies (`CharacterBody2D`, mask `1 | 2`; enemy-vs-enemy spacing handled via soft separation vector).

## Script Organization (`RedMoon/scripts/`)
| File | Responsibility |
|---|---|
| `config.gd` | Autoload `Config` holding all world dimensions, timers, costs, enemy/weapon/trap tuning, and tints. |
| `main.gd` | Root coordinator: scene layers, game-state machine, input routing, combat/event callbacks, and `--smoke` hooks. |
| `world_builder.gd` | Baked ground (`terrain/grass_0..3`, `wasteland_0..3`), concentric onion fence generator, 15 searchable POIs, Act 1 fog frame, and lunar crater decals. |
| `structure.gd` | 3D-shaded House (door, lights, cast shadow, cracks/smoke/flames, 3 s crumble → rubble, rebuild) and solid Fence segments (Lv 1–3, spikes, ghost foundations). |
| `player.gd` | Solid `CharacterBody2D` movement, spear melee, auto-aim bow + reload + indoor window shooting, indoor shelter healing, and lantern light. |
| `enemy.gd` | Solid `CharacterBody2D` enemy AI: chew structures, aggro/chase/leash player, open-door intruder entry, lure attraction, snare rooting, and daytime wanderers. |
| `arrow.gd` | Straight-flying bow & watchtower projectile with pierce support. |
| `pile.gd` | Collectible world pickups (`plank`, `scrap`, `arrow`, meteor shards) cleared cleanly at nightfall. |
| `trap.gd` | Functional Spike Trap, Snare, and Lure Post entities. |
| `watchtower.gd` | Automated defensive archer watchtower (max 2). |
| `dog.gd` | Asset-gated companion Dog system (dormant until `assets/animals/dog_idle_*` & `dog_run_*` exist). |
| `inventory.gd` | Stack-based resource container used for capped player `bag` (16) and unlimited house `stockpile`. |
| `economy_controller.gd` | House/fence/workshop/trap purchases, ring-wide stats, auto-deposit, POI loot rewards, settings actions, and day snapshots. |
| `wave_spawner.gd` | Night wave scheduling, edge spawn picking, day pickup/wanderer spawning, objective text, and HUD payload builder. |
| `world_effects.gd` | Hit sparks, floating combat/loot numbers, shockwave rings, meteor shower telegraphs/impacts, and `F8` debug collider overlay. |
| `sprite_data.gd` | Generated manifest mapping all static PNGs (including `moon/*`) and animated sprite strips to pixel sizes. |
| `sprite_factory.gd` | Texture/SpriteFrames cache, 3-font retro theme (`PixelOperator8`, Bold, `KiwiSoda`), 3D-shaded house builder, radial lights, blob shadows, and pixel icons. |
| `moon_sky.gd` | Reusable procedural night sky with stars, owner moon art, 3-layer Bayer-dithered occluding clouds, and horizon silhouette. |
| `moonrise.gd` | ~7 s skippable night-start moonrise cutscene (with Night 3 white-to-red crossfade). |
| `story_card.gd` | Full-screen retro story cards (opening intro with Night 5 false deadline + `WORLD EXPANDED!` reveal). |
| `hud.gd` | 640×360 HUD (header banners, persistent objective, HP/house/bow/trap strips, home arrow) + live `MoonSky` Main Menu & End screen. |
| `upgrade_ui.gd` | Keyboard-first modal UI for Inventory (`I`), House/Fence context menus (`U`/click), Pause (`Esc`), Controls, Settings, Achievements, and Credits. |
| `toast.gd` | Non-blocking bottom-right achievement & milestone toast queue. |
| `settings_store.gd` | Persistence layer for `user://settings.cfg` and `user://achievements.cfg` (15 achievements). |
| `sfx.gd` | Procedural 8-bit 22050 Hz mono `AudioStreamWAV` synthesizer pool. |
| `smoke_runner.gd` | Headless CLI `--smoke` automated 7-night & geometry verification runner. |

## Persistence Paths
- `user://settings.cfg` — `intro_seen`, `play_intro`, `fullscreen`, `master_volume`, `screen_shake`.
- `user://achievements.cfg` — unlocked flags for all 15 achievements.

## Controls Table
| Action | Keyboard | Mouse / Notes |
|---|---|---|
| Move | `WASD` or `Arrow Keys` | 8-directional movement |
| Spear Melee / Clear Intruder | `Space` | Clears intruders when sheltered inside |
| Hunting Bow (Auto-Aim) | `F` | `Left Click` (fires from windows when indoors) |
| Reload Bow | `R` | Auto-reloads on empty if reserve arrows exist |
| Door / Enter-Exit / Search | `E` | Tap at house door; **Hold `E`** (1.5 s) on ruins/cars to scavenge scrap; **Hold `E`** (2 s) on stray dog |
| Structure Upgrade / Repair Menu | `U` | `Left Click` on hovered House or Fence (within 80 px) |
| Inventory & Gear | `I` | Toggle Bag / Stockpile / Workshop summary |
| Shockwave Stun | `Q` | AoE push + 5 s stun; grows spear range up to 3× |
| Select Trap | `1` Spike / `2` Snare / `3` Lure | Highlights active trap type |
| Place Trap | `T` | Places selected trap in front of player (max 12) |
| Toggle Dog Follow / Guard | `G` | Active once dog textures exist and a dog is tamed |
| Pause / Back / Skip Intro | `Esc` | Opens Pause menu; skips intro cards or moonrise |
| Fullscreen Toggle | `F11` or `Alt+Enter` | Saved to `user://settings.cfg` |
| Mute Audio | `M` | Toggles SFX immediately |
| Debug Collider Overlay | `F8` | Draws solid fence/house/player/enemy colliders |
| Debug Meteor Shower | `F7` | Triggers a 6-meteor shower during gameplay |
