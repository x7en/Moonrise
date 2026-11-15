import { Config, STORY_CARDS, ACHIEVEMENT_DEFS } from "./config.js";
import { Assets } from "./assets.js";
import { Sfx } from "./sfx.js";
import { SaveStore } from "./save.js";
import { Bag, WorldMap, dist, rectIntersects } from "./world.js";
import {
  Player,
  Enemy,
  Ghost,
  Dog,
  Trap,
  Arrow,
  Boomerang,
  Watchtower,
  FxSystem,
  MoonSkyRenderer,
} from "./entities.js";
import { InputController } from "./touch.js";
import { UIController } from "./ui.js";

const STATE = {
  TITLE: "title",
  STORY: "story",
  DAY: "day",
  MOONRISE: "moonrise",
  NIGHT: "night",
  PAUSED: "paused",
  GAME_OVER: "game_over",
  VICTORY: "victory",
};

class MoonriseGame {
  constructor() {
    this.canvas = document.getElementById("game-canvas");
    this.ctx = this.canvas.getContext("2d");
    this.ctx.imageSmoothingEnabled = false;

    this.save = new SaveStore();
    this.save.load();
    Sfx.setVolume(this.save.masterVolume);

    this.state = STATE.TITLE;
    this.prePauseState = STATE.DAY;
    this.infoReturnToTitle = false;

    this.act = 1;
    this.day = 1;
    this.phaseTimer = Config.DAY_LENGTH;
    this.isBloodMoon = false;
    this.isEvenMoon = false;
    this.duskWarned = false;
    this.killsTotal = 0;
    this.intrudersInside = 0;
    this.intruderDmgAccum = 0;
    this.intruderPlayerTimer = 0;
    this.nightDamageTaken = false;
    this.hadIntruderThisNight = false;

    this.shockCd = 0;
    this.recallCd = 0;
    this.hitStop = 0;
    this.shakeTimer = 0;
    this.shakeAmp = 0;

    this.trapMode = false;
    this.selectedTrapSlot = 1;
    this.trapKeys = ["trap_snare", "trap_spike", "trap_lure"];

    this.searchKey = "";
    this.searchTimer = 0;
    this.searchProgress = 0;

    this.waveQueue = [];
    this.waveElapsed = 0;
    this.ghostTimer = 24;
    this.daySnapshot = null;

    this.bag = new Bag(Config.BAG_CAPACITY);
    this.stockpile = new Bag(-1);
    this.player = new Player();
    this.world = null;
    this.enemies = [];
    this.ghosts = [];
    this.dogs = [];
    this.traps = [];
    this.arrows = [];
    this.boomerangs = [];
    this.watchtowers = [];
    this.fx = new FxSystem();
    this.moonSky = new MoonSkyRenderer();

    this.cam = { x: Config.HOUSE_DOOR.x - Config.VIEW_W * 0.5, y: Config.HOUSE_DOOR.y - Config.VIEW_H * 0.5 };
    this.nightIntro = { active: false, elapsed: 0, duration: 5.5, isBlood: false, isEven: false, flashed: false };

    this.ui = new UIController({
      onPlay: (cont) => {
        Sfx.unlock();
        Sfx.play("ui_blip", 0.35);
        if (cont && this.daySnapshot) {
          this.retryDay();
        } else {
          this.beginNewRun();
        }
      },
      onTutorial: (fromTitle) => {
        Sfx.unlock();
        Sfx.play("ui_blip", 0.35);
        this.openTutorial(fromTitle);
      },
      onInfoPanel: (kind) => {
        Sfx.unlock();
        Sfx.play("ui_blip", 0.35);
        this.infoReturnToTitle = true;
        this.openInfoPanel(kind);
      },
      onOpenInventory: () => this.openGameplayModal("inventory"),
      onOpenCrafting: () => this.openGameplayModal("crafting"),
      onOpenPause: () => this.openGameplayModal("pause"),
      onToggleFullscreen: () => this.toggleFullscreen(),
      onCloseModal: () => this.closeModal(),
      onRetryDay: () => {
        Sfx.play("ui_blip", 0.35);
        this.retryDay();
      },
      onReturnToMenu: () => {
        Sfx.play("ui_blip", 0.35);
        this.returnToTitle();
      },
      onSkipNightIntro: () => this.finishNightIntro(),
      onTrapSlot: (slot) => this.toggleTrapSlot(slot),
    });

    this.input = new InputController({
      onAnyGesture: () => Sfx.unlock(),
      onPrimaryAttack: () => this.handlePrimaryAttack(),
      onSpear: () => this.triggerMeleeOrClearIntruders(),
      onInteractTap: () => this.tryInteract(),
      onReload: () => this.tryReload(),
      onShockwave: () => this.tryShockwave(),
      onRecallHome: () => this.tryRecallHome(),
      onTameDog: () => this.tryTameDog(),
      onUpgrade: () => this.tryOpenNearbyUpgrade(),
      onToggleDog: () => this.toggleDogMode(),
      onPlaceTrapForward: () => this.tryPlaceTrapAt(this.computeTrapPlacePos(null)),
      onCancelTrap: () => this.setTrapMode(false),
      onKeyDown: (e) => this.handleKeyDown(e),
    });
    this.input.setTouchMode(this.save.touchMode);

    this._bindCanvasPointer();
    this._bindLifecycle();
    this._resizeCanvas();
    window.addEventListener("resize", () => this._resizeCanvas());
  }

  async start() {
    await Assets.loadAll((done, total) => this.ui.setLoadingProgress(done, total));
    this.world = new WorldMap(1337);
    this.ui.hideLoading();

    if (!this.save.introSeen) {
      this.state = STATE.STORY;
      this.ui.hideAllScreens();
      this.input.setGameplayActive(false);
      this.ui.showCards(STORY_CARDS.opening, () => {
        this.save.markIntroSeen();
        this.returnToTitle();
      });
    } else {
      this.returnToTitle();
    }

    let last = performance.now();
    const tick = (now) => {
      const dt = Math.min(0.05, Math.max(0.001, (now - last) / 1000));
      last = now;
      this.update(dt);
      this.render(dt);
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  }

  _resizeCanvas() {
    const appW = window.innerWidth;
    const appH = window.innerHeight;
    const targetAspect = Config.VIEW_W / Config.VIEW_H;
    const winAspect = appW / Math.max(1, appH);

    // Keep crisp integer-friendly pixel viewport filling screen cleanly
    if (winAspect >= targetAspect) {
      this.canvas.height = Config.VIEW_H;
      this.canvas.width = Math.min(860, Math.max(Config.VIEW_W, Math.round(Config.VIEW_H * winAspect)));
    } else {
      this.canvas.width = Config.VIEW_W;
      this.canvas.height = Math.min(540, Math.max(Config.VIEW_H, Math.round(Config.VIEW_W / winAspect)));
    }
    this.ctx.imageSmoothingEnabled = false;
  }

  _bindLifecycle() {
    document.addEventListener("visibilitychange", () => {
      if (document.hidden && (this.state === STATE.DAY || this.state === STATE.NIGHT)) {
        this.openGameplayModal("pause");
      }
    });
  }

  _bindCanvasPointer() {
    this.canvas.addEventListener("pointerdown", (e) => {
      if (this.state !== STATE.DAY && this.state !== STATE.NIGHT) return;
      if (this.ui.isModalOpen()) return;
      Sfx.unlock();
      const worldPt = this._clientToWorld(e.clientX, e.clientY);

      // Right-click on desktop cancels trap mode or quick-repairs
      if (e.button === 2) {
        if (this.trapMode) {
          this.setTrapMode(false);
        } else {
          this.tryQuickRepairAt(worldPt);
        }
        return;
      }

      // In trap mode, tapping ground places trap right where you tapped (clamped to range)
      if (this.trapMode) {
        this.tryPlaceTrapAt(this.computeTrapPlacePos(worldPt));
        return;
      }

      // Tapping a nearby structure opens its upgrade menu
      const tappedStruct = this._findStructureAtPoint(worldPt);
      if (tappedStruct && dist(this.player.x, this.player.y, tappedStruct.x, tappedStruct.y) <= Config.STRUCTURE_MENU_REACH + 24) {
        this.openUpgradeModal(tappedStruct);
        return;
      }

      // Desktop mouse left-click fires active weapon (on touchscreens use right-hand buttons to avoid accidental shots)
      if (e.pointerType === "mouse" && !this.input.isTouchControlsVisible()) {
        this.handlePrimaryAttack();
      }
    });

    this.canvas.addEventListener("contextmenu", (e) => e.preventDefault());
  }

  _clientToWorld(clientX, clientY) {
    const rect = this.canvas.getBoundingClientRect();
    const cx = ((clientX - rect.left) / Math.max(1, rect.width)) * this.canvas.width;
    const cy = ((clientY - rect.top) / Math.max(1, rect.height)) * this.canvas.height;
    return { x: this.cam.x + cx, y: this.cam.y + cy };
  }

  _findStructureAtPoint(pt) {
    if (!this.world) return null;
    for (const s of this.world.structures) {
      const r = s.visualRect;
      if (pt.x >= r.x && pt.x <= r.x + r.w && pt.y >= r.y && pt.y <= r.y + r.h) {
        return s;
      }
    }
    return null;
  }

  toggleFullscreen() {
    if (!document.fullscreenElement) {
      document.documentElement.requestFullscreen?.().catch(() => {});
    } else {
      document.exitFullscreen?.().catch(() => {});
    }
  }

  // ==================== RUN & PHASE FLOW ====================
  returnToTitle() {
    this.state = STATE.TITLE;
    this.trapMode = false;
    this.ui.closeModal();
    this.ui.showTitle(Boolean(this.daySnapshot));
    this.input.setGameplayActive(false);
  }

  beginNewRun() {
    this.act = 1;
    this.day = 1;
    this.killsTotal = 0;
    this.intrudersInside = 0;
    this.shockCd = 0;
    this.recallCd = 0;
    this.trapMode = false;
    this.daySnapshot = null;

    this.bag.clear();
    this.stockpile.clear();
    this.stockpile.add("plank", Config.ACT1_START_STOCKPILE);
    this.bag.add("arrow", 18);
    this.bag.add("trap_snare", Config.START_BEAR_TRAPS);
    this.bag.add("trap_spike", Config.START_SPIKE_TRAPS);

    this.world = new WorldMap(1337 + Math.floor(Math.random() * 9999));
    this.world.act1FogVisible = true;
    this.player.reset(Config.HOUSE_DOOR.x, Config.HOUSE_DOOR.y);

    this.enemies = [];
    this.ghosts = [];
    this.dogs = [];
    this.traps = [];
    this.arrows = [];
    this.boomerangs = [];
    this.watchtowers = [];
    this.fx.clear();

    this.ui.closeModal();
    this.ui.showGameplay();
    this.input.setGameplayActive(true);
    this.startDay(1, false);
  }

  startDay(dayNum, isRetry) {
    this.day = dayNum;
    this.state = STATE.DAY;
    this.phaseTimer = Config.DAY_LENGTH;
    this.isBloodMoon = false;
    this.isEvenMoon = false;
    this.duskWarned = false;
    this.intrudersInside = 0;
    this.nightDamageTaken = false;
    this.hadIntruderThisNight = false;
    this.enemies = [];
    this.ghosts = [];
    this.arrows = [];
    this.boomerangs = [];
    this.player.boomerangInFlight = false;
    this.player.insideHouse = false;
    this.world.house.doorOpen = false;
    this.world.openAllGates();

    if (!isRetry && dayNum > 1) {
      // Dawn free repairs
      if (!this.world.house.isFallen) this.world.house.repair(Config.DAWN_FREE_REPAIR);
      for (const f of this.world.fences) {
        if (f.isBuilt) f.repair(Config.DAWN_FREE_REPAIR);
      }
      this.player.heal(10);
    }

    this.world.spawnDailyPiles(this.act, this.day);
    this._spawnDayWanderers();
    if (this.act >= 2) {
      this._spawnAct2StrayDogs();
    }
    this._saveDaySnapshot();

    this.ui.showGameplay();
    this.input.setGameplayActive(true);
    const sub =
      this.act === 1
        ? "Gather planks, chop trees, and fortify before dusk."
        : "Explore the valley for scrap, tame dogs, and hold the rings.";
    this.ui.showHeaderBanner(`DAY ${this.day}`, sub, "#ffdf80", 2.8);
  }

  _saveDaySnapshot() {
    this.daySnapshot = {
      act: this.act,
      day: this.day,
      bag: this.bag.snapshot(),
      stock: this.stockpile.snapshot(),
      hp: this.player.hp,
      gearTier: this.player.gearTier,
      activeWeapon: this.player.activeWeapon,
      bowMag: this.player.bowMag,
      houseHp: this.world.house.hp,
      houseLv: this.world.house.level,
      houseFallen: this.world.house.isFallen,
      fences: this.world.fences.map((f) => ({
        isBuilt: f.isBuilt,
        level: f.level,
        hp: f.hp,
        spiked: f.spiked,
      })),
    };
  }

  retryDay() {
    if (!this.daySnapshot) {
      this.beginNewRun();
      return;
    }
    const s = this.daySnapshot;
    this.act = s.act;
    this.day = s.day;
    this.world.act1FogVisible = this.act === 1;
    this.bag.restore(s.bag);
    this.stockpile.restore(s.stock);
    this.player.reset(Config.HOUSE_DOOR.x, Config.HOUSE_DOOR.y);
    this.player.applyGearTier(s.gearTier);
    this.player.hp = Math.max(20, s.hp);
    this.player.activeWeapon = s.activeWeapon;
    this.player.bowMag = s.bowMag;

    this.world.house.upgradeTo(s.houseLv);
    this.world.house.isFallen = s.houseFallen;
    this.world.house.hp = s.houseFallen ? 0 : s.houseHp;
    s.fences.forEach((fd, idx) => {
      const f = this.world.fences[idx];
      if (!f) return;
      f.upgradeTo(fd.level);
      f.isBuilt = fd.isBuilt;
      f.hp = fd.hp;
      f.spiked = fd.spiked;
    });

    this.traps = [];
    this.watchtowers = [];
    this.dogs = [];
    this.fx.clear();
    this.startDay(this.day, true);
  }

  _spawnDayWanderers() {
    const count =
      Config.DAY_WANDERER_MIN +
      Math.floor(Math.random() * (Config.DAY_WANDERER_MAX - Config.DAY_WANDERER_MIN + 1));
    const b = this.getActiveBounds();
    const hc = Config.HOUSE_CENTER;
    for (let i = 0; i < count; i++) {
      const ang = Math.random() * Math.PI * 2;
      const rad = this.act === 1 ? 210 + Math.random() * 140 : 300 + Math.random() * 480;
      const x = Math.max(b.x + 28, Math.min(b.x + b.w - 28, hc.x + Math.cos(ang) * rad));
      const y = Math.max(b.y + 28, Math.min(b.y + b.h - 28, hc.y + Math.sin(ang) * rad));
      this.enemies.push(new Enemy("zombie", x, y, true));
    }
  }

  _spawnAct2StrayDogs() {
    const tamed = this.dogs.filter((d) => d.isTamed());
    this.dogs = [...tamed];
    const hc = Config.HOUSE_CENTER;
    while (this.dogs.length < Config.DOG_MAX) {
      const ang = Math.random() * Math.PI * 2;
      const rad = 260 + Math.random() * 340;
      const x = Math.max(60, Math.min(Config.WORLD_W - 60, hc.x + Math.cos(ang) * rad));
      const y = Math.max(60, Math.min(Config.WORLD_H - 60, hc.y + Math.sin(ang) * rad));
      const canTame = Math.random() < Config.DOG_TAMEABLE_CHANCE || this.dogs.length === tamed.length;
      this.dogs.push(new Dog(x, y, canTame));
    }
  }

  startMoonrise() {
    this.setTrapMode(false);
    this.isBloodMoon = this.day === 3 || this.day === 7;
    this.isEvenMoon = !this.isBloodMoon && this.day <= 2;

    if (this.save.skipCutscenes) {
      this.startNightCombat();
      return;
    }

    this.state = STATE.MOONRISE;
    this.input.setGameplayActive(false);
    this.ui.hideAllScreens();
    this.ui.el.nightScreen.classList.remove("hidden");
    this.nightIntro = {
      active: true,
      elapsed: 0,
      duration: 5.2,
      isBlood: this.isBloodMoon,
      isEven: this.isEvenMoon,
      flashed: false,
    };

    if (this.isBloodMoon) {
      this.ui.el.nightTitle.textContent = this.day === 3 ? "BLOOD MOON RISES EARLY!" : "THE FINAL BLOOD MOON";
      this.ui.el.nightTitle.style.color = "#ff5c54";
      this.ui.el.nightNarration.textContent =
        this.day === 3
          ? "The radio was wrong — the crimson moon bleeds over Night 3! Hold the farmhouse!"
          : "Every terror in the valley converges tonight. Survive until dawn!";
    } else if (this.isEvenMoon) {
      this.ui.el.nightTitle.textContent = `NIGHT ${this.day} — EVEN MOON`;
      this.ui.el.nightTitle.style.color = "#f278a8";
      this.ui.el.nightNarration.textContent = "A wine-red glow bathes the hills. Shut the doors and watch the perimeter.";
    } else {
      this.ui.el.nightTitle.textContent = `NIGHT ${this.day}`;
      this.ui.el.nightTitle.style.color = "#d0dcf8";
      this.ui.el.nightNarration.textContent =
        this.day >= 5
          ? "Fast raiders join the dead from the east. Keep your weapons ready!"
          : "Darkness settles across the valley. Defend the farmhouse until sunrise.";
    }
  }

  finishNightIntro() {
    if (!this.nightIntro.active) return;
    this.nightIntro.active = false;
    this.ui.el.nightScreen.classList.add("hidden");
    this.startNightCombat();
  }

  startNightCombat() {
    this.state = STATE.NIGHT;
    this.phaseTimer = Config.nightLength(this.day);
    this.arrows = [];
    this.boomerangs = [];
    this.player.boomerangInFlight = false;
    this.world.piles = [];
    // Clear daytime wanderers and build wave queue
    this.enemies = [];
    this.ghosts = [];
    this._buildWaveQueue();
    this.waveElapsed = 0;
    this.ghostTimer = 14 + Math.random() * 8;

    this.ui.showGameplay();
    this.input.setGameplayActive(true);
    if (this.isBloodMoon) {
      Sfx.play("blood_moon", 0.55);
      this.ui.showHeaderBanner("BLOOD MOON", "Hold the line until sunrise!", "#ff5c54", 2.8);
    } else {
      this.ui.showHeaderBanner(`NIGHT ${this.day}`, "Survive the waves until dawn!", "#a8c4ff", 2.4);
    }
  }

  _buildWaveQueue() {
    const info = Config.NIGHTS[this.day] || Config.NIGHTS[7];
    const pool = [];
    for (let i = 0; i < info.zombies; i++) pool.push("zombie");
    for (let i = 0; i < info.raiders; i++) pool.push("raider");
    // Shuffle
    for (let i = pool.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [pool[i], pool[j]] = [pool[j], pool[i]];
    }
    const dur = Math.max(10, Config.nightLength(this.day) - 6);
    const gap = dur / Math.max(1, pool.length);
    const sides = ["north", "south", "east", "west"];
    this.waveQueue = pool.map((type, idx) => ({
      type,
      side: type === "raider" ? "east" : sides[idx % sides.length],
      time: 1.0 + idx * gap,
    }));
  }

  _spawnWaveEnemy(type, side) {
    const b = this.getActiveBounds();
    const pad = 18;
    let x = b.x + b.w * 0.5;
    let y = b.y + b.h * 0.5;
    if (side === "north") {
      x = b.x + pad + Math.random() * (b.w - pad * 2);
      y = b.y + pad;
    } else if (side === "south") {
      x = b.x + pad + Math.random() * (b.w - pad * 2);
      y = b.y + b.h - pad;
    } else if (side === "east") {
      x = b.x + b.w - pad;
      y = b.y + pad + Math.random() * (b.h - pad * 2);
    } else {
      x = b.x + pad;
      y = b.y + pad + Math.random() * (b.h - pad * 2);
    }
    this.enemies.push(new Enemy(type, x, y, false));
  }

  _spawnGhost() {
    if (this.act < 2 || this.day < Config.GHOST_MIN_DAY || this.ghosts.length >= Config.GHOST_MAX_ALIVE) return;
    const ang = Math.random() * Math.PI * 2;
    const rad = 175 + Math.random() * 80;
    const x = Math.max(40, Math.min(Config.WORLD_W - 40, this.player.x + Math.cos(ang) * rad));
    const y = Math.max(40, Math.min(Config.WORLD_H - 40, this.player.y + Math.sin(ang) * rad));
    const variant = Math.random() < 0.65 ? "scythe" : "lunge";
    this.ghosts.push(new Ghost(x, y, variant));
    Sfx.play("ghost_appear", 0.45);
    this.fx.spawnRing(x, y, 34, "rgba(170, 235, 255, 0.78)");
    this.ui.showToast("A cold chill passes nearby...", 2.0, "#a8ecff");
  }

  onNightSurvived() {
    if (this.day === 1) this.unlockAchievement("first_night");
    if (this.day === 3) this.unlockAchievement("blood_moon_survivor");
    if (!this.nightDamageTaken && !this.world.house.isFallen) this.unlockAchievement("perfect_night");
    if (this.hadIntruderThisNight) this.unlockAchievement("intruder_alert");

    if (this.day >= 7) {
      this.unlockAchievement("final_blood_moon");
      this.state = STATE.VICTORY;
      this.input.setGameplayActive(false);
      this.ui.showEndScreen(
        true,
        "DAWN BREAKS — VICTORY!",
        `You outlasted all 7 nights and survived the Final Blood Moon!\n\nTotal Hostiles Defeated: ${this.killsTotal}\nAchievements Unlocked: ${this.save.unlockedCount()}/${Object.keys(ACHIEVEMENT_DEFS).length}`,
        false
      );
      return;
    }

    // Night 3 triggers Act 2 World Expansion!
    if (this.act === 1 && this.day === Config.WORLD_EXPAND_NIGHT) {
      this.act = 2;
      this.world.act1FogVisible = false;
      this.stockpile.add("plank", Config.ACT2_START_STOCKPILE);
      this.unlockAchievement("world_expanded");
      this.state = STATE.STORY;
      this.input.setGameplayActive(false);
      this.ui.hideAllScreens();
      this.ui.showCards(STORY_CARDS.worldExpanded, () => {
        this.startDay(this.day + 1, false);
      });
      return;
    }

    this.startDay(this.day + 1, false);
  }

  onPlayerDied() {
    this.state = STATE.GAME_OVER;
    this.input.setGameplayActive(false);
    Sfx.play("crumble", 0.55);
    this.ui.showEndScreen(
      false,
      "YOU FELL TO THE NIGHT",
      `Day ${this.day} (Act ${this.act}) — Total Kills: ${this.killsTotal}\n\nRetry Day restarts from the morning with your saved walls and resources.`,
      Boolean(this.daySnapshot)
    );
  }

  // ==================== COMBAT & ACTIONS ====================
  getAllHostiles() {
    return [...this.enemies, ...this.ghosts];
  }

  getActiveBounds() {
    return this.act === 1 ? Config.ACT1_RECT : { x: 0, y: 0, w: Config.WORLD_W, h: Config.WORLD_H };
  }

  handlePrimaryAttack() {
    if (this.state !== STATE.DAY && this.state !== STATE.NIGHT) return;
    if (this.player.insideHouse) {
      this.triggerMeleeOrClearIntruders();
      return;
    }
    const w = this.player.activeWeapon;
    if (w === "spear") {
      this.triggerMeleeOrClearIntruders();
    } else if (w === "boomerang") {
      const shot = this.player.tryThrowBoomerang(this.getAllHostiles());
      if (shot) {
        Sfx.play("boomerang_throw", 0.45);
        this.boomerangs.push(new Boomerang(this.player, shot.origin.x, shot.origin.y, shot.dir, shot.damage));
      }
    } else {
      const res = this.player.tryFireBow(this.getAllHostiles(), this.bag);
      if (res.ok) {
        Sfx.play("bow_shoot", 0.45);
        this.arrows.push(new Arrow(res.origin.x, res.origin.y, res.dir, res.damage, Config.BOW_RANGE, res.pierce, true));
      } else if (res.reason === "empty") {
        Sfx.play("bow_empty", 0.45);
        this.ui.showToast("Out of arrows! Craft more or switch weapon.", 1.8, "#ffaa88");
      } else if (res.reason === "reloading") {
        Sfx.play("bow_reload", 0.35);
      }
    }
  }

  triggerMeleeOrClearIntruders() {
    if (this.state !== STATE.DAY && this.state !== STATE.NIGHT) return;
    if (this.player.insideHouse) {
      if (this.intrudersInside > 0) {
        this.intrudersInside--;
        this.killsTotal++;
        Sfx.play("hit", 0.5);
        this.fx.spawnText(Config.HOUSE_CENTER.x, Config.HOUSE_CENTER.y, "Intruder cleared!", "#8ef59a");
      }
      return;
    }
    const swing = this.player.trySpearSwing();
    if (!swing) return;
    Sfx.play("swing", 0.42);
    for (const h of this.getAllHostiles()) {
      if (h.isAlive() && rectIntersects(swing.hitbox, h.getHurtbox())) {
        const res = h.takeHit(swing.damage, swing.dir, false);
        if (res.hit) this._onHostileHit(h.x, h.y - 10, res.killed, false);
      }
    }
  }

  tryReload() {
    if (this.state !== STATE.DAY && this.state !== STATE.NIGHT) return;
    if (this.player.startReload(this.bag)) {
      Sfx.play("bow_reload", 0.35);
      this.ui.showToast("Reloading bow...", 1.2, "#c8e4ff");
    }
  }

  tryShockwave() {
    if (this.state !== STATE.DAY && this.state !== STATE.NIGHT) return;
    if (this.player.insideHouse || this.shockCd > 0) return;
    this.shockCd = this.act === 1 ? Config.BOUNCE_CD_ACT1 : Config.BOUNCE_CD_ACT2;
    Sfx.play("bounce", 0.55);
    this.fx.spawnRing(this.player.x, this.player.y - 6, 76, "rgba(116, 240, 255, 0.92)");
    this.addShake(0.18, 3.0);

    let hitCount = 0;
    for (const h of this.getAllHostiles()) {
      if (!h.isAlive()) continue;
      const d = dist(this.player.x, this.player.y, h.x, h.y);
      if (d <= 78) {
        const dx = (h.x - this.player.x) / Math.max(1, d);
        const dy = (h.y - this.player.y) / Math.max(1, d);
        h.x += dx * 24;
        h.y += dy * 24;
        h.applyStun(Config.BOUNCE_STUN);
        hitCount++;
      }
    }
    this.ui.showToast(hitCount > 0 ? `Shockwave stunned ${hitCount}!` : "Shockwave pulse!", 1.4, "#92f2ff");
  }

  tryRecallHome() {
    if (this.state !== STATE.DAY && this.state !== STATE.NIGHT) return;
    if (this.player.insideHouse || this.recallCd > 0) return;
    this.recallCd = Config.RECALL_COOLDOWN;
    this.player.x = Config.HOUSE_DOOR.x;
    this.player.y = Config.HOUSE_DOOR.y;
    this.player.startRecallHeal();
    Sfx.play("dropoff", 0.45);
    this.fx.spawnRing(this.player.x, this.player.y - 6, 36, "rgba(196, 152, 255, 0.9)");
    this.fx.spawnText(this.player.x, this.player.y - 16, "Recalled Home +Heal!", "#d6b0ff");
    this._depositBagAtHouse();
  }

  tryInteract() {
    if (this.state !== STATE.DAY && this.state !== STATE.NIGHT) return;
    // Exit house if inside
    if (this.player.insideHouse) {
      this.player.insideHouse = false;
      this.player.x = Config.HOUSE_DOOR.x;
      this.player.y = Config.HOUSE_DOOR.y;
      Sfx.play("door_creak", 0.45);
      return;
    }

    // Check house door
    if (!this.world.house.isFallen && dist(this.player.x, this.player.y, Config.HOUSE_DOOR.x, Config.HOUSE_DOOR.y) <= Config.DOOR_INTERACT_REACH) {
      if (!this.world.house.doorOpen) {
        this.world.house.doorOpen = true;
        Sfx.play("door_creak", 0.45);
        this.ui.showToast("Door opened — tap ACT again to enter.", 1.5, "#ffe08a");
      } else {
        // Enter house & shut door behind you
        this.player.insideHouse = true;
        this.world.house.doorOpen = false;
        this._depositBagAtHouse();
        Sfx.play("door_creak", 0.45);
        this.ui.showToast("Inside Farmhouse (Healing). Tap ACT to exit.", 2.0, "#8ef59a");
      }
      return;
    }

    // Check nearest built gate
    let nearGate = null;
    let bestGd = 34;
    for (const f of this.world.fences) {
      if (!f.isBuilt || !f.isGate) continue;
      const d = dist(this.player.x, this.player.y, f.x, f.y);
      if (d <= bestGd) {
        bestGd = d;
        nearGate = f;
      }
    }
    if (nearGate) {
      nearGate.gateOpen = !nearGate.gateOpen;
      Sfx.play("door_creak", 0.42);
      this.ui.showToast(nearGate.gateOpen ? "Gate opened" : "Gate closed", 1.2, "#ffe694");
      return;
    }

    // Quick repair if standing next to damaged fence
    const nearStruct = this._findNearestUpgradeStructure();
    if (nearStruct && nearStruct.kind === "fence" && nearStruct.hp < nearStruct.maxHp) {
      this.tryQuickRepairAt({ x: nearStruct.x, y: nearStruct.y });
    }
  }

  tryQuickRepairAt(pt) {
    const s = this._findStructureAtPoint(pt) || this._findNearestUpgradeStructure();
    if (!s || s.isFallen || s.hp >= s.maxHp) return;
    const totalPlanks = this.bag.count("plank") + this.stockpile.count("plank");
    if (totalPlanks <= 0) {
      this.ui.showToast("Need planks to repair!", 1.5, "#ff9688");
      return;
    }
    this._spendResources({ plank: 1 });
    s.repair(Config.PLANK_HEAL);
    Sfx.play("fence_rebuilt", 0.4);
    this.fx.spawnText(s.x, s.y - 12, `+${Config.PLANK_HEAL} HP`, "#8ef59a");
  }

  tryTameDog() {
    if (this.player.insideHouse || this.player.dead) return;
    if (this.dogs.filter((d) => d.isTamed()).length >= Config.DOG_MAX_TAMED) return;
    const stray = this._findNearestTameableDog();
    if (stray && stray.tameNow()) {
      Sfx.play("dog_bark", 0.5);
      this.fx.spawnSparks(stray.x, stray.y, "#8ef59a", 10);
      this.unlockAchievement("tamed_dog");
      this.ui.showToast("Dog tamed! Tap Dog button for Follow / Guard.", 2.4, "#8ef59a");
    }
  }

  toggleDogMode() {
    const tamed = this.dogs.filter((d) => d.isTamed());
    if (tamed.length === 0) return;
    for (const d of tamed) {
      d.toggleFollowGuard(this.player.x, this.player.y);
    }
    Sfx.play("dog_bark", 0.4);
    this.ui.showToast(
      tamed[0].mode === "guard" ? "Dog guarding this spot!" : "Dog following you!",
      1.6,
      "#96d4ff"
    );
  }

  _findNearestTameableDog() {
    let best = null;
    let bestD = Config.DOG_TAME_RANGE;
    for (const d of this.dogs) {
      if (!d.canBeTamed()) continue;
      const dd = dist(this.player.x, this.player.y, d.x, d.y);
      if (dd <= bestD) {
        bestD = dd;
        best = d;
      }
    }
    return best;
  }

  _findNearestUpgradeStructure() {
    if (!this.world) return null;
    if (dist(this.player.x, this.player.y, this.world.house.x, this.world.house.y) <= Config.STRUCTURE_MENU_REACH + 16) {
      return this.world.house;
    }
    let best = null;
    let bestD = Config.STRUCTURE_MENU_REACH;
    for (const f of this.world.fences) {
      if (!f.isBuilt) continue;
      const d = dist(this.player.x, this.player.y, f.x, f.y);
      if (d <= bestD) {
        bestD = d;
        best = f;
      }
    }
    return best;
  }

  tryOpenNearbyUpgrade() {
    if (this.state !== STATE.DAY && this.state !== STATE.NIGHT) return;
    const s = this._findNearestUpgradeStructure();
    if (s) {
      this.openUpgradeModal(s);
    } else {
      this.ui.showToast("Walk closer to the farmhouse or a fence to upgrade.", 1.8, "#ffe08a");
    }
  }

  // ==================== TRAPS ====================
  toggleTrapSlot(slotIdx) {
    if (this.state !== STATE.DAY && this.state !== STATE.NIGHT) return;
    if (this.trapMode && this.selectedTrapSlot === slotIdx) {
      this.setTrapMode(false);
    } else {
      this.selectedTrapSlot = slotIdx;
      this.setTrapMode(true);
    }
    Sfx.play("ui_blip", 0.3);
  }

  setTrapMode(active) {
    this.trapMode = active;
    if (!active) this.fx.trapPreview = null;
  }

  computeTrapPlacePos(worldPt) {
    if (worldPt) {
      const dx = worldPt.x - this.player.x;
      const dy = worldPt.y - this.player.y;
      const l = Math.hypot(dx, dy);
      if (l > Config.TRAP_PLACE_RANGE) {
        return {
          x: Math.round(this.player.x + (dx / l) * Config.TRAP_PLACE_RANGE),
          y: Math.round(this.player.y + (dy / l) * Config.TRAP_PLACE_RANGE),
        };
      }
      return { x: Math.round(worldPt.x), y: Math.round(worldPt.y) };
    }
    return {
      x: Math.round(this.player.x + this.player.facingVec.x * 22),
      y: Math.round(this.player.y + this.player.facingVec.y * 22),
    };
  }

  canPlaceTrap(tKey, pos) {
    if (this.traps.length >= Config.MAX_TRAPS) return { ok: false, reason: "Trap limit reached." };
    const inBag = this.bag.count(tKey) > 0;
    const info = Config.TRAPS[tKey];
    if (!inBag && !this._canAfford(info.cost)) return { ok: false, reason: "Need traps or 2 planks." };
    for (const tr of this.traps) {
      if (dist(tr.x, tr.y, pos.x, pos.y) < Config.TRAP_MIN_SPACING) {
        return { ok: false, reason: "Too close to another trap." };
      }
    }
    if (!this.world.house.isFallen && dist(pos.x, pos.y, this.world.house.x, this.world.house.y) < 58) {
      return { ok: false, reason: "Too close to farmhouse." };
    }
    return { ok: true, reason: "" };
  }

  tryPlaceTrapAt(pos) {
    const tKey = this.trapKeys[this.selectedTrapSlot - 1];
    const check = this.canPlaceTrap(tKey, pos);
    if (!check.ok) {
      this.ui.showToast(check.reason, 1.5, "#ff8e84");
      return;
    }
    if (this.bag.count(tKey) > 0) {
      this.bag.remove(tKey, 1);
    } else {
      this._spendResources(Config.TRAPS[tKey].cost);
    }
    this.traps.push(new Trap(tKey, pos.x, pos.y));
    Sfx.play("fence_rebuilt", 0.4);
    this.fx.spawnText(pos.x, pos.y - 10, `${Config.TRAPS[tKey].shortLabel} placed`, "#8ef59a");
  }

  // ==================== ECONOMY & UPGRADES ====================
  _totalResource(item) {
    return this.bag.count(item) + this.stockpile.count(item);
  }

  _canAfford(cost) {
    for (const [k, amt] of Object.entries(cost)) {
      if (this._totalResource(k) < amt) return false;
    }
    return true;
  }

  _spendResources(cost) {
    for (const [k, amt] of Object.entries(cost)) {
      let rem = amt;
      const fromStock = this.stockpile.remove(k, rem);
      rem -= fromStock;
      if (rem > 0) this.bag.remove(k, rem);
    }
  }

  _fmtCost(cost) {
    return Object.entries(cost)
      .map(([k, v]) => `${v} ${k === "plank" ? "P" : "S"}`)
      .join(" + ");
  }

  _depositBagAtHouse() {
    const p = this.bag.remove("plank", this.bag.count("plank"));
    const s = this.bag.remove("scrap", this.bag.count("scrap"));
    if (p > 0 || s > 0) {
      this.stockpile.add("plank", p);
      this.stockpile.add("scrap", s);
      Sfx.play("dropoff", 0.42);
      const parts = [];
      if (p > 0) parts.push(`+${p} Planks`);
      if (s > 0) parts.push(`+${s} Scrap`);
      this.fx.spawnText(this.player.x, this.player.y - 16, `Stored ${parts.join(", ")}`, "#ffe28a");
    }
  }

  unlockAchievement(id) {
    const def = this.save.unlock(id);
    if (def) {
      Sfx.play("toast", 0.45);
      this.ui.enqueueAchievement(def.title, def.desc, def.icon);
    }
  }

  // ==================== MODALS ====================
  openGameplayModal(kind) {
    if (this.state !== STATE.DAY && this.state !== STATE.NIGHT && this.state !== STATE.PAUSED) return;
    if (this.state !== STATE.PAUSED) {
      this.prePauseState = this.state;
      this.state = STATE.PAUSED;
    }
    this.infoReturnToTitle = false;
    this.input.setGameplayActive(false);

    if (kind === "pause") {
      this.ui.openModal("PAUSED", `Day ${this.day} (Act ${this.act})`, "Game paused while menus are open", [
        { label: "Resume", right: "", onClick: () => this.closeModal() },
        { label: "Inventory & Weapons", right: this.player.activeWeapon.toUpperCase(), onClick: () => this.openGameplayModal("inventory") },
        { label: "Crafting Bench", right: `P:${this._totalResource("plank")} S:${this._totalResource("scrap")}`, onClick: () => this.openGameplayModal("crafting") },
        { label: "Tutorial Cards", onClick: () => this.openTutorial(false) },
        { label: "Controls", onClick: () => this.openInfoPanel("controls") },
        { label: "Settings", onClick: () => this.openInfoPanel("settings") },
        { label: "Achievements", right: `${this.save.unlockedCount()}/${Object.keys(ACHIEVEMENT_DEFS).length}`, onClick: () => this.openInfoPanel("achievements") },
        { label: "Return to Main Menu", onClick: () => this.returnToTitle() },
      ]);
    } else if (kind === "inventory") {
      const items = Config.DEFAULT_WEAPONS.map((wId) => {
        const def = Config.WEAPON_DEFS[wId];
        const eq = this.player.activeWeapon === wId;
        return {
          label: def.label,
          right: eq ? "EQUIPPED" : "EQUIP",
          desc: def.desc,
          equipped: eq,
          onClick: () => {
            this.player.activeWeapon = wId;
            Sfx.play("ui_blip", 0.35);
            this.openGameplayModal("inventory");
          },
        };
      });
      items.push(
        { type: "kv", key: "Gear Tier", val: `Level ${this.player.gearTier} (Max 3)` },
        { type: "kv", key: "Arrows", val: `${this.player.bowMag}/${this.player.bowMagMax} loaded + ${this.bag.count("arrow")} reserve` },
        { type: "kv", key: "Bag Loot", val: `${this.bag.count("plank")} Planks, ${this.bag.count("scrap")} Scrap` },
        { type: "kv", key: "House Stockpile", val: `${this.stockpile.count("plank")} Planks, ${this.stockpile.count("scrap")} Scrap` },
        {
          type: "kv",
          key: "Traps Ready",
          val: `Bear x${this.bag.count("trap_snare")} | Spike x${this.bag.count("trap_spike")} | Lure x${this.bag.count("trap_lure")}`,
        }
      );
      this.ui.openModal("INVENTORY & WEAPONS", "Tap a weapon to equip it", "Tap Close or press I / Esc to resume", items);
    } else if (kind === "crafting") {
      const items = Config.CRAFT_RECIPES.map((rec) => {
        const can = this._canAfford(rec.cost);
        return {
          label: rec.label,
          right: this._fmtCost(rec.cost),
          desc: rec.desc,
          disabled: !can,
          onClick: () => {
            if (!this._canAfford(rec.cost)) return;
            this._spendResources(rec.cost);
            if (rec.action === "buy_arrows") {
              this.bag.add("arrow", rec.amount);
            } else {
              this.bag.add(rec.item, rec.amount);
            }
            Sfx.play("upgrade", 0.45);
            this.openGameplayModal("crafting");
          },
        };
      });
      this.ui.openModal(
        "CRAFTING",
        `Resources — Planks: ${this._totalResource("plank")}  |  Scrap: ${this._totalResource("scrap")}`,
        "Uses stockpile first, then bag",
        items
      );
    }
  }

  openUpgradeModal(struct) {
    if (this.state !== STATE.PAUSED) {
      this.prePauseState = this.state;
      this.state = STATE.PAUSED;
    }
    this.infoReturnToTitle = false;
    this.input.setGameplayActive(false);

    const stats = this.world.ringStats();
    const house = this.world.house;
    const items = [];

    // House repair / rebuild / upgrade
    if (house.isFallen) {
      const cost = this.act === 1 ? Config.COST_HOUSE_REBUILD_ACT1 : Config.COST_HOUSE_REBUILD;
      items.push({
        label: "Rebuild Farmhouse",
        right: this._fmtCost(cost),
        desc: "Restore collapsed house shelter.",
        disabled: !this._canAfford(cost),
        onClick: () => {
          this._spendResources(cost);
          house.upgradeTo(house.level);
          Sfx.play("upgrade", 0.5);
          this.openUpgradeModal(house);
        },
      });
    } else {
      if (house.hp < house.maxHp) {
        const planksNeeded = Math.max(1, Math.ceil((house.maxHp - house.hp) / Config.PLANK_HEAL));
        const cost = { plank: Math.min(planksNeeded, Math.max(1, this._totalResource("plank"))) };
        items.push({
          label: `Repair Farmhouse (${house.hp}/${house.maxHp})`,
          right: `${planksNeeded} P full`,
          desc: `Each plank restores +${Config.PLANK_HEAL} HP.`,
          disabled: this._totalResource("plank") < 1,
          onClick: () => {
            this._spendResources(cost);
            house.repair(cost.plank * Config.PLANK_HEAL);
            Sfx.play("fence_rebuilt", 0.45);
            this.openUpgradeModal(house);
          },
        });
      }
      if (house.level < 3) {
        const nextLv = house.level + 1;
        const cost = nextLv === 2 ? Config.COST_HOUSE_LV2 : Config.COST_HOUSE_LV3;
        items.push({
          label: `Upgrade Farmhouse → Lv ${nextLv}`,
          right: this._fmtCost(cost),
          desc: `Boosts max HP to ${Config.HOUSE_LEVEL_HP[nextLv - 1]} and full heals.`,
          disabled: !this._canAfford(cost),
          onClick: () => {
            this._spendResources(cost);
            house.upgradeTo(nextLv);
            if (nextLv === 3) this.unlockAchievement("house_level_3");
            Sfx.play("upgrade", 0.5);
            this.openUpgradeModal(house);
          },
        });
      }
    }

    // Fence rings 1, 2, 3
    for (const r of [1, 2, 3]) {
      const st = stats[r];
      if (!st.built) {
        if (r === 2 || (r === 3 && stats[2].built)) {
          const cost = r === 2 ? Config.COST_UNLOCK_RING2 : Config.COST_UNLOCK_RING3;
          items.push({
            label: `Build Fence Ring ${r}`,
            right: this._fmtCost(cost),
            desc: `Adds an outer defensive perimeter around the yard.`,
            disabled: !this._canAfford(cost),
            onClick: () => {
              this._spendResources(cost);
              for (const f of this.world.fences) {
                if (f.ring === r) {
                  f.upgradeTo(1);
                  if (f.isGate && this.prePauseState === STATE.DAY) f.gateOpen = true;
                }
              }
              Sfx.play("upgrade", 0.5);
              this.openUpgradeModal(struct);
            },
          });
        }
        continue;
      }

      if (st.repairPlanks > 0) {
        const canSpend = Math.min(st.repairPlanks, this._totalResource("plank"));
        items.push({
          label: `Repair Ring ${r} (${st.hp}/${st.maxHp})`,
          right: `${st.repairPlanks} P`,
          desc: "Repairs damaged & broken segments in this ring.",
          disabled: canSpend < 1,
          onClick: () => {
            this._spendResources({ plank: canSpend });
            let pool = canSpend * Config.PLANK_HEAL;
            for (const f of this.world.fences) {
              if (f.ring !== r || pool <= 0) continue;
              const need = f.maxHp - (f.isBuilt ? f.hp : 0);
              if (need > 0) {
                const give = Math.min(need, pool);
                f.repair(give);
                pool -= give;
              }
            }
            Sfx.play("fence_rebuilt", 0.45);
            this.openUpgradeModal(struct);
          },
        });
      }

      if (st.level < 3) {
        const nextLv = st.level + 1;
        const cost = nextLv === 2 ? Config.COST_RING_LV2[r] : Config.COST_RING_LV3[r];
        items.push({
          label: `Upgrade Ring ${r} → ${nextLv === 3 ? "Iron (Lv3)" : "Lv2"}`,
          right: this._fmtCost(cost),
          desc: `Raises every segment in Ring ${r} to ${Config.FENCE_LEVEL_HP[nextLv - 1]} HP.`,
          disabled: !this._canAfford(cost),
          onClick: () => {
            this._spendResources(cost);
            for (const f of this.world.fences) {
              if (f.ring === r) f.upgradeTo(nextLv);
            }
            if (nextLv === 2) this.unlockAchievement("fence_upgraded");
            if (nextLv === 3) this.unlockAchievement("metal_fences");
            Sfx.play("upgrade", 0.5);
            this.openUpgradeModal(struct);
          },
        });
      }

      if (!st.spiked) {
        const cost = Config.COST_RING_SPIKES[r];
        items.push({
          label: `Add Spikes to Ring ${r}`,
          right: this._fmtCost(cost),
          desc: "Enemies attacking Ring " + r + " take thorn damage.",
          disabled: !this._canAfford(cost),
          onClick: () => {
            this._spendResources(cost);
            for (const f of this.world.fences) {
              if (f.ring === r) f.spiked = true;
            }
            Sfx.play("upgrade", 0.5);
            this.openUpgradeModal(struct);
          },
        });
      }
    }

    // Gear Tier & Watchtowers
    if (this.player.gearTier < 3) {
      const nextT = this.player.gearTier + 1;
      const cost = nextT === 2 ? Config.COST_GEAR_TIER2 : Config.COST_GEAR_TIER3;
      items.push({
        label: `Upgrade Gear → Tier ${nextT}`,
        right: this._fmtCost(cost),
        desc: nextT === 2 ? "+10 Max HP & +1 Weapon Damage" : "+10 Max HP, Piercing Arrows & +1 Boomerang Dmg",
        disabled: !this._canAfford(cost),
        onClick: () => {
          this._spendResources(cost);
          this.player.applyGearTier(nextT);
          Sfx.play("upgrade", 0.5);
          this.openUpgradeModal(struct);
        },
      });
    }

    if (this.watchtowers.length < Config.WATCHTOWER_MAX) {
      const cost = Config.COST_WATCHTOWER;
      items.push({
        label: `Build Watchtower (${this.watchtowers.length}/${Config.WATCHTOWER_MAX})`,
        right: this._fmtCost(cost),
        desc: "Auto-fires arrows at enemies approaching the yard.",
        disabled: !this._canAfford(cost),
        onClick: () => {
          this._spendResources(cost);
          const spots = [
            { x: Config.HOUSE_CENTER.x - 86, y: Config.HOUSE_CENTER.y + 46 },
            { x: Config.HOUSE_CENTER.x + 86, y: Config.HOUSE_CENTER.y + 46 },
          ];
          const spot = spots[this.watchtowers.length] || spots[0];
          this.watchtowers.push(new Watchtower(spot.x, spot.y));
          Sfx.play("upgrade", 0.5);
          this.openUpgradeModal(struct);
        },
      });
    }

    this.ui.openModal(
      "FORTIFY & UPGRADE",
      `Planks: ${this._totalResource("plank")}  |  Scrap: ${this._totalResource("scrap")}`,
      "Upgrades apply immediately and save at dawn",
      items
    );
  }

  openInfoPanel(kind) {
    if (kind === "controls") {
      this.ui.openModal("CONTROLS", "Mobile Touch & Desktop Keyboard", "Both control schemes work simultaneously", [
        { type: "kv", key: "Move", val: "Left Virtual Joystick / WASD / Arrows" },
        { type: "kv", key: "Primary Weapon", val: "FIRE button / Click / F" },
        { type: "kv", key: "Quick Spear Melee", val: "SPEAR button / Space" },
        { type: "kv", key: "Doors, Gates, Chop, Search", val: "Tap or Hold ACT / E" },
        { type: "kv", key: "Reload Bow", val: "RLD button / R" },
        { type: "kv", key: "Shockwave Stun", val: "SHOCK button / Q" },
        { type: "kv", key: "Recall Home (+Heal)", val: "HOME button / B" },
        { type: "kv", key: "Traps", val: "Bottom Trap Slots / Keys 1–3" },
        { type: "kv", key: "Upgrade / Repair", val: "Upgrade button near walls / U" },
        { type: "kv", key: "Bag / Craft / Pause", val: "Top-right buttons / I, C, Esc" },
      ]);
    } else if (kind === "settings") {
      const volPct = Math.round(this.save.masterVolume * 100);
      this.ui.openModal("SETTINGS", "Saved automatically in your browser", "", [
        {
          label: `Audio Volume: ${volPct}%`,
          right: "TAP TO CYCLE",
          onClick: () => {
            const steps = [0, 0.35, 0.65, 0.85, 1.0];
            const idx = steps.findIndex((v) => Math.abs(v - this.save.masterVolume) < 0.08);
            this.save.masterVolume = steps[(idx + 1) % steps.length];
            Sfx.setVolume(this.save.masterVolume);
            this.save.saveSettings();
            Sfx.play("ui_blip", 0.4);
            this.openInfoPanel("settings");
          },
        },
        {
          label: `On-Screen Touch Controls: ${this.save.touchMode.toUpperCase()}`,
          right: "AUTO / ON / OFF",
          desc: "Choose ON to preview mobile touch controls on desktop.",
          onClick: () => {
            const modes = ["auto", "on", "off"];
            this.save.touchMode = modes[(modes.indexOf(this.save.touchMode) + 1) % modes.length];
            this.save.saveSettings();
            this.input.setTouchMode(this.save.touchMode);
            Sfx.play("ui_blip", 0.35);
            this.openInfoPanel("settings");
          },
        },
        {
          label: `Screen Shake: ${this.save.screenShake ? "ON" : "OFF"}`,
          onClick: () => {
            this.save.screenShake = !this.save.screenShake;
            this.save.saveSettings();
            Sfx.play("ui_blip", 0.35);
            this.openInfoPanel("settings");
          },
        },
        {
          label: `Skip Moonrise Cutscenes: ${this.save.skipCutscenes ? "ON" : "OFF"}`,
          onClick: () => {
            this.save.skipCutscenes = !this.save.skipCutscenes;
            this.save.saveSettings();
            Sfx.play("ui_blip", 0.35);
            this.openInfoPanel("settings");
          },
        },
        {
          label: "Toggle Fullscreen",
          onClick: () => this.toggleFullscreen(),
        },
      ]);
    } else if (kind === "achievements") {
      this.ui.openModal(
        "ACHIEVEMENTS",
        `${this.save.unlockedCount()} / ${Object.keys(ACHIEVEMENT_DEFS).length} Unlocked`,
        "",
        this.ui.buildAchievementItems(this.save)
      );
    } else if (kind === "credits") {
      this.ui.openModal("CREDITS", "Moonrise — Mobile HTML5 Edition", "", [
        { type: "kv", key: "Game Design & Code", val: "Moonrise / RedMoon" },
        { type: "kv", key: "Engine", val: "HTML5 Canvas + Web Audio API" },
        { type: "kv", key: "Fonts", val: "KiwiSoda & PixelOperator8" },
        { type: "kv", key: "Controls", val: "Multi-Touch Pointer API + Keyboard" },
      ]);
    }
  }

  openTutorial(fromTitle) {
    this.ui.closeModal();
    this.input.setGameplayActive(false);
    this.ui.showCards(STORY_CARDS.tutorial, () => {
      if (fromTitle) {
        this.returnToTitle();
      } else {
        this.openGameplayModal("pause");
      }
    });
  }

  closeModal() {
    this.ui.closeModal();
    if (this.infoReturnToTitle) {
      this.infoReturnToTitle = false;
      return;
    }
    if (this.state === STATE.PAUSED) {
      this.state = this.prePauseState;
      this.input.setGameplayActive(true);
    }
  }

  handleKeyDown(e) {
    if (this.ui.isCardsOpen()) {
      if (e.code === "Escape") this.ui.skipCards();
      else if (e.code === "Space" || e.code === "Enter") this.ui.advanceCard();
      return;
    }
    if (this.nightIntro.active) {
      if (e.code === "Escape" || e.code === "Space" || e.code === "Enter") this.finishNightIntro();
      return;
    }
    if (e.code === "KeyM") {
      Sfx.toggleMute();
      this.ui.showToast(Sfx.muted ? "Audio Muted" : "Audio On", 1.2);
      return;
    }
    if (this.ui.isModalOpen()) {
      if (e.code === "Escape" || e.code === "KeyI" || e.code === "KeyC") this.closeModal();
      return;
    }
    if (this.state !== STATE.DAY && this.state !== STATE.NIGHT) return;

    switch (e.code) {
      case "Escape":
        if (this.trapMode) this.setTrapMode(false);
        else this.openGameplayModal("pause");
        break;
      case "KeyI":
        this.openGameplayModal("inventory");
        break;
      case "KeyC":
        this.openGameplayModal("crafting");
        break;
      case "Space":
        e.preventDefault();
        this.triggerMeleeOrClearIntruders();
        break;
      case "KeyF":
        this.handlePrimaryAttack();
        break;
      case "KeyR":
        this.tryReload();
        break;
      case "KeyB":
        this.tryRecallHome();
        break;
      case "KeyQ":
        this.tryShockwave();
        break;
      case "KeyE":
        this.tryInteract();
        break;
      case "KeyU":
        this.tryOpenNearbyUpgrade();
        break;
      case "Digit1":
        this.toggleTrapSlot(1);
        break;
      case "Digit2":
        this.toggleTrapSlot(2);
        break;
      case "Digit3":
        this.toggleTrapSlot(3);
        break;
      case "KeyT":
        if (this.trapMode) this.tryPlaceTrapAt(this.computeTrapPlacePos(null));
        break;
      case "KeyG":
        this.toggleDogMode();
        break;
      default:
        break;
    }
  }

  // ==================== UPDATE LOOP ====================
  update(dt) {
    this.ui.stepTimers(dt);

    if (this.nightIntro.active) {
      this.nightIntro.elapsed += dt;
      if (this.nightIntro.isBlood && !this.nightIntro.flashed && this.nightIntro.elapsed >= 2.2) {
        this.nightIntro.flashed = true;
        Sfx.play("blood_moon", 0.5);
      }
      if (this.nightIntro.elapsed >= this.nightIntro.duration) {
        this.finishNightIntro();
      }
      return;
    }

    if (this.hitStop > 0) {
      this.hitStop = Math.max(0, this.hitStop - dt);
      return;
    }
    if (this.shakeTimer > 0) this.shakeTimer = Math.max(0, this.shakeTimer - dt);

    if (this.state !== STATE.DAY && this.state !== STATE.NIGHT) return;

    if (this.shockCd > 0) this.shockCd = Math.max(0, this.shockCd - dt);
    if (this.recallCd > 0) this.recallCd = Math.max(0, this.recallCd - dt);

    for (const s of this.world.structures) {
      if (s.flashTimer > 0) s.flashTimer = Math.max(0, s.flashTimer - dt);
      s.hovered = false;
    }

    // Highlight nearest upgradeable structure for clarity
    const nearUp = this._findNearestUpgradeStructure();
    if (nearUp) nearUp.hovered = true;

    const bounds = this.getActiveBounds();
    const colliders = this.world.getSolidColliders();
    const moveVec = this.input.getMoveVector();

    this.player.update(dt, moveVec, colliders, bounds, this.bag, () => {
      Sfx.play("bow_reload", 0.4);
      this.ui.showToast("Bow reloaded!", 1.0, "#b8e4ff");
    });

    // Auto-pickup loot piles & auto-deposit near farmhouse
    if (!this.player.insideHouse && !this.player.dead) {
      for (const p of this.world.piles) {
        if (p.collected) continue;
        if (dist(this.player.x, this.player.y, p.x, p.y) <= p.pickupRadius) {
          const added = this.bag.add(p.itemType, p.amount);
          if (added > 0) {
            p.amount -= added;
            if (p.amount <= 0) p.collected = true;
            Sfx.play("pickup", 0.4);
            this.fx.spawnText(p.x, p.y - 8, `+${added} ${p.itemType}`, "#ffe888");
            if (p.itemType === "plank") this.unlockAchievement("first_plank");
          }
        }
      }
      if (dist(this.player.x, this.player.y, Config.HOUSE_CENTER.x, Config.HOUSE_CENTER.y) <= 78) {
        this._depositBagAtHouse();
      }
    }

    // Hold-to-gather (wrecks & trees)
    this._stepHoldGather(dt);

    // Phase timers & spawning
    this.phaseTimer -= dt;
    if (this.state === STATE.DAY) {
      const duskThreshold = this.act === 1 ? Config.ACT1_DUSK_TIME : Config.ACT2_DUSK_TIME;
      if (!this.duskWarned && this.phaseTimer <= duskThreshold) {
        this.duskWarned = true;
        this.ui.showHeaderBanner("DUSK APPROACHES", "Head home & shut your doors!", "#ffae68", 2.5);
      }
      if (this.phaseTimer <= 0) {
        this.startMoonrise();
        return;
      }
    } else if (this.state === STATE.NIGHT) {
      this.waveElapsed += dt;
      while (this.waveQueue.length > 0 && this.waveQueue[0].time <= this.waveElapsed) {
        const w = this.waveQueue.shift();
        this._spawnWaveEnemy(w.type, w.side);
      }
      if (this.phaseTimer <= 0 && this.waveQueue.length === 0) {
        this.onNightSurvived();
        return;
      }
    }

    // Act 2 Ghost spawns
    if (this.act >= 2 && this.day >= Config.GHOST_MIN_DAY) {
      this.ghostTimer -= dt;
      if (this.ghostTimer <= 0) {
        this._spawnGhost();
        this.ghostTimer = this.state === STATE.NIGHT ? 18 + Math.random() * 10 : 25 + Math.random() * 12;
      }
    }

    // Intruders inside farmhouse
    this._stepIntruders(dt);

    // Update enemies
    const enemyCtx = {
      player: this.player,
      house: this.world.house,
      fences: this.world.fences,
      traps: this.traps,
      watchtowers: this.watchtowers,
      enemies: this.enemies,
      colliders,
      bounds,
      onStructDmg: (struct, dmg, enemy) => this._onEnemyHitStruct(struct, dmg, enemy),
      onPlayerDmg: (dmg) => this._onPlayerDamaged(dmg),
      onEnteredHouse: () => {
        this.intrudersInside++;
        this.hadIntruderThisNight = true;
        Sfx.play("player_hit", 0.45);
        this.ui.showToast("ZOMBIE ENTERED THE HOUSE! Go inside & attack!", 2.4, "#ff685c");
      },
    };
    for (const e of this.enemies) e.update(dt, enemyCtx);
    this.enemies = this.enemies.filter((e) => !e.removeMe);

    // Update ghosts
    for (const g of this.ghosts) {
      g.update(dt, this.player, (dmg) => {
        Sfx.play("ghost_slash", 0.45);
        this._onPlayerDamaged(dmg);
      });
    }
    this.ghosts = this.ghosts.filter((g) => !g.removeMe);

    // Update dogs
    const hostiles = this.getAllHostiles();
    for (const d of this.dogs) {
      d.update(
        dt,
        this.player,
        hostiles,
        colliders,
        bounds,
        (target) => {
          Sfx.play("dog_bark", 0.35);
          const res = target.takeHit(Config.DOG_DAMAGE, { x: 0, y: 0 }, false);
          if (res.hit) this._onHostileHit(target.x, target.y - 10, res.killed, false);
        },
        (fallen) => {
          Sfx.play("player_hit", 0.45);
          this.fx.spawnSparks(fallen.x, fallen.y, "#ff5c54", 8);
          this.ui.showToast("A companion dog has fallen!", 2.2, "#ff8878");
        }
      );
    }
    this.dogs = this.dogs.filter((d) => !d.removeMe);

    // Update traps
    for (const tr of this.traps) {
      tr.update(dt, this.enemies, (trap, en) => {
        Sfx.play("trap_trigger", 0.45);
        if (trap.trapType === "trap_snare") {
          this.fx.spawnText(en.x, en.y - 12, "SNARED!", "#ffe064");
        } else {
          this.fx.spawnSparks(en.x, en.y, "#ff584c", 6);
        }
        if (en.hp <= 0) this._onHostileHit(en.x, en.y - 10, true, false);
      });
    }
    this.traps = this.traps.filter((t) => !t.removeMe);

    // Update watchtowers
    for (const wt of this.watchtowers) {
      wt.update(dt, hostiles, (origin, target) => {
        const dx = target.x - origin.x;
        const dy = target.y - 8 - origin.y;
        Sfx.play("bow_shoot", 0.3);
        this.arrows.push(new Arrow(origin.x, origin.y, { x: dx, y: dy }, 1, Config.WATCHTOWER_RANGE + 25, 0, false));
      });
    }
    this.watchtowers = this.watchtowers.filter((wt) => !wt.removeMe);

    // Update arrows
    for (const a of this.arrows) {
      a.update(dt, hostiles, bounds, (target, arr) => {
        const l = Math.hypot(arr.vx, arr.vy) || 1;
        const res = target.takeHit(arr.damage, { x: arr.vx / l, y: arr.vy / l }, arr.fromPlayer);
        if (res.hit) this._onHostileHit(target.x, target.y - 10, res.killed, arr.fromPlayer);
      });
    }
    this.arrows = this.arrows.filter((a) => !a.removeMe);

    // Update boomerangs
    for (const b of this.boomerangs) {
      b.update(
        dt,
        hostiles,
        bounds,
        (target) => {
          const res = target.takeHit(b.damage, { x: 0, y: 0 }, false);
          if (res.hit) this._onHostileHit(target.x, target.y - 10, res.killed, false);
        },
        () => {
          this.player.boomerangInFlight = false;
          this.player.boomerangCd = Config.BOOMERANG_COOLDOWN;
          Sfx.play("boomerang_catch", 0.4);
        }
      );
    }
    this.boomerangs = this.boomerangs.filter((b) => !b.removeMe);

    // Update trap preview
    if (this.trapMode && !this.player.insideHouse) {
      const tKey = this.trapKeys[this.selectedTrapSlot - 1];
      const info = Config.TRAPS[tKey];
      const pos = this.computeTrapPlacePos(null);
      const check = this.canPlaceTrap(tKey, pos);
      this.fx.trapPreview = {
        x: pos.x,
        y: pos.y,
        radius: info.radius,
        attractRadius: info.attractRadius || 0,
        ok: check.ok,
      };
    } else {
      this.fx.trapPreview = null;
    }

    this.fx.update(dt);
    this._updateCamera();
    this._syncHudAndTouch();
  }

  _stepHoldGather(dt) {
    if (this.player.insideHouse || this.player.dead || !this.input.isInteractHeld()) {
      this.searchKey = "";
      this.searchTimer = 0;
      this.searchProgress = 0;
      return;
    }

    const wreck = this.world.findNearestSearchable(this.player.x, this.player.y, 34);
    const tree = wreck ? null : this.world.findNearestTree(this.player.x, this.player.y, 30);
    if (!wreck && !tree) {
      this.searchKey = "";
      this.searchTimer = 0;
      this.searchProgress = 0;
      return;
    }

    const key = wreck ? `w:${wreck.id}` : `t:${tree.id}`;
    const needed = wreck ? Config.SEARCH_HOLD_TIME : Config.CHOP_HOLD_TIME;
    if (this.searchKey !== key) {
      this.searchKey = key;
      this.searchTimer = 0;
    }
    this.searchTimer += dt;
    this.searchProgress = Math.min(1, this.searchTimer / needed);

    if (this.searchTimer >= needed) {
      this.searchKey = "";
      this.searchTimer = 0;
      this.searchProgress = 0;
      this.input.notifyGatherCompleted();

      if (wreck) {
        wreck.searched = true;
        const pAdded = this.bag.add("plank", wreck.lootPlank);
        if (pAdded < wreck.lootPlank) this.stockpile.add("plank", wreck.lootPlank - pAdded);
        if (wreck.lootScrap > 0) {
          const sAdded = this.bag.add("scrap", wreck.lootScrap);
          if (sAdded < wreck.lootScrap) this.stockpile.add("scrap", wreck.lootScrap - sAdded);
        }
        if (Math.random() < 0.45) this.bag.add("arrow", 4);
        Sfx.play("pickup", 0.48);
        this.unlockAchievement("first_plank");
        this.fx.spawnSparks(wreck.x, wreck.y - 6, "#ffe478", 8);
        this.fx.spawnText(
          wreck.x,
          wreck.y - 12,
          `+${wreck.lootPlank}P${wreck.lootScrap ? ` +${wreck.lootScrap}S` : ""}`,
          "#ffe478"
        );
      } else if (tree) {
        this.world.chopTree(tree);
        const wood = 2;
        const pAdded = this.bag.add("plank", wood);
        if (pAdded < wood) this.stockpile.add("plank", wood - pAdded);
        Sfx.play("wood_chop", 0.48);
        this.unlockAchievement("first_plank");
        this.fx.spawnSparks(tree.x, tree.y - 8, "#cfa068", 8);
        this.fx.spawnText(tree.x, tree.y - 12, `+${wood} Planks`, "#ffd884");
      }
    }
  }

  _stepIntruders(dt) {
    if (this.intrudersInside <= 0 || this.world.house.isFallen) return;
    this.intruderDmgAccum += Config.INTRUDER_HOUSE_DPS * this.intrudersInside * dt;
    if (this.intruderDmgAccum >= 1) {
      const whole = Math.floor(this.intruderDmgAccum);
      this.intruderDmgAccum -= whole;
      const fell = this.world.house.takeDamage(whole);
      this.nightDamageTaken = true;
      if (fell) this._onHouseCrumbled();
    }
    if (this.player.insideHouse) {
      this.intruderPlayerTimer += dt;
      if (this.intruderPlayerTimer >= Config.INTRUDER_PLAYER_INTERVAL) {
        this.intruderPlayerTimer = 0;
        this._onPlayerDamaged(Config.INTRUDER_PLAYER_DMG);
      }
    }
  }

  _onEnemyHitStruct(struct, dmg, enemy) {
    this.nightDamageTaken = true;
    Sfx.play("struct_hit", 0.42);
    this.fx.spawnSparks(struct.x, struct.y, "#e6a868", 4);
    if (struct.spiked && enemy && enemy.isAlive()) {
      const res = enemy.takeHit(1, { x: 0, y: 0 }, false);
      if (res.killed) this._onHostileHit(enemy.x, enemy.y - 10, true, false);
    }
    const broke = struct.takeDamage(dmg);
    if (broke && struct.kind === "house") {
      this._onHouseCrumbled();
    }
  }

  _onHouseCrumbled() {
    Sfx.play("crumble", 0.6);
    this.addShake(0.35, 4.5);
    this.unlockAchievement("house_fell");
    if (this.player.insideHouse) {
      this.player.insideHouse = false;
      this.player.x = Config.HOUSE_DOOR.x;
      this.player.y = Config.HOUSE_DOOR.y;
    }
    this.ui.showHeaderBanner("THE FARMHOUSE FELL!", "Rebuild it or survive in the open!", "#ff5c54", 3.0);
  }

  _onPlayerDamaged(dmg) {
    if (this.player.takeDamage(dmg)) {
      Sfx.play("player_hit", 0.5);
      this.addShake(0.16, 2.8);
      this.fx.spawnSparks(this.player.x, this.player.y - 8, "#ff4842", 6);
      if (this.player.dead) this.onPlayerDied();
    }
  }

  _onHostileHit(x, y, killed, fromBow) {
    Sfx.play("hit", killed ? 0.5 : 0.4);
    this.fx.spawnSparks(x, y, "#f54842", killed ? 9 : 5);
    this.hitStop = 0.03;
    if (killed) {
      this.killsTotal++;
      this.addShake(0.09, 1.8);
      if (fromBow) this.unlockAchievement("first_bow_kill");
    }
  }

  addShake(duration, amp) {
    if (!this.save.screenShake) return;
    this.shakeTimer = Math.max(this.shakeTimer, duration);
    this.shakeAmp = Math.max(this.shakeAmp, amp);
  }

  _updateCamera() {
    let tx = this.player.insideHouse ? Config.HOUSE_CENTER.x : this.player.x;
    let ty = this.player.insideHouse ? Config.HOUSE_CENTER.y : this.player.y;
    if (this.shakeTimer > 0 && this.save.screenShake) {
      tx += (Math.random() * 2 - 1) * this.shakeAmp;
      ty += (Math.random() * 2 - 1) * this.shakeAmp;
    }
    const b = this.getActiveBounds();
    const cw = this.canvas.width;
    const ch = this.canvas.height;
    let cx = tx - cw * 0.5;
    let cy = ty - ch * 0.5;
    cx = cw >= b.w ? b.x + (b.w - cw) * 0.5 : Math.max(b.x, Math.min(b.x + b.w - cw, cx));
    cy = ch >= b.h ? b.y + (b.h - ch) * 0.5 : Math.max(b.y, Math.min(b.y + b.h - ch, cy));
    this.cam.x = Math.round(cx);
    this.cam.y = Math.round(cy);
  }

  _syncHudAndTouch() {
    const house = this.world.house;
    const nearWreck = this.player.insideHouse ? null : this.world.findNearestSearchable(this.player.x, this.player.y, 34);
    const nearTree = this.player.insideHouse || nearWreck ? null : this.world.findNearestTree(this.player.x, this.player.y, 30);
    const nearDoor = !house.isFallen && dist(this.player.x, this.player.y, Config.HOUSE_DOOR.x, Config.HOUSE_DOOR.y) <= Config.DOOR_INTERACT_REACH;
    let nearGate = null;
    for (const f of this.world.fences) {
      if (f.isBuilt && f.isGate && dist(this.player.x, this.player.y, f.x, f.y) <= 34) {
        nearGate = f;
        break;
      }
    }
    const nearUpgrade = this._findNearestUpgradeStructure();
    const tameDog = this._findNearestTameableDog();
    const tamedDogs = this.dogs.filter((d) => d.isTamed());

    // Dynamic interact label & prompt
    let interactLabel = "ACT";
    let interactSub = "TAP/HOLD";
    let prompt = "";
    if (this.player.insideHouse) {
      interactLabel = "EXIT";
      interactSub = "HOUSE";
      prompt = this.intrudersInside > 0 ? "INTRUDERS INSIDE! Tap CLEAR / Space!" : "Safe inside Farmhouse (Healing). Tap EXIT to leave.";
    } else if (nearDoor) {
      interactLabel = house.doorOpen ? "ENTER" : "DOOR";
      interactSub = house.doorOpen ? "SHELTER" : "OPEN";
      prompt = house.doorOpen ? "Tap ENTER (E) to go inside farmhouse" : "Tap DOOR (E) to open farmhouse door";
    } else if (nearGate) {
      interactLabel = "GATE";
      interactSub = nearGate.gateOpen ? "SHUT" : "OPEN";
      prompt = nearGate.gateOpen ? "Tap GATE (E) to shut perimeter gate" : "Tap GATE (E) to open gate";
    } else if (nearWreck) {
      interactLabel = "SEARCH";
      interactSub = "HOLD";
      prompt = "Hold SEARCH (Hold E) to scavenge wreck";
    } else if (nearTree) {
      interactLabel = "CHOP";
      interactSub = "HOLD";
      prompt = "Hold CHOP (Hold E) to chop tree for planks";
    } else if (this.trapMode) {
      prompt = "Tap Place Trap or tap map ground to place";
    }

    let statusText = "";
    if (this.intrudersInside > 0) {
      statusText = `WARNING: ${this.intrudersInside} INTRUDER(S) IN FARMHOUSE!`;
    } else if (this.player.insideHouse) {
      statusText = "INDOORS — Recovering Health";
    }

    const objective =
      this.state === STATE.NIGHT
        ? `Hostiles left: ${this.enemies.length + this.waveQueue.length + this.ghosts.length}`
        : this.phaseTimer <= 15
          ? "Dusk! Shut gates & house door!"
          : this.act === 1
            ? "Gather planks & fortify Ring 1"
            : "Explore valley, tame dogs & fortify";

    this.ui.updateHud({
      hp: this.player.hp,
      maxHp: this.player.maxHp,
      houseHp: house.hp,
      houseMax: house.maxHp,
      houseFallen: house.isFallen,
      doorOpen: house.doorOpen,
      intruders: this.intrudersInside,
      bagUsed: this.bag.totalUsed(),
      bagCap: this.bag.capacity,
      bagPlanks: this.bag.count("plank"),
      bagScrap: this.bag.count("scrap"),
      stockPlanks: this.stockpile.count("plank"),
      stockScrap: this.stockpile.count("scrap"),
      day: this.day,
      act: this.act,
      timer: this.phaseTimer,
      isNight: this.state === STATE.NIGHT,
      isBloodMoon: this.isBloodMoon,
      isEvenMoon: this.isEvenMoon,
      objective,
      weapon: this.player.activeWeapon,
      gearTier: this.player.gearTier,
      bowMag: this.player.bowMag,
      bowMagMax: this.player.bowMagMax,
      arrows: this.bag.count("arrow"),
      reloading: this.player.reloading,
      reloadLeft: this.player.reloadTimer,
      rangFlying: this.player.boomerangInFlight,
      rangCd: this.player.boomerangCd,
      shockCd: this.shockCd,
      recallCd: this.recallCd,
      statusText,
      searchProgress: this.searchProgress,
      prompt,
      trapMode: this.trapMode,
      selectedTrap: this.selectedTrapSlot,
      nSnare: this.bag.count("trap_snare"),
      nSpike: this.bag.count("trap_spike"),
      nLure: this.bag.count("trap_lure"),
      trapsPlaced: this.traps.length,
    });

    this.input.updateButtonStates({
      insideHouse: this.player.insideHouse,
      intruders: this.intrudersInside,
      weapon: this.player.activeWeapon,
      bowMag: this.player.bowMag,
      bowMagMax: this.player.bowMagMax,
      arrows: this.bag.count("arrow"),
      reloading: this.player.reloading,
      reloadLeft: this.player.reloadTimer,
      rangFlying: this.player.boomerangInFlight,
      rangCd: this.player.boomerangCd,
      shockCd: this.shockCd,
      recallCd: this.recallCd,
      interactLabel,
      interactSub,
      canTameDog: Boolean(tameDog) && tamedDogs.length < Config.DOG_MAX_TAMED,
      canUpgrade: Boolean(nearUpgrade) && !this.player.insideHouse,
      upgradeLabel: nearUpgrade && nearUpgrade.kind === "house" ? "Upgrade House" : "Upgrade / Repair",
      hasTamedDog: tamedDogs.length > 0,
      dogModeLabel: tamedDogs.length > 0 && tamedDogs[0].mode === "guard" ? "Guard" : "Follow",
      trapMode: this.trapMode,
    });
  }

  // ==================== RENDERING ====================
  render(dt) {
    if (this.state === STATE.TITLE) {
      const tCtx = this.ui.el.titleSkyCanvas.getContext("2d");
      tCtx.imageSmoothingEnabled = false;
      this.moonSky.draw(tCtx, dt, { redBlend: 0.92, moonProgress: 0.95, isEven: false });
      return;
    }

    if (this.nightIntro.active) {
      const nCtx = this.ui.el.nightSkyCanvas.getContext("2d");
      nCtx.imageSmoothingEnabled = false;
      const p = Math.min(1, this.nightIntro.elapsed / 3.2);
      const rb = this.nightIntro.isBlood ? Math.min(1, Math.max(0, (this.nightIntro.elapsed - 1.2) / 1.4)) : 0.15;
      this.moonSky.draw(nCtx, dt, { redBlend: rb, moonProgress: p, isEven: this.nightIntro.isEven });
      const flashA =
        this.nightIntro.isBlood && this.nightIntro.elapsed > 2.2 && this.nightIntro.elapsed < 3.0
          ? Math.max(0, 1 - (this.nightIntro.elapsed - 2.2) / 0.8) * 0.45
          : 0;
      this.ui.el.nightFlash.style.background = `rgba(235, 36, 36, ${flashA.toFixed(2)})`;
      return;
    }

    if (!this.world) return;
    const ctx = this.ctx;
    const cw = this.canvas.width;
    const ch = this.canvas.height;
    const isNight = this.state === STATE.NIGHT;

    ctx.clearRect(0, 0, cw, ch);
    ctx.save();
    ctx.translate(-this.cam.x, -this.cam.y);

    // 1. Pre-baked ground + stumps
    this.world.drawGround(ctx, this.cam.x, this.cam.y, cw, ch);

    // 2. Traps on ground
    for (const tr of this.traps) tr.draw(ctx);

    // 3. Y-sorted entities, props, structures, loot piles
    const drawables = [];
    for (const s of this.world.structures) {
      drawables.push({ sortY: s.sortY, draw: () => s.draw(ctx, isNight) });
    }
    for (const p of this.world.props) {
      if (p.chopped) continue;
      if (p.x < this.cam.x - 60 || p.x > this.cam.x + cw + 60 || p.y < this.cam.y - 60 || p.y > this.cam.y + ch + 60) {
        continue;
      }
      drawables.push({
        sortY: p.y,
        draw: () => {
          Assets.drawShadow(ctx, p.x, p.y + 1, p.kind === "tree" ? 10 : 8, 3.5);
          Assets.drawStaticFeet(ctx, p.key, p.x, p.y, { alpha: p.searched ? 0.55 : 1 });
        },
      });
    }
    for (const pl of this.world.piles) {
      if (!pl.collected) drawables.push({ sortY: pl.sortY, draw: () => pl.draw(ctx) });
    }
    for (const wt of this.watchtowers) drawables.push({ sortY: wt.sortY, draw: () => wt.draw(ctx) });
    for (const d of this.dogs) drawables.push({ sortY: d.sortY, draw: () => d.draw(ctx) });
    for (const e of this.enemies) drawables.push({ sortY: e.sortY, draw: () => e.draw(ctx) });
    for (const g of this.ghosts) drawables.push({ sortY: g.sortY, draw: () => g.draw(ctx) });
    drawables.push({ sortY: this.player.sortY, draw: () => this.player.draw(ctx, isNight) });

    drawables.sort((a, b) => a.sortY - b.sortY);
    for (const item of drawables) item.draw();

    // 4. Projectiles & FX
    for (const a of this.arrows) a.draw(ctx);
    for (const b of this.boomerangs) b.draw(ctx);
    this.fx.draw(ctx);

    // 5. Act 1 Fog border
    this.world.drawAct1Fog(ctx);

    ctx.restore();

    // 6. Day / Dusk / Night / Blood Moon atmospheric tint overlay
    this._drawTimeTint(ctx, cw, ch);

    // 7. Yellow BASE directional arrow when exploring far from farmhouse
    this._drawBaseTrackerArrow(ctx, cw, ch);
  }

  _drawTimeTint(ctx, cw, ch) {
    let overlay = null;
    if (this.state === STATE.NIGHT) {
      if (this.isBloodMoon) overlay = "rgba(130, 14, 18, 0.34)";
      else if (this.isEvenMoon) overlay = "rgba(74, 22, 54, 0.34)";
      else overlay = "rgba(18, 24, 62, 0.44)";
    } else if (this.state === STATE.DAY && this.phaseTimer <= 18) {
      const t = Math.max(0, Math.min(1, 1 - this.phaseTimer / 18));
      overlay = `rgba(98, 42, 30, ${(t * 0.24).toFixed(2)})`;
    }
    if (overlay) {
      ctx.fillStyle = overlay;
      ctx.fillRect(0, 0, cw, ch);
    }
  }

  _drawBaseTrackerArrow(ctx, cw, ch) {
    if (this.player.insideHouse) return;
    const d = dist(this.player.x, this.player.y, Config.HOUSE_CENTER.x, Config.HOUSE_CENTER.y);
    if (d < Config.BASE_TRACKER_MIN_PX || d > Config.BASE_TRACKER_MAX_PX) return;

    const ang = Math.atan2(Config.HOUSE_CENTER.y - this.player.y, Config.HOUSE_CENTER.x - this.player.x);
    const padX = 48;
    const padY = 64;
    const cx = cw * 0.5 + Math.cos(ang) * (cw * 0.5 - padX);
    const cy = ch * 0.5 + Math.sin(ang) * (ch * 0.5 - padY);

    ctx.save();
    ctx.translate(Math.round(cx), Math.round(cy));
    ctx.rotate(ang);
    ctx.fillStyle = "#ffe056";
    ctx.strokeStyle = "#1a1020";
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(9, 0);
    ctx.lineTo(-6, -6);
    ctx.lineTo(-2, 0);
    ctx.lineTo(-6, 6);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    ctx.restore();

    ctx.save();
    ctx.font = 'bold 8px "PixelOp", monospace';
    ctx.textAlign = "center";
    ctx.fillStyle = "#09070f";
    const meters = Math.round(d / 16);
    ctx.fillText(`BASE ${meters}m`, Math.round(cx + 1), Math.round(cy + 16));
    ctx.fillStyle = "#ffe66c";
    ctx.fillText(`BASE ${meters}m`, Math.round(cx), Math.round(cy + 15));
    ctx.restore();
  }
}

const game = new MoonriseGame();
game.start();
