// Multi-touch mobile controller + unified keyboard/mouse input bridge
// Optimized for low-latency mobile play: follow-thumb joystick, input buffering,
// hold-to-attack, zero-latency instant interact, stuck-input protection, and live debug telemetry.

export class InputController {
  constructor(handlers) {
    this.handlers = handlers;
    this.touchLayer = document.getElementById("touch-layer");
    this.joyZone = document.getElementById("joystick-zone");
    this.joyBase = document.getElementById("joystick-base");
    this.joyKnob = document.getElementById("joystick-knob");

    this.btns = {
      attack: document.getElementById("tc-attack"),
      attackTitle: document.getElementById("tc-attack-title"),
      attackSub: document.getElementById("tc-attack-sub"),
      spear: document.getElementById("tc-spear"),
      interact: document.getElementById("tc-interact"),
      interactTitle: document.getElementById("tc-interact-title"),
      interactSub: document.getElementById("tc-interact-sub"),
      reload: document.getElementById("tc-reload"),
      reloadSub: document.getElementById("tc-reload-sub"),
      shock: document.getElementById("tc-shock"),
      shockSub: document.getElementById("tc-shock-sub"),
      swap: document.getElementById("tc-swap"),
      swapSub: document.getElementById("tc-swap-sub"),
      home: document.getElementById("tc-home"),
      homeSub: document.getElementById("tc-home-sub"),
      tame: document.getElementById("tc-tame"),
      upgrade: document.getElementById("tc-upgrade"),
      dogMode: document.getElementById("tc-dog-mode"),
      trapActions: document.getElementById("tc-trap-actions"),
      trapPlace: document.getElementById("tc-trap-place"),
      trapCancel: document.getElementById("tc-trap-cancel"),
    };

    this.keys = new Set();
    this.activePointers = new Map(); // pointerId -> { x, y, role }

    this.joyVec = { x: 0, y: 0 };
    this.joyRawNorm = 0;
    this.joyPointerId = null;
    this.joyOrigin = { x: 0, y: 0 };
    this.joyMaxRadius = 40;

    // Configurable control-optimization settings
    this.touchMode = "auto";
    this.joyMode = "follow"; // "follow" | "floating" | "fixed"
    this.joyDeadzone = 0.12;
    this.btnScale = 1.0;
    this.touchOpacity = 0.9;
    this.holdToAttack = true;
    this.haptics = true;

    // Hold-to-attack & 120ms input buffering
    this.attackHeld = false;
    this.attackPointerId = null;
    this.spearHeld = false;
    this.spearPointerId = null;
    this.attackBuffer = 0;
    this.spearBuffer = 0;

    // Smart Interact (instant on doors/gates, hold on trees/wrecks)
    this.interactHeld = false;
    this.interactPointerId = null;
    this.interactDownTime = 0;
    this.interactIsHoldAction = false;
    this.interactFiredOnDown = false;
    this.gatherCompletedDuringHold = false;

    this.detectedTouch =
      window.matchMedia("(pointer: coarse)").matches ||
      (navigator.maxTouchPoints && navigator.maxTouchPoints > 0);
    this.gameplayActive = false;

    this._bindJoystick();
    this._bindTouchButtons();
    this._bindKeyboard();
    this._bindGlobalPointerTelemetry();

    window.addEventListener(
      "touchstart",
      () => {
        if (!this.detectedTouch) {
          this.detectedTouch = true;
          this.refreshVisibility();
        }
      },
      { passive: true }
    );
  }

  applyControlSettings(cfg) {
    if (!cfg) return;
    if (cfg.touchMode) this.touchMode = cfg.touchMode;
    if (cfg.joyMode) this.joyMode = cfg.joyMode;
    if (typeof cfg.joyDeadzone === "number") this.joyDeadzone = cfg.joyDeadzone;
    if (typeof cfg.btnScale === "number") this.btnScale = cfg.btnScale;
    if (typeof cfg.touchOpacity === "number") this.touchOpacity = cfg.touchOpacity;
    if (typeof cfg.holdToAttack === "boolean") this.holdToAttack = cfg.holdToAttack;
    if (typeof cfg.haptics === "boolean") this.haptics = cfg.haptics;

    if (this.touchLayer && this.touchLayer.style && typeof this.touchLayer.style.setProperty === "function") {
      this.touchLayer.style.setProperty("--tc-scale", String(this.btnScale));
      this.touchLayer.style.setProperty("--tc-opacity", String(this.touchOpacity));
    }
    this.refreshVisibility();
  }

  haptic(ms = 10) {
    if (!this.haptics) return;
    try {
      if (navigator && typeof navigator.vibrate === "function") {
        navigator.vibrate(ms);
      }
    } catch {
      // Ignore on unsupported browsers
    }
  }

  setTouchMode(mode) {
    this.touchMode = mode;
    this.refreshVisibility();
  }

  setGameplayActive(active) {
    this.gameplayActive = active;
    if (!active) {
      this.resetTransient();
    }
    this.refreshVisibility();
  }

  isTouchControlsVisible() {
    if (this.touchMode === "on") return true;
    if (this.touchMode === "off") return false;
    return this.detectedTouch;
  }

  refreshVisibility() {
    const show = this.gameplayActive && this.isTouchControlsVisible();
    this.touchLayer.classList.toggle("hidden", !show);
  }

  resetTransient() {
    this.keys.clear();
    this.activePointers.clear();

    this.joyPointerId = null;
    this.joyVec = { x: 0, y: 0 };
    this.joyRawNorm = 0;
    this.joyBase.classList.remove("active");
    this.joyBase.style.left = "";
    this.joyBase.style.bottom = "";
    this.joyBase.style.top = "";
    this.joyKnob.style.transform = "translate(0px, 0px)";

    this.attackHeld = false;
    this.attackPointerId = null;
    this.spearHeld = false;
    this.spearPointerId = null;
    this.attackBuffer = 0;
    this.spearBuffer = 0;

    this.interactHeld = false;
    this.interactPointerId = null;
    this.interactFiredOnDown = false;

    for (const el of Object.values(this.btns)) {
      if (el && el.classList) el.classList.remove("pressed");
    }
  }

  stepBuffers(dt) {
    if (this.attackBuffer > 0) this.attackBuffer = Math.max(0, this.attackBuffer - dt);
    if (this.spearBuffer > 0) this.spearBuffer = Math.max(0, this.spearBuffer - dt);
  }

  wantsPrimaryAttack() {
    if (this.attackBuffer > 0) return true;
    if (!this.holdToAttack) return false;
    return this.attackHeld || this.keys.has("KeyF");
  }

  wantsSpearAttack() {
    if (this.spearBuffer > 0) return true;
    if (!this.holdToAttack) return false;
    return this.spearHeld || this.keys.has("Space");
  }

  consumeAttackBuffer() {
    this.attackBuffer = 0;
  }

  consumeSpearBuffer() {
    this.spearBuffer = 0;
  }

  queuePrimaryBuffer() {
    this.attackBuffer = 0.12;
  }

  queueSpearBuffer() {
    this.spearBuffer = 0.12;
  }

  getMoveVector() {
    const kx =
      (this.keys.has("KeyD") || this.keys.has("ArrowRight") ? 1 : 0) -
      (this.keys.has("KeyA") || this.keys.has("ArrowLeft") ? 1 : 0);
    const ky =
      (this.keys.has("KeyS") || this.keys.has("ArrowDown") ? 1 : 0) -
      (this.keys.has("KeyW") || this.keys.has("ArrowUp") ? 1 : 0);

    if (kx !== 0 || ky !== 0) {
      const l = Math.hypot(kx, ky);
      return { x: kx / l, y: ky / l };
    }
    return { x: this.joyVec.x, y: this.joyVec.y };
  }

  isInteractHeld() {
    return this.keys.has("KeyE") || this.interactHeld;
  }

  notifyGatherCompleted() {
    this.gatherCompletedDuringHold = true;
    this.haptic(16);
  }

  getDebugState() {
    return {
      touchVisible: this.isTouchControlsVisible(),
      touchMode: this.touchMode,
      joyMode: this.joyMode,
      joyDeadzone: this.joyDeadzone,
      joyActive: this.joyPointerId !== null,
      joyOrigin: { ...this.joyOrigin },
      joyMaxRadius: this.joyMaxRadius,
      joyVec: { ...this.joyVec },
      joyRawNorm: this.joyRawNorm,
      keys: [...this.keys],
      attackHeld: this.attackHeld || this.keys.has("KeyF"),
      spearHeld: this.spearHeld || this.keys.has("Space"),
      interactHeld: this.isInteractHeld(),
      attackBuffer: this.attackBuffer,
      spearBuffer: this.spearBuffer,
      pointers: [...this.activePointers.entries()].map(([id, info]) => ({ id, ...info })),
      joyZoneRect: this.joyZone.getBoundingClientRect(),
    };
  }

  updateButtonStates(state) {
    // Primary Attack button reflects equipped weapon or intruder clearing
    if (state.insideHouse) {
      this.btns.attackTitle.textContent = state.intruders > 0 ? "CLEAR" : "SAFE";
      this.btns.attackSub.textContent = state.intruders > 0 ? `${state.intruders} FOE` : "INDOORS";
    } else if (state.weapon === "bow") {
      this.btns.attackTitle.textContent = "FIRE";
      this.btns.attackSub.textContent = `${state.bowMag}/${state.bowMagMax}`;
    } else if (state.weapon === "boomerang") {
      this.btns.attackTitle.textContent = "THROW";
      this.btns.attackSub.textContent = state.rangFlying
        ? "FLYING"
        : state.rangCd > 0.05
          ? `${state.rangCd.toFixed(1)}s`
          : "RANG";
    } else {
      this.btns.attackTitle.textContent = "THRUST";
      this.btns.attackSub.textContent = "SPEAR";
    }

    // Quick Weapon Swap indicator
    if (this.btns.swap && this.btns.swapSub) {
      const shortMap = { bow: "BOW", boomerang: "RANG", spear: "SPEAR" };
      this.btns.swapSub.textContent = shortMap[state.weapon] || "BOW";
      this.btns.swap.classList.toggle("hidden", Boolean(state.insideHouse));
    }

    // Reload button (visible when Bow equipped)
    const showReload = state.weapon === "bow" && !state.insideHouse;
    this.btns.reload.classList.toggle("hidden", !showReload);
    if (showReload) {
      this.btns.reloadSub.textContent = state.reloading
        ? `${state.reloadLeft.toFixed(1)}s`
        : `${state.bowMag}/${state.arrows}`;
      this.btns.reload.classList.toggle("on-cd", state.reloading || state.bowMag >= state.bowMagMax);
    }

    // Shockwave cooldown
    const shockCd = state.shockCd > 0.05;
    this.btns.shock.classList.toggle("on-cd", shockCd);
    this.btns.shockSub.textContent = shockCd ? `${Math.ceil(state.shockCd)}s` : "RDY";

    // Recall Home cooldown
    const homeCd = state.recallCd > 0.05 || state.insideHouse;
    this.btns.home.classList.toggle("on-cd", homeCd);
    this.btns.homeSub.textContent = state.recallCd > 0.05 ? `${Math.ceil(state.recallCd)}s` : "RDY";

    // Dynamic Interact button label + instant-vs-hold hint
    this.interactIsHoldAction = Boolean(state.interactIsHold);
    this.btns.interactTitle.textContent = state.interactLabel || "ACT";
    this.btns.interactSub.textContent = state.interactSub || "TAP/HOLD";

    // Contextual popup buttons
    this.btns.tame.classList.toggle("hidden", !state.canTameDog);
    this.btns.upgrade.classList.toggle("hidden", !state.canUpgrade);
    if (state.canUpgrade && state.upgradeLabel) {
      this.btns.upgrade.textContent = state.upgradeLabel;
    }
    this.btns.dogMode.classList.toggle("hidden", !state.hasTamedDog);
    if (state.hasTamedDog) {
      this.btns.dogMode.textContent = `Dog: ${state.dogModeLabel}`;
    }
    this.btns.trapActions.classList.toggle("hidden", !state.trapMode);
  }

  _bindGlobalPointerTelemetry() {
    window.addEventListener("pointerdown", (e) => {
      if (typeof e.pointerId === "number") {
        this.activePointers.set(e.pointerId, { x: e.clientX, y: e.clientY, role: "screen" });
      }
    });
    window.addEventListener("pointermove", (e) => {
      if (this.activePointers.has(e.pointerId)) {
        const cur = this.activePointers.get(e.pointerId);
        cur.x = e.clientX;
        cur.y = e.clientY;
      }
    });
    const rm = (e) => this.activePointers.delete(e.pointerId);
    window.addEventListener("pointerup", rm);
    window.addEventListener("pointercancel", rm);
  }

  _bindJoystick() {
    this.joyZone.addEventListener("pointerdown", (e) => {
      if (this.joyPointerId !== null) return;
      e.preventDefault();
      e.stopPropagation();
      this.handlers.onAnyGesture();
      this.joyPointerId = e.pointerId;
      this.joyZone.setPointerCapture(e.pointerId);
      this.activePointers.set(e.pointerId, { x: e.clientX, y: e.clientY, role: "joy" });

      const zoneRect = this.joyZone.getBoundingClientRect();
      const baseRect = this.joyBase.getBoundingClientRect();
      const baseSize = this.joyBase.offsetWidth || baseRect.width || 100;
      const half = baseSize * 0.5;
      this.joyMaxRadius = Math.max(28, baseSize * 0.39);

      if (this.joyMode === "fixed") {
        this.joyOrigin = {
          x: baseRect.left + half,
          y: baseRect.top + half,
        };
      } else {
        // Floating / Follow origin clamped cleanly inside the joystick zone
        const lx = Math.max(half + 6, Math.min(zoneRect.width - half - 6, e.clientX - zoneRect.left));
        const ly = Math.max(half + 6, Math.min(zoneRect.height - half - 6, e.clientY - zoneRect.top));
        this.joyOrigin = { x: zoneRect.left + lx, y: zoneRect.top + ly };
        this.joyBase.style.left = `${lx - half}px`;
        this.joyBase.style.top = `${ly - half}px`;
        this.joyBase.style.bottom = "auto";
      }

      this.joyBase.classList.add("active");
      this._updateJoystick(e.clientX, e.clientY);
    });

    this.joyZone.addEventListener("pointermove", (e) => {
      if (e.pointerId !== this.joyPointerId) return;
      e.preventDefault();
      this.activePointers.set(e.pointerId, { x: e.clientX, y: e.clientY, role: "joy" });
      this._updateJoystick(e.clientX, e.clientY);
    });

    const endJoy = (e) => {
      if (e.pointerId !== this.joyPointerId) return;
      e.preventDefault();
      this.activePointers.delete(e.pointerId);
      this.joyPointerId = null;
      this.joyVec = { x: 0, y: 0 };
      this.joyRawNorm = 0;
      this.joyBase.classList.remove("active");
      this.joyBase.style.left = "";
      this.joyBase.style.top = "";
      this.joyBase.style.bottom = "";
      this.joyKnob.style.transform = "translate(0px, 0px)";
    };

    this.joyZone.addEventListener("pointerup", endJoy);
    this.joyZone.addEventListener("pointercancel", endJoy);
    this.joyZone.addEventListener("lostpointercapture", endJoy);
  }

  _updateJoystick(clientX, clientY) {
    let dx = clientX - this.joyOrigin.x;
    let dy = clientY - this.joyOrigin.y;
    let d = Math.hypot(dx, dy);
    const maxR = this.joyMaxRadius;

    // Follow-thumb dynamic recentering: if thumb drifts far beyond rim, gently slide origin inside zone
    if (this.joyMode === "follow" && d > maxR * 1.22) {
      const pull = d - maxR * 1.15;
      const ux = dx / d;
      const uy = dy / d;
      const zoneRect = this.joyZone.getBoundingClientRect();
      const baseSize = this.joyBase.offsetWidth || 100;
      const half = baseSize * 0.5;
      const nextOriginX = Math.max(
        zoneRect.left + half + 6,
        Math.min(zoneRect.right - half - 6, this.joyOrigin.x + ux * pull)
      );
      const nextOriginY = Math.max(
        zoneRect.top + half + 6,
        Math.min(zoneRect.bottom - half - 6, this.joyOrigin.y + uy * pull)
      );
      this.joyOrigin.x = nextOriginX;
      this.joyOrigin.y = nextOriginY;
      this.joyBase.style.left = `${nextOriginX - zoneRect.left - half}px`;
      this.joyBase.style.top = `${nextOriginY - zoneRect.top - half}px`;
      dx = clientX - this.joyOrigin.x;
      dy = clientY - this.joyOrigin.y;
      d = Math.hypot(dx, dy);
    }

    const clamped = Math.min(d, maxR);
    const ang = Math.atan2(dy, dx);
    const kx = Math.cos(ang) * clamped;
    const ky = Math.sin(ang) * clamped;
    this.joyKnob.style.transform = `translate(${kx.toFixed(1)}px, ${ky.toFixed(1)}px)`;

    const norm = clamped / maxR;
    this.joyRawNorm = norm;
    const dz = this.joyDeadzone;
    if (norm < dz) {
      this.joyVec = { x: 0, y: 0 };
    } else {
      const linear = Math.min(1, (norm - dz) / Math.max(0.05, 1 - dz));
      // Gentle precision curve for micro-adjustments near doors & traps, full speed at rim
      const curved = Math.pow(linear, 1.12);
      this.joyVec = { x: Math.cos(ang) * curved, y: Math.sin(ang) * curved };
    }
  }

  _bindInstantBtn(el, fn, hapticMs = 8) {
    if (!el) return;
    el.addEventListener("pointerdown", (e) => {
      e.preventDefault();
      e.stopPropagation();
      this.handlers.onAnyGesture();
      el.classList.add("pressed");
      this.haptic(hapticMs);
      fn();
    });
    const clear = () => el.classList.remove("pressed");
    el.addEventListener("pointerup", clear);
    el.addEventListener("pointercancel", clear);
    el.addEventListener("pointerleave", clear);
  }

  _bindHoldAttackBtn(el, onPress, setHeld, getPointerId, setPointerId, role) {
    if (!el) return;
    el.addEventListener("pointerdown", (e) => {
      e.preventDefault();
      e.stopPropagation();
      this.handlers.onAnyGesture();
      setPointerId(e.pointerId);
      el.setPointerCapture(e.pointerId);
      el.classList.add("pressed");
      setHeld(true);
      this.activePointers.set(e.pointerId, { x: e.clientX, y: e.clientY, role });
      this.haptic(8);
      onPress();
    });
    const end = (e) => {
      if (e.pointerId !== getPointerId()) return;
      e.preventDefault();
      this.activePointers.delete(e.pointerId);
      setPointerId(null);
      setHeld(false);
      el.classList.remove("pressed");
    };
    el.addEventListener("pointerup", end);
    el.addEventListener("pointercancel", end);
    el.addEventListener("lostpointercapture", end);
  }

  _bindTouchButtons() {
    this._bindHoldAttackBtn(
      this.btns.attack,
      () => {
        this.queuePrimaryBuffer();
        this.handlers.onPrimaryAttack();
      },
      (v) => (this.attackHeld = v),
      () => this.attackPointerId,
      (id) => (this.attackPointerId = id),
      "attack"
    );

    this._bindHoldAttackBtn(
      this.btns.spear,
      () => {
        this.queueSpearBuffer();
        this.handlers.onSpear();
      },
      (v) => (this.spearHeld = v),
      () => this.spearPointerId,
      (id) => (this.spearPointerId = id),
      "spear"
    );

    this._bindInstantBtn(this.btns.swap, () => this.handlers.onSwapWeapon?.(), 10);
    this._bindInstantBtn(this.btns.reload, () => this.handlers.onReload(), 8);
    this._bindInstantBtn(this.btns.shock, () => this.handlers.onShockwave(), 14);
    this._bindInstantBtn(this.btns.home, () => this.handlers.onRecallHome(), 14);

    // Smart Interact button:
    // - Fires IMMEDIATELY on pointerdown for doors/gates/exit/tame (0ms latency!)
    // - Smooth press-and-hold when near choppable trees or searchable wrecks
    this.btns.interact.addEventListener("pointerdown", (e) => {
      e.preventDefault();
      e.stopPropagation();
      this.handlers.onAnyGesture();
      this.interactPointerId = e.pointerId;
      this.btns.interact.setPointerCapture(e.pointerId);
      this.btns.interact.classList.add("pressed");
      this.activePointers.set(e.pointerId, { x: e.clientX, y: e.clientY, role: "act" });
      this.interactHeld = true;
      this.interactDownTime = performance.now();
      this.gatherCompletedDuringHold = false;
      this.interactFiredOnDown = false;

      if (!this.interactIsHoldAction) {
        this.interactFiredOnDown = true;
        this.haptic(10);
        this.handlers.onInteractTap();
      }
    });

    const endInteract = (e) => {
      if (e.pointerId !== this.interactPointerId) return;
      e.preventDefault();
      this.activePointers.delete(e.pointerId);
      this.interactPointerId = null;
      this.interactHeld = false;
      this.btns.interact.classList.remove("pressed");
      const heldMs = performance.now() - this.interactDownTime;
      if (!this.interactFiredOnDown && !this.gatherCompletedDuringHold && heldMs < 360) {
        this.handlers.onInteractTap();
      }
      this.interactFiredOnDown = false;
    };
    this.btns.interact.addEventListener("pointerup", endInteract);
    this.btns.interact.addEventListener("pointercancel", endInteract);
    this.btns.interact.addEventListener("lostpointercapture", endInteract);

    // Contextual popup buttons
    this._bindInstantBtn(this.btns.tame, () => this.handlers.onTameDog(), 12);
    this._bindInstantBtn(this.btns.upgrade, () => this.handlers.onUpgrade(), 10);
    this._bindInstantBtn(this.btns.dogMode, () => this.handlers.onToggleDog(), 10);
    this._bindInstantBtn(this.btns.trapPlace, () => this.handlers.onPlaceTrapForward(), 12);
    this._bindInstantBtn(this.btns.trapCancel, () => this.handlers.onCancelTrap(), 8);
  }

  _bindKeyboard() {
    window.addEventListener("keydown", (e) => {
      this.keys.add(e.code);
      if (e.repeat) return;
      this.handlers.onAnyGesture();
      this.handlers.onKeyDown(e);
    });
    window.addEventListener("keyup", (e) => {
      this.keys.delete(e.code);
    });
    window.addEventListener("blur", () => {
      this.resetTransient();
    });
  }
}
