import { Config } from "./config.js";
import { Assets } from "./assets.js";

// Deterministic seeded PRNG (Mulberry32)
export function makeRng(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export class Bag {
  constructor(capacity = -1) {
    this.capacity = capacity;
    this.items = {};
  }

  clear() {
    this.items = {};
  }

  count(item) {
    return this.items[item] || 0;
  }

  totalUsed() {
    let n = 0;
    for (const k of ["plank", "scrap"]) {
      n += this.items[k] || 0;
    }
    return n;
  }

  freeSpace() {
    if (this.capacity < 0) return 999999;
    return Math.max(0, this.capacity - this.totalUsed());
  }

  add(item, amount) {
    if (amount <= 0) return 0;
    let take = amount;
    if (this.capacity >= 0 && (item === "plank" || item === "scrap")) {
      take = Math.min(amount, this.freeSpace());
    }
    if (item === "arrow" && this.capacity >= 0) {
      take = Math.min(amount, Math.max(0, Config.BOW_RESERVE_MAX - this.count("arrow")));
    }
    if (take <= 0) return 0;
    this.items[item] = (this.items[item] || 0) + take;
    return take;
  }

  remove(item, amount) {
    const have = this.count(item);
    const take = Math.min(have, Math.max(0, amount));
    this.items[item] = have - take;
    return take;
  }

  snapshot() {
    return { ...this.items };
  }

  restore(data) {
    this.items = { ...(data || {}) };
  }
}

export function rectIntersects(a, b) {
  return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
}

export function rectHasPoint(r, px, py) {
  return px >= r.x && px <= r.x + r.w && py >= r.y && py <= r.y + r.h;
}

export function dist(ax, ay, bx, by) {
  return Math.hypot(bx - ax, by - ay);
}

export class Structure {
  constructor(opts) {
    this.kind = opts.kind; // "house" | "fence"
    this.ring = opts.ring || 0;
    this.side = opts.side || "";
    this.isHorizontal = opts.isHorizontal !== false;
    this.isGate = Boolean(opts.isGate);
    this.gateOpen = false;
    this.level = 1;
    this.spiked = false;
    this.isBuilt = opts.isBuilt !== false;
    this.isFallen = false;
    this.doorOpen = false;
    this.hovered = false;
    this.flashTimer = 0;

    this.x = opts.x;
    this.y = opts.y;
    this.w = opts.w;
    this.h = opts.h;
    this.maxHp = this.kind === "house" ? Config.HOUSE_LEVEL_HP[0] : Config.FENCE_LEVEL_HP[0];
    this.hp = this.isBuilt ? this.maxHp : 0;

    this.footprint = { x: this.x - this.w * 0.5, y: this.y - this.h * 0.5, w: this.w, h: this.h };
    this.visualRect =
      this.kind === "house"
        ? { x: this.x - 80, y: this.y - 72, w: 160, h: 120 }
        : { x: this.footprint.x - 4, y: this.footprint.y - 12, w: this.w + 8, h: this.h + 18 };
  }

  get sortY() {
    return this.kind === "house" ? this.y + 34 : this.y + this.h * 0.5;
  }

  isSolid() {
    if (!this.isBuilt || this.isFallen || this.hp <= 0) return false;
    if (this.isGate && this.gateOpen) return false;
    return true;
  }

  getColliderRect() {
    if (!this.isSolid()) return null;
    return this.footprint;
  }

  takeDamage(dmg) {
    if (!this.isBuilt || this.isFallen || this.hp <= 0 || dmg <= 0) return false;
    this.hp = Math.max(0, this.hp - dmg);
    this.flashTimer = 0.14;
    if (this.hp <= 0) {
      if (this.kind === "house") {
        this.isFallen = true;
      } else {
        this.isBuilt = false;
        this.gateOpen = false;
      }
      return true;
    }
    return false;
  }

  repair(amount) {
    if (this.isFallen) return false;
    if (this.kind === "fence" && !this.isBuilt) {
      this.isBuilt = true;
      this.hp = Math.min(this.maxHp, Math.max(12, amount));
      return true;
    }
    if (this.hp >= this.maxHp) return false;
    this.hp = Math.min(this.maxHp, this.hp + amount);
    return true;
  }

  upgradeTo(newLevel) {
    this.level = Math.max(1, Math.min(3, newLevel));
    this.maxHp =
      this.kind === "house"
        ? Config.HOUSE_LEVEL_HP[this.level - 1]
        : Config.FENCE_LEVEL_HP[this.level - 1];
    this.isBuilt = true;
    this.isFallen = false;
    this.hp = this.maxHp;
  }

  draw(ctx, isNight) {
    if (this.kind === "house") {
      this._drawHouse(ctx, isNight);
    } else {
      this._drawFence(ctx);
    }
  }

  _drawHouse(ctx, isNight) {
    if (this.isFallen) {
      ctx.save();
      ctx.fillStyle = "rgba(22, 16, 20, 0.72)";
      ctx.fillRect(Math.round(this.x - 56), Math.round(this.y - 24), 112, 64);
      Assets.drawStaticFeet(ctx, "props/rubble", this.x - 24, this.y + 18, { scale: 1.5 });
      Assets.drawStaticFeet(ctx, "props/rubble", this.x + 22, this.y + 22, { scale: 1.4 });
      Assets.drawStaticFeet(ctx, "props/rubble", this.x, this.y + 4, { scale: 1.6 });
      ctx.restore();
      return;
    }

    // Cast shadow
    ctx.save();
    ctx.fillStyle = "rgba(6, 5, 14, 0.36)";
    ctx.fillRect(Math.round(this.x - 68), Math.round(this.y + 28), 140, 18);
    ctx.restore();

    const key = `house/lv${this.level}${this.doorOpen ? "_open" : ""}`;
    const img = Assets.get(key);
    if (img) {
      ctx.save();
      ctx.drawImage(img, Math.round(this.x - 80), Math.round(this.y - 72));
      if (this.flashTimer > 0) {
        ctx.fillStyle = "rgba(255, 90, 80, 0.35)";
        ctx.fillRect(Math.round(this.x - 66), Math.round(this.y - 54), 132, 92);
      }
      if (isNight) {
        // Warm window glow at night
        const grad = ctx.createRadialGradient(this.x - 28, this.y + 8, 2, this.x - 28, this.y + 8, 34);
        grad.addColorStop(0, "rgba(255, 210, 120, 0.38)");
        grad.addColorStop(1, "rgba(255, 180, 80, 0)");
        ctx.fillStyle = grad;
        ctx.fillRect(this.x - 64, this.y - 26, 72, 68);
      }
      ctx.restore();
    }

    if (this.hovered) {
      ctx.save();
      ctx.strokeStyle = "rgba(255, 224, 118, 0.9)";
      ctx.lineWidth = 1.5;
      ctx.strokeRect(Math.round(this.x - 74), Math.round(this.y - 62), 148, 108);
      ctx.restore();
    }

    // HP bar if damaged
    if (this.hp < this.maxHp) {
      const bx = Math.round(this.x - 32);
      const by = Math.round(this.y - 68);
      ctx.fillStyle = "rgba(12, 8, 18, 0.9)";
      ctx.fillRect(bx, by, 64, 5);
      ctx.fillStyle = "#5ee078";
      ctx.fillRect(bx + 1, by + 1, Math.max(1, Math.round(62 * (this.hp / this.maxHp))), 3);
    }
  }

  _drawFence(ctx) {
    if (!this.isBuilt) {
      // Ghost footprint for unbuilt ring / broken segment
      ctx.save();
      ctx.fillStyle = this.hovered ? "rgba(255, 222, 112, 0.28)" : "rgba(180, 160, 140, 0.14)";
      ctx.fillRect(Math.round(this.footprint.x), Math.round(this.footprint.y), Math.round(this.w), Math.round(this.h));
      ctx.restore();
      return;
    }

    const mat = this.level >= 3 ? "iron" : "wood";
    ctx.save();
    if (this.isGate) {
      const gateKey = `fences/${mat}/gate_h`;
      const img = Assets.get(gateKey);
      if (this.gateOpen) {
        // Open gate swung aside
        ctx.fillStyle = mat === "iron" ? "#546072" : "#744c2e";
        ctx.fillRect(Math.round(this.footprint.x), Math.round(this.footprint.y - 10), 4, 16);
        ctx.fillRect(Math.round(this.footprint.x + this.w - 4), Math.round(this.footprint.y - 10), 4, 16);
        ctx.fillStyle = "rgba(130, 240, 155, 0.25)";
        ctx.fillRect(Math.round(this.footprint.x + 4), Math.round(this.footprint.y), Math.round(this.w - 8), Math.round(this.h));
      } else if (img) {
        const tiles = Math.max(1, Math.round(this.w / 16));
        for (let i = 0; i < tiles; i++) {
          ctx.drawImage(img, Math.round(this.footprint.x + i * 16), Math.round(this.footprint.y - 7));
        }
      }
    } else if (this.isHorizontal) {
      const img = Assets.get(`fences/${mat}/h`);
      const count = Math.max(1, Math.ceil(this.w / 16));
      for (let i = 0; i < count; i++) {
        const dx = Math.round(this.footprint.x + i * 16);
        const clipW = Math.min(16, Math.round(this.footprint.x + this.w - dx));
        if (img && clipW > 0) {
          ctx.drawImage(img, 0, 0, clipW, img.height, dx, Math.round(this.footprint.y - 6), clipW, img.height);
        }
      }
    } else {
      const img = Assets.get(`fences/${mat}/v`);
      const count = Math.max(1, Math.ceil(this.h / 16));
      for (let i = 0; i < count; i++) {
        const dy = Math.round(this.footprint.y + i * 16);
        const clipH = Math.min(16, Math.round(this.footprint.y + this.h - dy));
        if (img && clipH > 0) {
          ctx.drawImage(img, 0, 0, img.width, clipH, Math.round(this.footprint.x), dy - 4, img.width, clipH);
        }
      }
    }

    if (this.level === 2 && !this.isGate) {
      // Subtle iron-band reinforcement highlight for Lv2
      ctx.fillStyle = "rgba(210, 215, 228, 0.38)";
      ctx.fillRect(Math.round(this.footprint.x + 1), Math.round(this.footprint.y), Math.round(this.w - 2), 2);
    }

    if (this.spiked && !this.isGate) {
      ctx.fillStyle = "#d8dce8";
      if (this.isHorizontal) {
        for (let sx = this.footprint.x + 4; sx < this.footprint.x + this.w - 3; sx += 10) {
          ctx.fillRect(Math.round(sx), Math.round(this.footprint.y - 8), 2, 4);
        }
      } else {
        for (let sy = this.footprint.y + 4; sy < this.footprint.y + this.h - 3; sy += 10) {
          ctx.fillRect(Math.round(this.footprint.x - 2), Math.round(sy), 3, 2);
        }
      }
    }

    if (this.flashTimer > 0) {
      ctx.fillStyle = "rgba(255, 80, 70, 0.55)";
      ctx.fillRect(Math.round(this.footprint.x), Math.round(this.footprint.y - 6), Math.round(this.w), Math.round(this.h + 6));
    }

    if (this.hovered) {
      ctx.strokeStyle = "rgba(255, 228, 120, 0.9)";
      ctx.lineWidth = 1;
      ctx.strokeRect(
        Math.round(this.footprint.x - 2),
        Math.round(this.footprint.y - 8),
        Math.round(this.w + 4),
        Math.round(this.h + 10)
      );
    }

    if (this.hp < this.maxHp) {
      const bw = 20;
      const bx = Math.round(this.x - bw * 0.5);
      const by = Math.round(this.footprint.y - 12);
      ctx.fillStyle = "rgba(10, 8, 16, 0.88)";
      ctx.fillRect(bx, by, bw, 3);
      ctx.fillStyle = "#f2b84b";
      ctx.fillRect(bx + 1, by + 1, Math.max(1, Math.round((bw - 2) * (this.hp / this.maxHp))), 1);
    }
    ctx.restore();
  }
}

export class Pile {
  constructor(x, y, amount, tier, itemType = "plank") {
    this.x = Math.round(x);
    this.y = Math.round(y);
    this.amount = Math.max(1, amount);
    this.tier = tier;
    this.itemType = itemType;
    this.pickupRadius = 15;
    this.collected = false;
  }

  get sortY() {
    return this.y;
  }

  draw(ctx) {
    if (this.collected) return;
    Assets.drawShadow(ctx, this.x, this.y + 2, 7, 3);
    if (this.itemType === "scrap") {
      Assets.drawStaticFeet(ctx, "props/metal", this.x, this.y + 2, { scale: 0.6 });
      return;
    }
    if (this.itemType === "arrow") {
      Assets.drawStaticFeet(ctx, "weapons/arrow", this.x, this.y, { scale: 1 });
      return;
    }
    if (this.tier === "single" || this.tier === "near") {
      Assets.drawStaticFeet(ctx, "items/planks_2", this.x, this.y + 2);
    } else if (this.tier === "middle") {
      Assets.drawStaticFeet(ctx, "items/planks_1", this.x, this.y + 3);
    } else {
      Assets.drawStaticFeet(ctx, "items/planks_1", this.x, this.y + 3);
      Assets.drawStaticFeet(ctx, "items/planks_2", this.x, this.y - 3);
    }
  }
}

export class WorldMap {
  constructor(seed) {
    this.seed = seed;
    this.rng = makeRng(seed);
    this.groundCanvas = null;
    this.props = []; // trees, bushes, rocks, searchable wrecks
    this.stumps = [];
    this.house = null;
    this.fences = [];
    this.structures = [];
    this.piles = [];
    this.act1FogVisible = true;
    this._buildGroundCanvas();
    this._buildStructures();
    this._buildProps();
  }

  _buildGroundCanvas() {
    const c = document.createElement("canvas");
    c.width = Config.WORLD_W;
    c.height = Config.WORLD_H;
    const ctx = c.getContext("2d");
    ctx.imageSmoothingEnabled = false;

    const grassImgs = [0, 1, 2, 3].map((i) => Assets.get(`ground/grass_${i}`));
    const dirtImgs = [0, 1, 2, 3].map((i) => Assets.get(`ground/dirt_${i}`));
    const hc = Config.HOUSE_CENTER;

    for (let ty = 0; ty < Config.WORLD_H; ty += 16) {
      for (let tx = 0; tx < Config.WORLD_W; tx += 16) {
        const dx = tx + 8 - hc.x;
        const dy = ty + 8 - hc.y;
        const inYard = Math.abs(dx) < 118 && Math.abs(dy) < 82;
        const onSouthRoad = Math.abs(dx) < 22 && dy >= 52 && dy <= 660;
        const onEastPath = Math.abs(dy - 14) < 16 && dx >= 110 && dx <= 960;
        const isDirt = inYard || onSouthRoad || onEastPath;
        const pool = isDirt ? dirtImgs : grassImgs;
        const idx = Math.floor(this.rng() * pool.length);
        const img = pool[idx];
        if (img) {
          ctx.drawImage(img, tx, ty);
        } else {
          ctx.fillStyle = isDirt ? "#69553c" : "#3a5b37";
          ctx.fillRect(tx, ty, 16, 16);
        }
      }
    }
    this.groundCanvas = c;
  }

  _buildStructures() {
    const hc = Config.HOUSE_CENTER;
    this.house = new Structure({
      kind: "house",
      ring: 0,
      x: hc.x,
      y: hc.y,
      w: 132,
      h: 74,
      isBuilt: true,
    });
    this.structures.push(this.house);

    for (const def of Config.FENCE_RINGS) {
      const { ring, hx, hy, builtAtStart } = def;
      const gw = Config.FENCE_GATE_WIDTH;
      const segs = [
        // North wall (split into 2)
        { x: hc.x - hx * 0.5, y: hc.y - hy, w: hx, h: 8, isHorizontal: true, side: "north" },
        { x: hc.x + hx * 0.5, y: hc.y - hy, w: hx, h: 8, isHorizontal: true, side: "north" },
        // South left & right of gate
        {
          x: hc.x - hx + (hx - gw * 0.5) * 0.5,
          y: hc.y + hy,
          w: hx - gw * 0.5,
          h: 8,
          isHorizontal: true,
          side: "south",
        },
        {
          x: hc.x + gw * 0.5 + (hx - gw * 0.5) * 0.5,
          y: hc.y + hy,
          w: hx - gw * 0.5,
          h: 8,
          isHorizontal: true,
          side: "south",
        },
        // South Gate
        {
          x: hc.x,
          y: hc.y + hy,
          w: gw,
          h: 8,
          isHorizontal: true,
          isGate: true,
          side: "south",
        },
        // West wall
        { x: hc.x - hx, y: hc.y - hy * 0.5, w: 8, h: hy, isHorizontal: false, side: "west" },
        { x: hc.x - hx, y: hc.y + hy * 0.5, w: 8, h: hy, isHorizontal: false, side: "west" },
        // East wall
        { x: hc.x + hx, y: hc.y - hy * 0.5, w: 8, h: hy, isHorizontal: false, side: "east" },
        { x: hc.x + hx, y: hc.y + hy * 0.5, w: 8, h: hy, isHorizontal: false, side: "east" },
      ];

      for (const s of segs) {
        const f = new Structure({
          kind: "fence",
          ring,
          ...s,
          isBuilt: builtAtStart,
        });
        this.fences.push(f);
        this.structures.push(f);
      }
    }
  }

  _buildProps() {
    const hc = Config.HOUSE_CENTER;
    const treeKeys = [
      "nature/oak",
      "nature/tree_1",
      "nature/birch_1",
      "nature/birch_2",
      "nature/spruce_1",
      "nature/spruce_2",
      "nature/pine_big",
    ];
    const wreckKeys = [
      "props/car_red",
      "props/car_blue",
      "props/van_blue",
      "props/truck_scrap",
      "props/dumpster",
      "props/crate_red",
      "props/crate_green",
      "props/barrel_red",
    ];
    let id = 1;

    // Trees across Act 1 + Act 2
    for (let i = 0; i < 155; i++) {
      const px = 48 + this.rng() * (Config.WORLD_W - 96);
      const py = 56 + this.rng() * (Config.WORLD_H - 112);
      if (Math.abs(px - hc.x) < 236 && Math.abs(py - hc.y) < 194) continue;
      if (Math.abs(px - hc.x) < 34 && py > hc.y + 60 && py < hc.y + 520) continue;
      const key = treeKeys[Math.floor(this.rng() * treeKeys.length)];
      this.props.push({
        id: id++,
        kind: "tree",
        key,
        x: Math.round(px),
        y: Math.round(py),
        solid: true,
        collider: { x: Math.round(px) - 7, y: Math.round(py) - 8, w: 14, h: 10 },
        chopped: false,
      });
    }

    // Bushes & rocks (decor)
    for (let i = 0; i < 70; i++) {
      const px = 48 + this.rng() * (Config.WORLD_W - 96);
      const py = 48 + this.rng() * (Config.WORLD_H - 96);
      if (Math.abs(px - hc.x) < 224 && Math.abs(py - hc.y) < 184) continue;
      const keys = ["nature/bush_1", "nature/bush_2", "nature/rock", "nature/tuft"];
      const key = keys[Math.floor(this.rng() * keys.length)];
      this.props.push({
        id: id++,
        kind: "decor",
        key,
        x: Math.round(px),
        y: Math.round(py),
        solid: false,
      });
    }

    // Searchable wrecks (some in Act 1, plenty in Act 2)
    for (let i = 0; i < 30; i++) {
      const inAct1 = i < 7;
      let px, py;
      if (inAct1) {
        const ang = this.rng() * Math.PI * 2;
        const rad = 165 + this.rng() * 195;
        px = Math.max(760, Math.min(1640, hc.x + Math.cos(ang) * rad));
        py = Math.max(440, Math.min(915, hc.y + Math.sin(ang) * rad));
      } else {
        px = 76 + this.rng() * (Config.WORLD_W - 152);
        py = 76 + this.rng() * (Config.WORLD_H - 152);
      }
      if (Math.abs(px - hc.x) < 150 && Math.abs(py - hc.y) < 116) continue;
      const key = wreckKeys[Math.floor(this.rng() * wreckKeys.length)];
      this.props.push({
        id: id++,
        kind: "wreck",
        key,
        x: Math.round(px),
        y: Math.round(py),
        solid: true,
        collider: { x: Math.round(px) - 12, y: Math.round(py) - 10, w: 24, h: 12 },
        searched: false,
        lootPlank: 2 + Math.floor(this.rng() * 3),
        lootScrap: inAct1 ? (this.rng() < 0.45 ? 1 : 0) : 1 + Math.floor(this.rng() * 3),
      });
    }
  }

  spawnDailyPiles(act, day) {
    this.piles = [];
    const hc = Config.HOUSE_CENTER;
    const rng = makeRng(this.seed + day * 977 + act * 131);

    if (act === 1) {
      // Generous Act 1 clearing planks + occasional scrap
      for (let i = 0; i < 14; i++) {
        const ang = (i / 14) * Math.PI * 2 + rng() * 0.4;
        const rad = 138 + rng() * 190;
        const px = Math.max(756, Math.min(1644, hc.x + Math.cos(ang) * rad));
        const py = Math.max(442, Math.min(912, hc.y + Math.sin(ang) * rad));
        const amt = i % 3 === 0 ? 3 : 2;
        this.piles.push(new Pile(px, py, amt, amt >= 3 ? "middle" : "near", "plank"));
      }
      for (let s = 0; s < 3; s++) {
        const ang = rng() * Math.PI * 2;
        const rad = 175 + rng() * 165;
        const px = Math.max(765, Math.min(1635, hc.x + Math.cos(ang) * rad));
        const py = Math.max(445, Math.min(910, hc.y + Math.sin(ang) * rad));
        this.piles.push(new Pile(px, py, 1, "near", "scrap"));
      }
      return;
    }

    // Act 2 full valley piles
    const rings = [
      { count: 10, amt: 2, rMin: 225, rMax: 410, tier: "near" },
      { count: 9, amt: 3, rMin: 430, rMax: 740, tier: "middle" },
      { count: 8, amt: 5, rMin: 760, rMax: 1060, tier: "far" },
    ];
    for (const r of rings) {
      for (let i = 0; i < r.count; i++) {
        const ang = rng() * Math.PI * 2;
        const rad = r.rMin + rng() * (r.rMax - r.rMin);
        const px = Math.max(48, Math.min(Config.WORLD_W - 48, hc.x + Math.cos(ang) * rad));
        const py = Math.max(48, Math.min(Config.WORLD_H - 48, hc.y + Math.sin(ang) * rad));
        this.piles.push(new Pile(px, py, r.amt, r.tier, "plank"));
      }
    }
    for (let s = 0; s < 10; s++) {
      const ang = rng() * Math.PI * 2;
      const rad = 260 + rng() * 720;
      const px = Math.max(54, Math.min(Config.WORLD_W - 54, hc.x + Math.cos(ang) * rad));
      const py = Math.max(54, Math.min(Config.WORLD_H - 54, hc.y + Math.sin(ang) * rad));
      this.piles.push(new Pile(px, py, 2, "middle", "scrap"));
    }
  }

  getSolidColliders() {
    const out = [];
    for (const s of this.structures) {
      const r = s.getColliderRect();
      if (r) out.push(r);
    }
    for (const p of this.props) {
      if (p.solid && !p.chopped && p.collider) {
        out.push(p.collider);
      }
    }
    return out;
  }

  findNearestSearchable(px, py, range = 34) {
    let best = null;
    let bestD = range;
    for (const p of this.props) {
      if (p.kind !== "wreck" || p.searched) continue;
      const d = dist(px, py, p.x, p.y);
      if (d <= bestD) {
        bestD = d;
        best = p;
      }
    }
    return best;
  }

  findNearestTree(px, py, range = 30) {
    let best = null;
    let bestD = range;
    for (const p of this.props) {
      if (p.kind !== "tree" || p.chopped) continue;
      const d = dist(px, py, p.x, p.y);
      if (d <= bestD) {
        bestD = d;
        best = p;
      }
    }
    return best;
  }

  chopTree(tree) {
    tree.chopped = true;
    this.stumps.push({ x: tree.x, y: tree.y });
  }

  openAllGates() {
    for (const f of this.fences) {
      if (f.isBuilt && f.isGate) f.gateOpen = true;
    }
  }

  ringStats() {
    const stats = {};
    for (const r of [1, 2, 3]) {
      stats[r] = { built: false, level: 1, spiked: false, hp: 0, maxHp: 0, repairPlanks: 0 };
    }
    // Pass 1: determine which rings have been unlocked (Ring 1 is always unlocked)
    stats[1].built = true;
    for (const f of this.fences) {
      if (f.isBuilt) {
        stats[f.ring].built = true;
        stats[f.ring].level = Math.max(stats[f.ring].level, f.level);
        stats[f.ring].spiked = stats[f.ring].spiked || f.spiked;
      }
    }
    // Pass 2: sum HP & repair costs across all segments of unlocked rings
    for (const f of this.fences) {
      const d = stats[f.ring];
      if (!d.built) continue;
      if (f.isBuilt) {
        d.hp += f.hp;
        d.maxHp += f.maxHp;
        if (f.hp < f.maxHp) {
          d.repairPlanks += Math.ceil((f.maxHp - f.hp) / Config.PLANK_HEAL);
        }
      } else {
        d.maxHp += f.maxHp;
        d.repairPlanks += Math.ceil(f.maxHp / Config.PLANK_HEAL);
      }
    }
    return stats;
  }

  drawGround(ctx, camX, camY, viewW = Config.VIEW_W, viewH = Config.VIEW_H) {
    if (!this.groundCanvas) return;
    const sw = Math.min(Config.WORLD_W, Math.ceil(viewW) + 2);
    const sh = Math.min(Config.WORLD_H, Math.ceil(viewH) + 2);
    const sx = Math.max(0, Math.min(Config.WORLD_W - sw, Math.floor(camX)));
    const sy = Math.max(0, Math.min(Config.WORLD_H - sh, Math.floor(camY)));
    ctx.drawImage(this.groundCanvas, sx, sy, sw, sh, sx, sy, sw, sh);

    // Draw stumps on ground
    for (const st of this.stumps) {
      ctx.fillStyle = "#5c3f26";
      ctx.fillRect(st.x - 4, st.y - 2, 8, 5);
      ctx.fillStyle = "#9c744c";
      ctx.fillRect(st.x - 3, st.y - 2, 6, 3);
    }
  }

  drawAct1Fog(ctx) {
    if (!this.act1FogVisible) return;
    const r = Config.ACT1_RECT;
    ctx.save();
    ctx.fillStyle = "rgba(10, 9, 18, 0.72)";
    ctx.fillRect(0, 0, Config.WORLD_W, r.y);
    ctx.fillRect(0, r.y + r.h, Config.WORLD_W, Config.WORLD_H - (r.y + r.h));
    ctx.fillRect(0, r.y, r.x, r.h);
    ctx.fillRect(r.x + r.w, r.y, Config.WORLD_W - (r.x + r.w), r.h);
    ctx.strokeStyle = "rgba(180, 120, 145, 0.35)";
    ctx.lineWidth = 2;
    ctx.strokeRect(r.x, r.y, r.w, r.h);
    ctx.restore();
  }
}
