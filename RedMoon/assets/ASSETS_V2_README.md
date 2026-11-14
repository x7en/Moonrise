# Red Moon: Assets v2 (add-on pack)

Install: put this zip in the repo and extract it INTO the `RedMoon/` folder so `assets/` merges with the existing one
(`unzip -o RedMoon_Assets_v2.zip -d RedMoon/`). Nothing existing is overwritten.

## moon/  (all 32x32 transparent PNGs, use nearest filtering)
- `moon_00.png`        original gray moon disc (18x17 px, sits at 7,7 in the 32x32 canvas). The main moon.
- `moon_01.png` .. `moon_03.png`  smaller discs (about 11 px, 10 px, 6 px). Optional: use 03 -> 02 -> 01 -> 00 as a "growing" sprite swap while the moon rises, or ignore.
- `moon_00_white.png`  brightened pale-white version for NORMAL nights.
- `moon_00_red.png` .. `moon_03_red.png`  Blood Moon versions (gray ramp mapped to a red ramp, craters and shading kept).
- `lunar_04.png` .. `lunar_09.png`  gray moon-SURFACE ground tiles (full tile + eroded edge variants). NOT for the sky. Optional: meteor crater patches.
- There is NO cloud art: clouds are generated in code.

## fonts/  (three fonts chosen from the owner's set; extra Pixel Operator variants intentionally left out)
- `PixelOperator8.ttf`       body font: HUD labels, counters, objective line, menus, story narration. Sizes: multiples of 8 only (8, 16, 24).
- `PixelOperator8-Bold.ttf`  emphasis: banner headlines, "Day N", numbers, button labels. Sizes: 8, 16, 24.
- `KiwiSoda.ttf`             display font: game title, Blood Moon and story-card headings, moonrise captions. Sizes: 16, 32. Not for long text.
Licenses: Pixel Operator by Jayvee Enaguas (HarvettFox96) is CC0. KiwiSoda has NO license text inside the file: the owner must verify its license before any public or commercial release. Credit both in CREDITS.txt.

## animals/  (dogs: textures to be chosen by the owner later)
The dog system is built in code but stays OFF until these files exist. Horizontal strips, 16 px art scale like the rest of the game.
File names: `dog_<anim>_<dir>-Sheet<N>.png` where `<anim>` is `idle` or `run` (optional: `sit`, `hurt`, `bark`), `<dir>` is `down`, `up`, `left`, `right` (if only `right` is supplied, mirror it for `left`; `side` is also accepted), and `<N>` is the frame count (frame width = image width / N). If no `-Sheet<N>` suffix, frames are square.
