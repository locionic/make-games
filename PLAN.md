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

> **The rule was written down and two cards were breaking it at runtime anyway
> (fixed 2026-09-30, `3b0d28a` and the MEND clamp after it).** "No strictly
> dominated card" reads like a property of the *table*, so it was checked as
> one — every entry's description against its arm in `apply_upgrade` — and the
> table is fine. The violation was in the offer, where a card is not dominated
> by its own description but by the *run state at the moment it is dealt*. Two
> cards were:
>
> - **`ADD_DIE` with every bonus die already in hand.** The pool is 4 of
>   `MAX_DICE` 6, so the size clamp cannot catch it and the card had not been
>   taken, so the once-per-run clamp cannot either. Measured at **14 appearances
>   in 60 draws of three.** Reachable from exactly what the store description
>   advertises: three finished runs, hand chosen.
> - **`MEND` at full health.** Heal 14 is worth 0, the card is consumed anyway,
>   and unlike `ADD_DIE` it carries no clamp at all. Rewards are drawn straight
>   after `absorb`, so a perfectly blocked fight deals it to a full-health
>   player: **24.4% of all reward rolls, and 169 dead picks in 717 deals.** The
>   `_weak_pick` bot reads the biggest headline number, so it took "Heal 14"
>   first and spent a quarter of its picks on nothing — `test.gd`'s 40-run bot
>   went **2/40 → 8/40** when the clamp landed.
>
> The two need different kinds of clamp and that is the useful part. `ADD_DIE`
> is *permanently* inert once you hold them all, so it belongs on the card.
> `MEND` is *transiently* inert — you are full now and hurt in two turns — so
> clamping the card would delete the only heal from the rest of the run.
> Clamping the offer is right for both, and the difference is what tells them
> apart.
>
> `SHARPEN` and `BLESS` were checked for the same shape and cannot have it.
> Measured face-by-face across all seven dice, the roster splits five/two:
> Blade, Sunder, Hex, Spark and Fang carry only damage faces, and only Ward
> (6 block) and Riposte (5) carry only block. A hand is always four, and there
> are only two all-block dice, so a hand always holds something of both kinds
> and neither card can land on an empty pool. That is a property of the roster
> rather than of the cards, which makes it the thing to re-measure if a die is
> ever added — an eighth all-block die would leave a four-of-Ward hand, and
> SHARPEN would become a fourth card with nothing to give.

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

> **Answered 2026-09-30: no. The best policy is 1.46x, and it was never
> measured before.** There is no `2.0x`, no skill-to-random ratio and no
> baseline anywhere in the repo — `grep -rn "2\.0x\|skill.to.random" *.gd`
> returns only `512x512` — so the bullet above recorded a target that nothing
> checked, and the probe it names printed a table without ever computing a
> ratio. `_balance.gd` now prints it on every run, over 1000 trials each at
> `rng.seed = 7000 + i`:
>
> | policy | wins% | vs control | avg depth | vs control |
> |---|---|---|---|---|
> | `dice:nudge` (Tactical Nudger) | 26.4 | **1.46x** | 8.30 | 1.05x |
> | `dice:reach` | 21.0 | 1.16x | 8.19 | 1.04x |
> | `dice:read` | 18.5 | 1.02x | 8.16 | 1.04x |
> | `<random>` (Random Player) | 18.1 | — | 7.88 | — |
> | `dice:swing` (Greedy Gambler) | 14.8 | 0.82x | 7.71 | 0.98x |
> | `dice:chip` | 0.3 | 0.02x | 3.27 | 0.42x |
>
> **Re-measured after the two card clamps below, and the direction is worth
> more than the number.** Every row rose — the Nudger 25.4 → 26.4, the control
> 16.4 → 18.1 — and the ratio *fell*, 1.55x → 1.46x, because the control gained
> more than the best bot did. A fix that removed a dead pick from a quarter of
> all reward rolls helped whoever was wasting the most picks, and that turned
> out to be the bot playing at random. `dice:read` has collapsed to parity with
> the control (18.5 vs 18.1, from 1.12x) and `dice:reach` is the only other
> policy still clearly ahead of it. Do not read the drop as the design getting
> worse: the 12 single-card rows still span 0.98 avg depth against a 0.5 floor,
> and the gate `_balance.gd` actually enforces has not moved.
>
> Two things worth reading off the table. **The Nudger is the best bot in the
> game by a clear margin** — nothing else reaches 22% — which is the strongest
> evidence anywhere in this repo that Phase 0's Focus charge is a real decision
> rather than a second button, since the only policy that presses it is the one
> that wins. And **the depth ratio is 1.05x, not 1.46x**: tactics move the boss
> fight, not how far a run gets, which is the same upgrade/depth bind the
> probe's own notes warn about.
>
> This is deliberately **not** a gate. A hard check at 2.0x would be red on
> every run, and `_check.gd`'s own argument is that a permanently red check is
> a check nobody reads. Whether 1.46x is the skill ceiling this design wants is
> the owner's call — the alternative readings (retune the policies upward, or
> accept that a 9-fight roguelike with one correct policy has a narrow skill
> band) are design decisions, not something to quietly re-tune until a number
> in a plan comes out right.

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

> **`dicefate-release.aab` is not the artifact to deploy (measured 2026-09-30),
> and this bullet is why it matters.** It was built **2026-09-29 15:45:25**.
> Phase 3 landed at **09-30 06:38:06** (`368de82`, "PLAN.md 3.1 tactile dice, 3.2
> floating combat numbers") and `fight.gd` took four more commits after it
> (`79de3f5`, `73238fe`, `d035c37`, `599baac`). The release bundle predates all
> five by **14.9 hours**, so deploying it tests the pre-juice game: no floating
> numbers, no gold-focus tick, no screen shake, no boss haptic, and the old
> touch targets that `79de3f5` and `73238fe` exist to fix.
>
> Measured, not inferred. `fight.gdc` is **15,007 bytes** in
> `dicefate-release.aab` and **20,178** in `dicefate.aab` — the 5,171-byte gap is
> the Phase 3 work. It is the largest *shipped-logic* delta of the five
> scripts, and the qualification matters: `dice.gdc` differs by more, 17,947
> bytes, but that gap is the headless test suite (`2b07efd` alone accounts for
> 248 lines of it) and the release bundle ships no `_check.gdc` at all. Reading
> the biggest delta as the biggest gameplay delta would overstate the case, so
> the claim is scoped to what a player loads.
>
> Audio is *not* a differentiator and is worth saying so explicitly: both
> bundles carry all 9 files and are byte-identical at **1,188,787** bytes of
> imported `.oggvorbisstr`, so the "verify the audio mix" bullet above is
> equally satisfiable by either build. A file-size differential is how this was
> established; see the warning in `play/LISTING.md` about grepping the compiled
> `.gdc`, which returns "absent" for everything including a control string.
>
> **Neither bundle is right for the touch-ergonomics leg, and this note
> originally said "use `dicefate.aab`", which is only half true.** It is the
> better of the two — built after Phase 3, where the release bundle is not — so
> it is the one to sideload for the *juice* and *audio* bullets. But it was
> built at 06:54:37 and the touch-target fix `79de3f5` landed at 12:19:12, so it
> carries the same `custom_minimum_size = Vector2(0, 54)` this leg is supposed
> to be validating. Testing touch targets on it measures the known-bad size.
>
> **Rebuild before the hardware pass — but a rebuild alone is not enough.**
> This leg is a sideload onto a device, so unlike 4.3 it involves no Play
> upload, no `versionCode`, and none of the reuse trap. That part is right. The
> part that was wrong on the first pass: there is no path from here to a
> sideloadable file. `export_presets.cfg` has exactly one Android preset and it
> emits `build/android/dicefate.aab` — an **AAB**, which Android will not
> install directly — and `bundletool` is not on this machine. So rebuilding
> yields another AAB that still cannot be deployed.
>
> Getting an APK therefore needs one of: a second export preset writing `.apk`,
> or `bundletool` installed to convert the AAB. The first means editing
> `export_presets.cfg`, which is the file holding the release keystore password
> in plaintext, so that is a call for the owner and not one to make silently.
> Whichever is chosen, rebuild *after* it — the target file is
> `dicefate.aab`, which is gitignored and therefore unrecoverable once
> overwritten.

> **The paragraph above overstated what an APK costs, and the overstatement was
> the whole reason it read as an owner's decision (corrected 2026-09-30).** It
> says the route is "a second export preset", and a second preset carries its own
> `keystore/release_password`, so the note implied that fixing this would put
> the password in that file a second time. **It would not.** `export_presets.cfg`
> has one Android preset, `export_path="build/android/dicefate.aab"` at line 44
> and `gradle_build/export_format=1` at line 59. Both are non-secret, and both
> change in place:
>
> ```
> export_path="build/android/dicefate.apk"
> gradle_build/export_format=0
> ```
>
> The keystore block at lines 79–81 is **shared, not copied**, because it is one
> preset being re-pointed rather than a second preset existing. So the ask is two
> lines, neither of which is a credential.
>
> Two things had to be established before writing that down, and both are
> counter-intuitive enough to be worth keeping. **The enum runs backwards:**
> index 0 is the APK and index 1 is the AAB, so the preset is correct as written
> and the artifact is an AAB for the right reason. Read from the editor binary's
> own option hint, `Export APK,Export AAB`, and confirmed by the shipped file —
> `export_format=1` is what produced `BundleConfig.pb` and the 114 `base/` +
> 42 `assetPackInstallTime/` entries. Anyone "fixing" it by assuming 1 means APK
> would break the Play upload instead. **And the extension is enforced**, from the
> binary's `Invalid filename! Android APK requires the *.apk extension.` — which
> is why `export_path` has to move with it rather than after it.
>
> The toolchain is not the blocker either, and this is measured rather than
> assumed: `ANDROID_HOME`, `ANDROID_SDK_ROOT`, `gradle`, `apksigner` and
> `zipalign` are all **absent from this shell**, yet a *release-signed* AAB was
> produced at 06:54:37 today — `keytool -printcert -jarfile` gives the
> `CN=Dice Spike` release DN, not `CN=Android Debug`. Signing therefore happened
> through a toolchain this shell cannot see, so an APK export reaches exactly the
> same path.
>
> **One thing this does cost, and it is why it is two steps rather than one:**
> Play will only accept an AAB, so `play/LISTING.md`'s upload checklist and this
> leg cannot both be satisfied by one artifact. Export the APK for the sideload,
> then put both lines back before 4.3. The keystore is not the reason this needs
> the owner's hand; the flip-flop between two release artifacts is.
>
> The naming is actively backwards — the file called "release" is the older
> build — so the artifact name is not evidence of anything; the mtime and the
> `fight.gdc` delta are.

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
#    store art, and exits non-zero on a failed check.
xvfb-run -a godot --path . --rendering-driver opengl3 -s shot.gd -- --check

# 4. The same gate at the widths the layout is not authored on. 4.1's software
#    half: the touch targets are measured in dp, so a target that clears 48dp
#    on the authored 540 canvas is not thereby safe on a narrower phone.
#    Without these, a regression that only appears below 540 ships green.
for dp in 360 411; do
  xvfb-run -a godot --path . --rendering-driver opengl3 -s shot.gd -- --check --at $dp
done
```

> **Run gate 4, not just gate 3.** This was a real gap, not a formality: the
> sweep was added in `3d56b23` and its result was written down nowhere, so a
> person reading this file had no way to know it had been run or what it said.
>
> Measured 2026-09-30, smallest target 74x74 canvas units against a 48dp
> minimum:
>
> | width | smallest target | margin |
> |---|---|---|
> | 540dp (authored) | 74.0 dp | +26.0 |
> | 411dp | 56.3 dp | +8.3 |
> | 360dp | 49.3 dp | **+1.3** |
> | 320dp | 43.9 dp | −4.1, fails by design |
>
> **360dp passes by 1.3dp — 2.7% of the threshold.** That is the narrowest
> width in common use and it is the only one with no room, so the hardware pass
> in 4.1 is worth running for a narrower reason than "does it feel right": it is
> the only evidence that a 49dp target is actually tappable, because the
> software measurement has already said the size is legal and has nothing left
> to say.
>
> The sharper way to put the same number: at 360dp the gate starts failing
> below **72** canvas px, and the smallest target in the game is **74**. Two
> pixels of slack. The whole range from 48 to 71px passes gate 3 at 540dp and
> fails gate 4 at 360dp, because one canvas unit is one dp only on the authored
> width — so gate 3 alone cannot catch it, which is the reason gate 4 exists.
>
> `--at 320` is expected to fail and is not run as a gate; see the note above
> `TOUCH_MIN` in `shot.gd`, which is right about it — 320 is Play's screenshot
> floor, not a screen width anyone holds.

> **Gate 5 exists and is not in this list, which is the point of it.** Every gate
> above runs from source. `_pack.gd` is the only one that runs from an *exported
> pack*, and so the only one that can see the export filter in
> `export_presets.cfg` dropping a file — which is not hypothetical: the Android
> preset excludes `_*.gd`, and `dice.gd` and `run.gd` both `preload`
> `_check.gd`, so a filter matching that glob once took the whole rules layer
> out of the build. A gate 1 that is green says the code is correct on disk. It
> says nothing about what reached the player's phone, and every one of gates
> 1–4 would stay green through exactly that failure.
>
> ```bash
> godot --headless --path . -s _pack.gd -- Android
> ```
>
> It is safe to run at any time, which is worth saying because it does not look
> it: `--export-pack` invites the reading that it writes into `build/`, and it
> does not. `PROBE` is `/tmp/_pack_probe.pck` (`_pack.gd:43`) and the child is
> booted with `--main-pack` from `/tmp`, so it overwrites no gitignored artifact
> and nothing that cannot be regenerated. `play/LISTING.md` tells the releaser
> to run it after a rebuild; that is the right advice in the wrong place — it
> belongs in the gate loop, before the build, not in a release checklist after
> one.

To re-shoot the Play listing (overwrites `play/screenshots/`):
```bash
xvfb-run -a godot --path . --rendering-driver opengl3 -s shot.gd
```
