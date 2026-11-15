import { Config } from "./config.js";
import { Assets } from "./assets.js";
import { dist, rectIntersects } from "./world.js";

export function moveWithSlide(entity, dx, dy, halfW, halfH, colliders, bounds) {
  // Move X
  let nx = entity.x + dx;
  nx = Math.max(bounds.x + halfW, Math.min(bounds.x + bounds.w - halfW, nx));
  let boxX = { x: nx - halfW, y: entity.y - halfH * 2, w: halfW * 2, h: halfH * 2 };
  let blockedX = false;
  for (const c of colliders) {
    if (rectIntersects(boxX, c)) {
      blockedX = true;
      break;
    }
  }
  if (!blockedX) entity.x = nx;

  // Move Y
  let ny = entity.y + dy;
  ny = Math.max(bounds.y + halfH * 2, Math.min(bounds.y + bounds.h - 2, ny));
  let boxY = { x: entity.x - halfW, y: ny - halfH * 2, w: halfW * 2, h: halfH * 2 };
  let blockedY = false;
  for (const c of colliders) {
    if (rectIntersects(boxY, c)) {
      blockedY = true;
      break;
    }
  }
  if (!blockedY) entity.y = ny;
}

export class Player {
  constructor() {
    this.reset(Config.HOUSE_DOOR.x, Config.HOUSE_DOOR.y);
  }

  reset(x, y) {
    this.x = x;
    this.y = y;
    this.hp = Config.PLAYER_HP;
    this.maxHp = Config.PLAYER_HP;
    this.speed = Config.PLAYER_SPEED;
    this.facing = "down";
    this.facingVec = { x: 0, y: 1 };
    this.insideHouse = false;
    this.dead = false;
    this.animTime = 0;
    this.moving = false;

    this.activeWeapon = "bow";
    this.ownedWeapons = [...Config.DEFAULT_WEAPONS];
    this.gearTier = 1;
    this.spearDamage = 1;
    this.bowDamage = Config.BOW_DAMAGE;
    this.bowPierce = 0;

    this.swingTimer = 0;
    this.swingCd = 0;
    this.bowCd = 0;
    this.bowMag = Config.BOW_MAG;
    this.bowMagMax = Config.BOW_MAG;
    this.reloading = false;
    this.reloadTimer = 0;
    this.boomerangCd = 0;
    this.boomerangInFlight = false;

    this.invulnTimer = 0;
    this.flashTimer = 0;
    this.insideHealTimer = 0;
    this.recallHealLeft = 0;
    this.recallTickTimer = 0;
  }

  get sortY() {
    return this.y;
  }

  applyGearTier(tier) {
    this.gearTier = tier;
    this.spearDamage = tier >= 2 ? 2 : 1;
    this.bowDamage = tier >= 2 ? 2 : 1;
    this.bowPierce = tier >= 3 ? 1 : 0;
    this.maxHp = Config.PLAYER_HP + (tier - 1) * 10;
    this.hp = Math.min(this.maxHp, this.hp + 10);
  }

  takeDamage(dmg) {
    if (this.dead || this.invulnTimer > 0 || dmg <= 0) return false;
    this.hp = Math.max(0, this.hp - dmg);
    this.invulnTimer = Config.CONTACT_INVULN;
    this.flashTimer = 0.16;
    if (this.hp <= 0) {
      this.dead = true;
    }
    return true;
  }

  heal(amt) {
    if (this.dead || amt <= 0) return;
    this.hp = Math.min(this.maxHp, this.hp + amt);
  }

  startRecallHeal() {
    this.recallHealLeft = Config.RECALL_HEAL_DURATION;
    this.recallTickTimer = 0;
  }

  update(dt, moveVec, colliders, bounds, bag, onReloadDone) {
    this.animTime += dt;
    if (this.invulnTimer > 0) this.invulnTimer = Math.max(0, this.invulnTimer - dt);
    if (this.flashTimer > 0) this.flashTimer = Math.max(0, this.flashTimer - dt);
    if (this.swingTimer > 0) this.swingTimer = Math.max(0, this.swingTimer - dt);
    if (this.swingCd > 0) this.swingCd = Math.max(0, this.swingCd - dt);
    if (this.bowCd > 0) this.bowCd = Math.max(0, this.bowCd - dt);
    if (this.boomerangCd > 0) this.boomerangCd = Math.max(0, this.boomerangCd - dt);

    if (this.dead) return;

    // Reload timer
    if (this.reloading) {
      this.reloadTimer -= dt;
      if (this.reloadTimer <= 0) {
        this.reloading = false;
        const need = this.bowMagMax - this.bowMag;
        const pulled = bag.remove("arrow", need);
        this.bowMag += pulled;
        if (onReloadDone) onReloadDone();
      }
    }

    // Healing inside house or after recall
    if (this.insideHouse) {
      this.insideHealTimer += dt;
      if (this.insideHealTimer >= Config.INSIDE_HEAL_INTERVAL) {
        this.insideHealTimer = 0;
        this.heal(2);
      }
      this.moving = false;
      return;
    }

    if (this.recallHealLeft > 0) {
      this.recallHealLeft = Math.max(0, this.recallHealLeft - dt);
      this.recallTickTimer += dt;
      if (this.recallTickTimer >= Config.RECALL_HEAL_INTERVAL) {
        this.recallTickTimer = 0;
        this.heal(Config.RECALL_HEAL_TICK);
      }
    }

    const len = Math.hypot(moveVec.x, moveVec.y);
    this.moving = len > 0.08;
    if (this.moving) {
      const mag = Math.min(1, len);
      const nx = moveVec.x / len;
      const ny = moveVec.y / len;
      this.facingVec = { x: nx, y: ny };
      if (Math.abs(nx) > Math.abs(ny)) {
        this.facing = nx > 0 ? "right" : "left";
      } else {
        this.facing = ny > 0 ? "down" : "up";
      }
      moveWithSlide(this, nx * this.speed * mag * dt, ny * this.speed * mag * dt, 4, 4, colliders, bounds);
    }
  }

  startReload(bag) {
    if (this.reloading || this.bowMag >= this.bowMagMax || bag.count("arrow") <= 0) return false;
    this.reloading = true;
    this.reloadTimer = Config.BOW_RELOAD;
    return true;
  }

  trySpearSwing() {
    if (this.dead || this.insideHouse || this.swingCd > 0) return null;
    this.swingTimer = Config.SWING_TIME;
    this.swingCd = Config.SWING_COOLDOWN;
    const cx = this.x + this.facingVec.x * Config.SWING_OFFSET;
    const cy = this.y - 6 + this.facingVec.y * Config.SWING_OFFSET;
    return {
      hitbox: {
        x: cx - Config.SWING_BOX.w * 0.5,
        y: cy - Config.SWING_BOX.h * 0.5,
        w: Config.SWING_BOX.w,
        h: Config.SWING_BOX.h,
      },
      dir: { ...this.facingVec },
      damage: this.spearDamage,
    };
  }

  tryFireBow(hostiles, bag) {
    if (this.dead || this.insideHouse || this.bowCd > 0 || this.reloading) return { ok: false, reason: "busy" };
    if (this.bowMag <= 0) {
      if (bag.count("arrow") > 0) {
        this.startReload(bag);
        return { ok: false, reason: "reloading" };
      }
      return { ok: false, reason: "empty" };
    }

    // Auto-aim nearest living hostile within BOW_RANGE
    let best = null;
    let bestD = Config.BOW_RANGE;
    for (const h of hostiles) {
      if (!h.isAlive()) continue;
      const d = dist(this.x, this.y - 6, h.x, h.y - 8);
      if (d <= bestD) {
        bestD = d;
        best = h;
      }
    }
    let dir = { ...this.facingVec };
    if (best) {
      const dx = best.x - this.x;
      const dy = best.y - 8 - (this.y - 6);
      const l = Math.hypot(dx, dy) || 1;
      dir = { x: dx / l, y: dy / l };
      this.facingVec = dir;
      this.facing = Math.abs(dir.x) > Math.abs(dir.y) ? (dir.x > 0 ? "right" : "left") : dir.y > 0 ? "down" : "up";
    }

    this.bowMag--;
    this.bowCd = Config.BOW_FIRE_INTERVAL;
    if (this.bowMag <= 0 && bag.count("arrow") > 0) {
      this.startReload(bag);
    }
    return {
      ok: true,
      origin: { x: this.x, y: this.y - 8 },
      dir,
      damage: this.bowDamage,
      pierce: this.bowPierce,
    };
  }

  tryThrowBoomerang(hostiles) {
    if (this.dead || this.insideHouse || this.boomerangInFlight || this.boomerangCd > 0) return null;
    let best = null;
    let bestD = Config.BOOMERANG_RANGE;
    for (const h of hostiles) {
      if (!h.isAlive()) continue;
      const d = dist(this.x, this.y - 6, h.x, h.y - 8);
      if (d <= bestD) {
        bestD = d;
        best = h;
      }
    }
    let dir = { ...this.facingVec };
    if (best) {
      const dx = best.x - this.x;
      const dy = best.y - 8 - (this.y - 6);
      const l = Math.hypot(dx, dy) || 1;
      dir = { x: dx / l, y: dy / l };
    }
    this.boomerangInFlight = true;
    return { origin: { x: this.x, y: this.y - 8 }, dir, damage: Config.BOOMERANG_DAMAGE + (this.gearTier >= 3 ? 1 : 0) };
  }

  draw(ctx, isNight) {
    if (this.insideHouse) return;
    if (isNight && !this.dead) {
      // Soft warm lantern glow around player at night
      const grad = ctx.createRadialGradient(this.x, this.y - 8, 4, this.x, this.y - 8, 56);
      grad.addColorStop(0, "rgba(255, 214, 140, 0.34)");
      grad.addColorStop(1, "rgba(255, 195, 110, 0)");
      ctx.fillStyle = grad;
      ctx.fillRect(this.x - 58, this.y - 66, 116, 116);
    }

    Assets.drawShadow(ctx, this.x, this.y + 1, 6, 2.5);

    let key = `player/idle_${this.facing}`;
    let frame = this.animTime * 6;
    if (this.dead) {
      key = this.facing === "left" ? "player/death_left" : "player/death_right";
      frame = 5;
    } else if (this.swingTimer > 0) {
      key = `player/punch_${this.facing}`;
      frame = Math.min(3, Math.floor((1 - this.swingTimer / Config.SWING_TIME) * 4));
    } else if (this.moving) {
      key = `player/run_${this.facing}`;
      frame = this.animTime * 9;
    }

    const blink = this.invulnTimer > 0 && Math.floor(this.invulnTimer * 18) % 2 === 0;
    Assets.drawAnimFeet(ctx, key, frame, this.x, this.y, {
      alpha: blink ? 0.5 : 1,
      flash: this.flashTimer > 0,
    });

    // Spear thrust visual during swing
    if (this.swingTimer > 0) {
      const ang = Math.atan2(this.facingVec.y, this.facingVec.x);
      const reach = 14 + Math.sin((1 - this.swingTimer / Config.SWING_TIME) * Math.PI) * 8;
      ctx.save();
      ctx.translate(Math.round(this.x + this.facingVec.x * reach), Math.round(this.y - 7 + this.facingVec.y * reach));
      ctx.rotate(ang);
      ctx.fillStyle = "#9c6d42";
      ctx.fillRect(-10, -1, 14, 2);
      ctx.fillStyle = "#e8eef8";
      ctx.fillRect(4, -2, 6, 4);
      ctx.restore();
    }
  }
}

export class Enemy {
  constructor(type, x, y, isWanderer = false) {
    const info = Config.ENEMY_TYPES[type] || Config.ENEMY_TYPES.zombie;
    this.enemyType = type;
    this.x = Math.round(x);
    this.y = Math.round(y);
    this.hp = info.hits;
    this.maxHp = info.hits;
    this.speed = info.speed;
    this.structDmg = info.structDmg;
    this.attackInterval = info.attackInterval;
    this.playerDmg = info.playerDmg;
    this.aggroRadius = isWanderer ? Config.DAY_WANDERER_AGGRO : info.aggroRadius;
    this.isWanderer = isWanderer;
    this.wanderHome = { x: this.x, y: this.y };
    this.wanderTarget = { x: this.x, y: this.y };
    this.wanderWait = 0.5 + Math.random() * 1.5;

    this.facing = "down";
    this.animTime = Math.random() * 5;
    this.attackCd = 0;
    this.attackAnimTimer = 0;
    this.stunTimer = 0;
    this.rootTimer = 0;
    this.flashTimer = 0;
    this.dead = false;
    this.deathTimer = 0;
    this.removeMe = false;
    this.aggroTimer = 0;
  }

  get sortY() {
    return this.y;
  }

  isAlive() {
    return !this.dead && this.hp > 0;
  }

  getHurtbox() {
    return { x: this.x - 8, y: this.y - 18, w: 16, h: 18 };
  }

  applyStun(sec) {
    if (!this.isAlive()) return;
    this.stunTimer = Math.max(this.stunTimer, sec);
  }

  applyRoot(sec) {
    if (!this.isAlive()) return;
    this.rootTimer = Math.max(this.rootTimer, sec);
  }

  takeHit(dmg, pushDir, fromBow = false) {
    if (!this.isAlive()) return { hit: false, killed: false };
    this.hp = Math.max(0, this.hp - Math.max(1, dmg));
    this.flashTimer = 0.14;
    if (pushDir && (pushDir.x !== 0 || pushDir.y !== 0)) {
      const k = fromBow ? 6 : Config.KNOCKBACK;
      this.x += pushDir.x * k;
      this.y += pushDir.y * k;
    }
    if (this.hp <= 0) {
      this.dead = true;
      this.deathTimer = 0.55;
      return { hit: true, killed: true, fromBow };
    }
    return { hit: true, killed: false, fromBow };
  }

  update(dt, ctx) {
    this.animTime += dt;
    if (this.flashTimer > 0) this.flashTimer = Math.max(0, this.flashTimer - dt);
    if (this.attackCd > 0) this.attackCd = Math.max(0, this.attackCd - dt);
    if (this.attackAnimTimer > 0) this.attackAnimTimer = Math.max(0, this.attackAnimTimer - dt);

    if (this.dead) {
      this.deathTimer -= dt;
      if (this.deathTimer <= 0) this.removeMe = true;
      return;
    }

    if (this.stunTimer > 0) {
      this.stunTimer = Math.max(0, this.stunTimer - dt);
      return;
    }

    const { player, house, fences, traps, watchtowers, enemies, colliders, bounds, onStructDmg, onPlayerDmg, onEnteredHouse } = ctx;

    // Pick target: active decoy lure -> nearby player -> blocking fence -> house
    let targetX = house.x;
    let targetY = house.y + 18;
    let targetObj = house;
    let targetKind = "house";

    // Check decoy lures
    for (const tr of traps) {
      if (tr.trapType === "trap_lure" && tr.isActive()) {
        if (dist(this.x, this.y, tr.x, tr.y) <= (tr.attractRadius || 150)) {
          targetX = tr.x;
          targetY = tr.y;
          targetObj = tr;
          targetKind = "lure";
          break;
        }
      }
    }

    // Check player aggro
    if (targetKind === "house" && !player.dead && !player.insideHouse) {
      const dp = dist(this.x, this.y, player.x, player.y);
      if (dp <= this.aggroRadius) {
        this.aggroTimer = Config.ENEMY_LEASH_TIME;
      }
      if (this.aggroTimer > 0 && dp <= Config.ENEMY_LEASH_RADIUS) {
        this.aggroTimer -= dt;
        targetX = player.x;
        targetY = player.y;
        targetObj = player;
        targetKind = "player";
      }
    }

    // Daytime wanderer idling when not aggroed
    if (this.isWanderer && targetKind === "house") {
      this.wanderWait -= dt;
      if (dist(this.x, this.y, this.wanderTarget.x, this.wanderTarget.y) < 8 || this.wanderWait <= 0) {
        const ang = Math.random() * Math.PI * 2;
        const r = 24 + Math.random() * 68;
        this.wanderTarget = {
          x: Math.max(bounds.x + 24, Math.min(bounds.x + bounds.w - 24, this.wanderHome.x + Math.cos(ang) * r)),
          y: Math.max(bounds.y + 24, Math.min(bounds.y + bounds.h - 24, this.wanderHome.y + Math.sin(ang) * r)),
        };
        this.wanderWait = 2.5 + Math.random() * 3.0;
      }
      targetX = this.wanderTarget.x;
      targetY = this.wanderTarget.y;
      targetKind = "wander";
    }

    // Check if close to an intact fence segment or watchtower along the way
    if (targetKind === "house") {
      let nearFence = null;
      let bestFd = 26;
      for (const f of fences) {
        if (!f.isSolid()) continue;
        const fx = Math.max(f.footprint.x, Math.min(f.footprint.x + f.w, this.x));
        const fy = Math.max(f.footprint.y, Math.min(f.footprint.y + f.h, this.y));
        const d = dist(this.x, this.y, fx, fy);
        if (d < bestFd) {
          bestFd = d;
          nearFence = f;
        }
      }
      if (nearFence) {
        targetObj = nearFence;
        targetKind = "fence";
      } else {
        for (const wt of watchtowers) {
          if (wt.isStanding() && dist(this.x, this.y, wt.x, wt.y) < 26) {
            targetObj = wt;
            targetKind = "watchtower";
            break;
          }
        }
      }
    }

    // Attacks
    if (targetKind === "player" && dist(this.x, this.y, player.x, player.y) <= 16) {
      if (this.attackCd <= 0) {
        this.attackCd = 1.0;
        this.attackAnimTimer = 0.35;
        onPlayerDmg(this.playerDmg, this);
      }
      return;
    }

    if (targetKind === "lure" && dist(this.x, this.y, targetObj.x, targetObj.y) <= 20) {
      if (this.attackCd <= 0) {
        this.attackCd = this.attackInterval;
        this.attackAnimTimer = 0.35;
        targetObj.takeLureDamage(this.structDmg);
      }
      return;
    }

    if (targetKind === "fence") {
      if (this.attackCd <= 0) {
        this.attackCd = this.attackInterval;
        this.attackAnimTimer = 0.35;
        onStructDmg(targetObj, this.structDmg, this);
      }
      return;
    }

    if (targetKind === "watchtower") {
      if (this.attackCd <= 0) {
        this.attackCd = this.attackInterval;
        this.attackAnimTimer = 0.35;
        targetObj.takeDamage(this.structDmg);
      }
      return;
    }

    if (targetKind === "house") {
      // Check open door intrusion
      if (!house.isFallen && house.doorOpen && dist(this.x, this.y, Config.HOUSE_DOOR.x, Config.HOUSE_DOOR.y) < 22) {
        this.removeMe = true;
        this.dead = true;
        onEnteredHouse(this);
        return;
      }
      if (!house.isFallen) {
        const hx = Math.max(house.footprint.x, Math.min(house.footprint.x + house.w, this.x));
        const hy = Math.max(house.footprint.y, Math.min(house.footprint.y + house.h, this.y));
        if (dist(this.x, this.y, hx, hy) <= 18) {
          if (this.attackCd <= 0) {
            this.attackCd = this.attackInterval;
            this.attackAnimTimer = 0.35;
            onStructDmg(house, this.structDmg, this);
          }
          return;
        }
      } else if (!player.dead) {
        // House crumbled -> hunt player
        targetX = player.x;
        targetY = player.y;
      }
    }

    if (this.rootTimer > 0) {
      this.rootTimer = Math.max(0, this.rootTimer - dt);
      return;
    }

    // Move toward target + light crowd separation
    let dx = targetX - this.x;
    let dy = targetY - this.y;
    const d = Math.hypot(dx, dy) || 1;
    dx /= d;
    dy /= d;

    for (const other of enemies) {
      if (other === this || !other.isAlive()) continue;
      const ox = this.x - other.x;
      const oy = this.y - other.y;
      const od = Math.hypot(ox, oy);
      if (od > 0.1 && od < Config.ENEMY_SEPARATION_RADIUS) {
        dx += (ox / od) * 0.6;
        dy += (oy / od) * 0.6;
      }
    }
    const nl = Math.hypot(dx, dy) || 1;
    dx /= nl;
    dy /= nl;

    this.facing = Math.abs(dx) > Math.abs(dy) ? (dx > 0 ? "right" : "left") : dy > 0 ? "down" : "up";
    const spd = targetKind === "wander" ? this.speed * 0.55 : this.speed;
    moveWithSlide(this, dx * spd * dt, dy * spd * dt, 5, 5, colliders, bounds);
  }

  draw(ctx) {
    Assets.drawShadow(ctx, this.x, this.y + 1, 6, 2.4);

    let key = `enemies/${this.enemyType}/walk_${this.facing}`;
    let frame = this.animTime * 7;
    if (this.dead) {
      key = `enemies/${this.enemyType}/death_${this.facing === "left" ? "left" : "right"}`;
      frame = Math.min(5, Math.floor((1 - this.deathTimer / 0.55) * 6));
    } else if (this.attackAnimTimer > 0) {
      key = `enemies/${this.enemyType}/attack_${this.facing}`;
      frame = this.animTime * 11;
    }

    Assets.drawAnimFeet(ctx, key, frame, this.x, this.y, { flash: this.flashTimer > 0 });

    if (this.stunTimer > 0 && !this.dead) {
      ctx.fillStyle = "#88f0ff";
      ctx.fillRect(Math.round(this.x - 4), Math.round(this.y - 22), 8, 2);
    } else if (this.rootTimer > 0 && !this.dead) {
      ctx.fillStyle = "#ffd95e";
      ctx.fillRect(Math.round(this.x - 5), Math.round(this.y - 2), 10, 2);
    }

    if (!this.dead && this.hp < this.maxHp) {
      const bx = Math.round(this.x - 7);
      const by = Math.round(this.y - 21);
      ctx.fillStyle = "rgba(12, 8, 18, 0.9)";
      ctx.fillRect(bx, by, 14, 3);
      ctx.fillStyle = "#f24c48";
      ctx.fillRect(bx + 1, by + 1, Math.max(1, Math.round(12 * (this.hp / this.maxHp))), 1);
    }
  }
}

export class Ghost {
  constructor(x, y, variant = "scythe") {
    this.variant = variant === "lunge" ? "lunge" : "scythe";
    this.x = Math.round(x);
    this.y = Math.round(y);
    this.hp = Config.GHOST_HP;
    this.maxHp = Config.GHOST_HP;
    this.speed = this.variant === "lunge" ? Config.GHOST_SPEED_LUNGE : Config.GHOST_SPEED_SCYTHE;
    this.life = Config.GHOST_LIFETIME;
    this.animTime = 0;
    this.dmgCd = 0;
    this.stunTimer = 0;
    this.flashTimer = 0;
    this.facingRight = false;
    this.dead = false;
    this.removeMe = false;
  }

  get sortY() {
    return this.y + 4;
  }

  isAlive() {
    return !this.dead && this.hp > 0;
  }

  getHurtbox() {
    return { x: this.x - 10, y: this.y - 22, w: 20, h: 22 };
  }

  applyStun(sec) {
    this.stunTimer = Math.max(this.stunTimer, Math.min(2.5, sec));
  }

  takeHit(dmg, pushDir, fromBow = false) {
    if (!this.isAlive()) return { hit: false, killed: false };
    this.hp = Math.max(0, this.hp - Math.max(1, dmg));
    this.flashTimer = 0.14;
    if (pushDir) {
      this.x += pushDir.x * 8;
      this.y += pushDir.y * 8;
    }
    if (this.hp <= 0) {
      this.dead = true;
      this.removeMe = true;
      return { hit: true, killed: true, fromBow };
    }
    return { hit: true, killed: false, fromBow };
  }

  update(dt, player, onPlayerDmg) {
    this.animTime += dt;
    this.life -= dt;
    if (this.life <= 0) {
      this.dead = true;
      this.removeMe = true;
      return;
    }
    if (this.flashTimer > 0) this.flashTimer = Math.max(0, this.flashTimer - dt);
    if (this.dmgCd > 0) this.dmgCd = Math.max(0, this.dmgCd - dt);
    if (this.stunTimer > 0) {
      this.stunTimer = Math.max(0, this.stunTimer - dt);
      return;
    }
    if (player.dead || player.insideHouse) return;

    const dx = player.x - this.x;
    const dy = player.y - this.y;
    const d = Math.hypot(dx, dy) || 1;
    this.facingRight = dx > 0;
    if (d > 18) {
      this.x += (dx / d) * this.speed * dt;
      this.y += (dy / d) * this.speed * dt;
    } else if (this.dmgCd <= 0) {
      this.dmgCd = Config.GHOST_DAMAGE_COOLDOWN;
      onPlayerDmg(Config.GHOST_DAMAGE, this);
    }
  }

  draw(ctx) {
    const bob = Math.sin(this.animTime * 4) * 2.5;
    Assets.drawShadow(ctx, this.x, this.y + 2, 7, 2.5, "rgba(70, 240, 210, 0.32)");
    const key = this.variant === "lunge" ? "enemies/ghost/ghost_lunge_strip" : "enemies/ghost/ghost_scythe_strip";
    Assets.drawAnimFeet(ctx, key, this.animTime * 8, this.x, this.y + bob, {
      scale: 0.55,
      flipX: this.facingRight,
      alpha: Math.min(0.92, this.life / 1.5),
      flash: this.flashTimer > 0,
    });
    if (this.hp < this.maxHp) {
      ctx.fillStyle = "rgba(12, 8, 18, 0.88)";
      ctx.fillRect(Math.round(this.x - 7), Math.round(this.y - 24), 14, 3);
      ctx.fillStyle = "#6bf5d1";
      ctx.fillRect(Math.round(this.x - 6), Math.round(this.y - 23), Math.max(1, Math.round(12 * (this.hp / this.maxHp))), 1);
    }
  }
}

export class Dog {
  constructor(x, y, allowTame = false) {
    this.x = Math.round(x);
    this.y = Math.round(y);
    this.mode = "stray"; // "stray" | "follow" | "guard"
    this.isTameable = allowTame;
    this.guardAnchor = { x: this.x, y: this.y };
    this.hp = Config.DOG_HP;
    this.maxHp = Config.DOG_HP;
    this.facing = "right";
    this.animTime = Math.random() * 4;
    this.moving = false;
    this.attackCd = 0;
    this.flashTimer = 0;
    this.wanderTarget = { x: this.x, y: this.y };
    this.wanderWait = 1.2;
    this.removeMe = false;
  }

  get sortY() {
    return this.y;
  }

  isTamed() {
    return this.mode !== "stray";
  }

  canBeTamed() {
    return this.mode === "stray" && this.isTameable && this.hp > 0;
  }

  tameNow() {
    if (!this.canBeTamed()) return false;
    this.mode = "follow";
    this.hp = this.maxHp;
    return true;
  }

  toggleFollowGuard(px, py) {
    if (!this.isTamed()) return;
    if (this.mode === "follow") {
      this.mode = "guard";
      this.guardAnchor = { x: px, y: py };
    } else {
      this.mode = "follow";
    }
  }

  update(dt, player, hostiles, colliders, bounds, onBite, onDied) {
    this.animTime += dt;
    if (this.attackCd > 0) this.attackCd = Math.max(0, this.attackCd - dt);
    if (this.flashTimer > 0) this.flashTimer = Math.max(0, this.flashTimer - dt);
    if (this.hp <= 0) {
      this.removeMe = true;
      return;
    }

    if (this.mode === "stray") {
      this.wanderWait -= dt;
      if (dist(this.x, this.y, this.wanderTarget.x, this.wanderTarget.y) < 8 || this.wanderWait <= 0) {
        const ang = Math.random() * Math.PI * 2;
        const r = 30 + Math.random() * 80;
        this.wanderTarget = {
          x: Math.max(bounds.x + 28, Math.min(bounds.x + bounds.w - 28, this.x + Math.cos(ang) * r)),
          y: Math.max(bounds.y + 28, Math.min(bounds.y + bounds.h - 28, this.y + Math.sin(ang) * r)),
        };
        this.wanderWait = 2.0 + Math.random() * 2.5;
      }
      const dx = this.wanderTarget.x - this.x;
      const dy = this.wanderTarget.y - this.y;
      const d = Math.hypot(dx, dy);
      this.moving = d > 6;
      if (this.moving) {
        this.facing = dx >= 0 ? "right" : "left";
        moveWithSlide(this, (dx / d) * 34 * dt, (dy / d) * 34 * dt, 4, 3, colliders, bounds);
      }
      return;
    }

    // Tamed: hunt nearby hostile within anchor range
    const anchor = this.mode === "guard" ? this.guardAnchor : player;
    const huntRange = this.mode === "guard" ? Config.DOG_GUARD_RANGE : Config.DOG_HUNT_RANGE;
    let target = null;
    let bestD = huntRange;
    for (const h of hostiles) {
      if (!h.isAlive()) continue;
      const d = dist(anchor.x, anchor.y, h.x, h.y);
      if (d <= bestD) {
        bestD = d;
        target = h;
      }
    }

    if (target) {
      const dx = target.x - this.x;
      const dy = target.y - this.y;
      const d = Math.hypot(dx, dy) || 1;
      this.facing = dx >= 0 ? "right" : "left";
      if (d <= 15) {
        this.moving = false;
        if (this.attackCd <= 0) {
          this.attackCd = Config.DOG_ATTACK_INTERVAL;
          onBite(target, this);
          // Enemy counter-scratches dog occasionally
          if (Math.random() < 0.35) {
            this.hp = Math.max(0, this.hp - Config.DOG_ENEMY_DMG);
            this.flashTimer = 0.14;
            if (this.hp <= 0) {
              this.removeMe = true;
              onDied(this);
            }
          }
        }
      } else {
        this.moving = true;
        moveWithSlide(this, (dx / d) * Config.DOG_SPEED_CHASE * dt, (dy / d) * Config.DOG_SPEED_CHASE * dt, 4, 3, colliders, bounds);
      }
      return;
    }

    // Return near player / guard anchor
    const dx = anchor.x - this.x;
    const dy = anchor.y - this.y;
    const d = Math.hypot(dx, dy);
    this.moving = d > 24;
    if (this.moving) {
      this.facing = dx >= 0 ? "right" : "left";
      const spd = d > 80 ? 78 : Config.DOG_SPEED_FOLLOW;
      moveWithSlide(this, (dx / d) * spd * dt, (dy / d) * spd * dt, 4, 3, colliders, bounds);
    }
  }

  draw(ctx) {
    Assets.drawShadow(ctx, this.x, this.y + 1, 6, 2.5);
    const key = `dog/${this.moving ? "run" : "idle"}_${this.facing}`;
    Assets.drawDogFeet(ctx, key, this.animTime * (this.moving ? 9 : 6), this.x, this.y, 0.5, this.flashTimer > 0);
    if (this.isTamed() && this.hp < this.maxHp) {
      ctx.fillStyle = "rgba(12, 8, 18, 0.85)";
      ctx.fillRect(Math.round(this.x - 7), Math.round(this.y - 20), 14, 3);
      ctx.fillStyle = "#6ce673";
      ctx.fillRect(Math.round(this.x - 6), Math.round(this.y - 19), Math.max(1, Math.round(12 * (this.hp / this.maxHp))), 1);
    }
  }
}

export class Trap {
  constructor(kind, x, y) {
    const info = Config.TRAPS[kind] || Config.TRAPS.trap_spike;
    this.trapType = kind;
    this.x = Math.round(x);
    this.y = Math.round(y);
    this.radius = info.radius || 14;
    this.triggersLeft = info.maxTriggers || 1;
    this.hp = info.hp || 30;
    this.maxHp = this.hp;
    this.attractRadius = info.attractRadius || 0;
    this.cooldown = 0;
    this.pulseTime = 0;
    this.springAnim = 0;
    this.removeMe = false;
  }

  get sortY() {
    return this.y - 4;
  }

  isActive() {
    if (this.removeMe) return false;
    return this.trapType === "trap_lure" ? this.hp > 0 : this.triggersLeft > 0;
  }

  takeLureDamage(dmg) {
    if (this.trapType !== "trap_lure" || this.hp <= 0) return;
    this.hp = Math.max(0, this.hp - dmg);
    if (this.hp <= 0) this.removeMe = true;
  }

  update(dt, enemies, onTriggered) {
    if (!this.isActive()) return;
    this.pulseTime += dt;
    if (this.springAnim > 0) this.springAnim = Math.max(0, this.springAnim - dt);
    if (this.trapType === "trap_lure") return;
    if (this.cooldown > 0) {
      this.cooldown = Math.max(0, this.cooldown - dt);
      return;
    }

    const info = Config.TRAPS[this.trapType];
    for (const e of enemies) {
      if (!e.isAlive()) continue;
      if (dist(this.x, this.y, e.x, e.y) <= this.radius) {
        if (this.trapType === "trap_spike") {
          e.takeHit(info.damage, { x: 0, y: 0 }, false);
          this.cooldown = info.cooldown || 0.7;
        } else if (this.trapType === "trap_snare") {
          e.takeHit(info.damage, { x: 0, y: 0 }, false);
          e.applyRoot(info.rootTime || 2.6);
        }
        this.triggersLeft--;
        this.springAnim = 0.35;
        onTriggered(this, e);
        if (this.triggersLeft <= 0) {
          this.removeMe = true;
        }
        return;
      }
    }
  }

  draw(ctx) {
    Assets.drawShadow(ctx, this.x, this.y + 3, 8, 3);
    if (this.trapType === "trap_lure") {
      // Pulse attraction ring
      const r = 14 + ((this.pulseTime * 34) % 32);
      const a = Math.max(0, 1 - (r - 14) / 32) * 0.45;
      ctx.strokeStyle = `rgba(255, 214, 86, ${a.toFixed(2)})`;
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.arc(Math.round(this.x), Math.round(this.y - 4), r, 0, Math.PI * 2);
      ctx.stroke();

      Assets.drawStaticFeet(ctx, "fences/wood/post", this.x, this.y + 2);
      Assets.drawAnimFeet(ctx, "traps/lure_fire", this.pulseTime * 9, this.x, this.y - 10);
      if (this.hp < this.maxHp) {
        ctx.fillStyle = "rgba(10, 8, 16, 0.85)";
        ctx.fillRect(Math.round(this.x - 9), Math.round(this.y - 25), 18, 3);
        ctx.fillStyle = "#f25c48";
        ctx.fillRect(Math.round(this.x - 8), Math.round(this.y - 24), Math.max(1, Math.round(16 * (this.hp / this.maxHp))), 1);
      }
    } else if (this.trapType === "trap_spike") {
      const f = this.springAnim > 0 ? 9 : 3;
      Assets.drawAnimFeet(ctx, "traps/spike_sheet", f, this.x, this.y + 10, { scale: 0.72 });
    } else {
      const f = this.springAnim > 0 ? 2 : 0;
      Assets.drawAnimFeet(ctx, "traps/snare_sheet", f, this.x, this.y + 10, { scale: 0.72 });
    }
  }
}

export class Arrow {
  constructor(x, y, dir, dmg, maxRange, pierce = 0, fromPlayer = true) {
    this.x = x;
    this.y = y;
    const l = Math.hypot(dir.x, dir.y) || 1;
    this.vx = (dir.x / l) * Config.ARROW_SPEED;
    this.vy = (dir.y / l) * Config.ARROW_SPEED;
    this.angle = Math.atan2(this.vy, this.vx);
    this.damage = dmg;
    this.rangeLeft = maxRange;
    this.pierceLeft = pierce;
    this.fromPlayer = fromPlayer;
    this.hitSet = new Set();
    this.removeMe = false;
  }

  update(dt, hostiles, bounds, onHit) {
    const sx = this.vx * dt;
    const sy = this.vy * dt;
    this.x += sx;
    this.y += sy;
    this.rangeLeft -= Math.hypot(sx, sy);
    if (
      this.rangeLeft <= 0 ||
      this.x < bounds.x ||
      this.y < bounds.y ||
      this.x > bounds.x + bounds.w ||
      this.y > bounds.y + bounds.h
    ) {
      this.removeMe = true;
      return;
    }

    for (const h of hostiles) {
      if (!h.isAlive() || this.hitSet.has(h)) continue;
      const box = h.getHurtbox();
      if (
        this.x >= box.x - 3 &&
        this.x <= box.x + box.w + 3 &&
        this.y >= box.y - 3 &&
        this.y <= box.y + box.h + 3
      ) {
        this.hitSet.add(h);
        onHit(h, this);
        if (this.pierceLeft > 0) {
          this.pierceLeft--;
        } else {
          this.removeMe = true;
          return;
        }
      }
    }
  }

  draw(ctx) {
    const key = this.pierceLeft > 0 ? "weapons/arrow_pierce" : "weapons/arrow";
    const img = Assets.get(key);
    ctx.save();
    ctx.translate(Math.round(this.x), Math.round(this.y));
    ctx.rotate(this.angle);
    if (img) {
      ctx.drawImage(img, -Math.round(img.width * 0.5), -Math.round(img.height * 0.5));
    } else {
      ctx.fillStyle = "#ffe6a0";
      ctx.fillRect(-5, -1, 10, 2);
    }
    ctx.restore();
  }
}

export class Boomerang {
  constructor(owner, x, y, dir, dmg) {
    this.owner = owner;
    this.x = x;
    this.y = y;
    const l = Math.hypot(dir.x, dir.y) || 1;
    this.vx = (dir.x / l) * Config.BOOMERANG_SPEED;
    this.vy = (dir.y / l) * Config.BOOMERANG_SPEED;
    this.damage = dmg;
    this.rangeLeft = Config.BOOMERANG_RANGE;
    this.leg = "out";
    this.spin = 0;
    this.hitOut = new Set();
    this.hitBack = new Set();
    this.removeMe = false;
  }

  update(dt, hostiles, bounds, onHit, onCaught) {
    this.spin += Config.BOOMERANG_SPIN_SPEED * dt;
    if (this.leg === "out") {
      const sx = this.vx * dt;
      const sy = this.vy * dt;
      this.x += sx;
      this.y += sy;
      this.rangeLeft -= Math.hypot(sx, sy);

      for (const h of hostiles) {
        if (!h.isAlive() || this.hitOut.has(h)) continue;
        if (dist(this.x, this.y, h.x, h.y - 8) <= Config.BOOMERANG_HIT_RADIUS + 4) {
          this.hitOut.add(h);
          onHit(h, this, false);
          this.leg = "return";
          break;
        }
      }

      if (
        this.rangeLeft <= 0 ||
        this.x < bounds.x + 8 ||
        this.y < bounds.y + 8 ||
        this.x > bounds.x + bounds.w - 8 ||
        this.y > bounds.y + bounds.h - 8
      ) {
        this.leg = "return";
      }
    } else {
      const tx = this.owner.x;
      const ty = this.owner.y - 8;
      const dx = tx - this.x;
      const dy = ty - this.y;
      const d = Math.hypot(dx, dy);
      if (d <= 14) {
        this.removeMe = true;
        onCaught(this);
        return;
      }
      this.x += (dx / d) * Config.BOOMERANG_RETURN_SPEED * dt;
      this.y += (dy / d) * Config.BOOMERANG_RETURN_SPEED * dt;

      for (const h of hostiles) {
        if (!h.isAlive() || this.hitBack.has(h)) continue;
        if (dist(this.x, this.y, h.x, h.y - 8) <= Config.BOOMERANG_HIT_RADIUS + 4) {
          this.hitBack.add(h);
          onHit(h, this, true);
        }
      }
    }
  }

  draw(ctx) {
    Assets.drawShadow(ctx, this.x, this.y + 7, 5, 2);
    const img = Assets.get("placeholders/boomerang_placeholder");
    ctx.save();
    ctx.translate(Math.round(this.x), Math.round(this.y));
    ctx.rotate(this.spin);
    if (img) {
      const sz = Math.round(img.width * 0.72);
      ctx.drawImage(img, -Math.round(sz * 0.5), -Math.round(sz * 0.5), sz, sz);
    } else {
      ctx.strokeStyle = "#f2c66d";
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.arc(0, 0, 7, 0, Math.PI * 1.1);
      ctx.stroke();
    }
    ctx.restore();
  }
}

export class Watchtower {
  constructor(x, y) {
    this.x = Math.round(x);
    this.y = Math.round(y);
    this.hp = Config.WATCHTOWER_HP;
    this.maxHp = Config.WATCHTOWER_HP;
    this.fireTimer = 0.4;
    this.removeMe = false;
  }

  get sortY() {
    return this.y;
  }

  isStanding() {
    return this.hp > 0 && !this.removeMe;
  }

  takeDamage(dmg) {
    this.hp = Math.max(0, this.hp - dmg);
    if (this.hp <= 0) this.removeMe = true;
  }

  update(dt, hostiles, onFire) {
    if (!this.isStanding()) return;
    this.fireTimer -= dt;
    if (this.fireTimer > 0) return;

    let best = null;
    let bestD = Config.WATCHTOWER_RANGE;
    for (const h of hostiles) {
      if (!h.isAlive()) continue;
      const d = dist(this.x, this.y - 20, h.x, h.y - 8);
      if (d <= bestD) {
        bestD = d;
        best = h;
      }
    }
    if (best) {
      this.fireTimer = Config.WATCHTOWER_FIRE_INTERVAL;
      onFire({ x: this.x, y: this.y - 22 }, best);
    }
  }

  draw(ctx) {
    Assets.drawShadow(ctx, this.x, this.y + 2, 10, 4);
    ctx.save();
    ctx.translate(Math.round(this.x), Math.round(this.y));
    // Timber tower legs + platform
    ctx.fillStyle = "#5c3d24";
    ctx.fillRect(-7, -26, 3, 26);
    ctx.fillRect(4, -26, 3, 26);
    ctx.fillStyle = "#7a5232";
    ctx.fillRect(-10, -32, 20, 8);
    ctx.fillStyle = "#a37044";
    ctx.fillRect(-11, -34, 22, 3);
    ctx.restore();

    if (this.hp < this.maxHp) {
      ctx.fillStyle = "rgba(12, 8, 18, 0.88)";
      ctx.fillRect(Math.round(this.x - 10), Math.round(this.y - 39), 20, 3);
      ctx.fillStyle = "#6ce07a";
      ctx.fillRect(Math.round(this.x - 9), Math.round(this.y - 38), Math.max(1, Math.round(18 * (this.hp / this.maxHp))), 1);
    }
  }
}

export class FxSystem {
  constructor() {
    this.sparks = [];
    this.rings = [];
    this.texts = [];
    this.trapPreview = null;
  }

  clear() {
    this.sparks = [];
    this.rings = [];
    this.texts = [];
    this.trapPreview = null;
  }

  spawnSparks(x, y, color, count = 6) {
    for (let i = 0; i < count; i++) {
      const ang = Math.random() * Math.PI * 2;
      const spd = 24 + Math.random() * 58;
      this.sparks.push({
        x,
        y,
        vx: Math.cos(ang) * spd,
        vy: Math.sin(ang) * spd - 12,
        life: 0.25 + Math.random() * 0.2,
        maxLife: 0.45,
        color,
      });
    }
  }

  spawnRing(x, y, maxRadius, color) {
    this.rings.push({ x, y, r: 6, maxR: maxRadius, life: 0.34, maxLife: 0.34, color });
  }

  spawnText(x, y, text, color = "#ffffff") {
    this.texts.push({ x, y: y - 10, text, color, life: 1.05, maxLife: 1.05 });
  }

  update(dt) {
    for (let i = this.sparks.length - 1; i >= 0; i--) {
      const s = this.sparks[i];
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.life -= dt;
      if (s.life <= 0) this.sparks.splice(i, 1);
    }
    for (let i = this.rings.length - 1; i >= 0; i--) {
      const r = this.rings[i];
      r.life -= dt;
      r.r = r.maxR * (1 - r.life / r.maxLife);
      if (r.life <= 0) this.rings.splice(i, 1);
    }
    for (let i = this.texts.length - 1; i >= 0; i--) {
      const t = this.texts[i];
      t.y -= 18 * dt;
      t.life -= dt;
      if (t.life <= 0) this.texts.splice(i, 1);
    }
  }

  draw(ctx) {
    if (this.trapPreview) {
      const p = this.trapPreview;
      ctx.save();
      ctx.strokeStyle = p.ok ? "rgba(110, 255, 140, 0.9)" : "rgba(255, 90, 90, 0.9)";
      ctx.fillStyle = p.ok ? "rgba(90, 240, 120, 0.18)" : "rgba(255, 80, 80, 0.18)";
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.arc(Math.round(p.x), Math.round(p.y), p.radius, 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();
      if (p.attractRadius > 0) {
        ctx.setLineDash([4, 4]);
        ctx.strokeStyle = "rgba(255, 224, 110, 0.4)";
        ctx.beginPath();
        ctx.arc(Math.round(p.x), Math.round(p.y), p.attractRadius, 0, Math.PI * 2);
        ctx.stroke();
      }
      ctx.restore();
    }

    for (const r of this.rings) {
      ctx.save();
      ctx.globalAlpha = Math.max(0, r.life / r.maxLife);
      ctx.strokeStyle = r.color;
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc(Math.round(r.x), Math.round(r.y), r.r, 0, Math.PI * 2);
      ctx.stroke();
      ctx.restore();
    }

    for (const s of this.sparks) {
      ctx.save();
      ctx.globalAlpha = Math.max(0, s.life / s.maxLife);
      ctx.fillStyle = s.color;
      ctx.fillRect(Math.round(s.x - 1), Math.round(s.y - 1), 2, 2);
      ctx.restore();
    }

    ctx.save();
    ctx.font = 'bold 8px "PixelOp", monospace';
    ctx.textAlign = "center";
    for (const t of this.texts) {
      ctx.globalAlpha = Math.max(0, Math.min(1, t.life / 0.35));
      ctx.fillStyle = "#08060e";
      ctx.fillText(t.text, Math.round(t.x + 1), Math.round(t.y + 1));
      ctx.fillStyle = t.color;
      ctx.fillText(t.text, Math.round(t.x), Math.round(t.y));
    }
    ctx.restore();
  }
}

export class MoonSkyRenderer {
  constructor() {
    this.time = 0;
    this.stars = [];
    let s = 4207;
    const rng = () => {
      s = (s * 1664525 + 1013904223) >>> 0;
      return s / 4294967296;
    };
    for (let i = 0; i < 52; i++) {
      this.stars.push({
        x: Math.floor(8 + rng() * 624),
        y: Math.floor(6 + rng() * 230),
        sz: rng() < 0.28 ? 2 : 1,
        phase: rng() * Math.PI * 2,
        spd: 1.2 + rng() * 2.0,
      });
    }
    this.trees = [];
    for (let i = 0; i < 24; i++) {
      this.trees.push({
        x: i * 28 + (rng() * 14 - 7),
        h: 28 + rng() * 44,
        w: 16 + rng() * 14,
      });
    }
  }

  draw(ctx, dt, opts = {}) {
    this.time += dt;
    const w = 640;
    const h = 360;
    const redBlend = opts.redBlend ?? 0.9;
    const moonProgress = opts.moonProgress ?? 0.94;
    const isEven = Boolean(opts.isEven);

    // 3-band pixel sky
    ctx.fillStyle = `rgb(${Math.round(10 + redBlend * 22)}, ${Math.round(10 + (1 - redBlend) * 4)}, ${Math.round(28 - redBlend * 10)})`;
    ctx.fillRect(0, 0, w, Math.round(h * 0.45));
    ctx.fillStyle = `rgb(${Math.round(20 + redBlend * 36)}, ${Math.round(15 + (1 - redBlend) * 4)}, ${Math.round(40 - redBlend * 16)})`;
    ctx.fillRect(0, Math.round(h * 0.45), w, Math.round(h * 0.3));
    ctx.fillStyle = `rgb(${Math.round(32 + redBlend * 44)}, ${Math.round(22)}, ${Math.round(46 - redBlend * 18)})`;
    ctx.fillRect(0, Math.round(h * 0.75), w, Math.round(h * 0.25));

    // Twinkling stars
    for (const st of this.stars) {
      const a = 0.35 + 0.55 * (0.5 + 0.5 * Math.sin(this.time * st.spd + st.phase));
      ctx.fillStyle = `rgba(235, 240, 255, ${a.toFixed(2)})`;
      ctx.fillRect(st.x, st.y, st.sz, st.sz);
    }

    // Moon rising
    const moonX = w * 0.5;
    const moonY = h * 0.85 - moonProgress * (h * 0.52);
    const glowGrad = ctx.createRadialGradient(moonX, moonY, 18, moonX, moonY, 118);
    if (isEven) {
      glowGrad.addColorStop(0, "rgba(210, 48, 108, 0.45)");
      glowGrad.addColorStop(1, "rgba(180, 30, 90, 0)");
    } else {
      glowGrad.addColorStop(0, `rgba(${Math.round(220 + redBlend * 35)}, ${Math.round(210 * (1 - redBlend) + 46)}, ${Math.round(200 * (1 - redBlend) + 42)}, 0.44)`);
      glowGrad.addColorStop(1, "rgba(220, 30, 30, 0)");
    }
    ctx.fillStyle = glowGrad;
    ctx.fillRect(moonX - 120, moonY - 120, 240, 240);

    const moonBase = Assets.get("sky/moon");
    const moonRed = Assets.get("sky/blood_moon");
    if (moonBase) {
      ctx.save();
      ctx.drawImage(moonBase, Math.round(moonX - 56), Math.round(moonY - 56), 112, 112);
      if (redBlend > 0.01 && moonRed) {
        ctx.globalAlpha = Math.max(0, Math.min(1, redBlend));
        ctx.drawImage(moonRed, Math.round(moonX - 56), Math.round(moonY - 56), 112, 112);
      }
      ctx.restore();
    }

    // Drifting clouds
    const c1 = Assets.get("sky/clouds_1");
    if (c1) {
      const off = (this.time * 9) % w;
      ctx.save();
      ctx.globalAlpha = 0.28;
      ctx.drawImage(c1, Math.round(-off), 54);
      ctx.drawImage(c1, Math.round(w - off), 54);
      ctx.restore();
    }

    // Horizon silhouette: ground, trees, hilltop farmhouse
    ctx.fillStyle = "#0b0812";
    ctx.fillRect(0, h - 54, w, 54);
    for (const tr of this.trees) {
      if (Math.abs(tr.x - w * 0.5) < 58) continue;
      ctx.beginPath();
      ctx.moveTo(tr.x, h - 54 - tr.h);
      ctx.lineTo(tr.x - tr.w * 0.5, h - 52);
      ctx.lineTo(tr.x + tr.w * 0.5, h - 52);
      ctx.closePath();
      ctx.fill();
    }
    // Farmhouse silhouette
    ctx.fillRect(w * 0.5 - 32, h - 84, 64, 32);
    ctx.beginPath();
    ctx.moveTo(w * 0.5 - 38, h - 84);
    ctx.lineTo(w * 0.5, h - 108);
    ctx.lineTo(w * 0.5 + 38, h - 84);
    ctx.closePath();
    ctx.fill();
    // Lit amber windows
    ctx.fillStyle = "#ffcb66";
    ctx.fillRect(w * 0.5 - 18, h - 74, 8, 8);
    ctx.fillRect(w * 0.5 + 10, h - 74, 8, 8);
  }
}
