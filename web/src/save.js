import { ACHIEVEMENT_DEFS } from "./config.js";

const SETTINGS_KEY = "moonrise_web_settings_v1";
const ACH_KEY = "moonrise_web_achievements_v1";

export class SaveStore {
  constructor() {
    this.introSeen = false;
    this.masterVolume = 0.85;
    this.screenShake = true;
    this.skipCutscenes = false;
    this.touchMode = "auto"; // "auto" | "on" | "off"
    this.unlocked = {};
  }

  load() {
    try {
      const raw = localStorage.getItem(SETTINGS_KEY);
      if (raw) {
        const data = JSON.parse(raw);
        this.introSeen = Boolean(data.introSeen);
        this.masterVolume = typeof data.masterVolume === "number" ? data.masterVolume : 0.85;
        this.screenShake = data.screenShake !== false;
        this.skipCutscenes = Boolean(data.skipCutscenes);
        if (["auto", "on", "off"].includes(data.touchMode)) {
          this.touchMode = data.touchMode;
        }
      }
      const rawAch = localStorage.getItem(ACH_KEY);
      if (rawAch) {
        this.unlocked = JSON.parse(rawAch) || {};
      }
    } catch {
      // Storage unavailable (private mode); stay in-memory
    }
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
          touchMode: this.touchMode,
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
