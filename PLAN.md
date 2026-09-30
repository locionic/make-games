# Dice Fate — Game Development & Release Plan

> **Design Principle**: *Juice is a multiplier on depth.* Do not polish a 3-tap loop that plays itself. Every system added must expand player agency, tactical trade-offs, and turn-to-turn tension before tuning flat percentages or adding visual polish.

---

## The Core Diagnosis

In the current game, combat is: **Roll $\rightarrow$ re-roll lowest numbers $\rightarrow$ End Turn**.
The player does not make decisions; they run a greedy algorithm:
1. Look for 0s or low numbers.
2. Tap them.
3. Tap Re-roll.
4. Tap End Turn.

Tweaking `BLESS` from 7.3% to 12% or adding floating damage numbers does not change this. Polishing the game before fixing the turn loop would only mask the lack of depth.

This plan puts **Phase 0: The Decision Space** at the very front.

---

## Phase 0: Deepening the Turn Decision Space (Priority 1)
*Objective: Transform every turn from an automatic greedy algorithm into an active tactical dilemma with competing resources and risk/reward choices.*

### 0.1 The Second Per-Turn Spend: Focus vs. Gamble
- **Problem**: Re-rolling is the *only* button. The only choice is "gamble on this die or keep it".
- **Design**: Introduce a per-turn tactical resource alongside re-rolls:
  - **Focus (Nudge)**: Instead of spending a reroll to gamble, the player can spend a Focus charge to nudge a die up one face step (or lock in a guaranteed bump).
  - **Tension**: Do you spend your budget gambling on a re-roll of Sunder (could roll 0 or 14), or do you use Focus to guarantee Blade steps from 5 to 7 to meet lethal threshold?
  - **Implementation**:
    - Extend `dice.gd:Encounter` with `focus_left` and `nudge_die(index)`.
    - Add a "Focus" / "Nudge" button to `fight.gd`.

### 0.2 Die Banking (Hold for Next Turn)
- **Problem**: Every die must be spent on the current turn. If the enemy attacks for 0 or you already have lethal, defensive dice rolled this turn are completely wasted.
- **Design**: Allow the player to **Bank (Hold)** 1 die across turns (it stays on the board, locked on its rolled face for the next turn, but doesn't resolve its stats this turn).
  - **Tension**: Do you cash in Ward's 9 block now against a weak 3-damage attack, or bank it to survive next turn's telegraphed Enraged strike?
  - **Implementation**:
    - `Encounter.banked_die` in `dice.gd`.
    - UI toggle on long-press or tap-to-bank slot in `fight.gd`.

### 0.3 Status Conditions & Threshold Triggers (Synergies)
- **Problem**: Combat is purely linear subtraction (`dealt = dmg - armor`, `hp -= hit - block`).
- **Design**: Introduce 2–3 sticky status effects that reward dice combinations:
  - **Vulnerable / Exposed**: Hits against an exposed enemy bypass armor or deal +50%.
  - **Sundered / Bleed**: Damage dealt over time, allowing slow defensive builds to win.
  - **Reactive Enemies**: An enemy that counters on rolls > 10, or an enemy that gains armor on small hits < 4 (punishing flat attacks like Blade while rewarding swing attacks like Sunder).

---

## Phase 1: Decision-Driven Synergies & Upgrade Redesign
*Objective: Ensure reward cards (`run.gd`) offer genuine build archetypes that leverage the new mechanics.*

### 1.1 Archetype-Defining Cards
Replace flat "+1 to face" upgrades with upgrades that interact with Phase 0 decisions:
- **Disciplined Mind**: Gain +1 Focus charge every turn, but -1 re-roll. (Enables the precision build).
- **Gambler's Rush**: Re-rolling a die into a higher face deals 3 bonus piercing damage.
- **Bastion Hold**: When a die is banked, gain 4 block immediately.
- **Precision Strike**: Nudging a die to its maximum face applies Exposed to the enemy.

### 1.2 The Offer Table as Strategic Drafting
- Maintain the rule established in `BALANCE.md` (no dead-weight / strictly dominated cards).
- Every card offered must support a distinct axis (Variance/Gamble vs. Focus/Certainty vs. Banking/Stalling).

---

## Phase 2: Empirical Balance Verification
*Objective: Measure the expanded decision space against automated bots and establish the new skill-to-random ratio.*

### 2.1 Update the Headless Bot (`_balance.gd`)
- Teach the simulation bot distinct archetypal strategies:
  1. *Greedy Gambler* (prioritizes re-rolls on swing dice).
  2. *Tactical Nudger* (uses Focus for guaranteed thresholds).
  3. *Banker* (banks defensive dice against low incoming damage).
  4. *Random Player* (plays blindly / baseline).
- Measure: Does the gap between tactical strategies and the random player widen significantly beyond the baseline 2.0x?

### 2.2 Re-tune Outlier Cards & Rules
- With distinct decision paths established, evaluate `BLESS`, acquired-die armor pierce, and paired faces against the new decision-driven gate.
- Record all runs in `BALANCE.md`.

---

## Phase 3: Combat Juice & Audiovisual Polish
*Objective: Multiply the player's emotional engagement now that the underlying decisions have real weight.*

### 3.1 Tactile Dice Feel
- Add face cycling/tumbling during the roll phase in `fight.gd`.
- Visual cues for banked dice (glowing border / tucked slot).
- Distinct animations for a "Nudged" die (gold flash, rising tick) vs a "Re-rolled" die (spin, clatter).

### 3.2 Floating Combat Feedback & Audio Stings
- Floating numbers for damage dealt, damage blocked, armor deflection, and status infliction.
- Haptic pulses on Android (`Input.vibrate_handheld(25)`) for heavy hits and boss attacks.
- Screen impact micro-shake on critical thresholds.

---

## Phase 4: Platform Builds, QA & Store Launch
*Objective: Deliver a solid, tested package to players.*

### 4.1 Real Hardware Validation (Android)
- Deploy `dicefate-release.aab` to a physical Android device.
- Test touch ergonomics for the new buttons (Focus, Bank, Re-roll) on small screens (540x960 baseline).
- Verify audio mix through device speakers and headphone jack.

### 4.2 Web Demo & Community Feedback
- Export to `build/web/` and publish an itch.io private playtest.
- Gather qualitative feedback on whether the Focus and Bank mechanics feel intuitive and rewarding.

### 4.3 Google Play Store Release
- Finalize store metadata in `play/LISTING.md`.
- Upload release bundle to Google Play Console closed testing track.

---

## Verification & Execution Gates

Before moving between phases, all tests must pass:
```bash
# 1. Rules, state & UI load test
godot --headless --path . -s test.gd

# 2. Strategy vs Random empirical balance evaluation
godot --headless --path . -s _balance.gd

# 3. Screenshot layout regression test (ensures UI fits 540x960 cleanly)
#    --check runs the same flow and the same assertions without writing the
#    store art, and exits non-zero on a failed check. Add `--at 360` / `--at 411`
#    to re-measure the touch targets on narrower phones (4.1).
xvfb-run -a godot --path . --rendering-driver opengl3 -s shot.gd -- --check
```

To re-shoot the Play listing (overwrites `play/screenshots/`):
```bash
xvfb-run -a godot --path . --rendering-driver opengl3 -s shot.gd
```
