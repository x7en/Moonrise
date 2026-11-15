import { Config, ACHIEVEMENT_DEFS } from "./config.js";
import { Assets } from "./assets.js";

export class UIController {
  constructor(callbacks) {
    this.cb = callbacks;
    this.el = {
      loading: document.getElementById("loading-screen"),
      loadingStatus: document.getElementById("loading-status"),
      loadingFill: document.getElementById("loading-bar-fill"),

      vignette: document.getElementById("danger-vignette"),
      hud: document.getElementById("hud"),
      hpFill: document.getElementById("hp-bar-fill"),
      hpLabel: document.getElementById("hp-label"),
      houseIcon: document.getElementById("house-icon"),
      houseLabel: document.getElementById("house-label"),
      bagLabel: document.getElementById("bag-label"),
      dayLabel: document.getElementById("day-label"),
      objLabel: document.getElementById("objective-label"),
      weaponLabel: document.getElementById("weapon-label"),
      cdLabel: document.getElementById("cooldown-label"),
      statusBanner: document.getElementById("status-banner"),
      headerBanner: document.getElementById("header-banner"),
      headerTitle: document.getElementById("header-title"),
      headerSub: document.getElementById("header-sub"),
      hudToast: document.getElementById("hud-toast"),
      searchBar: document.getElementById("search-bar"),
      searchFill: document.getElementById("search-bar-fill"),
      promptLabel: document.getElementById("prompt-label"),
      trapMeta: document.getElementById("trap-meta"),
      trapSlots: [...document.querySelectorAll(".trap-slot")],
      trapSlotSpans: [
        document.getElementById("trap-slot-1"),
        document.getElementById("trap-slot-2"),
        document.getElementById("trap-slot-3"),
      ],
      rotateHint: document.getElementById("rotate-hint"),

      titleScreen: document.getElementById("title-screen"),
      titleSkyCanvas: document.getElementById("title-sky-canvas"),
      btnContinue: document.getElementById("btn-title-continue"),

      cardsScreen: document.getElementById("cards-screen"),
      cardTitle: document.getElementById("card-title"),
      cardCanvas: document.getElementById("card-art-canvas"),
      cardBody: document.getElementById("card-body"),
      btnCardNext: document.getElementById("btn-card-next"),
      btnCardSkip: document.getElementById("btn-card-skip"),

      nightScreen: document.getElementById("night-intro-screen"),
      nightSkyCanvas: document.getElementById("night-sky-canvas"),
      nightFlash: document.getElementById("night-blood-flash"),
      nightTitle: document.getElementById("night-intro-title"),
      nightNarration: document.getElementById("night-intro-narration"),

      modalScreen: document.getElementById("modal-screen"),
      modalTitle: document.getElementById("modal-title"),
      modalSubtitle: document.getElementById("modal-subtitle"),
      modalList: document.getElementById("modal-list"),
      modalFooter: document.getElementById("modal-footer"),

      endScreen: document.getElementById("end-screen"),
      endTitle: document.getElementById("end-title"),
      endBody: document.getElementById("end-body"),
      btnEndRetry: document.getElementById("btn-end-retry"),

      achToast: document.getElementById("ach-toast"),
      achIcon: document.getElementById("ach-toast-icon"),
      achTitle: document.getElementById("ach-toast-title"),
      achDesc: document.getElementById("ach-toast-desc"),
    };

    this.headerTimer = 0;
    this.toastTimer = 0;
    this.achQueue = [];
    this.achTimer = 0;
    this.rotateDismissed = false;

    this.cardQueue = [];
    this.cardIdx = 0;
    this.cardOnDone = null;
    this.cardLock = 0;

    this._bindButtons();
    this._checkOrientation();
    window.addEventListener("resize", () => this._checkOrientation());
  }

  _bindButtons() {
    document.getElementById("btn-title-continue").addEventListener("click", () => this.cb.onPlay(true));
    document.getElementById("btn-title-play").addEventListener("click", () => this.cb.onPlay(false));
    document.getElementById("btn-title-tutorial").addEventListener("click", () => this.cb.onTutorial(true));
    document.getElementById("btn-title-controls").addEventListener("click", () => this.cb.onInfoPanel("controls"));
    document.getElementById("btn-title-settings").addEventListener("click", () => this.cb.onInfoPanel("settings"));
    document.getElementById("btn-title-achievements").addEventListener("click", () => this.cb.onInfoPanel("achievements"));
    document.getElementById("btn-title-credits").addEventListener("click", () => this.cb.onInfoPanel("credits"));

    document.getElementById("btn-hud-inv").addEventListener("click", () => this.cb.onOpenInventory());
    document.getElementById("btn-hud-craft").addEventListener("click", () => this.cb.onOpenCrafting());
    document.getElementById("btn-hud-dbg").addEventListener("click", () => this.cb.onOpenDebug?.());
    document.getElementById("btn-hud-pause").addEventListener("click", () => this.cb.onOpenPause());
    document.getElementById("btn-hud-fs").addEventListener("click", () => this.cb.onToggleFullscreen());

    document.getElementById("btn-modal-close").addEventListener("click", () => this.cb.onCloseModal());
    this.el.modalScreen.addEventListener("click", (e) => {
      if (e.target === this.el.modalScreen) this.cb.onCloseModal();
    });

    document.getElementById("btn-end-retry").addEventListener("click", () => this.cb.onRetryDay());
    document.getElementById("btn-end-new").addEventListener("click", () => this.cb.onPlay(false));
    document.getElementById("btn-end-menu").addEventListener("click", () => this.cb.onReturnToMenu());

    this.el.btnCardNext.addEventListener("click", () => this.advanceCard());
    this.el.btnCardSkip.addEventListener("click", () => this.skipCards());
    this.el.nightScreen.addEventListener("pointerdown", () => this.cb.onSkipNightIntro());

    document.getElementById("btn-dismiss-rotate").addEventListener("click", () => {
      this.rotateDismissed = true;
      this.el.rotateHint.classList.add("hidden");
    });

    for (const btn of this.el.trapSlots) {
      btn.addEventListener("pointerdown", (e) => {
        e.preventDefault();
        e.stopPropagation();
        const slot = Number(btn.dataset.slot);
        this.cb.onTrapSlot(slot);
      });
    }
  }

  _checkOrientation() {
    const portrait = window.innerHeight > window.innerWidth && window.innerWidth < 760;
    const inGame = !this.el.hud.classList.contains("hidden");
    this.el.rotateHint.classList.toggle("hidden", !portrait || this.rotateDismissed || !inGame);
  }

  setLoadingProgress(done, total) {
    const pct = Math.round((done / Math.max(1, total)) * 100);
    this.el.loadingFill.style.width = `${pct}%`;
    this.el.loadingStatus.textContent = `Loading sprites... ${done}/${total}`;
  }

  hideLoading() {
    this.el.loading.classList.add("hidden");
  }

  showTitle(hasContinue) {
    this.el.titleScreen.classList.remove("hidden");
    this.el.hud.classList.add("hidden");
    this.el.endScreen.classList.add("hidden");
    this.el.cardsScreen.classList.add("hidden");
    this.el.nightScreen.classList.add("hidden");
    this.el.btnContinue.classList.toggle("hidden", !hasContinue);
    this._checkOrientation();
  }

  showGameplay() {
    this.el.titleScreen.classList.add("hidden");
    this.el.endScreen.classList.add("hidden");
    this.el.cardsScreen.classList.add("hidden");
    this.el.nightScreen.classList.add("hidden");
    this.el.hud.classList.remove("hidden");
    this._checkOrientation();
  }

  hideAllScreens() {
    this.el.titleScreen.classList.add("hidden");
    this.el.hud.classList.add("hidden");
    this.el.endScreen.classList.add("hidden");
    this.el.nightScreen.classList.add("hidden");
  }

  showEndScreen(victory, title, body, canRetry) {
    this.el.titleScreen.classList.add("hidden");
    this.el.hud.classList.add("hidden");
    this.el.endScreen.classList.remove("hidden");
    this.el.endTitle.textContent = title;
    this.el.endTitle.style.color = victory ? "#8ef59e" : "#ff6259";
    this.el.endBody.textContent = body;
    this.el.btnEndRetry.classList.toggle("hidden", !canRetry);
  }

  // ==================== STORY & TUTORIAL CARDS ====================
  showCards(cards, onDone) {
    this.cardQueue = cards;
    this.cardIdx = 0;
    this.cardOnDone = onDone;
    this.el.cardsScreen.classList.remove("hidden");
    this._renderCard();
  }

  isCardsOpen() {
    return !this.el.cardsScreen.classList.contains("hidden");
  }

  _renderCard() {
    const card = this.cardQueue[this.cardIdx];
    if (!card) {
      this.skipCards();
      return;
    }
    this.cardLock = 0.22;
    this.el.cardTitle.textContent = card.title;
    this.el.cardTitle.style.color = card.accent || "#fae0c7";
    this.el.cardBody.textContent = card.body;
    const isLast = this.cardIdx >= this.cardQueue.length - 1;
    this.el.btnCardNext.textContent = isLast
      ? "Start / Close"
      : `Continue (${this.cardIdx + 1}/${this.cardQueue.length})`;

    const ctx = this.el.cardCanvas.getContext("2d");
    ctx.imageSmoothingEnabled = false;
    ctx.clearRect(0, 0, 160, 96);

    const art = card.art || "moon";
    if (art === "moon" || art === "blood_moon") {
      const img = Assets.get(art === "blood_moon" ? "sky/blood_moon" : "sky/moon");
      if (img) ctx.drawImage(img, 48, 16, 64, 64);
    } else if (art === "house") {
      const img = Assets.get("house/lv1");
      if (img) ctx.drawImage(img, 16, 0, 128, 96);
    } else if (art === "dog") {
      Assets.drawDogFeet(ctx, "dog/idle_right", 0, 80, 74, 1.35);
    } else if (art === "bow") {
      const img = Assets.get("weapons/bow");
      if (img) ctx.drawImage(img, 48, 16, 64, 64);
    } else if (art === "boomerang") {
      const img = Assets.get("placeholders/boomerang_placeholder");
      if (img) ctx.drawImage(img, 44, 12, 72, 72);
    } else if (art === "trap_snare") {
      const img = Assets.get("traps/snare");
      if (img) ctx.drawImage(img, 44, 12, 72, 72);
    }
  }

  advanceCard() {
    if (!this.isCardsOpen() || this.cardLock > 0) return;
    this.cardIdx++;
    if (this.cardIdx >= this.cardQueue.length) {
      this.skipCards();
    } else {
      this._renderCard();
    }
  }

  skipCards() {
    if (!this.isCardsOpen()) return;
    this.el.cardsScreen.classList.add("hidden");
    const cb = this.cardOnDone;
    this.cardOnDone = null;
    if (cb) cb();
  }

  // ==================== HEADER BANNER, TOASTS, HUD ====================
  showHeaderBanner(title, sub, color = "#ffdf80", duration = 2.6) {
    this.el.headerTitle.textContent = title;
    this.el.headerTitle.style.color = color;
    this.el.headerSub.textContent = sub;
    this.el.headerBanner.classList.remove("hidden");
    this.el.headerBanner.style.opacity = "1";
    this.headerTimer = duration;
  }

  showToast(text, duration = 2.0, color = "#ffecad") {
    this.el.hudToast.textContent = text;
    this.el.hudToast.style.color = color;
    this.el.hudToast.classList.remove("hidden");
    this.el.hudToast.style.opacity = "1";
    this.toastTimer = duration;
  }

  enqueueAchievement(title, desc, iconKey = "ui/trophy") {
    this.achQueue.push({ title, desc, iconKey });
    if (this.achTimer <= 0) this._popAchievement();
  }

  _popAchievement() {
    if (this.achQueue.length === 0) {
      this.el.achToast.classList.add("hidden");
      return;
    }
    const item = this.achQueue.shift();
    this.el.achIcon.src = `./assets/${item.iconKey}.png`;
    this.el.achTitle.textContent = `Achievement: ${item.title}`;
    this.el.achDesc.textContent = item.desc;
    this.el.achToast.classList.remove("hidden");
    this.achTimer = 3.4;
  }

  stepTimers(dt) {
    if (this.cardLock > 0) this.cardLock = Math.max(0, this.cardLock - dt);
    if (this.headerTimer > 0) {
      this.headerTimer = Math.max(0, this.headerTimer - dt);
      this.el.headerBanner.style.opacity = String(Math.min(1, this.headerTimer / 0.45));
      if (this.headerTimer <= 0) this.el.headerBanner.classList.add("hidden");
    }
    if (this.toastTimer > 0) {
      this.toastTimer = Math.max(0, this.toastTimer - dt);
      this.el.hudToast.style.opacity = String(Math.min(1, this.toastTimer / 0.35));
      if (this.toastTimer <= 0) this.el.hudToast.classList.add("hidden");
    }
    if (this.achTimer > 0) {
      this.achTimer -= dt;
      if (this.achTimer <= 0) this._popAchievement();
    }
  }

  updateHud(d) {
    const hpPct = Math.max(0, Math.min(100, (d.hp / Math.max(1, d.maxHp)) * 100));
    this.el.hpFill.style.width = `${hpPct}%`;
    this.el.hpLabel.textContent = `HP ${d.hp}/${d.maxHp}`;

    if (d.houseFallen) {
      this.el.houseLabel.textContent = "HOUSE FALLEN!";
      this.el.houseLabel.style.color = "#ff6b5c";
      this.el.houseIcon.src = "./assets/ui/danger.png";
    } else {
      const doorTag = d.doorOpen ? "OPEN!" : "Shut";
      this.el.houseLabel.textContent = `House ${d.houseHp}/${d.houseMax} (${doorTag})`;
      this.el.houseLabel.style.color = d.doorOpen ? "#ffb859" : "#daf0de";
      this.el.houseIcon.src = d.intruders > 0 ? "./assets/ui/danger.png" : "./assets/ui/house.png";
    }

    this.el.bagLabel.textContent = `Bag ${d.bagUsed}/${d.bagCap} P:${d.bagPlanks} S:${d.bagScrap} | Stock P:${d.stockPlanks} S:${d.stockScrap}`;

    const sec = Math.max(0, Math.ceil(d.timer));
    const mm = String(Math.floor(sec / 60)).padStart(2, "0");
    const ss = String(sec % 60).padStart(2, "0");
    if (d.isNight) {
      const tag = d.isBloodMoon ? "BLOOD MOON" : d.isEvenMoon ? "EVEN MOON" : "NIGHT";
      this.el.dayLabel.textContent = `${tag} ${d.day} — ${mm}:${ss}`;
      this.el.dayLabel.style.color = d.isBloodMoon ? "#ff665c" : d.isEvenMoon ? "#f278a8" : "#98b8ff";
    } else {
      this.el.dayLabel.textContent = `Day ${d.day} (Act ${d.act}) — ${mm}:${ss}`;
      this.el.dayLabel.style.color = d.timer <= 15 ? "#ffae64" : "#ffdf80";
    }
    this.el.objLabel.textContent = d.objective;

    // Weapon status
    if (d.weapon === "boomerang") {
      this.el.weaponLabel.textContent = d.rangFlying
        ? "Boomerang: IN FLIGHT"
        : d.rangCd > 0.05
          ? `Boomerang: CD ${d.rangCd.toFixed(1)}s`
          : "Boomerang: Ready";
    } else if (d.weapon === "spear") {
      this.el.weaponLabel.textContent = `Spear Lv${d.gearTier} (Melee)`;
    } else {
      this.el.weaponLabel.textContent = d.reloading
        ? `Bow: Reloading ${d.reloadLeft.toFixed(1)}s`
        : `Bow ${d.bowMag}/${d.bowMagMax} (${d.arrows})`;
    }

    const shockStr = d.shockCd > 0.05 ? `Shock ${Math.ceil(d.shockCd)}s` : "Shock RDY";
    const homeStr = d.recallCd > 0.05 ? `Home ${Math.ceil(d.recallCd)}s` : "Home RDY";
    this.el.cdLabel.textContent = `${shockStr} | ${homeStr}`;

    // Status warning
    if (d.statusText) {
      this.el.statusBanner.textContent = d.statusText;
      this.el.statusBanner.classList.remove("hidden");
    } else {
      this.el.statusBanner.classList.add("hidden");
    }

    // Low HP / Blood Moon vignette
    const lowHpAlpha = d.hp <= d.maxHp * 0.3 ? 0.55 : d.isBloodMoon ? 0.25 : 0;
    this.el.vignette.classList.toggle("hidden", lowHpAlpha <= 0);
    this.el.vignette.style.opacity = String(lowHpAlpha);

    // Search/chop progress bar
    if (d.searchProgress > 0) {
      this.el.searchBar.classList.remove("hidden");
      this.el.searchFill.style.width = `${Math.round(d.searchProgress * 100)}%`;
    } else {
      this.el.searchBar.classList.add("hidden");
    }

    // Prompt text
    if (d.prompt) {
      this.el.promptLabel.textContent = d.prompt;
      this.el.promptLabel.classList.remove("hidden");
    } else {
      this.el.promptLabel.classList.add("hidden");
    }

    // Trap hotbar
    const counts = [d.nSnare, d.nSpike, d.nLure];
    const names = ["Bear", "Spike", "Lure"];
    this.el.trapMeta.textContent = `Traps Left: ${d.nSnare + d.nSpike + d.nLure} | Placed ${d.trapsPlaced}/${Config.MAX_TRAPS}`;
    for (let i = 0; i < 3; i++) {
      this.el.trapSlotSpans[i].textContent = `${names[i]} x${counts[i]}`;
      const active = d.trapMode && d.selectedTrap === i + 1;
      this.el.trapSlots[i].classList.toggle("active", active);
      this.el.trapSlots[i].classList.toggle("empty", counts[i] <= 0 && !active);
    }
  }

  // ==================== MODAL PANELS ====================
  openModal(title, subtitle, footer, items) {
    this.el.modalTitle.textContent = title;
    this.el.modalSubtitle.textContent = subtitle || "";
    this.el.modalFooter.textContent = footer || "";
    this.el.modalList.innerHTML = "";

    for (const item of items) {
      if (item.type === "kv") {
        const row = document.createElement("div");
        row.className = "modal-kv";
        const k = document.createElement("span");
        k.className = "modal-kv-key";
        k.textContent = item.key;
        const v = document.createElement("span");
        v.className = "modal-kv-val";
        v.textContent = item.val;
        row.append(k, v);
        this.el.modalList.appendChild(row);
      } else {
        const btn = document.createElement("button");
        btn.type = "button";
        btn.className = `modal-row-btn${item.equipped ? " equipped" : ""}`;
        btn.disabled = Boolean(item.disabled);
        const top = document.createElement("div");
        top.className = "modal-row-top";
        const l = document.createElement("span");
        l.textContent = item.label;
        top.appendChild(l);
        if (item.right) {
          const r = document.createElement("span");
          r.style.color = item.disabled ? "#ff928a" : "#ffe07d";
          r.textContent = item.right;
          top.appendChild(r);
        }
        btn.appendChild(top);
        if (item.desc) {
          const desc = document.createElement("div");
          desc.className = "modal-row-desc";
          desc.textContent = item.desc;
          btn.appendChild(desc);
        }
        btn.addEventListener("click", () => {
          if (item.onClick) item.onClick();
        });
        this.el.modalList.appendChild(btn);
      }
    }

    this.el.modalScreen.classList.remove("hidden");
  }

  closeModal() {
    this.el.modalScreen.classList.add("hidden");
  }

  isModalOpen() {
    return !this.el.modalScreen.classList.contains("hidden");
  }

  // ==================== ACHIEVEMENTS PANEL HELPER ====================
  buildAchievementItems(save) {
    return Object.entries(ACHIEVEMENT_DEFS).map(([id, def]) => {
      const done = Boolean(save.unlocked[id]);
      return {
        type: "kv",
        key: `${done ? "[DONE] " : "[ ] "}${def.title}`,
        val: def.desc,
      };
    });
  }
}
