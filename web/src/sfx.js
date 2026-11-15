// Procedural 8-bit Web Audio synth matching RedMoon/scripts/sfx.gd

class SfxEngine {
  constructor() {
    this.ctx = null;
    this.masterGain = null;
    this.muted = false;
    this.volume = 0.85;
    this.buffers = new Map();
    this.built = false;
  }

  unlock() {
    if (!this.ctx) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return;
      this.ctx = new AC();
      this.masterGain = this.ctx.createGain();
      this.masterGain.connect(this.ctx.destination);
      this._applyGain();
    }
    if (this.ctx.state === "suspended") {
      this.ctx.resume().catch(() => {});
    }
    if (!this.built && this.ctx) {
      this._buildAll();
      this.built = true;
    }
  }

  setVolume(vol) {
    this.volume = Math.max(0, Math.min(1, vol));
    this._applyGain();
  }

  toggleMute() {
    this.muted = !this.muted;
    this._applyGain();
    return this.muted;
  }

  _applyGain() {
    if (!this.masterGain) return;
    this.masterGain.gain.value = this.muted ? 0 : this.volume * 0.55;
  }

  play(name, gainScale = 0.5) {
    if (this.muted) return;
    if (!this.ctx) this.unlock();
    if (!this.ctx || !this.built) return;
    if (this.ctx.state === "suspended") {
      this.ctx.resume().catch(() => {});
    }
    const buf = this.buffers.get(name);
    if (!buf) return;
    const src = this.ctx.createBufferSource();
    src.buffer = buf;
    const g = this.ctx.createGain();
    g.gain.value = gainScale;
    src.connect(g);
    g.connect(this.masterGain);
    src.start();
  }

  _makeBuffer(duration, fn) {
    const rate = 22050;
    const len = Math.max(1, Math.floor(duration * rate));
    const buf = this.ctx.createBuffer(1, len, rate);
    const data = buf.getChannelData(0);
    let phase = 0;
    for (let i = 0; i < len; i++) {
      const t = i / len;
      const out = fn(i, t, rate, phase);
      data[i] = Math.max(-1, Math.min(1, out.sample));
      phase = out.phase;
    }
    return buf;
  }

  _sweep(dur, f0, f1, noiseMix, amp) {
    return this._makeBuffer(dur, (_i, t, rate, phase) => {
      const freq = f0 + (f1 - f0) * t;
      const nextPhase = phase + (Math.PI * 2 * freq) / rate;
      const tone = Math.sin(nextPhase) >= 0 ? 1 : -1;
      const noise = Math.random() * 2 - 1;
      const env = 1 - t;
      return { sample: (tone * (1 - noiseMix) + noise * noiseMix) * env * amp, phase: nextPhase };
    });
  }

  _notes(freqs, noteDur, amp) {
    const total = freqs.length * noteDur;
    return this._makeBuffer(total, (_i, t, rate, phase) => {
      const idx = Math.min(freqs.length - 1, Math.floor(t * freqs.length));
      const localT = t * freqs.length - idx;
      const nextPhase = phase + (Math.PI * 2 * freqs[idx]) / rate;
      const env = Math.max(0, 1 - localT * 0.85);
      const tone = Math.sin(nextPhase) >= 0 ? 1 : -1;
      return { sample: tone * env * amp, phase: nextPhase };
    });
  }

  _buildAll() {
    this.buffers.set("swing", this._sweep(0.085, 420, 160, 0.25, 0.35));
    this.buffers.set("hit", this._sweep(0.11, 200, 62, 0.55, 0.42));
    this.buffers.set("struct_hit", this._sweep(0.16, 130, 46, 0.65, 0.48));
    this.buffers.set("player_hit", this._sweep(0.15, 340, 120, 0.25, 0.45));
    this.buffers.set("pickup", this._notes([523, 784], 0.055, 0.38));
    this.buffers.set("dropoff", this._notes([330, 440, 587], 0.055, 0.36));
    this.buffers.set("bounce", this._sweep(0.32, 180, 620, 0.2, 0.45));
    this.buffers.set("blood_moon", this._sweep(0.72, 110, 42, 0.45, 0.5));
    this.buffers.set("fence_rebuilt", this._notes([392, 523, 659, 784], 0.05, 0.38));
    this.buffers.set("ui_blip", this._sweep(0.05, 290, 210, 0.0, 0.26));
    this.buffers.set("bow_shoot", this._sweep(0.075, 760, 290, 0.2, 0.32));
    this.buffers.set("bow_empty", this._sweep(0.05, 180, 140, 0.1, 0.26));
    this.buffers.set("bow_reload", this._notes([294, 392, 494], 0.05, 0.3));
    this.buffers.set("door_creak", this._sweep(0.22, 160, 240, 0.35, 0.32));
    this.buffers.set("crumble", this._sweep(0.85, 120, 34, 0.72, 0.52));
    this.buffers.set("toast", this._notes([523, 659, 784, 1046], 0.065, 0.34));
    this.buffers.set("upgrade", this._notes([440, 554, 659], 0.055, 0.38));
    this.buffers.set("trap_trigger", this._sweep(0.12, 540, 120, 0.5, 0.4));
    this.buffers.set("dog_bark", this._notes([480, 620], 0.06, 0.34));
    this.buffers.set("ghost_appear", this._sweep(0.42, 680, 220, 0.42, 0.24));
    this.buffers.set("ghost_slash", this._sweep(0.14, 520, 140, 0.38, 0.3));
    this.buffers.set("boomerang_throw", this._sweep(0.16, 360, 740, 0.18, 0.3));
    this.buffers.set("boomerang_catch", this._notes([520, 680], 0.045, 0.28));
    this.buffers.set("wood_chop", this._sweep(0.12, 220, 95, 0.46, 0.34));
  }
}

export const Sfx = new SfxEngine();
