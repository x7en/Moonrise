// Multi-touch mobile controller + unified keyboard/mouse input bridge

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
    this.joyVec = { x: 0, y: 0 };
    this.joyPointerId = null;
    this.joyOrigin = { x: 0, y: 0 };
    this.joyMaxRadius = 40;

    this.interactHeld = false;
    this.interactPointerId = null;
    this.interactDownTime = 0;
    this.gatherCompletedDuringHold = false;

    this.detectedTouch =
      window.matchMedia("(pointer: coarse)").matches ||
      (navigator.maxTouchPoints && navigator.maxTouchPoints > 0);
    this.touchMode = "auto";
    this.gameplayActive = false;

    this._bindJoystick();
    this._bindTouchButtons();
    this._bindKeyboard();

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
    this.joyPointerId = null;
    this.joyVec = { x: 0, y: 0 };
    this.joyBase.classList.remove("active");
    this.joyBase.style.left = "";
    this.joyBase.style.bottom = "";
    this.joyBase.style.top = "";
    this.joyKnob.style.transform = "translate(0px, 0px)";
    this.interactHeld = false;
    this.interactPointerId = null;
    this.btns.interact.classList.remove("pressed");
  }

  getMoveVector() {
    let kx =
      (this.keys.has("KeyD") || this.keys.has("ArrowRight") ? 1 : 0) -
      (this.keys.has("KeyA") || this.keys.has("ArrowLeft") ? 1 : 0);
    let ky =
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

    // Dynamic Interact button label
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

  _bindJoystick() {
    this.joyZone.addEventListener("pointerdown", (e) => {
      if (this.joyPointerId !== null) return;
      e.preventDefault();
      e.stopPropagation();
      this.handlers.onAnyGesture();
      this.joyPointerId = e.pointerId;
      this.joyZone.setPointerCapture(e.pointerId);

      const zoneRect = this.joyZone.getBoundingClientRect();
      const baseSize = this.joyBase.offsetWidth || 100;
      const half = baseSize * 0.5;
      this.joyMaxRadius = baseSize * 0.38;

      // Floating origin clamped inside the joystick zone
      const lx = Math.max(half + 6, Math.min(zoneRect.width - half - 6, e.clientX - zoneRect.left));
      const ly = Math.max(half + 6, Math.min(zoneRect.height - half - 6, e.clientY - zoneRect.top));

      this.joyOrigin = { x: zoneRect.left + lx, y: zoneRect.top + ly };
      this.joyBase.style.left = `${lx - half}px`;
      this.joyBase.style.top = `${ly - half}px`;
      this.joyBase.style.bottom = "auto";
      this.joyBase.classList.add("active");
      this._updateJoystick(e.clientX, e.clientY);
    });

    this.joyZone.addEventListener("pointermove", (e) => {
      if (e.pointerId !== this.joyPointerId) return;
      e.preventDefault();
      this._updateJoystick(e.clientX, e.clientY);
    });

    const endJoy = (e) => {
      if (e.pointerId !== this.joyPointerId) return;
      e.preventDefault();
      this.joyPointerId = null;
      this.joyVec = { x: 0, y: 0 };
      this.joyBase.classList.remove("active");
      this.joyBase.style.left = "";
      this.joyBase.style.top = "";
      this.joyBase.style.bottom = "";
      this.joyKnob.style.transform = "translate(0px, 0px)";
    };

    this.joyZone.addEventListener("pointerup", endJoy);
    this.joyZone.addEventListener("pointercancel", endJoy);
  }

  _updateJoystick(clientX, clientY) {
    const dx = clientX - this.joyOrigin.x;
    const dy = clientY - this.joyOrigin.y;
    const dist = Math.hypot(dx, dy);
    const maxR = this.joyMaxRadius;
    const clamped = Math.min(dist, maxR);
    const ang = Math.atan2(dy, dx);
    const kx = Math.cos(ang) * clamped;
    const ky = Math.sin(ang) * clamped;
    this.joyKnob.style.transform = `translate(${kx.toFixed(1)}px, ${ky.toFixed(1)}px)`;

    const norm = clamped / maxR;
    if (norm < 0.14) {
      this.joyVec = { x: 0, y: 0 };
    } else {
      const scaled = (norm - 0.14) / 0.86;
      this.joyVec = { x: Math.cos(ang) * scaled, y: Math.sin(ang) * scaled };
    }
  }

  _bindInstantBtn(el, fn) {
    el.addEventListener("pointerdown", (e) => {
      e.preventDefault();
      e.stopPropagation();
      this.handlers.onAnyGesture();
      el.classList.add("pressed");
      fn();
    });
    const clear = () => el.classList.remove("pressed");
    el.addEventListener("pointerup", clear);
    el.addEventListener("pointercancel", clear);
    el.addEventListener("pointerleave", clear);
  }

  _bindTouchButtons() {
    this._bindInstantBtn(this.btns.attack, () => this.handlers.onPrimaryAttack());
    this._bindInstantBtn(this.btns.spear, () => this.handlers.onSpear());
    this._bindInstantBtn(this.btns.reload, () => this.handlers.onReload());
    this._bindInstantBtn(this.btns.shock, () => this.handlers.onShockwave());
    this._bindInstantBtn(this.btns.home, () => this.handlers.onRecallHome());

    // Interact button supports BOTH quick tap (doors/gates) AND press-and-hold (chop trees / search wrecks)
    this.btns.interact.addEventListener("pointerdown", (e) => {
      e.preventDefault();
      e.stopPropagation();
      this.handlers.onAnyGesture();
      this.interactPointerId = e.pointerId;
      this.btns.interact.setPointerCapture(e.pointerId);
      this.btns.interact.classList.add("pressed");
      this.interactHeld = true;
      this.interactDownTime = performance.now();
      this.gatherCompletedDuringHold = false;
    });

    const endInteract = (e) => {
      if (e.pointerId !== this.interactPointerId) return;
      e.preventDefault();
      this.interactPointerId = null;
      this.interactHeld = false;
      this.btns.interact.classList.remove("pressed");
      const heldMs = performance.now() - this.interactDownTime;
      if (!this.gatherCompletedDuringHold && heldMs < 360) {
        this.handlers.onInteractTap();
      }
    };
    this.btns.interact.addEventListener("pointerup", endInteract);
    this.btns.interact.addEventListener("pointercancel", endInteract);

    // Contextual popup buttons
    this._bindInstantBtn(this.btns.tame, () => this.handlers.onTameDog());
    this._bindInstantBtn(this.btns.upgrade, () => this.handlers.onUpgrade());
    this._bindInstantBtn(this.btns.dogMode, () => this.handlers.onToggleDog());
    this._bindInstantBtn(this.btns.trapPlace, () => this.handlers.onPlaceTrapForward());
    this._bindInstantBtn(this.btns.trapCancel, () => this.handlers.onCancelTrap());
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
      this.keys.clear();
      this.resetTransient();
    });
  }
}
