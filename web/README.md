# Moonrise — HTML5 Mobile & Web Edition

Standalone HTML5 Canvas + Web Audio API port of **Moonrise**, kept completely isolated from the Godot project in `../RedMoon/`.

## Features
- **Zero build step & zero external dependencies** — pure ES Modules, HTML5 Canvas, and procedural Web Audio API sound effects.
- **Self-contained assets** — `web/assets/` holds all sprites and pixel fonts (`KiwiSoda`, `PixelOperator8`), so this `web/` directory can be hosted directly on GitHub Pages, Netlify, Vercel, Cloudflare Pages, or zipped for itch.io HTML5.
- **Mobile-first multi-touch controls** — dynamic follow-thumb/floating/fixed virtual joystick (`PointerEvent` with `setPointerCapture` + `lostpointercapture` safety), hold-to-attack + 120ms input buffering, quick 1-tap weapon `SWAP`, zero-latency instant `ACT` for doors/gates/taming and hold-to-gather for chopping/searching, dedicated combat cluster (`FIRE`/`THROW`, `SPEAR`, `RLD`, `SHOCK`, `HOME`), contextual buttons (`Upgrade / Repair`, `Tame Dog`, `Follow / Guard`, `Place Trap`), bottom trap hotbar, haptic feedback, safe-area inset support, and auto-pause when switching apps.
- **Built-in Debug & Control Tuning (`DBG` button or `F3`)** — live FPS/frame-time/input telemetry HUD, toggleable world hitboxes & range rings, touch-zone & active-pointer visualizer, persisted joystick mode/deadzone/button-scale/opacity/auto-aim/hold-to-attack tuning, and quick sandbox test actions.
- **Full desktop keyboard + mouse support** — both touch and keyboard/mouse controls work seamlessly; you can force touch controls ON/OFF/AUTO in Settings.

## Running Locally
Serve the `web/` directory over HTTP (ES modules require HTTP, not `file://`):

```bash
cd web
python3 -m http.server 8080
```

Then open `http://localhost:8080` in a desktop or mobile browser.
