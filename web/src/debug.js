import { Config } from "./config.js";

export class DebugController {
  constructor() {
    this.hudEl = document.getElementById("debug-hud");
    this.touchCanvas = document.getElementById("debug-touch-overlay");

    this.showHud = false;
    this.showHitboxes = false;
    this.showRanges = false;
    this.showTouchZones = false;

    this.frameTimes = [];
    this.maxSamples = 60;
    this.fps = 60;
    this.avgMs = 16.6;
    this.maxMs = 16.6;
    this.hudUpdateAccum = 0;
  }

  setHudVisible(visible) {
    this.showHud = Boolean(visible);
    if (this.hudEl) this.hudEl.classList.toggle("hidden", !this.showHud);
  }

  setTouchOverlayVisible(visible) {
    this.showTouchZones = Boolean(visible);
    if (this.touchCanvas) {
      this.touchCanvas.classList.toggle("hidden", !this.showTouchZones);
    }
  }

  recordFrame(dtSec) {
    const ms = Math.max(0.1, dtSec * 1000);
    this.frameTimes.push(ms);
    if (this.frameTimes.length > this.maxSamples) this.frameTimes.shift();

    let sum = 0;
    let peak = 0;
    for (let i = 0; i < this.frameTimes.length; i++) {
      const v = this.frameTimes[i];
      sum += v;
      if (v > peak) peak = v;
    }
    this.avgMs = sum / Math.max(1, this.frameTimes.length);
    this.maxMs = peak;
    this.fps = Math.round(1000 / Math.max(1, this.avgMs));
  }

  updateTelemetry(dt, game) {
    if (!this.showHud || !this.hudEl) return;
    this.hudUpdateAccum += dt;
    if (this.hudUpdateAccum < 0.08) return;
    this.hudUpdateAccum = 0;

    const inp = game.input.getDebugState();
    const mv = game.input.getMoveVector();
    const mag = Math.hypot(mv.x, mv.y);
    const heldTags = [];
    if (inp.attackHeld) heldTags.push("ATK");
    if (inp.spearHeld) heldTags.push("SPR");
    if (inp.interactHeld) heldTags.push("ACT");
    if (inp.attackBuffer > 0) heldTags.push("BUF-A");
    if (inp.spearBuffer > 0) heldTags.push("BUF-S");

    const flags = [];
    if (game.player.godMode) flags.push("GOD");
    if (this.showHitboxes) flags.push("BOX");
    if (this.showRanges) flags.push("RNG");
    if (this.showTouchZones) flags.push("TCH");

    const lines = [
      `FPS:${String(this.fps).padStart(3, " ")} (${this.avgMs.toFixed(1)}ms max ${this.maxMs.toFixed(1)})  ${game.state.toUpperCase()} A${game.act} D${game.day}${flags.length ? ` [${flags.join(",")}]` : ""}`,
      `POS:(${Math.round(game.player.x)},${Math.round(game.player.y)}) FACE:${game.player.facing} MV:(${mv.x.toFixed(2)},${mv.y.toFixed(2)}) |${mag.toFixed(2)}|`,
      `JOY:${inp.joyMode.toUpperCase()} dz:${Math.round(inp.joyDeadzone * 100)}% ptr:${inp.pointers.length} held:${heldTags.join("+") || "-"}`,
      `ENT: E:${game.enemies.length} G:${game.ghosts.length} D:${game.dogs.length} T:${game.traps.length} ARR:${game.arrows.length} WT:${game.watchtowers.length}`,
    ];
    this.hudEl.textContent = lines.join("\n");
  }

  drawWorldOverlay(ctx, game) {
    if (!this.showHitboxes && !this.showRanges) return;
    const p = game.player;

    ctx.save();
    ctx.lineWidth = 1;

    if (this.showRanges && !p.insideHouse) {
      // Weapon range ring
      const wRange =
        p.activeWeapon === "bow"
          ? Config.BOW_RANGE
          : p.activeWeapon === "boomerang"
            ? Config.BOOMERANG_RANGE
            : Config.SWING_OFFSET + 16;
      ctx.strokeStyle = "rgba(120, 245, 255, 0.35)";
      ctx.beginPath();
      ctx.arc(p.x, p.y - 6, wRange, 0, Math.PI * 2);
      ctx.stroke();

      // Door & upgrade reach circles
      ctx.strokeStyle = "rgba(110, 255, 145, 0.4)";
      ctx.beginPath();
      ctx.arc(Config.HOUSE_DOOR.x, Config.HOUSE_DOOR.y, Config.DOOR_INTERACT_REACH, 0, Math.PI * 2);
      ctx.stroke();

      // Traps trigger & attract radii
      for (const tr of game.traps) {
        const info = Config.TRAPS[tr.trapType];
        ctx.strokeStyle = "rgba(255, 224, 96, 0.55)";
        ctx.beginPath();
        ctx.arc(tr.x, tr.y, info.radius, 0, Math.PI * 2);
        ctx.stroke();
        if (info.attractRadius) {
          ctx.strokeStyle = "rgba(255, 130, 80, 0.35)";
          ctx.beginPath();
          ctx.arc(tr.x, tr.y, info.attractRadius, 0, Math.PI * 2);
          ctx.stroke();
        }
      }

      // Watchtower fire ranges
      for (const wt of game.watchtowers) {
        ctx.strokeStyle = "rgba(180, 140, 255, 0.35)";
        ctx.beginPath();
        ctx.arc(wt.x, wt.y, Config.WATCHTOWER_RANGE, 0, Math.PI * 2);
        ctx.stroke();
      }
    }

    if (this.showHitboxes) {
      // Solid structure colliders
      ctx.strokeStyle = "rgba(255, 152, 64, 0.7)";
      for (const c of game.world.getSolidColliders()) {
        ctx.strokeRect(c.x, c.y, c.w, c.h);
      }

      // Player body box + facing ray
      if (!p.insideHouse) {
        ctx.strokeStyle = "#52f4ff";
        ctx.strokeRect(p.x - 4, p.y - 8, 8, 8);
        ctx.beginPath();
        ctx.moveTo(p.x, p.y - 6);
        ctx.lineTo(p.x + p.facingVec.x * 20, p.y - 6 + p.facingVec.y * 20);
        ctx.stroke();

        // Active spear swing box
        if (p.swingTimer > 0 && p.lastSwingBox) {
          const b = p.lastSwingBox;
          ctx.strokeStyle = "#ffe64c";
          ctx.strokeRect(b.x, b.y, b.w, b.h);
        }

        // Auto-aim ray
        if (game.save.autoAim) {
          const range = p.activeWeapon === "boomerang" ? Config.BOOMERANG_RANGE : Config.BOW_RANGE;
          const target = p.findAimTarget(game.getAllHostiles(), range);
          if (target) {
            ctx.strokeStyle = "rgba(130, 255, 120, 0.85)";
            ctx.beginPath();
            ctx.moveTo(p.x, p.y - 8);
            ctx.lineTo(target.x, target.y - 8);
            ctx.stroke();
          }
        }
      }

      // Enemy & Ghost hurtboxes
      ctx.strokeStyle = "#ff4e4e";
      for (const e of game.enemies) {
        if (!e.isAlive()) continue;
        const hb = e.getHurtbox();
        ctx.strokeRect(hb.x, hb.y, hb.w, hb.h);
      }
      ctx.strokeStyle = "#ff68f0";
      for (const g of game.ghosts) {
        if (!g.isAlive()) continue;
        const hb = g.getHurtbox();
        ctx.strokeRect(hb.x, hb.y, hb.w, hb.h);
      }
    }

    ctx.restore();
  }

  drawTouchOverlay(input) {
    if (!this.showTouchZones || !this.touchCanvas) return;
    const w = window.innerWidth;
    const h = window.innerHeight;
    if (this.touchCanvas.width !== w || this.touchCanvas.height !== h) {
      this.touchCanvas.width = w;
      this.touchCanvas.height = h;
    }
    const ctx = this.touchCanvas.getContext("2d");
    ctx.clearRect(0, 0, w, h);

    const dbg = input.getDebugState();
    const zr = dbg.joyZoneRect;

    ctx.save();
    // Highlight joystick touch capture region
    ctx.strokeStyle = "rgba(110, 240, 180, 0.55)";
    ctx.fillStyle = "rgba(110, 240, 180, 0.08)";
    ctx.lineWidth = 1.5;
    ctx.fillRect(zr.left, zr.top, zr.width, zr.height);
    ctx.strokeRect(zr.left, zr.top, zr.width, zr.height);

    // Deadzone + max-radius rings when joystick active
    if (dbg.joyActive) {
      const ox = dbg.joyOrigin.x;
      const oy = dbg.joyOrigin.y;
      const maxR = dbg.joyMaxRadius;
      const dzR = maxR * dbg.joyDeadzone;

      ctx.strokeStyle = "rgba(255, 224, 96, 0.8)";
      ctx.beginPath();
      ctx.arc(ox, oy, maxR, 0, Math.PI * 2);
      ctx.stroke();

      ctx.strokeStyle = "rgba(255, 92, 92, 0.85)";
      ctx.beginPath();
      ctx.arc(ox, oy, dzR, 0, Math.PI * 2);
      ctx.stroke();

      ctx.strokeStyle = "#62ff9e";
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(ox, oy);
      ctx.lineTo(ox + dbg.joyVec.x * maxR, oy + dbg.joyVec.y * maxR);
      ctx.stroke();
    }

    // Active pointer crosshairs
    ctx.font = "11px monospace";
    for (const pt of dbg.pointers) {
      ctx.strokeStyle = pt.role === "joy" ? "#72f5a8" : "#ffcf66";
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.arc(pt.x, pt.y, 16, 0, Math.PI * 2);
      ctx.stroke();
      ctx.fillStyle = "#ffffff";
      ctx.fillText(`#${pt.id}:${pt.role}`, pt.x + 18, pt.y - 6);
    }

    ctx.restore();
  }
}
