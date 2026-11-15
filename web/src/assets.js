import { SPRITE_ANIM, SPRITE_STATIC_KEYS } from "./config.js";

class AssetStore {
  constructor() {
    this.images = new Map();
    this.loadedCount = 0;
    this.totalCount = 0;
  }

  async loadAll(onProgress) {
    const keys = [...Object.keys(SPRITE_ANIM), ...SPRITE_STATIC_KEYS];
    const unique = [...new Set(keys)];
    this.totalCount = unique.length;
    this.loadedCount = 0;

    await Promise.all(
      unique.map(
        (key) =>
          new Promise((resolve) => {
            const img = new Image();
            img.decoding = "async";
            img.onload = () => {
              this.images.set(key, img);
              this.loadedCount++;
              if (onProgress) onProgress(this.loadedCount, this.totalCount);
              resolve();
            };
            img.onerror = () => {
              this.loadedCount++;
              if (onProgress) onProgress(this.loadedCount, this.totalCount);
              resolve();
            };
            img.src = `./assets/${key}.png`;
          })
      )
    );
  }

  get(key) {
    return this.images.get(key) || null;
  }

  /**
   * Draw one frame from a horizontal strip anchored at feet (bottom-center).
   */
  drawAnimFeet(ctx, key, frameIdx, x, y, opts = {}) {
    const img = this.get(key);
    if (!img) return;
    const meta = SPRITE_ANIM[key];
    let frames = 1;
    let fw = img.width;
    let fh = img.height;
    if (meta) {
      frames = meta[0];
      fw = Math.floor(img.width / frames);
      fh = img.height;
    }
    const idx = ((Math.floor(frameIdx) % frames) + frames) % frames;
    const scale = opts.scale ?? 1;
    const dw = fw * scale;
    const dh = fh * scale;
    const ox = opts.ox ?? -dw * 0.5;
    const oy = opts.oy ?? -dh + 1;

    ctx.save();
    if (opts.alpha !== undefined) ctx.globalAlpha = opts.alpha;
    ctx.translate(Math.round(x), Math.round(y));
    if (opts.flipX) ctx.scale(-1, 1);
    ctx.drawImage(img, idx * fw, 0, fw, fh, Math.round(ox), Math.round(oy), Math.round(dw), Math.round(dh));
    if (opts.flash) {
      ctx.globalCompositeOperation = "source-atop";
      ctx.fillStyle = "rgba(255,255,255,0.65)";
      ctx.fillRect(Math.round(ox), Math.round(oy), Math.round(dw), Math.round(dh));
    }
    ctx.restore();
  }

  /**
   * Draw a square-framed dog strip (width / height frames) scaled to match 16px pixel characters.
   */
  drawDogFeet(ctx, key, frameIdx, x, y, scale = 0.5, flash = false) {
    const img = this.get(key);
    if (!img) return;
    const fh = Math.max(1, img.height);
    const frames = Math.max(1, Math.round(img.width / fh));
    const fw = Math.floor(img.width / frames);
    const idx = ((Math.floor(frameIdx) % frames) + frames) % frames;
    const dw = fw * scale;
    const dh = fh * scale;
    ctx.save();
    ctx.translate(Math.round(x), Math.round(y));
    ctx.drawImage(img, idx * fw, 0, fw, fh, Math.round(-dw * 0.5), Math.round(-dh + 4), Math.round(dw), Math.round(dh));
    if (flash) {
      ctx.fillStyle = "rgba(255,255,255,0.45)";
      ctx.fillRect(Math.round(-dw * 0.35), Math.round(-dh + 6), Math.round(dw * 0.7), Math.round(dh * 0.7));
    }
    ctx.restore();
  }

  drawStaticFeet(ctx, key, x, y, opts = {}) {
    const img = this.get(key);
    if (!img) return;
    const scale = opts.scale ?? 1;
    const dw = img.width * scale;
    const dh = img.height * scale;
    const ox = opts.ox ?? -dw * 0.5;
    const oy = opts.oy ?? -dh;
    ctx.save();
    if (opts.alpha !== undefined) ctx.globalAlpha = opts.alpha;
    ctx.translate(Math.round(x), Math.round(y));
    if (opts.rot) ctx.rotate(opts.rot);
    ctx.drawImage(img, Math.round(ox), Math.round(oy), Math.round(dw), Math.round(dh));
    ctx.restore();
  }

  drawShadow(ctx, x, y, rx = 6, ry = 2.6, color = "rgba(6, 5, 12, 0.38)") {
    ctx.save();
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.ellipse(Math.round(x), Math.round(y), rx, ry, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }
}

export const Assets = new AssetStore();
