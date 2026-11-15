# Moonrise — HTML5 Mobile & Web Edition

Standalone HTML5 Canvas + Web Audio API port of **Moonrise**, kept completely isolated from the Godot project in `../RedMoon/`.

## Features
- **Zero build step & zero external dependencies** — pure ES Modules, HTML5 Canvas, and procedural Web Audio API sound effects.
- **Self-contained assets** — `web/assets/` holds all sprites and pixel fonts (`KiwiSoda`, `PixelOperator8`), so this `web/` directory can be hosted directly on GitHub Pages, Netlify, Vercel, Cloudflare Pages, or zipped for itch.io HTML5.
- **Mobile-first multi-touch controls** — floating virtual joystick (`PointerEvent` with `setPointerCapture`), dedicated right-hand combat/action pad (`FIRE`/`THROW`, `SPEAR`, tap/hold `ACT` for doors/gates/chopping/searching, `RLD`, `SHOCK`, `HOME`), contextual buttons (`Upgrade / Repair`, `Tame Dog`, `Follow / Guard`, `Place Trap`), bottom trap hotbar, safe-area inset support, and auto-pause when switching apps.
- **Full desktop keyboard + mouse support** — both touch and keyboard/mouse controls work seamlessly; you can force touch controls ON/OFF/AUTO in Settings.

## Running Locally
Serve the `web/` directory over HTTP (ES modules require HTTP, not `file://`):

```bash
cd web
python3 -m http.server 8080
```

Then open `http://localhost:8080` in a desktop or mobile browser.
