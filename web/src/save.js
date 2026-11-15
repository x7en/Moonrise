import { ACHIEVEMENT_DEFS } from "./config.js";

const SETTINGS_KEY = "moonrise_web_settings_v2";
const LEGACY_SETTINGS_KEY = "moonrise_web_settings_v1";
const ACH_KEY = "moonrise_web_achievements_v1";

export const DEFAULT_CONTROL_SETTINGS = {
  touchMode: "auto", // "auto" | "on" | "off"
  joyMode: "follow", // "follow" | "floating" | "fixed"
  joyDeadzone: 0.12, // 0.06 .. 0.24
  btnScale: 1.0, // 0.85 .. 1.3
  touchOpacity: 0.9, // 0.55 .. 1.0
  holdToAttack: true,
  autoAim: true,
  haptics: true,
};

export class SaveStore {
  constructor() {
    this.introSeen = false;
    this.masterVolume = 0.85;
    this.screenShake = true;
    this.skipCutscenes = false;
    this.debugHud = false;
    Object.assign(this, DEFAULT_CONTROL_SETTINGS);
    this.unlocked = {};
  }

  load() {
    try {
      const raw = localStorage.getItem(SETTINGS_KEY) || localStorage.getItem(LEGACY_SETTINGS_KEY);
      if (raw) {
        const data = JSON.parse(raw);
        this.introSeen = Boolean(data.introSeen);
        this.masterVolume = typeof data.masterVolume === "number" ? data.masterVolume : 0.85;
        this.screenShake = data.screenShake !== false;
        this.skipCutscenes = Boolean(data.skipCutscenes);
        this.debugHud = Boolean(data.debugHud);

        if (["auto", "on", "off"].includes(data.touchMode)) {
          this.touchMode = data.touchMode;
        }
        if (["follow", "floating", "fixed"].includes(data.joyMode)) {
          this.joyMode = data.joyMode;
        }
        if (typeof data.joyDeadzone === "number" && data.joyDeadzone >= 0.04 && data.joyDeadzone <= 0.3) {
          this.joyDeadzone = data.joyDeadzone;
        }
        if (typeof data.btnScale === "number" && data.btnScale >= 0.75 && data.btnScale <= 1.4) {
          this.btnScale = data.btnScale;
        }
        if (typeof data.touchOpacity === "number" && data.touchOpacity >= 0.35 && data.touchOpacity <= 1.0) {
          this.touchOpacity = data.touchOpacity;
        }
        if (typeof data.holdToAttack === "boolean") this.holdToAttack = data.holdToAttack;
        if (typeof data.autoAim === "boolean") this.autoAim = data.autoAim;
        if (typeof data.haptics === "boolean") this.haptics = data.haptics;
      }
      const rawAch = localStorage.getItem(ACH_KEY);
      if (rawAch) {
        this.unlocked = JSON.parse(rawAch) || {};
      }
    } catch {
      // Storage unavailable (private mode); stay in-memory
    }
  }

  resetControlDefaults() {
    Object.assign(this, DEFAULT_CONTROL_SETTINGS);
    this.saveSettings();
  }

  saveSettings() {
    try {
      localStorage.setItem(
        SETTINGS_KEY,
        JSON.stringify({
          introSeen: this.introSeen,
          masterVolume: this.masterVolume,
          screenShake: this.screenShake,
          skipCutscenes: this.skipCutscenes,
          debugHud: this.debugHud,
          touchMode: this.touchMode,
          joyMode: this.joyMode,
          joyDeadzone: this.joyDeadzone,
          btnScale: this.btnScale,
          touchOpacity: this.touchOpacity,
          holdToAttack: this.holdToAttack,
          autoAim: this.autoAim,
          haptics: this.haptics,
        })
      );
    } catch {
      // Ignore quota errors
    }
  }

  markIntroSeen() {
    this.introSeen = true;
    this.saveSettings();
  }

  unlock(id) {
    if (!ACHIEVEMENT_DEFS[id] || this.unlocked[id]) return null;
    this.unlocked[id] = true;
    try {
      localStorage.setItem(ACH_KEY, JSON.stringify(this.unlocked));
    } catch {
      // Ignore
    }
    return ACHIEVEMENT_DEFS[id];
  }

  unlockedCount() {
    return Object.keys(this.unlocked).filter((k) => this.unlocked[k] && ACHIEVEMENT_DEFS[k]).length;
  }
}
