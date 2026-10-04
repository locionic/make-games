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

> **This diagnosis was right, it is why the plan exists, and it is written in
> present tense about a state Phase 0 removed.**
>
> The greedy algorithm is still in this repo, but as a *measuring instrument*
> rather than as the game — `_balance.gd`'s greedy policy defines it as "re-roll
> the worst face, which never reads the enemy", and every card row in the bench is
> measured under it. That is the better afterlife for a diagnosis: the thing it
> describes became the control the plan is read against, rather than a claim
> about a game that has since changed.
>
> **The one concrete number here is stale, and the task it names was tried and
> dropped on an inverted premise.** `BLESS 7.3% → 12%` is the nine-card-pool
> figure. On the shipped twelve-card pool BLESS measures *above* random
> (`BALANCE.md`, cards item 3 — re-run on 4000 paired seeds and scored on the
> discordant pairs), and raising it was reverted precisely *because* it would
> have made the game easier. Cited here as the wrong thing to do first, it now
> reads as a recommendation.
>
> **The whole of what Phase 0 bought is one addition to that algorithm.** `nudge`
> *is* the greedy algorithm — `_balance.gd:429-445` runs the same re-roll loop
> as the control and adds a single `_spend_all_focus` call — and it is the
> strongest row in the game at `1.46x` the control. So the decision space this
> plan set out to build is, measured, the greedy algorithm plus spending the
> charge.
>
> **And the charge is in real conflict with the re-roll, which is the part this
> section would most want back.** Focus is spent *before* the re-rolls and the
> two compete for the same die, because a focused die is spent and a re-roll
> request on it is refused (`dice.gd`'s `toggle_pick`, whose first line is
> `if over or dice[i].spent or i == banked: return`). That is a genuine ordering
> decision over one turn's budget rather than two independent buttons — a
> direct answer to "the player does not make decisions", and not visible
> anywhere in the four steps above.

---

## Phase 0: Deepening the Turn Decision Space (Priority 1)
*Objective: Transform every turn from an automatic greedy algorithm into an active tactical dilemma with competing resources and risk/reward choices.*

### 0.1 The Second Per-Turn Spend: Focus vs. Gamble
- **Problem**: Re-rolling is the *only* button. The only choice is "gamble on this die or keep it".
- **Design**: Introduce a per-turn tactical resource alongside re-rolls:
  - **Focus (Nudge)**: Instead of spending a reroll to gamble, the player can spend a Focus charge to nudge a die up one face step (or lock in a guaranteed bump).
  - **Tension**: Do you spend your budget gambling on a re-roll of Sunder (could roll 0 or 14), or do you use Focus to guarantee Blade steps from 5 to 7 to meet lethal threshold?
  - **Implementation**:
    - Extend `dice.gd:Encounter` with `focus_left` and `nudge_die(index)`. Both
      were prescriptions; `focus_left` shipped as written and `nudge_die` did
      not — the method is **`focus_die(i)`**, alongside `focus_face`,
      `can_focus` and `focus_gain`. No symbol in the repo is named `nudge`.
    - Add a "Focus" / "Nudge" button to `fight.gd`. The shipped label is
      **`Focus`** alone (`"Focus (%d)"`), so "Nudge" is a second name for the
      same action that never reached a player.

### 0.2 Die Banking (Hold for Next Turn)
- **Problem**: Every die must be spent on the current turn. If the enemy attacks for 0 or you already have lethal, defensive dice rolled this turn are completely wasted.
- **Design**: Allow the player to **Bank (Hold)** 1 die across turns (it stays on the board, locked on its rolled face for the next turn, but doesn't resolve its stats this turn).
  - **Tension**: Do you cash in Ward's 9 block now against a weak 3-damage attack, or bank it to survive next turn's telegraphed Enraged strike?
  - **Implementation**:
    - `Encounter.banked_die` in `dice.gd`. It shipped as **`banked: int = -1`**
      (where `-1` means nothing is held) with **`toggle_bank(i)`** as the only
      way to set or clear it. Nothing is named `banked_die`.
    - UI toggle on long-press or tap-to-bank slot in `fight.gd`.

> **This mechanic shipped, and it is measured to be a losing line — a finding
> this section does not carry.** `BALANCE.md`'s paired rows put a bot that holds
> when the rules say to at **1.4%** of runs cleared, against **15.9%** for one
> that never holds: deferring a die costs a full turn of its damage, and an
> enemy hit of 3–9 rarely repays that. It also records that the obvious
> counter-argument is already answered in game — surviving a telegraphed big
> hit is better done by taking the block this turn, which is free — and lays
> out three ways out, cheapest first, while saying that choosing between them
> is the owner's call rather than its own. Those numbers are not repeated here;
> read them there.

### 0.3 Status Conditions & Threshold Triggers (Synergies)
- **Problem**: Combat is purely linear subtraction (`dealt = dmg - armor`, `hp -= hit - block`). *(Falsified by the first Design bullet below — see the note.)*
- **Design**: Introduce 2–3 sticky status effects that reward dice combinations:
  - **Vulnerable / Exposed**: Hits against an exposed enemy bypass armor or deal +50%. *(Shipped as the `+50%` branch. The bypass reading was built, measured at `2.1%` against a `7.3%` control, and cut.)*
  - **Sundered / Bleed**: ~~Damage dealt over time, allowing slow defensive builds to win.~~ **(Dropped — see the note below.)**
  - **Reactive Enemies**: An enemy that counters on rolls > 10, or an enemy that gains armor on small hits ~~< 4~~ **`< 6`**. *(Shipped as `BEH_BRACE`. The "counters on rolls > 10" half does not exist in the roster.)*

> **One of the three shipped, one shipped with a different number, and this
> section's own Problem line is falsified by its own first Design bullet.**
>
> | status | what actually shipped | where |
> |---|---|---|
> | Vulnerable / Exposed | `enemy.exposed`, damage `× 3 / 2` | `dice.gd:198-201` |
> | Sundered / Bleed | **nothing at all** | — |
> | Reactive Enemies | `BEH_BRACE` at `< 6`, not `< 4` | `dice.gd:155`, `:165` |
>
> **Sundered / Bleed does not exist under any name.** Searched for `bleed`,
> `sunder`, `poison`, `burn`, `wound`, `dot`, `over time` and `overtime` across
> `dice.gd` and `run.gd`: zero hits that are not the die named Sunder or the
> word "under". `BALANCE.md` closes it at length and the reason is structural
> rather than a tuning miss — **the game has no window for time-based damage
> to occupy**, because a resolve can only overshoot by driving HP to zero, and a
> resolve that does that *is* the killing blow. It measures the surplus at
> **18.6%** of all damage dealt, then shows that reaching it requires a
> non-killing resolve that does not exist: **0 of 4,620 fights.** Four ways out
> are enumerated there and all four close, which is why its advice is not to
> retry without first changing `dice.gd` so a fight does not end at zero.
>
> **The `> 10` counter does not exist either.** The roster has six behaviours
> (`dice.gd:150-155`) and none of them counts high rolls: `NONE`, `ARMOR_GROW`,
> `LIFESTEAL`, `CURSE`, `ENRAGE`, `BRACE`. `BALANCE.md` records why — no die but
> Sunder reaches 10 and only 2 of 24 faces do, so an enemy that counters rolls
> above 10 would be a stat block with extra words. The `"or"` in the bullet made
> the line true regardless; the half that survived is the half with the wrong
> number.
>
> **The threshold is `6`, and it is judged on the face rather than on what
> survived armour.** `REACT_LOW := 6` (`dice.gd:165`) is tested against
> `face_hit` in both the normal path (`:574`) and the held die's cash (`:591`).
> The face reading is deliberate and is the thing that makes it playable: a
> `cleave 12` reads as 12 on the card and counts as 12, because a reactive rule
> the player must hold in their head instead of read off the board is a
> memorisation test rather than a decision.
>
> **The Problem line is stale in a way this section caused.** `dealt = dmg -
> armor` was the rule when it was written. The rule today is `Enemy.pierce`
> (`dice.gd:198-201`): `dmg * 3 / 2` when the enemy is exposed, and
> `maxi(0, dmg - maxi(0, armor - pierce_bonus))` otherwise. The first branch
> does not subtract armour at all; the second has both a pierce term and a
> clamp at zero. **Shipping Exposed is precisely what stopped combat being
> linear subtraction**, so the premise and the fix cannot both be current, and
> the premise is the one that was left behind.
>
> **`+50%` is `dmg * 3 / 2` in integer arithmetic, so it rounds down.** An 11
> hit resolves to 16, not 16.5 — `+45%`. The float text calls it "takes half
> again", which is worded as an approximation and is one.

---

## Phase 1: Decision-Driven Synergies & Upgrade Redesign
*Objective: Ensure reward cards (`run.gd`) offer genuine build archetypes that leverage the new mechanics.*

### 1.1 Archetype-Defining Cards
Replace flat "+1 to face" upgrades with upgrades that interact with Phase 0 decisions:
- ~~**Disciplined Mind**~~: Gain +1 Focus charge every turn, but -1 re-roll. **(Dropped — see the note below.)**
- **Gambler's Rush**: Re-rolling a die into a higher face deals 3 bonus piercing damage.
- **Bastion Hold**: When a die is banked, gain 4 block immediately.
- **Precision Strike**: Nudging a die to its maximum face applies Exposed to the enemy.

> **The bullets above are the spec as written; three of the four were built
> differently and one was cut.** Recorded 2026-10-01 against `run.gd`'s
> `UPGRADES` descriptions, which is what the player reads:
>
> | card | 1.1 specifies | what ships |
> |---|---|---|
> | `GAMBLERS_RUSH` | "3 bonus piercing damage" | half the gain, floor 1 — `maxi(RUSH_FLOOR, rushed / RUSH_SHARE)` in the resolve |
> | `PRECISE_STRIKE` | "nudging a die to its maximum face" | a **10+ hit** — the hand's hardest face against `EXPOSE_AT` |
> | `BASTION_HOLD` | "4 block immediately" | as specified |
> | `DISCIPLINED_MIND` | "+1 Focus, −1 re-roll" | **does not exist.** Built, measured, dropped 2026-09-30 on `BALANCE.md` criterion 3 — `BALANCE.md:659` |
>
> Both mechanical changes are the same kind of error, and it is worth naming
> because it is not a tuning drift. **`GAMBLERS_RUSH` as specified is flat, and
> flat is the wrong shape for the card.** A re-roll that gains 1 pays 3, a
> re-roll that gains 11 pays 3: the card is meant to reward the swing dice, and
> a constant rewards rolling badly. It is a fraction of the gain now, so Sunder
> `1` → `cleave 12` pays 5 where Blade `4` → `5` pays 0, floored to 1.
>
> **`PRECISE_STRIKE` as specified could not fire.** Focus steps a die to the
> next *strictly better* face, not to its maximum (the check reading `"focus
> never moves a face down"` asserts it), so "nudging to its maximum face" is a trigger with
> no reachable value — and Blade, the starter die, tops out at 9, one short of
> `EXPOSE_AT`. The threshold was rebuilt as a 10+ hit, which is what the card's
> name describes and what `EXPOSE_AT` already existed to measure: Sunder, Fang
> and Spark clear it out of the box, Blade needs SHARPEN stacked, and that is
> the build path `dice.gd:216` argues for rather than an accident.
>
> `DISCIPLINED_MIND` is the row most likely to be read as current, because it
> is listed here unstruck in a plan whose every other section is annotated with
> what actually happened. `BALANCE.md` recorded the drop the same day and this
> file did not pick it up — so the correction belongs here rather than only
> there. `_balance.gd` now checks that every card 1.1 names is in the pool,
> which makes the next cut of one a red gate instead of a stale line.

> **Twelve card descriptions read against their arms: eleven matched, and the
> one that didn't was REFORGE.** `game.gd:501` renders `desc` verbatim, so this
> is the exact text a player reads. Checked: the SHARPEN and BLESS arms touch
> only faces with a nonzero value, which is what "every damage face" and "every
> block face" have to mean or they would flatten a face into a damage face;
> VIGOR adds 8 to `max_hp` *and* `hp` so the heal cannot overflow; MEND is the
> only one capped, which is the whole of "it does not last"; PIERCE, FOCUS,
> BULWARK, PRECISE_STRIKE, GAMBLERS_RUSH and BASTION_HOLD each set exactly the
> one flag their text names.
>
> REFORGE said **"Raise your weakest die-face."** The arm picks a die with
> `rng.randi_range` and calls `forge()` on it, and `forge()`
> raises *that die's* `worst_index()`. So with four dice the
> player's globally weakest face is the one lifted **one time in four**, and a
> strong die can be drawn and have a face it already outclasses bumped
> instead. Same shape as `PRECISE_STRIKE` above, and the table's own comment
> beside PRECISE_STRIKE calls it "a card promising something the rules do not do".
>
> **The copy was corrected; the code was not.** Making the arm raise the
> global worst is a balance change that would need the full gate re-run, and
> the 4.7% pick rate `BALANCE.md` records is a measurement of the *code* — so
> the text was the false half and changing it moves no number. Now "Raise any
> die's worst face.", and the comment in `_balance.gd`'s axis table that
> said "raises the weakest face" was the same claim in a second copy.
>
> **Kept to 25 characters deliberately.** A reward Label has no autowrap and
> `shot.gd`'s fit check only ever sees the three cards it stages
> (PRECISE_STRIKE 66, ADD_DIE 30, BULWARK 29), so the pool
> has two descriptions longer than anything measured — GAMBLERS_RUSH at 64,
> which is inside PRECISE_STRIKE's margin by two characters, and BASTION_HOLD
> at 36, which is the one a future edit would break first. A first attempt at
> this text read "a random die's", 32 characters, and was pulled back for
> exactly that reason: with one font and no wrap, label width is monotonic in
> text length, so 25 is the longest string here with layout evidence behind it
> at 360, 411 and 540.
>
> **The card's effect had no test either.** `run.gd`'s self_test asserted
> `upgrades.has("REFORGE")` — that the id was recorded, not that a die changed.
> `forge()` is covered on a bare die by the check reading `"forge raises the
> weakest face by one"`, so what was untested is
> the wiring: whether the arm reaches a face of a die in *this* hand. The new
> check measures total face damage either side of a second
> application, which pins the effect and the "one face, by one" together and is
> a delta because the arm draws at random. Forced red both ways: the arm
> reaching no die, and the arm forging every die.
>
> **And the deeper version of the same gap: no check anywhere read a card's
> `desc`.** REFORGE's copy was corrected by a person reading it, which fixes
> that one sentence and leaves the class open — the next person to move a
> constant that a card quotes puts the lie back, and nothing notices. All twelve
> descriptions were read against their `apply_upgrade` arms and all twelve hold;
> `SHARPEN` +1 on `f.dmg > 0`, `BLESS` +1 on `f.block > 0`, `VIGOR` +8/+8,
> `PIERCE` +1 through `maxi(0, armor - pierce)`, `MEND` `mini(hp + 14, max_hp)`,
> `BULWARK` `thorns += 4` fired on `hit > 0` so a full block stops it,
> `PRECISE_STRIKE` on `hardest >= EXPOSE_AT` (10) with `dmg * 3 / 2` while
> exposed, `GAMBLERS_RUSH` `rushed / RUSH_SHARE` (2) added to `dealt` outside
> `pierce()`, `BASTION_HOLD` `block += BASTION_BLOCK` (4) on the hold.
>
> Three of those magnitudes are *derivable* — the number lives in a constant and
> the copy quotes it — and those three are now checked: `BASTION_BLOCK`,
> `EXPOSE_AT`, and `RUSH_SHARE` (where "half" is asserted as `RUSH_SHARE == 2`,
> the promise rather than a restatement of it). Forced red together by moving
> all three, `5 of 8568 CHECKS FAILED`.
>
> **Honest about what that buys: the behaviour was already covered.** Moving
> those constants also trips pre-existing checks ("a doubled 5 reaches EXPOSE_AT
> and exposes"), so a maintainer would not have been left with a silently wrong
> mechanic. What was missing is that the *copy* going false produced a failure
> saying the mechanic broke, not one saying the sentence did. The check exists
> to make the second one say the second thing.
>
> **The other seven cannot be checked without changing code, and naming that is
> more useful than faking it.** `SHARPEN`'s 1, `BLESS`'s 1, `VIGOR`'s 8, `MEND`'s
> 14, `BULWARK`'s 4, `FOCUS`'s 1, `PIERCE`'s 1 are each one literal typed twice —
> once in `apply_upgrade`, once in the card — so there is nothing to read the
> value out *of*. (`ADD_DIE` and `REFORGE` are the other two of the twelve, and
> quote no tunable number: "one die" is `dice.append` called once, and "any die's
> worst face" has no magnitude at all.) Hardcoding the number in a check would
> be a second copy with nothing to propagate it: the defect wearing a check's
> clothes. The fix is to hoist each into a constant and add it to the same
> `derived` table; that is a refactor of seven arms and was not done unasked.
>
> One limit worth stating rather than hiding. `_headline_number`
> parses the first digits out of a description for the bot's
> `_weak_pick`, returning −1 when there are none. Both the old and the new
> text are digit-free, so the bot's policy is unchanged — but that means a
> description starting with a number would silently become a card preference,
> which is a trap waiting for the next person to write one.

> **And the same title is interpolated into three log lines that added an article
> of their own.** `Encounter._init` opened every fight with `"A %s blocks your
> path."`, `resolve_faces` ended it with `"The %s falls."` and `take_turn` with
> `"The %s dies to your thorns."` — so a run's last fight **opened** with
> "A The Devourer blocks your path." and could **end** with "The The Devourer
> falls." `The Devourer` is the only one of the nine titles that carries an
> article, which is exactly why nothing caught it: the same three lines read
> correctly for the other eight, and every *other* line in both methods already
> printed the bare title.
>
> All three were reachable, not theoretical. The opening line is on every fight,
> the fall is how every boss fight ends, and thorns is a card the player takes —
> the boss enrages past any block a first run has, so `hit > 0` always holds when
> the thorns block is reached. Reverting each string in turn and reading the gate:
> **9 failures each**, and the boss row named its own line,
> `"A The Devourer blocks your path."` and
> `"The The Devourer dies to your thorns."`.
>
> Twenty-seven checks, nine depths by three sites, driven from `run.gd` rather
> than `dice.gd` because `start_fight()` builds the encounter from the actual
> roster — a check that hardcoded the boss would still have caught today's bug and
> would go quiet on the next enemy to pick up an article. Nine of the twenty-seven
> enforce consistency on the eight titles that have no article ("Grunt falls."
> rather than "The Grunt falls."), which is a stricter rule than the bug needed
> and the one the surrounding log lines already follow.
>
> **Both this and the `capitalize()` fix are the same defect wearing different
> clothes: a name that already knows how to write itself, handed to a format
> string that assumes it does not.** `fight.gd` title-cased a deliberately
> lowercase behaviour name; `dice.gd` gave an already-definite title an "A". The
> cheap way to catch the next one is to look for the fixed word next to an
> interpolated title, which is what the sweep that found these was — five minutes
> with a grep, against three sites and twenty-seven checks.

> **And the store copy came back wrong after being repaired, which is the shape
> this whole section is really about.** The Play description said "Hexweaver
> curses one of your dice to nothing." `Dice.Encounter._curse_one` picks a die
> at random and drops it on *that die's* lowest-`worth()` face, and only Sunder's
> is a nothing, because Sunder is the one die carrying `rust`. Blade's is a plain
> `2`, Ward's a `2` that blocks instead of striking, Hex's a `1` — three of the
> four library dice. An earlier pass had already caught this and repaired it to
> "A few faces are nothing at all, **which is exactly what Hexweaver reaches
> for**", which is false in a second and subtler way: it is not reaching *for*
> the nothing faces, it is reaching for whatever is worst on a die it picked at
> random. Measured the same way both times — the claim written as a check and
> the gate left to decide. The first form failed on exactly Blade, Ward and Hex.
>
> The copy now says "drags one of your dice down to its worst face", and names
> both outcomes in the same sentence so the next reader is not left assuming
> `rust` is the only thing a curse can do. The store block is **3121** of Play's
> 4000 characters, measured with `shot.gd`'s own fence-and-strip rather than
> estimated from the prose note it corrects. That note said 3046 and was **66**
> stale — reconstructed exactly rather than by hand, after a first pass at
> "seven" came out of subtracting two strings in my head and was wrong by an
> order of magnitude. It is the drift the note is describing, one level down.
>
> **A second absolute in the same block, found the same way, and this one was an
> over-*pitch* rather than an over-*claim*.** "Between fights you take one of
> three upgrades, and upgrades change your dice, not a stat bar" is contradicted
> by two of the game's own twelve: `VIGOR` writes `max_hp += 8; hp += 8` and `MEND`
> writes `hp = mini(hp + 14, max_hp)`. Hit points *are* the stat bar. Five more
> cards change neither dice nor hit points but the rules they roll under —
> `FOCUS`, `PIERCE`, `BULWARK`, `PRECISE_STRIKE`, `BASTION_HOLD` — so "change
> your dice" was wrong for seven of twelve, and "Every choice reshapes the hand
> you roll next fight" was wrong for all of those. The three examples the
> sentence listed next were die-changing cards, which is what made the summary
> read as a sample of the whole set rather than the whole set.
>
> The copy now says they "change your dice or the rules you roll them under —
> only two of the twelve buy hit points back", which is both true and a better
> sell: two hit-point cards out of twelve is the interesting fact, and the old
> sentence hid it by denying it existed. The `run.gd` half applies every card to
> a fresh run and counts the ones that move hit points, rather than reading the
> twelve `match` arms — reading them is how the sentence survived. Falsified by
> expecting three: `2 of the twelve cards move hit points (MEND and VIGOR)`.
>
> **The shape both of these share: a description sentence with a "not" in it is a
> claim about every case**, and the cases the author was not holding in mind are
> the ones it is about. "Not a stat bar", "to nothing", "which is exactly what
> Hexweaver reaches for" — three sentences, one block, and not one of them
> survived contact with `apply_upgrade` and `_curse_one`. That is worth more than
> the three fixes, because it is the shape rather than the instances, and it is
> checkable: `_store_copy` now asserts both negatives against the shipped file so
> a fourth one cannot be added without the same question being asked.
>
> Two checks, in two files on purpose. `run.gd`'s `self_test` holds the mechanic
> half, beside the other store-copy claims: fewer than every library die has a
> nothing for a worst face, which is what makes "to nothing" an overclaim.
> `test.gd`'s `_store_copy` holds the copy half and re-reads the fenced
> block of `play/LISTING.md`, the same normalising `shot.gd` does. It is in
> `test.gd` rather than in `_check_copy_claims` because **`shot.gd` cannot be
> executed from this session** — a check in a gate nobody can run is the floor
> problem again, one file over. Falsified by reverting the copy:
> `2 of 8572 CHECKS FAILED`, exit 1.
>
> The generalisation, and the reason it is worth the four lines: **a repaired
> sentence reads as settled.** The 7.1%-of-faces count in the note above is
> right, the Hexweaver claim attached to it was not, and they had been written
> into one paragraph as though one reading had settled both. Splitting them was
> the whole fix; a second pass over the same paragraph is what found it.

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
> | `dice:nudge` (Tactical Nudger) | 26.2 | **1.46x** | 8.38 | 1.06x |
> | `dice:reach` | 23.5 | 1.31x | 8.29 | 1.05x |
> | `dice:read` | 19.1 | 1.06x | 8.18 | 1.03x |
> | `<random>` (Random Player) | 18.0 | — | 7.93 | — |
> | `dice:swing` (Greedy Gambler) | 17.3 | 0.96x | 7.92 | 1.00x |
> | `dice:chip` | 0.1 | 0.01x | 3.24 | 0.41x |
>
> **Re-measured three times now — after the two card clamps and after the
> re-roll carry fix below — and the direction is worth more than the number.**
> The card clamps moved every row up and the ratio *down* (1.55x → 1.46x),
> because removing a dead pick from a quarter of all reward rolls helped
> whoever was wasting the most picks, and that was the bot playing at random.
> The re-roll fix then moved depth up on both sides (Nudger 8.30 → 8.38,
> control 7.88 → 7.93) and left the ratio at 1.46x.
>
> **What the re-roll fix cost is the card spread: 0.98 → 0.86.** Still clear of
> the 0.5 floor, so the gate is green, but the direction is consistent and worth
> watching — the bottom of the table rose rather than the top falling, REFORGE
> 7.27 → 7.41 and BASTION_HOLD 7.22 → 7.34, while ADD_DIE held at 8.19. A live
> bonus re-roll rewards rolling well, which is the same axis every card is
> competing on, so upgrades matter marginally less once it works. Two fixes in
> the same direction is the thing to watch, not either number alone.
>
> Two things worth reading off the table. **The Nudger is the best bot in the
> game by a clear margin** — nothing else reaches 24% — which is the strongest
> evidence anywhere in this repo that Phase 0's Focus charge is a real decision
> rather than a second button, since the only policy that presses it is the one
> that wins. And **the depth ratio is 1.06x, not 1.46x**: tactics move the boss
> fight, not how far a run gets, which is the same upgrade/depth bind the
> probe's own notes warn about.
>
> One row sits outside this table and is worth a look rather than a fix:
> `<rand>+gamble` wins 30.3% at depth 8.46, above every `dice:*` policy. It is
> a paired row, so the gate excludes it by design — it moves two variables and
> answers no single question. But a card-and-policy pair beating the best pure
> die policy is the shape Phase 0.1 was asking for, and it is the first time
> one has.
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

> **Answered 2026-10-01: all three were evaluated and all three are recorded in
> `BALANCE.md`. Nothing above is false, which is rarer than this file's
> average and worth saying plainly before the caveat.**
>
> | subject | verdict | recorded at |
> |---|---|---|
> | `BLESS` | DROP, on the premise rather than the numbers | cards item 3 |
> | acquired-die armour pierce | KEEP | rules item 7 |
> | paired faces | KEEP | rules item 8 |
>
> **The numbers are deliberately not repeated here.** Each is a dated
> measurement on named seeds at a stated N, and `BALANCE.md` is their single
> copy — the defect this file has now caught in itself twice, being a second
> copy of a fact with nothing to propagate it. Read them there or not at all.
>
> **"Gate" is the one loose word, and neither thing it can mean is one.** 2.1's
> answer above states outright that the ratio is deliberately not a gate. The
> band (random 8–18%) and the depth floor (7.6) are a gate too, but a *prose*
> one: they live in `BALANCE.md` and are applied by the unattended loop, not in
> code. Measured rather than assumed — `_balance.gd` makes exactly **eleven**
> `Check.check` calls, and **not one of them touches a win rate.** Three look at
> depth: a fight cannot pass depth 9, the `<random>` control must
> clear `5.0` and the single-card rows must span more than `0.5` of
> depth. The last two are instrument integrity rather than performance —
> the first asks whether the control bot is real at all, the second whether the
> cards are distinguishable. The other seven are axis coverage, a
> histogram invariant, PLAN.md 1.1's correspondence (three checks) and PLAN.md
> 0.3's reactive threshold (two). **The `7.6`
> depth floor and the `8–18%` band are in none of them**, so a balance
> regression is *printed* by this gate, not failed by it.
>
> Those seven were eight, and the eighth is mine: the `dice:read >= 0.0` guard
> added with the Ironhide verdict below. It is the closest this file has come to
> a win-rate check, so it is worth being exact about why it is not one — it
> asserts that the strategy table still carries a row *labelled* `dice:read`, so
> the verdict below has something to print, and the win rate it reads into
> `read_wins` is never compared against anything. Deleting the guard makes the
> verdict silently print nothing, which is the one failure mode this repo has
> spent the most time closing. It counts as instrument integrity, and if it ever
> acquires a threshold it is a balance gate and this paragraph is wrong.
>
> Every one of those eleven was cited here by line number. All eleven had
> drifted by the time this was re-read, the three depth ones by six lines and
> the rest by seventy to a hundred and thirty, because every edit above them
> moves a pointer that names something below. That is the second time this file
> has had to un-cite a block for exactly this reason, so the rule generalises:
> **cite the check's own text, never its address.** A grep for
> `"a run cannot pass depth 9"` is a sentence a reader can act on; `:448` was
> decoration that decays.
>
> **The roster's armour shape was in none of them either, and the one comment
> resting on it had both its counts wrong.** `_balance.gd:179` argues the
> roster is what makes sunder near-universal, on two numbers: "the roster
> carries armour on seven of nine enemies with two of them growing into the
> 12 cap". Measured against `run.gd`'s `enemy_for` (`:120-137`):
>
> | | claim | measured |
> |---|---|---|
> | enemies carrying armour | 7 of 9 | **8 of 9** — all but the Grunt, whose 0 is the table's only zero |
> | able to grow into the 12 cap | 2 | **3** — Rust Golem and Stone Sentinel by `BEH_ARMOR_GROW`, Ironhide by `BEH_BRACE` |
>
> Seven counts only if Bloodletter's armour of **1** is discounted, and it is
> not: `pierce()` (`dice.gd:198`) is `maxi(0, dmg - maxi(0, armor - pierce_bonus))`,
> so 1 turns Sunder's `1` into 0 and Blade's 2 into 1. The second count missed
> Ironhide entirely, because only the two behaviours whose name *grows* were
> counted — and `dice.gd:156` names `ARMOR_GROW_CAP` as the ceiling for
> `BEH_BRACE` as well. The argument's conclusion is unaffected and if anything
> strengthened, but the numbers under it had never been measured.
>
> Two checks added in `run.gd`'s self_test, beside the block that already pins
> the roster's titles, behaviours and the boss's 78 health. Counted over every
> depth rather than asserted per enemy, so a daily's `order` shuffle cannot move
> them — it permutes the same nine. Forced red both ways: giving the Grunt 1
> armour ("measured 9"), and retagging Ironhide off `BEH_BRACE` ("measured 2" —
> and the armoured count correctly stayed green, since Ironhide keeps its 2).
>
> **0.1 and 0.2 have no correspondence check, deliberately, and a citation
> regex is what breaks that.** Both sections record a prescribed symbol that did
> not ship, in the same sentence as the shipped one that replaced it: 0.1 writes
> `nudge_die` did not — the method is `focus_die(i)`. A regex
> pairing a backticked name with the citation after it takes the **first** name
> and pairs `nudge_die` with `488`, which declares `focus_die`, so the check is
> red forever — the same permanently-red failure `:788` exists to prevent. 1.1
> is checkable because it lists only shipped cards in one regular bullet form,
> and 0.3 because its claim is a single number in a single sentence.
>
> **0.1 and 0.2 are now cited by symbol rather than by line, and the reason is
> in the paragraph below.** The shipped names are `focus_left`, `focus_face`,
> `can_focus`, `focus_gain`, `focus_die`, `banked: int = -1` and
> `toggle_bank`; every one of those still exists and still resolves to exactly
> what 0.1 and 0.2 say it is. A line number cannot survive an edit, and these
> two sections are edited from above far more often than from below.

> **That paragraph held for two edits, and it was wrong about five of the seven
> when it went.** The first failure was mine and was recorded then: rewriting a
> comment *above* `focus_die` pushed it from `488` to `494` and falsified the
> citation. The second was nobody's in particular, and was found by the citation
> sweep in the Gates section below resolving the list one item at a time:
> **`focus_face`, `can_focus`, `focus_gain`, `focus_die` and `toggle_bank` had
> all moved.** `focus_face` and `can_focus` by the same amount, which is the
> tell: an edit inserting lines above `focus_face` pushes
> everything below it, and every citation naming something *below* that edit is
> falsified by an edit that has nothing to do with it.
>
> **Only `var focus_left` and `banked: int = -1` survived, and they are the two
> that sit above where the edits landed.** That is the whole shape of the defect,
> and it is why the fix is to delete the numbers rather than restate them: a
> corrected number is a fresh claim about a moving target, and this is the third
> paragraph this file has written to argue exactly that.
>
> **The claim that citation pointed at was itself wrong, and it contradicted
> itself.** `focus_die`'s comment said, in order:
>
> > Bounding the step to "worth + N" was tried and is a no-op … The gap is a
> > property of the dice, not of the rule -- cap it and Sunder becomes
> > unfocusable from every face worth caring about.
>
> Both halves cannot hold. A cap is a no-op only when N is at least the widest
> step in the library, and the widest step is **11**: Sunder's `1` (worth 1) to
> `cleave` (worth 12). So the cap changes nothing at N ≥ 11 — a cap permitting
> the exact jump focus exists to refuse — and at every N a player would
> actually want it binds, leaving Sunder focusable from `rust` and nowhere
> else. The comment's *premise* was wrong too, and in the opposite direction:
> it said faces are "spaced further apart than any useful N", where Blade,
> Ward, Hex and Spark are all spaced exactly **1** apart. What was right was
> the last sentence, which is the sentence that contradicted the first.
>
> `_focus_gap_tests` now pins the 11, because the argument for
> cutting the cap is a fact about the face tables rather than about the rule,
> and that is the kind of claim that rots without a red gate. Forced red two
> ways: moving the expectation, and moving Sunder's `cleave` to 13 — the second
> also took down two `pierce` checks, so that value is pinned twice over. The
> failure message reports the measured number rather than asserting 11, because
> a message that states a falsehood on the way out is the defect class this
> audit keeps finding, and it would have been one here.
>
> The same paragraph also called `cleave` Sunder's "best face" and said an index
> rule makes it "its worst". `cleave` is worth 12 and `rend` is worth 14, and
> one array step from `cleave` lands on a `1` — worth 1, second-lowest, not the
> `rust` at 0. Fixed in both copies — the comment inside `focus_die` and the
> test block beside the `"cleave focuses to rend"` check — because the example is
> the reason the rule exists and it should be
> exactly true.
> **This paragraph said eight and said "a run", and it was wrong twice.** The
> two `REACT_LOW` checks were added after it was written and the count was not
> carried; every line number it quoted had moved too. That is a second copy of a
> fact with nothing to propagate it, written in the paragraph naming that defect,
> and **the floor cannot catch it** — whoever adds a check updates the floor in
> the same breath, which is the entire point of the floor. What the floor does
> catch is a check that stops running: the other 22 are 12 (one per `UPGRADES`
> card) + 3 (one per PLAN.md 1.1 bullet) + 7, and reformatting those three bullets
> to plain `- Name:` form reports `167691, expected 167694` and names the cause.
> All ten sites have now been forced red one at a time; none of them is a check
> that cannot fail.
> **And the check all three of those depth readings rest on could not have
> failed. `:448` — "a run cannot pass depth 9" — is not a gameplay invariant.**
> It reads `r.depth + 1 <= FINAL_DEPTH + 1`, and `RunState.at_boss()` is
> `depth >= 8` and breaks the run loop there, so `depth` never reaches 9 on any
> code path. No card, die or enemy change makes it go red.
>
> | probe | result |
> |---|---|
> | where the checks come from | 1000 runs per row, but `:448` sits inside a `while true` over **fights** — **167,672 of the gate's 167,694 checks are this one line** |
> | baseline runtime | 60s |
> | disable `at_boss()` (`:453`) — the only thing bounding `depth` | still running at 240s, 7 lines of output, **0 failures** |
> | same, with the run loop bounded at `:470` | **red in 66s**, 3,645 stranded runs, one collapsed line |
>
> **So the floor is not coverage.** 99.998% of `_balance.gd`'s check count is
> a count of simulated fights: a measurement output, not a fixed input. It is
> deterministic (seeds are `7000 + i`) and nothing else catches a test throwing
> partway, but it will also go red on any gameplay retune, with a message that
> points at the wrong cause. The bound at `:470` fixes the silence and is a
> no-op on correct code — `depth` never exceeds 8 — so the count is unchanged.
> **The partial is `BLESS`, and it is not an oversight.** It has no die-policy
> row because no policy presses its button: BLESS is `f.block += 1` on every
> face that has block, `+6` on Ward's six (the check reads `"BLESS lifts all
> six block faces"`),
> and `BALANCE.md` already records the general law
> — *any flat bonus to output is a flat bonus, wherever it lives*. Paired rows
> exist for cards that define an **axis**, which `_balance.gd:121-126` says in
> its own comment: the only two in the bench are `GAMBLERS_RUSH`+`gamble` and
> `BASTION_HOLD`+`bank` (`:127`). The pairing this bullet asks for is therefore
> *undefined* for BLESS rather than unrun, and its 4000 paired seeds scored on
> the discordant pairs (item 3) is the right instrument for a card with no axis.
> Reading BLESS beside `dice:nudge` would be inventing a number.

> **The most recent run is the one `BALANCE.md` has not recorded, and it moves
> the control to the top of its own band.** The "Baseline — measured, not
> remembered" block is stamped `dc6622c`, **09-30 15:02**, and reads
> `<random>` `16.4%` with "1.6–2.4 points of room up". The gate today prints
> **`18.0%`**. Row by row, same seeds, same N:
>
> | | `dc6622c` | now | |
> |---|---|---|---|
> | `<random>` | 16.4% | **18.0%** | +1.6 |
> | best card, ADD_DIE | 24.4% | 27.9% | +3.5 |
> | best policy, `dice:nudge` | 25.4% | 26.2% | +0.8 |
> | shallowest row, BASTION_HOLD | 7.13 | 7.34 | +0.21 |
> | `<rand>+gamble` | 21.9% | **30.3%** | +8.4 |
>
> **Twenty-one of the twenty-two rows moved up, and the single exception is
> `dice:chip` at 0.3 → 0.1** — the row `BALANCE.md` itself calls "a control for
> how bad a re-roll policy has to get to read as a signal", which sits near zero
> by construction. Twenty-one up against one pinned is the signature of a
> *uniform* rules change, and `BALANCE.md` already names that shape: a rules
> change lifts every strategy because every strategy plays the same dice, and
> lifting the floor lifts the denominator. Five commits touching
> `dice.gd`/`run.gd`/`fight.gd`/`game.gd` landed after the stamp, and two are
> `run.gd` gameplay fixes — `3b0d28a` (a new die dealt to a hand already holding
> all three) and `87afe50` (heal 14 to full-health players). `run.gd` is where
> `ADD_DIE` and `MEND` live, and those are the two largest movers in the table.
>
> **Which commit did it is not measured, and the attribution is not the
> finding.** Naming it would take a revert and two bench runs per arm, which is
> not worth doing on a tree other sessions are working in — and the band result
> does not turn on which of the five it was.
>
> **What needs an owner is the consequence.** Under `BALANCE.md`'s own gate the
> game still passes all three criteria: `27.9%` beats criterion 1's `24.4%` bar,
> `18.0%` is inside `8–18%`, depth `7.93` clears `7.6`. But criterion 2 now has
> **zero headroom above** where the document records 1.6–2.4 points of it, so
> any further uniform lift fails a hard criterion on a tenth of a point — and
> `BALANCE.md` measures the band's own asymmetry as roughly 8 points of room
> *down* against none up. Restamping that baseline is the file's own standing
> instruction ("in the same commit as any change to the rules"); it is another
> session's uncommitted file, so it is recorded here rather than edited there.

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

> **The haptic bullet's numbers are a sketch of what shipped, and it names two
> triggers where there are three.** `Input.vibrate_handheld(25)` never existed
> in the build. The call is `vibrate_handheld(ms)` with the magnitude picked at
> the call site, and the ladder that ships is:
>
> | trigger | ms | site |
> |---|---|---|
> | a hit you deal, 10 or more | 40 | `fight.gd:647` |
> | a hit you deal, under 10 | 20 | `fight.gd:647` |
> | a hit you take from a boss (`max_hp > 60`) | 70 | `fight.gd:667` |
> | a hit you take from anything else | 45 | `fight.gd:667` |
> | spending a Focus charge | 12 | `fight.gd:814` |
>
> The third trigger is the one this bullet never mentions, and it is the
> smallest on purpose. Focus is the certainty half of the turn's decision
> (0.1), so its pulse is a **Tick** rather than a hit — which is the word the
> float text above it already uses as its own tag (`fight.gd:813`). `HAPTIC_BOSS`
> is 70 and is deliberately *not* the same constant as the 60 in `BOSS_HP`: the
> two mean unrelated things and were named apart on purpose (`fight.gd:26`).
>
> **All seven site references in this block and the shake one below it were
> wrong before 2026-10-02, six of them by exactly one line, and the sweep that
> should have caught them did not — it is the off-by-one that is the finding.**
> `_haptic` and `shake` are called at `fight.gd:644`, `647`, `667`, `814` and
> `1030`; the block cited `516`, `519`, `539`, `662`, `664`, `848` and `22`.
> Every one of those *is* a real, non-blank line in `fight.gd`, and four of
> them are the `_float_text`/`_sfx` calls sitting immediately above the haptic
> they were cited for — so the wrong answer looks like the right one at a
> glance, and a reader checking "is there a call here?" says yes. `22` is the
> outlier at four lines out, because it points at the constant rather than a
> call and `HAPTIC_BOSS` sits below a four-line comment.
>
> The cause is the one this file has now seen twice: **an edit above a pointer
> invalidates every pointer below it**, and `_haptic`'s docstring grew without
> anyone re-reading the table that indexes it. Same shape as the `focus_left` /
> `focus_face` pair in 0.1, where the two symbols above an edit survived and the
> two below it moved together.
>
> **`_haptic` is gated on `OS.has_feature("mobile")`, so no gate in this repo
> can execute it** — neither headless nor under xvfb. Measured rather than
> assumed: deleting all three call sites left `test.gd` at 8527 checks and
> `shot.gd --check` at zero failures, so the whole feature could be removed
> from the shipped game and every gate would still be green. The paragraph in
> `shot.gd` that opens "shipped with five call sites"
> names that gap for these five call sites and then covers the shake, which
> *can* be sampled. `test.gd` now checks the wiring against the source instead
> — a weaker guarantee, and the only one available, since no amount of headless
> work changes what a mobile-gated call does.

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

> **The artifact already in `build/web/` is 62 commits stale, and publishing it
> would ship the wrong game. This is 4.1's trap on a section that had no note
> about it.** `build/web/index.pck` is dated **Sep 30 06:53**; HEAD is
> `992f0a4`, **10-01 00:17** — 17h24m and sixty-two commits, of which these touch
> shipped gameplay code:
>
> | commit | time | what a playtester would not get |
> |---|---|---|
> | `79de3f5` | 12:19 | the touch-target fix — **the thing 4.2 exists to test** |
> | `d035c37` | 14:09 | the boss haptic, which is 3.2's own deliverable |
> | `599baac` | 14:42 | item 7, the acquired-die armour pierce |
> | `3b0d28a` | 23:19 | a new die dealt to a hand already holding all three |
> | `87afe50` | 23:39 | heal 14 dealt to full-health players, four times as often |
>
> **Re-export before any playtest, and treat the export as blocked until then.**
> The command is `godot --headless --path . -s _pack.gd -- Web`, and it has not
> been run: the permission classifier denied it in an earlier session, so
> nothing in this repo has verified the web preset at all. Unlike 4.1 this is a
> *stale* artifact rather than a wrongly-typed one, which makes the failure
> quieter — the folder is populated, the page loads, and the only symptom is a
> playtest scoring a build whose touch targets fail on every phone narrower
> than 540dp.
>
> **`_pack.gd` is the one gate with no count floor, and that is not an
> oversight to be fixed by guessing.** Both its `Check.report` calls are
> floorless (`:87`, `:130`), so a throw inside a helper silently reduces what it
> checks and the gate still exits 0 — the defect `shot.gd` had until this
> session. It cannot take an exact floor either: its two failure loops
> (`for m in missing:` at `_pack.gd:118`, `for b in bad:` at `_pack.gd:154`) contribute **zero** checks on a clean
> run and one per finding otherwise, so the count is a function of how much is
> broken. **A clean run produces exactly 6** — `Check.check(argv.size() == 1,` at `_pack.gd:85` args, `"%s exports (exit %d)"` at `_pack.gd:94` export exit,
> `"the exporter reported %d files"` at `_pack.gd:98` files reported, `"a main scene is configured"` at `_pack.gd:102` main scene, `Check.check(shipped.has("res://_check.gd"),` at `_pack.gd:126` shipped, `"%s pack boots (exit %d)"` at `_pack.gd:143` pack
> boots — which is *derived* from reading the source, not measured, because the
> classifier that denied the export denies the run that would measure it.
> `_check.gd` says a guessed floor is "permanently red, which is worse than
> none", so none was added. **First person to run it legitimately should set
> `Check.report("_pack.gd", 6)`** and confirm the number before trusting it.
> `_runs` is reached (`:129`, immediately before the report), so nothing there
> is dead code.
>
> Those eight are in quoting form and the other three are not, deliberately: the
> eight are the ones the "6" is derived from, so a seventh check anywhere in
> `_pack.gd` must turn this paragraph red rather than quietly falsify its own
> conclusion. Nine of the eleven line numbers in it had drifted by one when this
> was checked against the file — every citation above line 90, with the two loop
> citations still correct, which is the signature of a single line inserted
> near the top at some point after they were stamped. That is the **fourth**
> hand correction of line numbers in this document and, like the previous three,
> the gate was green on every one of them.
>
> Converting them was then worth twice what it was expected to be. `_pack.gd`'s
> own header was rewritten twice below, once to correct a false claim and once
> for a `static`, and each rewrite pushed the file down by more than a dozen
> lines. The first rewrite turned **nine checks red** with the quoted text, the
> file and the line in the message; the second turned **ten red**, one of them a
> structural check catching that a line number now pointed at a blank. Both
> would have been silent. That is four of this document's line-number
> corrections in a row that the gate could not have caught, against two that it
> caught on the same day the conversion landed — which is the whole argument for
> doing the conversion, and the only evidence so far that it is not the
> theoretical improvement it looked like two blocks ago.
>
> And the reason the gate was green on all eleven is worth stating plainly,
> because it is a gap nobody has written down: **the original eleven were bare
> `:NN`**, with no file in front of them. `plain` compiles to a filename and a
> colon and a number, so a bare line number matches nothing at all — it is not a
> citation the gate passed, it is text the gate never looked at. Six had just
> been given a filename and a quote before that was noticed. A shorthand that
> reads like a citation to the person who wrote it, in a document whose subject
> is whether citations are checked, is the most expensive kind of typo there is.
>
> **The second bullet's question is half answerable without a playtest.** "Do
> Focus and Bank feel intuitive and *rewarding*" — the bench has already measured
> the second half. A bot that holds a die when the rules say to clears the boss
> **1.4%** of runs against **15.9%** for one that never holds, and `BALANCE.md`
> records three ways out and states that choosing between them is the owner's
> call. Focus is the half that paid: `dice:nudge` is the strongest row in the
> game at **1.46x** the control. A playtest remains the only way to learn whether
> either is *intuitive*; it is not the way to learn whether Bank is worth
> anything.

> **One harness ceiling, hit during this sweep and not worth building around.**
> `test.gd` extends `SceneTree` and calls `quit()` at the end of `_init()`, so a
> **parse error in a game script leaves the gate hanging, not failing** — measured
> with a one-line deliberate error in `run.gd`: `EXIT=124` after a 300 s timeout,
> alongside an immediate and unmissable
> `Parse Error: Static function "library()" not found in base "Die"` on stderr.
> GDScript has no `try`/`catch`, so a throw inside `_init()` cannot reach `quit()`
> and there is nothing to fix in-game. The mitigations that exist are the loud
> stderr line in the first second and whatever timeout the caller supplies, so
> **run the gate under `timeout` if a CI job is ever pointed at it.** The
> alternative — wrapping the suite so a parse failure exits non-zero — is a
> second harness to keep honest, which is a worse thing to add late than to leave
> named here.

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

# 5. The only gate that boots an exported pack, and so the only one that can
#    see the export filter dropping a file -- the failure gates 1-4 cannot
#    detect at all. The only one of the five that writes anything: it needs a
#    writable /tmp (see the note below).
godot --headless --path . -s _pack.gd -- Android
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

> **Gate 2's floor was calibrated on a simulation statistic, and it fired on a
> seed.** `_balance.gd`'s floor was 167694, set to the live count the way
> `_check.gd` requires — and the live count was not a fact about the code.
>
> 167640 of those checks came from a single assertion, `reached <= FINAL_DEPTH
> + 1`, which sits **inside** the run loop. That placement is deliberate and
> correct: the bound comment above it explains that a per-run check skips the
> very iteration that reports an overshoot, and that the first version of the
> bound "passed green on a build that could never win a fight". But per-fight
> means the count is *how many fights 22000 runs happen to play*, which is a
> property of the simulation, not of the source.
>
> So the floor was moved to `91000 + i` and back, changing nothing else:
>
> | seed base | checks run | old floor | verdict |
> |---|---|---|---|
> | 7000 (shipped) | 167694 | 167694 | green |
> | 47000 | 167694 | 167694 | green |
> | 91000 | 167662 | 167694 | **exit 1, "32 never executed"** |
>
> Same code, same checks, one number that held only for the base it was
> calibrated on. Two faults, and the second is worse than the first. A floor
> calibrated on a statistic is not a floor — re-roll the seeds and the gate
> goes red having found nothing. But it is also **backwards**: runs getting
> shorter is exactly what a balance change looks like, so this floor would
> have failed the gate for a legitimate rebalance while staying green through
> every abort it was written to catch. The check at `_balance.gd:587` refuses
> to gate on an absolute depth for the identical reason, one function below.
>
> The floor is now **22025**, the count that is structural on every seed:
> 20 from `_axis_report` and `_plan_cards` (12 axes, 1 histogram, 1 heading,
> 3 PLAN.md 1.1 bullets, 3 prose checks — all measured, not summed on faith),
> 3 from the verdict checks, 2 from `_gate_ratio`, and 22000 from the trial
> loop, held up from below by `for i in N:` having no `break` in it and every
> fight. Verified green at both 7000 (167694) and 91000 (167662).
>
> **The generalisable rule, and the reason this is here rather than in a
> comment:** a check count is only a floor if the count is a fact about the
> code. Put an assertion inside a simulation loop and it stops being one, and
> the failure is silent in both directions — no run of this gate alone could
> have told you, because the shipped seed base was the one it was calibrated
> on. The tell is a total much larger than the number of `Check.check` sites
> in the file: thirteen sites, some of them inside loops, produced 167697 checks,
> and a ratio that large means something is counted per event rather than per line.
>
> **The other two gates were then held to that rule, and both already pass.**
> `test.gd`'s 9041 decomposes as 8434 (`dice.self_test`) + 155
> (`run.self_test`, being 8589 − 8434: `Check.checks` is a shared static, so
> each reporter prints a running total, not its own) + 452 of its own — 21 in the
> `UI` loop (ten scripts at two checks each, plus `main.tscn`, which is not a
> `Script` and so takes only the load check), 3 haptics, 9 `_enemy_tag`, 5
> `_store_copy`, 2 `_depth_display`, 10 `_best_caption`, 7 `_face_word`,
> 6 `_pack_walk`, 5 `_contrast`, 8 `_sfx_names`, 374
> `_citations` — 359 of them two per citation site across the repo's `.gd`
> comments *and* its three markdown documents (168 sites, plus one more for each
> of the twenty-three that quotes its target), and 17 more, one per source file,
> asserting that none of the twenty-three is one of the wrapped ones described
> below.
> And
> 164 check sites producing 8421 looks alarming until the loops are read: every
> one is constant-bound (`for _i in 2000`, `for s in 40`) or roster-bound
> (`Encounter.library()`, `die.faces`), and `run.gd`'s `TRIALS` autoplay loop
> contains no check at all — only `wins += 1`, with both verdicts after it.
> Structural, so 9041 is a floor rather than a measurement. (That count sat at
> 155 beside the old 8410 and had gone stale the same way — a number in the
> middle of a paragraph arguing that other numbers go stale. So did this
> decomposition, and not twice but three times: it claimed 81 of `test.gd`'s own
> checks against a 229 `_citations` that both read high, the two errors partly
> cancelled, and a third survived both of those fixes. That was `346` standing
> for the own-checks total where the itemisation printed directly beneath it
> sums to 368, so the three terms came to 8935 and the paragraph went on
> explaining a total of 8957. It survived the earlier repair precisely because
> that repair had established the parts were individually sound — every part
> reads plausibly and only the sum is wrong, which is the one shape a
> cancelling pair of errors guarantees you will miss. Found by adding 23 checks
> and re-deriving the new total from the old one, at which point the shortfall
> is the only thing the arithmetic can say. Read out of `Check.checks` after
> each helper, which is the only way a number in a paragraph about counting
> gets to be one.)
>
> `shot.gd` is the instructive contrast, because it is the one gate that got
> this right **by measurement** rather than by assumption. Its floor is 766
> and it is explicitly a **lower bound**, because its check is guarded on
> `if my_hp - panel.enc.hp > 0` — deliberately, so a turn that rolled all
> block stays silent — which makes the count depend on the roll. The author
> then **ran it nine times** and wrote the spread down: 766, 767, 767, 766,
> 766, 767, 767, 766, 766. Having *seen* the count move, an exact floor would
> have been "red roughly half the time for no reason" — the same "permanently
> red, worse than none" that `_check.gd:58` warns about. `_balance.gd` picked
> an exact floor on a statistic it had never seen move. The difference between
> the two gates is one measurement.
>
> While writing that up I re-read the line it cites and found the comment's own
> citation had drifted: it named `shot.gd:321`, and the guard was thirty lines
> lower. The reasoning around it was still correct, so nothing was wrong with
> the gate — only the pointer to it, which is the cheapest thing in this repo
> to get
> wrong and the most expensive to notice, because a reader who trusts it is
> reading a line that says something else. Fixed. The general rule from the
> citation sweep is the one that catches it: **never write a line number, write
> the code, and let the reader find it.**

> **The Ironhide criterion was prose with no enforcement, and is now printed.**
> `_reroll`'s docstring stakes the whole mechanic on one comparison: *"`read`
> above `<random>` and the mechanic is real, `read` level with `<random>` and
> Ironhide is a stat block with extra words."* Nothing checked it. Ten
> `Check.check` sites in `_balance.gd` and none of them mentioned `read`,
> `<random>` or wins, so the sentence deciding whether a shipped mechanic is a
> real decision had no more force than the comment holding it — and unlike the
> 2.0x bar, which at least printed a ratio, this one printed nothing at all.
>
> It is now printed on every run, and deliberately **not** gated. Three seed
> bases, same code, nothing else changed:
>
> | seed base | `read` | `<random>` | gap |
> |---|---|---|---|
> | 7000 (shipped) | 19.1% | 18.0% | **+1.1** |
> | 47000 | 22.5% | 18.4% | **+4.1** |
> | 91000 | 20.5% | 18.1% | **+2.4** |
>
> The sign holds on all three and the gap swings by four points, so the bar is
> **met, and not yet safely met**. A floor at +1 point is red about half the
> time for no reason. A floor at +0.5 clears all three samples today and could
> go red on the fourth, which is worse than not gating at all — the output
> would read as Ironhide having stopped working when the real cause is which
> seeds the bench happened to draw. That is `shot.gd`'s exact dilemma, and it
> was solved there by measuring nine runs first.
>
> The upgrade path is half-built already: the arms are **paired** (`rng.seed =
> 7000 + i` is identical for every row), so recording each trial's win for both
> arms turns "+1.1 points" into the count of trials where they disagree. That
> is the signed error bar this lacks, and it is the only form of this number a
> gate should ever be given — two independent proportions cannot be compared at
> N=1000 at a gap this size.
>
> The print got a guard of its own, on the `_axis_report` precedent (*"A
> measurement a PLAN.md claim rests on simply stopped existing and nothing said
> so"*): a rename of the `dice:read` label makes the lookup miss, both prints
> skip, and the gate would otherwise stay green having reported nothing. One
> check — falsified rather than asserted, by mangling the label to
> `dice:reed`, which gives one FAILED check and exit 1.

> **Citation sweep: the first pass found 3 wrong out of 111, and that number was
> wrong too — the test it used cannot see most of the drift.** Every
> `file.gd:NNN` in the `.gd` and `.md` files was extracted and resolved against
> the file as it stands. 98 of them point into a different file; all 98 land on
> a real, non-blank line. The sweep's one remaining flag, `_pack.gd:53` citing
> game.gd's line 0, is **correct** — that is a claim about the shape of Godot's
> `Compile Error: Failed to compile depended scripts`, which names the root
> script at line 0, not a line that exists.
>
> **"Lands on a real, non-blank line" is the weak half of that test, and it is
> where the drift hides.** A citation that has moved points at *another real
> line* — the wrong one, in the right file. It is not out of range, not blank,
> and passes every mechanical check the sweep made. The second pass, 2026-10-02,
> read what each cited line actually says rather than whether it exists, and
> found **five more wrong against a tree that had only grown** (132 refs now,
> same two out-of-range flags, both the known-good game.gd line 0):
>
> | where | claimed | actually |
> |---|---|---|
> | `run.gd` REFORGE comment | REFORGE's copy is 25 characters | **27** |
> | `run.gd` REFORGE comment | the staged cards are `PRECISE_STRIKE 66, ADD_DIE 30, BULWARK 29` | BULWARK is **49**, so "25 is the longest with layout evidence behind it" had inverted |
> | `run.gd` REFORGE comment | a reward Label has no autowrap, at `game.gd:492` | it is a container offset; the desc Label is on a different line entirely |
> | `run.gd` PRECISE_STRIKE comment | the window is `dice.gd:617/622` | the decrement and re-arm are 24 lines lower |
> | `_balance.gd` | `Face.pairs` on Fang's `5` is `dice.gd` line 309 | it is two dozen lines off that, inside a comment about banking |
> | `shot.gd` | exposure is set after the damage is paid, `dice.gd:601` | `601` is the gambler's-rush line; exposure is set further down |
>
> **And the sweep had already been recorded as complete, which is what makes
> this a defect of the record rather than of the citations.** The block said
> *"Every `file.gd:NNN` in the `.gd` and `.md` files was extracted and resolved
> against the file as it stands"* — true of the extraction, and true of the
> resolution, and **not** true of the reading. A reader taking the block at its
> word would stop looking, and five false claims would keep answering for
> themselves. It is the same shape this file has now found three times: a
> measurement recorded, then treated as covering more than it measured.
>
> **The rule that survives it, and it is stronger than "cite the text":** a
> citation's test has to be the one that would catch the failure you are
> guarding against. "Resolves" was checked because an unresolvable citation is
> easy to spot; the drift that actually happened is an *invisible* one. Both
> citations that mattered — `dice.gd` lines 601 and 309 — point at real,
> non-blank, topically-adjacent lines, which is exactly what makes them
> expensive to notice and cheap to introduce.
>
> Three were genuinely wrong.
>
> | where | claimed | actually |
> |---|---|---|
> | `_balance.gd:808` | `run.gd` line 268 holds `picks.size() < 4` | `run.gd:331` holds `picks.size() < OFFER_COUNT` |
> | `test.gd:63` | `shot.gd:558` lists the five call sites | the listing is `shot.gd:588` |
> | `shot.gd:588` | haptics have "zero assertions — not here, not in `test.gd`" | `test.gd::_haptics_wired` asserts three |
>
> The first is wrong twice over, and that is what makes it the interesting one.
> Beyond the drifted line, the quoted code was **the mutation, not the shipped
> source** — `< 4` is what the experiment temporarily set, and it was put back.
> A reader who trusts the quote, opens `run.gd` line 268, and finds neither the line
> number nor the text concludes the experiment was never run and the histogram
> check's one empirical basis is fiction. Both halves had to be named: the
> mutation is now written as *"`picks.size() < OFFER_COUNT` at `run.gd:331`
> becomes `< 4` for the length of a run and is put back afterwards"*, which is
> longer and is the only version a reader can check.
>
> **And the correction was wrong too, which is the part worth writing down.**
> The first pass of this sweep replaced `268` with `284` and moved on — but `284`
> had drifted the same way, so the corrected value was stale on the day it was
> written down, and this table then carried it as the *actual*. One fix
> ratified a bad number twice and made it more credible each time, because a
> table cell reading "actually" is trusted further than the comment it
> corrects. The real line is `run.gd:312` and the real text is
> `picks.size() < OFFER_COUNT`; `OFFER_COUNT := 3` is a constant at `run.gd:29`,
> so quoting the literal `3` was a third copy of a number that already has a
> name. **A corrected citation is a fresh claim about a moving target, and the
> correction is the only citation in the repo that nobody re-reads**, because
> writing it feels like the end of the work. The haptics table below is the
> same mistake at larger scale — seven references, six off by one — and the
> paragraph that had *verified* that table said so in as many words.
>
> The second is a **second copy of a fact with nothing to propagate it** — the
> exact pattern the icon investigation turned up. `PLAN.md:601` already said
> `shot.gd:588` and was right; `test.gd:63` said `558` and was wrong. Same
> fact, two files, one rotted, nothing to have carried the correction. Only
> `test.gd` was edited, because only `test.gd` was wrong.
>
> The third is a **false negative**, which is worse than a false positive
> because it costs a reader their reason to keep looking. `shot.gd` said the
> haptics had no assertions "anywhere", which is a claim that a safety check is
> *missing*. `test.gd::_haptics_wired` then added three of them, reading the
> source text because `_haptic` is `mobile`-gated and cannot execute anywhere
> here. The sentence was overtaken by the very fix it prompted, and would have
> told the next reader to go looking for a hole that had since been half-plugged
> — so it now states the split honestly: two shake sites sampled by *running*
> `shot.gd`, three haptic sites counted by *reading* `test.gd`, and no gate in
> this repo has ever executed a vibration.
>
> **The first of these was checked, and the check was wrong — which is the
> only thing here worth recording.** The sweep confirmed both bullets and
> ratified them: *"the 'site' column is correct"* and *"It holds."* Neither
> did. All seven references are off, six by one line and `fight.gd:22` by four,
> and the sweep passed them because the structural half of its test — does the
> cited line exist, is it non-blank, is it in the right file — is satisfied by
> every one of them. A **paragraph written to record that a claim was verified
> is harder to catch than the claim**, because it reads as the end of the
> question rather than another instance of it, and because it recruits the
> reader's trust against re-reading it. The rule that follows from it is the
> one the citation sweep already states, applied one level down: *a verification
> is not a verification until it has been checked by something that would fail
> if the claim were false* — and a check that reads *"the column is correct"*
> back out of the document is a check that reads the document.
>
> What does hold, and is unchanged: PLAN.md 3.2b's haptics table lists five
> *triggers* over three call sites, and 3 haptic + 2 shake is still five call
> sites between the two systems (`fight.gd:647`, `1030`). The counts were never
> the problem; every number here was right and every line number was wrong.


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
> **It is now in the gate loop above, and the reason it was not is worth
> keeping.** It was documented in this note while the loop beside it listed
> gates 1–4 only, so a person running "all the gates" never ran the one gate
> that can see an export filter, and the note itself said the advice "belongs in
> the gate loop, before the build, not in a release checklist after one" — the
> diagnosis was right and the fix was not applied. `play/LISTING.md` still
> carries that checklist copy; it is now a pointer, not the only place.
>
> **What the safety note used to omit is the only part that can actually bite.**
> It argued safety by listing what the command does *not* touch: `--export-pack`
> "invites the reading that it writes into `build/`", and it does not, so it
> "overwrites no gitignored artifact and nothing that cannot be regenerated."
> Every clause of that is true and none of them is the risk. **It writes outside
> the repository.** `PROBE` is `/tmp/_pack_probe.pck` (`_pack.gd:71`) and the
> child is booted by `cd`-ing to `/tmp` first (`_pack.gd:75`, used at
> `_pack.gd:141`). Nothing in the project is damaged — that part stands — but a
> sandbox, a CI runner or any environment that denies writes outside the working
> tree refuses this gate outright, and the refusal looks like an unrelated
> permissions error rather than a property of the command. That is not
> hypothetical: it is refused here for exactly that reason, and the old note
> would have given a reader no way to predict it. Needs a writable `/tmp`.

> **The four mutable turn resources each have exactly one decrement site, and
> every one of those sites is guarded — so the invariant is structural, not
> merely asserted.** Asked as an exploit question (can a player drive a
> counter negative and buy re-rolls or Focus out of nothing?) and answered by
> enumerating writes rather than by trusting the existing checks:

> | resource | decrement sites | guard | pinned by |
> |---|---|---|---|
> | `rerolls_left` | one, `rerolls_left -= spent` | `spent >= rerolls_left` breaks the loop *before* the subtract | "budget exhausted", "one reroll spent" |
> | `focus_left` | one, `focus_left -= 1` | `focus_left <= 0` is the **first** clause of `focus_face`, which returns null | "no charge left", "a second focus is refused" |
> | `banked` | one slot, cleared to `-1` in two places | `i < 0 or i >= dice.size()` refused at the tap | "an out-of-range tap is refused outright" |
> | dice count | one, the `ADD_DIE` arm | `dice.size() >= MAX_DICE` skips the card | `shot.gd`'s `dice.size() == 6` |
>
> **The one that looked exploitable is the re-roll, and it is guarded in the
> least obvious place.** `toggle_pick` checks `over`, `spent` and `banked` —
> and **not** `rerolls_left`. So a player can queue more dice than they have
> budget for, and the subtraction is by the full count of what it rolled. That
> reads as a free-spend hole until you reach `resolve_rerolls`, whose own
> comment says the rule is "enforced here, not in the UI": the loop refuses
> each die once `spent >= rerolls_left` and logs "No re-rolls left for…", so
> the counter cannot underflow. The guard is a `continue` *above* the
> `spent += 1` eight lines further down, so a read-from-the-top pass sees an
> increment that looks unconditional and a subtraction that looks unguarded.
>
> **Recorded for the edit, not the report: adding a second decrement to any of
> these is what breaks this, not changing the guard.** Every row is safe
> because there is exactly one place the value falls, and a second one would
> be unguarded by construction — the checks above would still pass, because
> they assert the outcome from the normal path.

> **The five enemy behaviour names are all true; the one comment behind them
> was not, and the check that should have caught it could not have.** The
> player-facing surface is `behavior_name()` — five strings, one per behaviour.
> Each was read against the code, not against the comment beside it:

> | string | implementation | |
> |---|---|---|
> | "hardens each turn" | `armor = min(armor + 1, ARMOR_GROW_CAP)` at the top of `take_turn` | **false — see the tag finding below** |
> | "drinks your blood" | heals `hit / 2`, and `hit` is post-block | true, but see below |
> | "curses a die" | drags one random die to its worst face, never the held one | true |
> | "rages each turn" | `atk += 1`, uncapped | true |
> | "braces off weak hits" | `armor = min(armor + low, CAP)` for each face with `0 < hit < 6` | true |
>
> **`BEH_LIFESTEAL`'s comment said "heals for half the damage it deals", and
> that is wrong in a way a balance pass would act on.** The heal is
> `mini(max_hp - hp, hit / 2)` where `hit = atk - soaked` — half of what *lands
> on you*, not half of what the enemy deals. Blocking therefore does double
> duty: it cuts the damage and it cuts the healing, and a comment claiming the
> healing is independent of the block invites a rebalance that spends Ward's
> block value twice. Now reads "half the damage that *lands*".
>
> **The BRACE claim is where this nearly went the other way, and the near-miss
> is the finding.** Reading `_react(low)` with `enemy.armor = mini(enemy.armor +
> low, ...)` next to a constant annotated "+1 armour per hit" looks like the
> comment is wrong and the code sums damage. It is not: `low` is incremented by
> **1** at both accumulation sites, so it is a count of faces under
> `REACT_LOW`, and the comment is right. But nothing in the suite could tell the
> two readings apart — all three existing BRACE cases put exactly **one**
> qualifying face on the board, and per-hit, per-damage and flat-one-per-resolve
> all produce 1 there. A check added on top of those would have been the first
> to put two faces down. It asserts 2 for Blade 4 plus Sunder 1, and was
> falsified rather than trusted: mutating `low += 1` to `low += face_hit(i)`
> gives `2 of 8556 CHECKS FAILED` and exit 1 — this check *and* the pre-existing
> "a BRACE takes one armour for the one chip", which catches it too.
>
> **The generalisation, and it is the same one the citation sweep keeps
> arriving at: a test that cannot distinguish two rules is not testing either.**
> The three old cases were real, green, and worthless for the question actually
> being asked about them.

> **Those five names were being title-cased on the way to the screen, and the
> third row above is the worst of it.** `fight.gd` renders the tag
> `tag.capitalize()`, and `String.capitalize()` is **title case** in Godot 4 —
> it uppercases the first letter of *every* word and lowercases the rest. All
> five names are multi-word, so all five were affected: `"curses a die"` reached
> the player as **"Curses A Die"**, alongside "Hardens Each Turn", "Drinks Your
> Blood", "Rages Each Turn" and "Braces Off Weak Hits". The strings are authored
> in sentence case precisely so the UI does not have to know they are lowercase;
> one `.capitalize()` undid that.
>
> Measured, not remembered. The first version of the check asserted that
> `capitalize()` is sentence case, written to *pass* so the gate could settle
> the question — and the gate answered no, failing at eight of the nine depths:
> `8 of 8565 CHECKS FAILED`. Depth 0 is the Grunt, `BEH_NONE`, whose name is
> `""` and therefore trivially satisfied any rule. That version was then **wrong
> as a gate** and was rebuilt rather than kept: it pinned the engine's semantics,
> so it stayed red against correct code *and* would have gone green again if
> `fight.gd` were reverted. Measuring once is worth it; a check that cannot go
> green is not a check.
>
> **What ships instead.** `fight.gd` sentence-cases by hand —
> `tag.substr(0, 1).to_upper() + tag.substr(1)` — and two checks guard it: the
> names must arrive from `behavior_name()` all lowercase (runtime, real
> property of `dice.gd`), and `fight.gd` must contain no `.capitalize()` at all
> (source, anchored on *absence* so a future tag path is covered too, with
> comment lines stripped so the check does not match the comment explaining it).
> Both were falsified in the same run: reverting the fix and capitalising one
> name gives `2 of 8565 CHECKS FAILED`, exit 1.
>
> The finished string itself is checked in `shot.gd`, which is the only place
> `enemy_tag.text` exists — it is set in `_refresh`, which needs the mounted
> panel. That check borrows the Golem's behaviour for the assertion and puts it
> back, because `_on_play` opens at depth 0 where the Grunt's `behavior_name()`
> is `""`, and "Armour 12   Exposed" is the same string under either rule. It
> is **not executed by any gate runnable here**: `test.gd` loads `shot.gd` to
> assert it parses and never calls its checks.
>
> **The same blind spot sat in `shot.gd`'s own comment**, which justified
> capitalised search strings by saying the tag is "capitalize()d on the way
> out". That was true when written and became false the moment the line above
> changed — the same shape as this sweep's `run.gd:284`, a correction that
> outlived its own subject, and like that one it reads as settled *because* it
> explains itself.

> **One claim in this sweep was falsified before it shipped, and the way it was
> wrong is the point.** `shot.gd` spells every number in the store description
> by indexing a lookup table with the constant that owns it — `COUNT_WORD` has
> thirteen entries, indices 0..12 — and **seven constants** are indexed into it
> at eight sites, `POOL_SIZE` twice. Six of the seven are 9 or smaller. The
> seventh, `COUNT_WORD[Rules.Enemy.ARMOR_GROW_CAP]` — that site now reads
> `_count_word(...)`, so the literal is gone from `shot.gd` and the line it sat
> on is somebody else's — sits at **exactly 12**, the last valid index, and
> `ARMOR_GROW_CAP` is a balance
> constant in a project with a whole tuning harness. That reads like an
> unguarded coupling with zero headroom: bump the cap by one and a routine
> balance edit indexes past the end of a list, in the one script no gate runs.
>
> A check was written for it in `test.gd` — deliberately not in `shot.gd`,
> because a check in the unrunnable script guards nothing — asserting the table
> has room. Then the constant was moved to 13 to see.
>
> **It is guarded, and the check was deleted.**
> `COUNT_WORD[Rules.Enemy.ARMOR_GROW_CAP]` sits in a const-folded literal, so
> the out-of-range index is not a runtime error at all: `shot.gd` fails to
> **parse** — `Cannot get index "13" from [...]` — which `test.gd`'s existing
> script-load check already reports red, as `res://shot.gd fails to parse (error
> 43)`. `dice.gd` fails a balance check of its own — `it still lands 9 at the
> armour cap` at `dice.gd:1678`, guarding `cap.pierce(15, 6) == 9` — and `run.gd`
> reports one
> failure of its own, and autoplay's average clear depth moves 8.0 to 6.8. Both
> suites' messages print under `test.gd` because `Check.failures` is a static
> shared by all three and the last `report()` prints the lot — so the `[test.gd]`
> prefix on a failure that lives in `dice.gd` is the reporting suite, not the
> origin.
>
> The new check was worse than useless as well as redundant: on the mutated
> constant it **threw** instead of failing, because `load("res://shot.gd")`
> returns a script that failed to parse and therefore has no `COUNT_WORD` to
> read. A check that raises instead of reporting is the same defect as one that
> cannot fail, one level deeper down.
>
> Inside the table the mechanism corrects itself anyway: a cap of 11 parses, and
> "to a ceiling of eleven" is then true by construction. Only the out-of-range
> case was ever in question, and that is a parse error `test.gd` was already
> catching.

> **The save had six fields, and the two that decide what a player sees next
> were the two with no assertion.** `load_stats()` returns exactly six — the
> literal `{"best_depth": 0, "runs": 0, "wins": 0, "unlocked": 0, "loadout":
> [], "muted": false}` it builds its defaults from. Three were pinned by
> `run.gd`'s own `self_test`: `best_depth` and `wins` by the two checks sitting
> under `record_run(5, true)`, `unlocked` by the check on
> `load_stats()["unlocked"]` under the third. `muted` was pinned by the two
> `shot.gd` checks reading `load_stats()["muted"]`, one either side of the
> master-bus toggle. Every one of those five was a bare line number when this
> was written, and four of the five had drifted by the time it was next read —
> the two `muted` pins by ten lines and all three `run.gd` pins by fifty-four,
> because edits above `self_test` move a pointer that names something below
> them. So they name code now. Nothing read back `runs` or `loadout`, and both have readers
> that a player would notice immediately:
>
> | field | reader | consequence of an off-by-one |
> |---|---|---|
> | `runs` | the title screen's `"%d runs · %d victories"` label and the `"Play" if int(stats["runs"]) > 0` ternary that builds the Play button | the button's label, which reads "Begin the run" at zero and "Play" above it |
> | `loadout` | `saved_loadout()`, called from `_init` | the starting hand of *every run*, since `_init` runs on every `RunState` |
>
> Three checks added (the three under the `runs_before` probe in
> `record_run`'s round trip), asserted as deltas rather than totals
> because five `record_run` calls now sit in that function and an absolute count
> goes stale the moment a sixth is added. All three forced red one at a time,
> and the third is the one that earns its place: with `record_run` still
> writing the field correctly, inverting `saved_loadout()`'s empty-fallback
> ternary goes **only** the third check red. The round-trip check reads the
> dictionary directly and cannot see the read path, so that branch had nothing.
>
> **I called the `loadout` write dead first, and it is not.** The grep was
> `["loadout"]` and missed `saved_loadout()`'s `.get("loadout", [])` — the reader
> was there the whole time. Recorded because a "dead write" is the finding that
> would have justified deleting a feature, and the grep that produced it was
> one token too narrow.
>
> The defensive half is genuinely sound, which is worth stating because it is
> the shape that *would* be broken: `load_stats` guards its entire merge with
> `typeof(parsed) == TYPE_DICTIONARY`, so a truncated or
> half-written file returns defaults instead of crashing on a null, and both
> write paths — `set_muted` and `record_run` — are
> read-modify-write *through* `load_stats()`. A second writer that built a
> fresh dictionary would silently erase the other field, and a gate that
> asserted each field separately would not have noticed. Neither is present.
>
> One consequence of the same table, which is a real limit rather than a
> defect: `muted` is asserted by **gate 3 only**. Gate 1 green does not mean
> the mute choice survives a restart, because nothing in `run.gd`'s
> `self_test` — which is all gate 1 runs — touches that key.

> **Gates 3 and 4 could destroy the player's save, and the way to find out was
> running six of them at once.** *(Historical: the staging this describes is
> gone. Both tools redirect the save path now — see the Superseded block below.
> What follows is kept because the six-instance measurement is the evidence
> for the fix, not because the code is still there.)* Gate 3 came back red
> exactly once in ~24 runs,
> one failed check, and I lost the message — my `grep` took only the summary
> line, so the first thing I had was a failure with no text. Worth recording as
> process: the fix for "I threw away the evidence" is to reproduce it and keep
> *everything*, which is what the next attempt did.
>
> The cause is `shot.gd`, and it was never a check problem. `BACKUP` was the
> fixed path `/tmp/dice-save-backup.json`, and `shot.gd` stages the run by
> copying the real `user://` save out to it (now `:71`) and deleting the
> original (now `:73`). Run B starting while run A is in flight finds no save
> — A deleted it — so it fell through to a sweep that deleted a backup file
> sitting there, commented `## left over from an earlier run`. A's in-flight
> backup is indistinguishable from that leftover. A's restore (now `:733`) then
> failed to open a file that no longer existed, and the save deleted at `:73`
> was never put back.
>
> Measured, not reasoned. Six instances of gate 3 at once:
>
> | instance | checks | what went red |
> |---|---|---|
> | 1 | 766 | `and the choice is written to the save` |
> | 3 | 766 | `pressing it again unmutes`, `pressing the button mutes the bus` |
> | 5 | 766 | `pressing the button mutes the bus` |
>
> All three at `user://`, all in the save-mute section, all with
> `Failed to open /tmp/dice-save-backup.json` beside them. 39 further runs, alone
> and then six-wide, produced no other failure — so this is the whole of it, and
> the 766/767 alternation that remains is the documented `my_hp - panel.enc.hp > 0`
> guard (a turn that rolled all block stays silent), with the floor at 766.
>
> The fix is the format string, and it is one line: `BACKUP` now carries
> `OS.get_process_id()`, so two runs hold two backups and each restores its own.
> The leftover sweep is **deleted** rather than fixed, because the only version
> of it that could not be wrong is one that never deletes a file holding
> someone's save. A crashed run now leaves its backup on disk, which is the
> recoverable outcome; `/tmp` is reaped anyway.
>
> It is `var BACKUP`, not `const`, and that is not a style note. A function call
> is not a constant expression, so the `const` spelling is **error 43 at load**,
> which gate 1 caught on the first run of the fix. This file already documents
> the identical trap three lines above, for `SAVE := RunState.SAVE_PATH`, and
> the answer it gives is `var` — so the trap was documented, adjacent, and
> walked into anyway. Second time this file has needed the same correction.
>
> **Superseded: `shot.gd` does not stage the save at all any more.** The per-pid
> `BACKUP` above fixed the race and kept the window — and then `_rects.gd` turned
> up carrying the identical pattern, which showed the window never needed to
> exist. Both tools now redirect the save path and delete nothing of the
> player's:
>
> ```gdscript
> RunState.SAVE_PATH = "user://shot-scratch.json"
> if FileAccess.file_exists(RunState.SAVE_PATH):
>     DirAccess.remove_absolute(ProjectSettings.globalize_path(RunState.SAVE_PATH))
> ```
>
> `SAVE`, `BACKUP`, `had_save`, the staging block and the restore are all gone —
> 30 lines of declaration comment and 9 of code, for 3 lines. `copy_absolute`
> no longer appears anywhere in the repo, and every `SAVE_PATH` assignment in
> it (`_rects.gd`, `run.gd`'s own self-test, `shot.gd`, `test.gd`) now points
> at a scratch file. **`user://run.json` is never written, moved or deleted by
> any tool here.** That is the whole of the data-loss class, closed at the root
> rather than narrowed, and the reason it is worth doing at all is that the
> narrow version had already been written and shipped unverified.
>
> The `var`-not-`const` note went with the variables it described. That is not
> a loss: a member initializer reading a static var is error 43 at load, and
> gate 1 turns that into a one-line headless failure.
>
> The floor is untouched at **766**, and not by hope: the splice removed exactly
> one `_check` (`BACKUP.contains(pid)`) and added exactly one
> (`SAVE_PATH == "user://shot-scratch.json"`), and neither the declarations nor
> the restore block contained any. The replacement pins a *stronger* invariant —
> the old one could only say "unique", this says "not yours" — and it reads the
> value the remove and every later write actually use, so a source grep cannot
> satisfy it.
>
> **Still not run, and this change does not make that safe to assume.** The new
> code is verified as *parsed* (gate 1, 8539, exit 0) and nothing more. If the
> redirect silently failed to take, gate 3 would dump a title screen carrying
> the player's real stats — a wrong screenshot, visible and harmless, against
> the old code's version of the same failure destroying the save. The failure
> modes are not symmetric, which is the only reason this is safe to change
> blind. It is not safe to *run* blind, and I am not running it: the denial of
> gate 3 stands and is not being re-attempted by another route.

> What the per-pid check asserted, and what had **not** been shown at the time: it read the
> **value** — `BACKUP.contains(str(OS.get_process_id()))` — so it fails the day
> the format goes back to a fixed name, and unlike a source grep for the pid in
> the declaration it cannot be satisfied by a path nothing ever opens. But it
> has **never been observed red.** Two attempts to drive it red were both
> blocked before `godot` ran: the first by the sandbox classifier, on the
> grounds that the reverted form is the data-losing configuration and must not
> be executed; the second by the same classifier timing out. The gate-3 command
> itself was then denied outright for touching `/tmp` and the real save, so
> **gate 3 has not been run against this change at all** — not once green, not
> once red.
>
> What *is* verified: gate 1 at **9041** and gate 2 at **167697**, both green
> against this tree, and gate 1 is what proved `shot.gd` parses. The mechanism
> is a one-line format plus a deleted branch, and the read-back path at `:728`
> is untouched. Gate 3 must be run before this is believed:

> **Gate 1's floor was 26 below its own count, and its comment said it must not
> be.** `test.gd` passes `Check.report("test.gd", 8539)` and printed 8565, so
> 26 checks could have been removed or skipped without the gate noticing — which
> is verbatim the failure the paragraph above that line describes ("rather than
> as a floor that quietly stopped meaning anything"), sitting inside the
> paragraph that forbids it.
>
> The cause is the direction the comment argues about. It says a floor fires on
> *fewer* checks, so **adding** a check moves the count up and leaves the gate
> green — "which is correct". It never mentions that adding is also how the
> floor goes stale, and that the slack then buys silent loss in the other
> direction. Nine checks added over this sweep moved the count 8556 → 8565; the
> floor was never re-stamped, because nothing said to.
>
> Set to the live 8565 and falsified: deleting one check reports `8564 checks
> ran, 8565 expected -- 1 never executed`, exit 1. The same deletion under the
> old 8539 reports 8564 > 8539 and passes.
>
> **This is only safe because gate 1's count is a structure, where gate 2's is
> a statistic** — the distinction the decomposition above already draws, and the
> reason the two floors are now 145,672 apart and both correct. `_balance.gd`'s
> 22025 is structural on every seed and *must not* be raised to 167697: the
> count is fights played across 22000 runs, so calibrating on it goes red on a
> re-roll having found nothing, and stays green through every abort it was
> written to catch. Gate 1's 8565 held across six consecutive runs, and every
> one of its checks is a fixed assertion or one per iteration of a fixed-length
> loop, so there is nothing there to drift.
>
> It has drifted since, upward, which is the safe direction and the reason the
> argument above holds: 8565 → 8568 (the card-copy magnitudes) → 8572 (the
> Hexweaver clause) → 8599 (the three log-line article sites, 9 depths × 3) →
> **8602** (the stat-bar absolute) → **8606** (the ARMOR_GROW ceiling, 4) →
> **8620** (the depth off-by-one, 12 mapping + 2 source) → **8622** (the
> ARMOR_GROW behaviour tag, + the re-anchored stat-bar row, net 2) → **8663**
> (`_citations` over the `.gd` comments, 41 — and the first move here that is
> neither a fixed assertion nor a fixed-length loop, so its count is a property
> of the comments rather than of the code; see the `_citations` entries) →
> **8850** (the same check widened to the three markdown documents, and six
> citations that were on purpose rewritten as prose so it could stay green) →
> **8860** (the BEST HIT caption's three branches) → **8864** (the exposed
> turn-summary modifier, 4) → **8868** (the thorns log order, 3, and one more
> citation site from re-citing two) → **8875** (the stale face label, 7) → **8892**
> (the wrapped-quote-form guard, 17, net of one citation converted and one
> rewritten as prose because it quoted a literal that no longer exists) →
> **8922** (the `_pack.gd` walk, 6, plus eight of the eleven bare line numbers in
> its own paragraph given a filename and a quote, 24) → **8927** (the palette's
> contrast invariant, 5) → **8930** (the `effect_labels` citation in the
> contrast finding, added plain and immediately converted to quote form, +3 —
> which is the whole argument for the form: the plain one is cheaper and
> rots) → **8941** (the sound-name bijection, 8, and one citation for the
> block-on-Focus claim) → **8944** (one citation for the forward-only sound check
> that motivated `_sfx_names`) → **8957** (six citations for the icon and export
> finding, one of them quote-form) → **8980** (eleven for the `_check.gd` audit,
> one of them quote-form, and the decomposition's own third error found by having
> to re-derive a new total from the old one) → **9031** (the citation sweep, +51,
> and deliberately not decomposed further into named groups — the block recording
> it is about a hand-built approximation of a regex that undercounted the very
> sites it was sent to find, and writing a tidy per-group breakdown is the same
> reflex. A single global replace of the old count is its own hazard here: the
> first pass at this step rewrote the sweep's own result too) → **9039** (the
> `_balance.gd` floor audit, +8, four plain citations in its block) → **9041**
> (the `BALANCE.md` audit, +2, and only one of them — a citation into markdown
> is not one the gate can check, which is the finding as well as the
> arithmetic). The number that matters is the measured one, and it reconciles:
> 145 plain and 23 quote-form sites give 359 + 17, the 76 own checks give 376,
> and 8434 + 155 + 452 is 9041. The 303 that used to sit in that reconciliation
> was wrong on its own terms, not merely stale: it costed the twenty-three
> quote-form sites at one check each where the gate charges three, so it read
> 303 where 349 was right — the fourth error in a sentence about arithmetic,
> and the only one no run of the gate could have caught.
> Every move re-stamped the floor in the same commit that made it, which is the
> whole fix — a floor that has to be re-stamped by hand is one that eventually is
> not.
>
> ### The BEST HIT caption named armour for a roll that had no damage in it
>
> The fight HUD shows the most any one die can land this turn, after armour, and
> at zero it explained why: `ARMOUR n — NOTHING LANDS`. That reads as a claim
> about the enemy, and it is one — for the ordinary case, where the hand rolled
> damage and the armour ate it. Zero has a second cause, and the copy had no room
> for it.
>
> Ward is six block faces. Riposte is five block faces and a junk. Both are
> ordinary dice — Ward ships in the starting library, Riposte is one of the three
> `ADD_DIE` grants — and `set_loadout` filters titles against what is owned and
> nothing else, so the die picker will hand you `Ward + Riposte + Sunder + Spark`
> and the run will start on it. Sunder and Spark each carry two faces that deal
> nothing, which is what lets the other two join them on the same roll. When all
> four do, `best` is 0 — and against a Grunt, whose armour is 0, the caption read
> **`ARMOUR 0 — NOTHING LANDS`**. True that nothing lands, and blaming armour on
> the one enemy in the roster that cannot be the reason.
>
> The comment above the line said the caption was there to *"name the cause"*,
> which is the part that fails: at zero with nothing rolled, the cause is the roll
> and the caption names something else. Worse than a wrong number, because the
> number is right and the player is sent to look at the enemy.
>
> Fixed by splitting the two, and the discriminator is free: `raw`, the most
> damage in the pool ignoring armour. `raw == 0` means nothing was rolled;
> anything higher means something was and the armour took it. They cannot
> overlap, because armour only ever subtracts, so there is no case where both are
> true and no case where neither is.
>
> The caption now goes through a `static` so it can be tested at all. It was an
> inline ternary inside `_refresh`, and `_refresh` builds the entire fight scene,
> so before this the only way to read the string was to stand up the fight and
> screenshot it — which is not a test, and is the reason the claim survived. The
> premise the caption rests on is pinned separately in `_best_caption`, because
> that part *is* checkable headlessly and it is the part that was silently
> load-bearing: Ward and Riposte having no damaging face, Sunder and Spark each
> having two, the picker accepting that four, all four being able to show a
> nothing-deals face at once, and a Grunt reporting armour 0 while that hand
> reads `best` 0.
>
> The mutation is the useful part: deleting the `raw == 0` branch turns exactly
> one check red — *"and the caption names the roll instead of armour 0"* — so the
> new branch is live and the other two are not carrying it.
>
> It is also the fifth time this shape has turned up. *"Fixing an instance, not
> the claim"* was recorded four times before, and this is the same defect wearing
> a different hat: a UI string that asserts a cause, written against the case its
> author had. Every previous instance was a wrong number; this one had the right
> number and the wrong sentence around it, which is strictly harder to notice
> because nothing about the display looks broken.
>
> Adding the function also shifted `fight.gd` down by sixteen lines past the
> insertion point, which silently moved two `play/LISTING.md` citations onto
> unrelated code — and `_citations` stayed green on both, because that is the
> documented half of the gate that only checks a plain citation is in range and
> non-blank. Restated to the lines they now name. This is the first time the
> limitation has fired on the change that introduced it rather than on some older
> drift, which is the sharpest evidence yet for closing it: it was the fourth
> hand correction of the session, made to a document edited for an unrelated
> reason.
>
> *(That paragraph is why the next one says "line 1559" in prose rather than
> writing the citation out. Quoting the broken form to illustrate it trips the
> gate that is checking it — the same shape as `_enemy_tag`'s `ponytail:` note,
> and the reason that comment describes the pattern instead of spelling it.)*
>
> ### The turn summary credited armour on turns where armour was never read
>
> Every resolve ends `"You deal N (armour A). You gain B block."` The
> parenthetical names the modifier, and against an armoured enemy that is the
> armour. But `Enemy.pierce` opens with `if exposed > 0: return dmg * 3 / 2` —
> it returns before it ever looks at `armor`. On a Precision Strike turn every
> face hit that turn went through that line, so the log named a number that had
> not been subtracted from anything, and did so in the same breath as the card
> saying the hits count for half again. Same defect as the BEST HIT caption one
> screen over: right number, wrong sentence around it, blaming a thing that was
> not involved.
>
> Read `enemy.exposed` *before* the decrement that spends the window, which is
> seventeen lines further down — so the line reports the value that governed the
> resolve rather than the one that outlived it. Rush is the near-miss beside it:
> `dealt += maxi(RUSH_FLOOR, ...)` is added after `pierce`, so a Gambler's Rush
> turn is also part armourless, and the parenthetical is still incomplete there.
> Left alone deliberately — incomplete is a different defect from false, and
> naming the exposure is the part that is actually untrue.
>
> `dice.gd`'s own comment above that line already said why none of this showed
> up: the resolve paths *"all passed on unarmoured enemies"*. On an unarmoured
> enemy `(armour 0)` reads as harmless, so the suite could not see the shape of
> the bug no matter how many seeds it ran. The two new encounters are armoured
> on purpose, which is the whole comment turned into a precondition.
>
> Fixing it cost seven lines above everything below, which re-stated five
> citations across three files — the `run.gd` and `shot.gd` pair that has now
> drifted twice, and two more in `PLAN.md` that had been wrong much longer and
> were passing for a different reason. See the drift entry above: one of them
> was fifty-six lines stale and survived because its target line happened not to
> be blank. That is the second time in one session that a citation has been
> found wrong by an unrelated edit rather than by looking at it, and it is the
> argument for the gate having caught it at all that the remaining loose half is
> the cheaper thing to close.
>
> ### The log answered the enemy's blow out of order, and dropped it entirely
>
> `take_turn` applies the enemy's attack first — `hp -= hit`, `block = 0` — and
> reported it last, after lifesteal and after thorns. Two things were wrong with
> that at once, and only one of them is visible in a screenshot.
>
> The visible one: when thorns finished the enemy, the `return` inside that
> block came *before* the hit line, so the line never ran. The player watched
> ten damage leave their health bar and the log ended on the enemy's corpse:
>
> ```
> Spiky blocks your path. | Thorns deal 4. | Spiky dies to your thorns. |
> ```
>
> Nothing in the log accounts for the damage. The bar moved, so it is not a
> mystery exactly — but the log is the channel that narrates the turn, and it
> narrated a kill while skipping the attack that earned the counter. Reordering
> the append to sit where the subtraction sits fixes both halves, because the
> non-lethal case was also reading backwards: the counterattack was announced
> before the attack it answered.
>
> Worth recording for the wrong reason it was found. It was not found by
> reading — it was found by the **ordering check** failing, and that check was
> nearly worthless: written first as `find("hits for") < find("Thorns deal")`,
> which is *true* when the first string is absent and the index comes back −1.
> It passed against the broken code. Tightened to require both indices ≥ 0, it
> then went red against the same code and green against the fix, and inverting
> it now goes red again — so it discriminates. That is the second time this
> session that a check written for a real defect was itself vacuous, after the
> `Check.check(true, ...)` in `_best_caption`. Both were caught the same way:
> by running the thing the check was supposed to catch.
>
> ### The gate that watches the export filter describes a bug that was fixed
>
> `_pack.gd` opens by explaining why it exists: *"The export filter is a list of
> globs in `export_presets.cfg` and nothing checks it. That is not
> hypothetical: the Android preset excludes `_*.gd` ..."* Three claims, and all
> three are false now.
>
> The filter is **not** a list of globs. `export_presets.cfg` carries
> `export_filter="all_resources"` — an option — and the globs live nowhere; both
> presets carry a literal `exclude_filter` naming eight dev-only files. And it
> **does not** exclude `_*.gd`. It never could: that glob was fixed in `3e743e5`,
> titled *"fix: the Android export shipped a rules layer that cannot parse"*, and
> that commit's own message is the one that documents the glob, the black screen
> and the preloads it broke. The current list does not contain `_check.gd`, and
> its being absent is the entire reason the build is not broken.
>
> So the header describes an incident **in the present tense, permanently**,
> because the file was written during the incident and never revisited. The gate
> itself is exactly right — it is the regression test, and the named check at the
> bottom asserts `_check.gd` ships precisely so the glob cannot come back
> unnoticed. Nothing about the code is wrong. Only the reason a reader is given
> for it, which describes a live bug in their build that has been fixed for the
> life of the repository. This is the seventh instance of the same shape and the
> first where **the thing being claimed is absent rather than inaccurate** — five
> wrong numbers, one wrong sentence, and now a whole paragraph about a closed
> incident. A file explaining why it exists is the highest-traffic prose in a
> gate, and it is the prose most likely to be written once and never read again.
>
> ### And none of that gate's logic was ever executed by anything
>
> Reading `_pack.gd` closely turned up something worse than the stale header,
> which is that its entire decision-making has never run. `_init` exports a pack;
> the export is denied here, so the two pure functions below it — `_stored`, which
> parses the exporter's log, and `_referenced`, which decides what must ship —
> were reachable only from the one code path that cannot run. `test.gd` listed
> `_pack.gd` in its load array and stopped there: two checks that it parses. The
> logic had **zero** coverage, and the file whose whole purpose is catching a
> defect no other test can see was itself untested.
>
> Both take everything they read as an argument and touch no instance state, so
> `static` is not tidiness — it is the only reason a test can reach them at all,
> because instantiating the script runs `_init`, which exports and then calls
> `quit()`. That rewrite is the one risk in here, because the script that got
> changed is the one that cannot be run to find out. It is covered anyway: GDScript
> resolves static calls at compile time, so a conversion that broke the bare
> `_stored(log)` and `_referenced(shipped)` calls inside `_init` would be a parse
> error, and the `UI` loop's `reload()` check catches exactly that and reports
> parse failures separately from load failures. `_pack.gd` reloads clean.
>
> Six checks now cover the walk, and each was mutated to confirm it is
> not vacuous: the reference regex matching nothing takes down exactly the two
> path assertions; a required path that does not exist takes down exactly the
> one that counts absent paths; removing the `.remap` fold takes down exactly
> its own check. The seed deliberately **omits** `_check.gd`, because
> `_referenced` returns its own seed and a seed containing the file under test
> would make the assertion true without a walk having occurred.
>
> Two things came out of writing them that were not the point. The check that
> asserts no required path is absent from the repository passed **trivially**
> under the broken-regex mutation, because an empty walk has nothing absent in
> it — the third vacuous check of this audit, and the first one written
> deliberately as a universal property, which is exactly why it was the easy one
> to get wrong. It now also requires a non-empty walk. And the `.gdc` fold check
> was red on its first run against **my own test input**: a binary-exported
> script is stored as `run.gdc`, not `run.gd.gdc`, because the exporter swaps the
> extension. `script_export_mode=2` in both presets says encrypted, and the
> transform in the code is right and my synthetic line was wrong — the check
> caught the error on the run that introduced it, which is the cheapest a
> correct check can be.
>
> One claim in that file's header was false in the other direction, and it is
> worth recording because the *replacement* was nearly adopted on its strength.
> The header said the dependency set was walked out with
> `ResourceLoader.get_dependencies`. It is not, and it should not be: measured,
> it returns `["res://game.gd"]` for the main scene and an **empty list for
> every `.gd` in the project**, including both that preload the rules layer. A
> walk built on it stops after one hop and never reaches `_check.gd` — not the
> file it is least able to miss, the one the gate exists to watch. The lower
> comment already said as much, so the file contradicted itself: a header
> describing a mechanism its own body had replaced, having gone stale the same
> way its export-filter paragraph had, in the same file. A header is the part of
> a file most likely to be written once from memory.
>
> ### The die's name was illegible on the three states where you are asked to act
>
> `fight.gd` sets a die card's name label once, to `MUTED`, and never recolours
> it — while the label beneath it, `effect_labels`, is recoloured per state three
> lines apart. The justification is written immediately above the assignment:
>
> *MUTED, not FAINT: the die's name is its identity across a run, not a
> de-emphasised tag. FAINT measured 2.15:1 on CARD_HI — under the 4.5:1 of
> WCAG 2.2 SC 1.4.3...*
>
> Every word of that is true, and 2.15 is the right number for the right
> surface. **But a die card's fill is not always `CARD`.** It becomes `CARD_HI`
> in four states, and three of them render at full brightness: **armed** as a
> Focus target, **picked** for a re-roll, and plain **hover** — and the last two
> are not edge cases, they are how a re-roll is queued and how the Web build
> looks whenever a mouse is over a die. MUTED on `CARD_HI` was **4.13:1**.
> Legible, and short, on exactly the states where the player is being asked to
> do something. The remaining state, `held`, also takes `CARD_HI` but multiplies
> the card by `SPENT_DIM` first, which drops the name to 1.96:1 — that one is an
> inactive component and WCAG 1.4.3 exempts it, so it is not the finding; the
> other three are.
>
> The label is what makes it a finding rather than a tint: `name_labels[i]` is
> assigned once and never recoloured, while `effect_labels[i]` three lines below
> it is recoloured per state —
> `effect_labels[i].add_theme_color_override("font_color",` at `fight.gd:882`
> The die's *name* is its identity across a run, so it is the one string that
> must stay readable through every state — and it is the one string with no
> per-state path.
>
> `MUTED` is now `#949eb2`, which clears at 4.79 on `CARD_HI` and 5.44 on `CARD`.
> That is a real cost, taken knowingly: the name's separation from `TEXT` drops
> from 2.81:1 to 2.42:1, so the die's title is now less obviously recessive than
> it was. The alternative was recolouring `name_labels` per state the way
> `effect_labels` already is, which preserves the hierarchy and costs a line of
> code the player sees change. One constant was the better trade because it also
> covers the hover case, which no recolouring path would.
>
> The reason no one caught it is the shape this audit has been finding all along,
> one level down: **the invariant existed only as a ratio written in a comment.**
> Nothing measured it, so nothing could notice that the surface it was measured
> against was not the surface it was used on. Five checks now compute it, and
> they assert the *decision* rather than the *number* — MUTED clears 4.5 on the
> lightest surface it is ever drawn on, FAINT clears it nowhere so that "MUTED,
> not FAINT" still means something, and TEXT and MUTED stay visibly apart.
> Asserting 2.44 exactly would fail on a deliberate palette change for the wrong
> reason and say nothing about whether the change was right.
>
> Three things came out of writing them, none of them the point.
>
> **`Color.get_luminance()` is the wrong function and it looks like the right
> one.** It applies the 0.2126/0.7152/0.0722 weights to *un-linearised* sRGB
> values, so it understates dark-on-dark contrast badly enough to change the
> answer: `TEXT` on `CARD_HI` reads **4.13** under it and **11.60** under WCAG,
> and FAINT on `CARD` reads 2.11 rather than the 2.44 this codebase has quoted
> since before the audit began. The first `_contrast` written used it and
> reported 1.00:1 for everything. So the numbers in those comments were computed
> *correctly, outside the engine* — and the one helper any reader would reach for
> gives a different answer to the same question. Six lines of `_srgb` are the
> entire gap, and they are the only reason this finding is measurable in-repo.
>
> **The first threshold I wrote could never have passed.** The check that MUTED
> stays visibly apart from TEXT was given a bar of 3.0, invented rather than
> measured, and it failed against a palette that had been in the repository all
> along: the design point is 2.81. A check that only passes for the value it was
> invented against blocks the next change without saying anything about whether
> the change was right. It now sits at 2.0, and the 0.39 of separation the fix
> cost is written down rather than discovered later.
>
> **And the helper itself had a copy-paste bug that no amount of reading found.**
> `_ratio` took `hi` and `lo` from the *same* ternary, so it returned 1.00 for
> every pair — including for `TEXT` on `CARD_HI`, which is the ratio that decides
> the whole question. It was found because the check went red with a value of
> exactly 1.00, which is not a contrast ratio any two colours can produce, and
> that is not something to read your way to.
>
> Both mutations discriminate: restoring `MUTED` to its old value takes down
> exactly the `CARD_HI` check, reporting **4.13** — the defect's own number, now
> caught by the gate rather than by reading. Making `FAINT` compliant takes down
> exactly the check that says "MUTED, not FAINT" still means something.
>
> A third, and the one that matters most, because it moves the other half of
> the pair: lightening `CARD_HI` to `#39415a` takes down exactly one check,
> reporting MUTED at **3.75:1** on it. The original defect was a text colour
> measured against the wrong surface, so a check that only ever varied the text
> would have left the surface half ungated — and `CARD_HI` is the fill a card
> takes in three states, so it is the half more likely to move. It now fails in
> either direction, which is the property that makes the ratio worth writing
> down rather than the number.

### And then the fix made a new stale number, which the gate could not see
>
> `game.gd` draws the same die's name in the collection row, for the same
> reason, citing the same reasoning — *"MUTED, not FAINT, for the same reason as
> the die card... 4.70:1 on the card, against FAINT's 2.44:1."* That was
> accurate when written: MUTED on `CARD` **was** 4.70. It is not now, because
> lightening MUTED moved it to 5.44, and **the sentence describing a design
> decision went stale the instant the fix shipped.** The row is also `CARD_HI`
> while a die is IN HAND and again on hover, so it had the identical exposure
> and needed no fix — one constant covered both files, which is the whole
> argument for the constant over a per-call choice.
>
> What makes this the second finding rather than a footnote is that **8930
> checks, 273 of them citation checks, did not catch it.** A ratio in prose has
> no `file.gd:NN` to hang a quote-form citation on, so the entire mechanism this
> session spent its length building is structurally blind to it. The audit found
> it by recomputing every literal in every source comment against the palette —
> nine of them, in four files — and asking which ones the palette still produces.
>
> Two things came out of that sweep, one of them a near-miss worth recording.
>
> **The version that looked like a check was vacuous.** The first form of it
> built the set of ratios over every ordered pair of palette constants *plus the
> pre-fix palette*, and tested membership. That passes: the old palette still
> produces 4.70, so the stale number is still "a ratio the palette has ever
> had". Including history is what made it useless — the same mistake as the
> invented 3.0 threshold, one level up, and it passed for the same reason. A
> check whose rule is "this number was true once" cannot catch a number that has
> stopped being true.
>
> **And the block I wrote describing the first finding misquoted it.** In the
> draft of this very section I rendered the die-card comment as reading 2.44:1
> on `CARD` when it reads 2.15:1 on `CARD_HI`, and carried the wrong numbers
> into a claim that "both numbers verify exactly". Found by running the
> computation instead of trusting the paraphrase — the numbers I had quoted were
> real ratios, of the right palette, on the wrong surface, which is the exact
> failure the finding is about. It happened in the write-up of a fix for it.
>
> The fix for `game.gd` was deletion, not a new number: the ratio is gone, the
> reason it was there is not, and the comment now says why it deliberately
> quotes no ratio and points at `_contrast` for the one that matters. **No check
> was added.** Every ratio still in a `.gd` file is now either 4.5 (the WCAG
> standard, not a measurement), a past-tense justification for a decision about
> `FAINT`, or the defect's own 4.13. A gate that scans comment prose for numbers
> is checking prose style, and it would re-introduce the burden it removes: the
> argument for pushing live numbers into the test is that there is then one
> place to recompute them, and a check that permits a re-quote is a check that
> invites the next one.
>
> One surface was found by measuring and is **not** a defect. The locked row
> draws its name at 60% alpha over `CARD` — **2.90:1** — and nothing anywhere
> had ever put that number down. It is below the bar, and it is also correct:
> the row is `disabled`, the comment above it says a locked die "still has to
> read as a goal, not a gap", and the caption and border beneath keep FAINT for
> the same reason. The codebase's stated rule is that FAINT is for what is meant
> to disappear, and this is it. Recorded because "measured it and it is
> deliberate" and "did not think about it" look identical from the outside.

### The sound table's numbers were all true, and two of its sentences were not
>
> Audited the audio surface the same way as the palette: enumerate the claims,
> measure each one. Ten of them, across `play/LISTING.md` and the assets.
>
> **Every number was exact.** The seven one-shots sum to **46,338 B** against a
> stated "45 KiB (46,338 bytes)"; the beds are 539,931 and 561,899 to the byte;
> `icon.png` is 315,682 B and `feature.png` 580,736 B, which are the stated 308
> and 567 KiB. Including one that looks impossible: the claim that the nine
> `.oggvorbisstr` blobs in both AABs total **1,188,787 bytes** — a claim about a
> file that cannot be built here — verifies to the byte by summing
> `.godot/imported/*.oggvorbisstr` on disk. A reviewer does not need the AABs to
> check the AAB claim, which is worth knowing and was not written down anywhere.
>
> **And one file was not made by the script that is credited with making it.**
> `LISTING.md` said "Seven one-shots, synthesised by `_mksfx.py`... Regenerate
> with `python3 _mksfx.py`". Six of the seven are: `tap`, `strike`, `hurt`,
> `block`, `win` and `lose` each equal what the script's own arithmetic produces,
> to the sample. The seventh cannot be, and not because of the seed.
>
> `_mksfx.py` builds `roll` from seven impacts and a 50 ms tail. Measured against
> its own seed that is **0.509s**, and the ceiling over *every* seed is
> **0.520s** — the per-impact jitter is 30 ms and there are seven of them, so no
> rerun can reach the shipped file's **0.711s**. No hit count from 5 to 14 gets
> there either (`range(11)` lands at 0.722s). `git log` answers "which changed?"
> with the same commit for both: `088a3f1`, the first one in the repo, neither
> file touched since. **This is not drift. The claim was false on arrival**, and
> every history-based explanation is unavailable because there is no history.
> Following the documented regeneration would produce a file 0.2 s short and turn
> the duration gate red — so the gate catches the consequence and nothing caught
> the cause, which is the shape of most of what this audit has found.
>
> **Two "fires on" rows named one call site each and were silent about three.**
> Counting `_sfx`/`play_sfx` sites per sound: `roll` 2, `tap` 4, `strike` 1,
> `hurt` 1, `block` 2, `win` 1, `lose` 1. `roll`, `strike`, `hurt`, `win` and
> `lose` name every site. `tap` was described as "queueing or unqueueing a die"
> and actually fires on queuing a die, banking a die, **arming** Focus and
> **arming** Bank — so it is not a sound about dice at all, it is the
> interface's click, and the row made it read as the opposite. `block` was
> "a roll that gained block" and also sounds on a Focus spend. Neither was a
> typo: both rows were true of one site and quiet about the rest.
>
> Which exposed the gate, because the reason it missed is the reason it exists.
> `shot.gd` walks the sound table's *other* half —
> `for n in game.SFX.keys():` at `shot.gd:151` — and checks each key resolves to
> a file. That is one direction of a bijection, and the direction that cannot
> fail: a key stops resolving when a file goes missing. Nobody walked the names
> the code *asks for*. A typo in `_sfx("blok")` indexes a dict that does not
> have the key, `preload` yields null, `play_sfx` returns without touching the
> pool, and the sound stops playing with **every gate in the repo green** — which
> is precisely the loss the duration gate was written for, reached from the
> other end. "The name still resolves" is the one thing a truncated file gets
> right, so a whole gate was built to look past it; here the resolution itself is
> what fails.
>
> `_sfx_names` closes it in eight checks: a regex over the two files' source for
> every `_sfx(`/`play_sfx(` literal, each name checked against `game.SFX`, plus
> one asserting the scan found at least seven distinct names so a renamed
> duplicate cannot quietly shrink the set. `shot.gd` is excluded because it asks
> for `"no-such-sound"` on purpose. Both halves were mutated: `"block"` →
> `"blok"` takes down exactly one check and names the file and the sound;
> collapsing `strike` into `tap` takes down exactly the count check. It is a
> source-text walk rather than a hook on `play_sfx` because the names are string
> literals at the call site and the only way to read them off a running fight is
> a test that plays every branch of it.
>
> A near-miss worth the line: `_rects.gd --six` looks like it might be vacuous,
> since it reaches six dice by calling `apply_upgrade("ADD_DIE")` twice and that
> upgrade is normally offered at most once per run. It is not — `shot.gd` makes
> the same two calls and asserts the result is six, at the line whose comment
> records a bug where it called itself six-dice while holding five. Same route,
> already gated. Recorded because "checked it and it is fine" and "did not look"
> look identical from the outside.

### An argument that could not say what it meant, and what it drew anyway
>
> `icon.gd` is a throwaway generator for two shipped PNGs, guarded so that
> running it the obvious way writes nothing — `has("--overwrite")` at
> `icon.gd:34` — because `res://icon.png` is the only image inside the APK and a
> careless run replaces it with art drawn in code. That guard is why the file was
> safe to read closely. Two claims in it check out exactly: `play/.gdignore`
> exists, so the feature graphic really does stay out of the build; and 0.56 of
> the short edge really does sit inside Android's 0.66 adaptive safe zone
> (286.7 inside 337.9, and inside it again once the shadow's 4% offset is
> added).
>
> And the third argument of `_box` could not express its own value:
> `maxi(int(side * border), 1)` floors the border at one pixel, so the **0.0**
> the drop shadow passes at `icon.gd:92` — a black box that is supposed to be
> nothing but a black box — came out as a one-pixel `GOLD_DARK` outline, since
> `_box` sets `border_color` unconditionally. A soft shadow with a gold hairline
> in it, on the only image the player sees in their launcher.
>
> It is measurable, and measurably not a shadow. Sampling `icon.png` down the
> die's centre line against bare backdrop on the same rows: a 50% black shadow
> over that backdrop reads about **−4** on red-minus-blue, and the strip under
> the die reads **+39**, decaying over ten pixels as the viewport filter smears
> the line. The warmth is gold, and it is where the code says it should be.
>
> The size of that is the part worth writing down. The launcher scales the icon
> to 48px, so ten pixels of smear arrives as roughly one — **this has never been
> visible**, and nobody reporting "the icon looks odd" is a plausible event
> anywhere in this project's history. It was found by reading one expression
> that cannot do its job, after the project's own rule (measure, don't squint at
> a downscaled PNG) sent me to the pixels to confirm the reading.
>
> `sb.set_border_width_all(int(side * border))` at `icon.gd:131` — the floor is
> gone. The die's own border is `int(286.72 * 0.02)` = 5 and never depended on
> it, so this is the whole diff. **The shipped `icon.png` still has the
> hairline**: regenerating it means `--overwrite` on a tracked binary, which is
> the user's call and was not taken. The code and the artefact now disagree, and
> that is the correct state to leave them in rather than silently rewriting a
> store icon nobody asked to change.
>
> **The export filter was also censused, and the answer was mostly reassuring.**
> All seven throwaway `.gd` tools are excluded, and `_check.gd` is correctly
> *not* — `dice.gd:3` and `run.gd:12` preload it, and `_pack.gd:10` records that
> the old `_*.gd` glob took it with the rest and broke the shipped build, which
> is why that file's absence is deliberate and not an oversight. One gap: the
> filter is a hand-curated string of `.gd` names and never mentions file
> extension, so **`_mksfx.py` — 5,399 bytes of build-irrelevant Python — ships
> in every pack.** Small enough not to be worth editing the file that holds a
> leaked keystore password for, and it carries nothing secret.
>
> **No check was added for that filter, and the reason is the ladder rather
> than the budget.** `_pack.gd` is already the gate for it — `_pack_walk`'s own
> comment says "`_pack.gd` is the only gate that can see an export filter
> dropping a file" — and it is gate 5 in the loop below. A static approximation
> in `test.gd` would duplicate a sanctioned gate while reading
> `export_presets.cfg`, the one file in this repository that must not be read
> casually, for coverage the real gate already has and this cannot. The
> right answer is not a new check; it is that gate 5 cannot run here.
>
> `_rects.gd` and `_stats.gd` were read for the same pass. `_rects.gd --six`
> looks like it might be vacuous — it reaches six dice with two
> `apply_upgrade("ADD_DIE")` calls on an upgrade normally offered once per run —
> and is not, because `shot.gd` makes the identical two calls and asserts the
> result is six, at the line whose comment records a bug where it called itself
> six-dice while holding five. `_stats.gd` has no shipped claims to be false.

### Two citations converted rather than re-stamped
>
> The armour-cap citation went wrong three times in one afternoon: stale by
> fifty-six lines when first found, then moved twice by edits made *above* it
> for unrelated reasons. Each time the gate was green, because a plain citation
> is only checked for being in range and non-blank, and the wrong line was
> always in range and never blank.
>
> The fourth fix is not a number. Both of those claims already quoted their
> target — one quoted the check's own failure message, the other the condition
> it rests on — so both were rewritten into the form `_citations` checks
> properly: the quote, then `at`, then the file and line. The gate then verifies
> the quoted text is *on* the named line, which is the check the plain form
> cannot do and the one that makes a citation self-correcting: when the line
> moves, the quote stops being there and the gate goes red on its own.
>
> It earned its keep immediately. Converting the second one produced a red on
> the spot, because the line it named had already moved four lines from an edit
> earlier in this same stretch — drift the plain form was sitting on silently
> at that very moment. That is the loose half of the gate closing for the cost
> of two sentences and no new code, and it is the first evidence this session
> that the gap is not inherent: the two conversions were chosen precisely
> because they already had the quote, and both took. The rest of the repo's
> citations do not have it, and rewriting them all is still a diff across five
> files — but this is no longer an argument that the half cannot be closed.
>
> ### A card named its number, and the number stopped being true
>
> The sixth instance of this shape is the first one where nothing is *wrong* —
> no wrong number, no wrong sentence, and nothing that looks broken. Blade's
> faces are labelled with their own damage: `"2"`, `"3"`, `"4"`, `"5"`, `"7"`,
> `"9"`. The label is not decoration, it is a second copy of the stat. Then
> `SHARPEN` applies `if f.dmg > 0: f.dmg += 1` and `forge()` builds
> `Face.new(f.label, f.dmg + 1, f.block, f.rerolls)` — both raise the damage and
> neither touches the label, because the label is a `String` and neither has any
> reason to know what it says. `_paint_card` printed the live value large and
> `f.label` underneath, so a sharpened Blade card read **10 DAMAGE** with a **9**
> under it, and the two numbers disagreed on the same card in the same frame.
>
> `String.is_valid_int()` is the discriminator, and it happens to be the right
> one for a reason worth naming: it separates a label that is *a number* from a
> label that is *a word*. Ward's block faces are `"2" BLOCK` and Riposte's are
> `"2 blk"` — also numeric at the front, and they must keep their word, so a
> blanket "strip the digits" fix would have broken six faces across two of the
> three starting dice to fix one. `face_word` falls back to `kind`, which the
> card already builds from live stats, so the label is never a second copy of
> anything that can drift: `cleave`, `rend`, `fend`, `rust` and `spark` ride
> along, and a paired Fang whose label is `"5"` and whose value is `10` shows
> the doubled number it actually deals.
>
> `_face_word` asserts the *precondition* rather than the symptom, which is
> backwards from every other check here and is why it found both cases from one
> loop: it runs `SHARPEN` and `REFORGE` over a real hand and counts how many
> numeric labels now name a damage they no longer deal, and requires both counts
> to be **non-zero**. If a future rewrite made the labels stop drifting, those
> two checks go red — a test for a bug that fires when the bug is fixed, which is
> only safe because the loop is what supplies the evidence either way.
>
> Mutation: the rule inverted to the pre-fix form goes red on exactly the two
> checks that cover it — the drifted label and the paired face — and on nothing
> else. That inversion is not a free choice, though, and the reason is the
> sharpest thing here. The old code could not be expressed in this signature at
> all: it compared `hit != f.dmg`, which needs the pre-armour damage this
> static never sees. **The fix could not be tested by putting the old code
> back**, only by putting back the *nearest rule expressible in the new terms* —
> so the mutation tests the new rule, not the old bug. Recording that, because
> "mutation-tested" reads like a stronger claim than it is.
>
> ### Three citations, and one was wrong on arrival
>
> The block above says this session's insertions "moved two `play/LISTING.md`
> citations onto unrelated code" and that they were restated. That was true
> when written, and then the *next* insertion in the same file — six lines, the
> `face_word` static, immediately above `best_caption` — moved both of them
> again, within the same stretch of work, to the same neighbouring function.
> Both were now citing code with nothing to do with them: the "re-roll widens
> to" citation sat on `_paint_card(i, enc.dice[i].face(), true)` and the status
> line's on `intent_num.text = str(enc.enemy.atk)`. Real lines, correct file,
> blank. Green.
>
> So the restatement was not wrong, it was **insufficient and unorderable**: two
> edits to one file, both inserting above both citations, cannot both leave the
> citations correct. What actually closes this is not a better hand
> correction — it is the quote form, which fails on its own when the line
> moves, which is the whole reason the previous block converted two citations.
> Both of these were converted for that reason.
>
> The third was found while checking, and is the one that should have been
> found first: a range in `play/LISTING.md` cited for the button row `Roll`,
> `Focus`, `Bank`, `Re-roll`, `End turn`. The row is at 222, 235, 237, 239, 241.
> The cited range covered **four of the five** and missed `Roll`, because it
> opened on the line after the `Focus` button. Nothing in this session touched
> line 222 — both
> insertions were around 890 — so this was wrong before the first of them, and
> the gate has been sitting on it since it was written. Every previous instance
> of citation drift was *drift*: correct once, broken by an edit. **A plain
> citation can be wrong on arrival too**, and the structural check passes both
> identically. The button row is now cited by its anchor line's own text.
>
> *(This paragraph names the bad range the same way the one about the thorns
> insertion does — it describes the broken form instead of writing it out,
> because writing a citation you have just established is wrong is exactly what
> trips the gate that is checking it. The gate is green on the prose either
> way; it is the reader who has to take the claim on trust, and this note is
> what stops the trust from being asked for twice.)*
>
> ### The quoting form silently stops quoting the moment prose wraps it
>
> The block above credits the quoting form with making a citation
> self-correcting. It does, **while it stays on one line**, and the previous
> block's own two conversions were — so the claim was tested only where it
> worked. `quoted` is run per line: `quoted.search_all(lines[i])`. A citation
> whose closing backtick and trailing ` at` land at the end of its line, with the
> file and line number on the next, matches **nothing**, falls through to the
> plain pass, and gets the structural pair instead of the pair plus the content
> check. No red, no warning, no change to the text an author edited.
>
> Found by the only method that finds this class: converting a citation whose
> line I already knew was wrong, and **not** getting red. Line 223 is
> `roll_btn.pressed.connect(_on_roll)`; the citation quoted
> `roll_btn = _mk_button(btns, "Roll", T.GOLD)`; the content check could not
> have missed it. Put the same citation on one line and it went red immediately,
> naming the quoted text, the file and the line. So the wrap was the entire
> difference, and the gate's own comments never say the form is single-line.
>
> Three were wrapped, and the third is the one that matters. `play/LISTING.md`
> cited the button-label assignment in `theme.gd` over a three-line range — and
> that assignment is on the range's **last** line, two below where the range
> opened, so the citation had been wrong for two lines at once, behind a
> wrapping. It is the site the quoting form exists to protect, sitting inside the
> exact blind spot the quoting form has. Two lines is nothing; the general case is
> an entire function body.
>
> The fix is one check per source file asserting no quote-form citation wraps —
> not one check per wrap, because a check that only fires once it is already
> broken contributes **zero** to the floor, and then the count carries no sign
> that the guard is installed at all. Seventeen sources, seventeen checks,
> always paid. Verified by wrapping one of the good citations: red, naming the
> file and the count.
>
> The generalisable half is not about citations. `theme.gd` and `fight.gd` both
> assign a button label verbatim with `b.text = text` — the same statement, at
> 141 and at 339 — which is the fact the wrapping citation was making, and both
> survive into the fix because they are what is actually true.
>
> *(And the guard's own comment tripped the gate on its first run, by containing
> the punctuation it was describing. That is three times now in this audit: the
> armour cap, the thorns line, and this. Every one was a comment explaining a
> broken citation by writing it out, which is the most natural way to explain
> one and the only way that makes the gate go red over the explanation. The
> house fix is the one already used above and in the `_enemy_tag` note: describe
> the pattern, never spell it.)*
>
> *(And then this paragraph did it a fourth time, one edit later, in the same
> sentence shape it had just told readers not to use — which is the finding
> rather than the incident. The rule is not knowledge the writer is missing; it
> is defeated by the ordinary pressure to make a paragraph concrete. A gate that
> the author of the document cannot write prose without tripping is not a gate
> the author will keep green. The alternative was not "remember harder" — it is
> the one already taken three paragraphs up: the citation goes in quote form
> when it is worth checking, and into prose when it is only worth telling, and
> the count of those is now printed by `_citations` itself, so the split cannot
> rot the way a convention does.)*
>
> **The ARMOR_GROW ceiling held and was still a lie, in the log.** `take_turn`
> capped correctly — `mini(enemy.armor + 1, Enemy.ARMOR_GROW_CAP)` — but had no
> `else`, so from turn 12 on every enemy turn appended "Wall hardens. Armour is
> now 12." while nothing changed. Seven turns for a Stone Sentinel, nine for a
> Rust Golem (`run.gd:151` armour 5, `run.gd:147` armour 3), both well inside a
> fight a player sees, and that line is the *only* place the ceiling is ever
> told. The same shape as `BEH_ENRAGE`'s uncapped `atk` in the behaviour table
> below, one
> layer down: there the number ran away, here the number was right and the
> sentence claiming it moved was not.
>
> `_react` already got this right for `BEH_BRACE` — it takes the growth and
> prints the ceiling when there was none — so the fix is its wording, verbatim,
> which also means the ceiling now reads identically whichever behaviour hit it.
>
> **And the one check that named the cap was checking a different enemy.**
> `dice.gd`'s "armour never passes the cap" runs on `br`, a `BEH_BRACE` enemy;
> `ARMOR_GROW`'s use of `ARMOR_GROW_CAP` had no check on it at all, weeks of
> gates notwithstanding. That is the recurring shape: a check named after a
> constant covers one of its users and reads as if it covers both.
>
> Four checks added, and each half falsified by mutation rather than by reading.
> Deleting the `mini(...)` turns the tree red on two of them and green on the
> first — which is itself the finding, and why that check's message now says
> "climbs to the cap without stepping past it". `while armor < CAP: take_turn`
> exits at exactly 12 whether or not a cap exists, so it can only fail on an
> overshoot. Enforcing the cap is the *last* check's job, and it does.
>
> **The death screen named one fight two different depths.** It printed "You
> reached depth 9 of 9" and, two lines below, "The Devourer waits at depth 8" —
> and the fight HUD had labelled that same fight "depth 9 of 9". `FINAL_DEPTH` is
> an index, every sentence about it is a number, and of the six sites in
> `game.gd` that print a depth, five added one and one did not. Read down the
> file it is invisible: each line is locally reasonable, and only the *pair*
> contradicts. Found by the technique that has paid best all sweep — enumerate
> every player-visible sentence that asserts a quantity, then check the
> quantity — which is also the only reason it was ever going to be found.
>
> The fix is `RunState.depth_no`, one static that owns the one-based mapping,
> with all six sites routed through it and twelve checks pinning it: the first
> fight reads as 1, the boss as `FINAL_DEPTH + 1`, every depth as itself plus
> one, a run past the end still reading as the last fight.
>
> **And those twelve checks did not catch the bug they were written for.**
> Measured, not assumed: with `"% RunState.FINAL_DEPTH"` put back at
> `game.gd:539` — the original defect, verbatim — the tree stayed at 8618 and
> exit 0. A helper is correct by construction, so a call site that never calls it
> is invisible to every assertion about it. This is the `br` /
> `ARMOR_GROW_CAP` failure one layer up, and it is worth naming as a *pattern*
> rather than a third instance: **a check on a value is not a check on the
> wiring.** Whenever the fix is a helper and the defect was a caller, the helper's
> checks certify the helper and the bug walks past them.
>
> So the covering checks live in `test.gd` and are source-anchored — `game.gd`
> builds Controls and cannot be executed from a headless session, the same weaker
> guarantee `_haptics_wired` and `_enemy_tag` already make. Each names the exact
> shape that shipped: a `%` format printing the bare index, and a hand-rolled
> `+ 1` beside it. Both falsified separately against the restored defect.
>
> The ceiling that leaves, recorded so it is a known one: a future site can
> dodge both by formatting a depth a third way. Closing it means extracting the
> sentences into statics the suite could call and compare. Not done — it doubles
> the surface to guard a hypothetical no one has hit yet.
>
> **The store copy claimed it avoided a stat bar, in a second sentence, one
> paragraph from the one already repaired.** The upgrades sentence said "they
> change your dice, not a stat bar" and that was false — MEND heals 14, VIGOR
> grants +8 max health — and it was fixed and gated. What survived is "You are
> not managing a timer or a stat bar", thirty lines below it, making the same
> promise in the same block, on a screen that carries **two** `ProgressBar`s
> (`enemy_bar` at `fight.gd:243`, `player_bar` at `:298`) and a player's health
> that two of the twelve cards move.
>
> **The check that was supposed to stop it tested the phrase, not the claim.**
> `_store_copy` asserted `"not a stat bar" not in text`. The second sentence does
> not contain that substring — it reads "not managing a timer **or a stat bar**"
> — so the gate sat green over the exact defect it was written for. Re-anchored
> on the noun: `"stat bar" not in text`. That is the whole fix, and it is the
> same mistake as the depth one, in a different key: **fixing the instance, not
> the claim.** Three times now this sweep has found a second occurrence of
> something it had already repaired once — `capitalize()` on two lines, the
> article-doubled title on three, the stat-bar absolute on two — and in every
> case the repair was correct and the **anchor** was what failed.
>
> Copy now reads "No timer, and nothing to grind: you are reading four numbers
> and choosing which one to bet. Health is the one number that ends the run" —
> true (`if hp <= 0:` at `dice.gd:723`), and it keeps the four counters
> the HUD actually prints while conceding the one bar the game really has.
>
> **How it was found, since the method is the transferable part:** not by
> re-reading the sentence that had been complained about, but by enumerating
> *every* quantitative sentence in the block and checking each one. Thirty-one
> came back. Six were false or loose and had already been repaired; the rest were
> verified against code, several by measuring rather than reading — the audio
> table's "45 KiB (46,338 bytes)" is the exact sum of the seven SFX, and both
> beds match to the byte. Cheap, and the only reason the survivor was a survivor.
>
> One near-miss, recorded because not finding a bug is a result: `fight.gd`'s
> `"ARMOUR %d — NOTHING LANDS"` caption names armour as the cause whenever the
> best die lands 0, and Ward and Riposte have no positive-damage face at all, so
> a hand of pure block also reads 0. Tried to falsify it and could not: only two
> of the seven dice are block-only and `MAX_DICE` is 6, so a hand always carries
> a die with a positive face and the self-contradicting `"ARMOUR 0"` is
> unreachable. Incomplete, not false. Left alone deliberately.
>
> **The behaviour tag made the same false claim as the store copy, on the screen
> where it is read every turn.** `Enemy.behavior_name()` returned "hardens each
> turn" — the identical promise the Rust Golem sentence made in LISTING.md, fixed
> there and never noticed here. Measured over 300 bot fights per enemy, with a
> throwaway probe written, run and deleted:

> | enemy | fights that touch the cap | enemy turns that *begin* at the cap |
> |---|---|---|
> | Rust Golem (armour 3) | 51.3% | **59.5%** |
> | Stone Sentinel (armour 5) | 100% | **75.0%** |
>
> So on most turns against both, the line under the enemy's name says "Hardens
> each turn" while the log — as fixed above — says "Its armour is already at its
> limit." **They contradict each other on screen, and the tag is the wrong one.**
> It is now `"hardens each turn, to %d" % ARMOR_GROW_CAP`, derived from the
> constant, so moving the cap moves the sentence. Two checks, both falsified:
> restoring the old string reds the first, and giving the genuinely-uncapped
> `BEH_ENRAGE` a ceiling reds the second — ENRAGE is the control, because
> "rages each turn" is *true* of it and this must not become "every tag states a
> ceiling". Verified as a derivation: at `ARMOR_GROW_CAP = 14` the tag check
> stays green on its own, having followed the constant to 14.
>
> **`test.gd`'s `_enemy_tag` could not have caught this, and that is the fifth
> instance of one shape.** It checks that the names arrive lowercase and that
> `fight.gd` contains no `.capitalize()`. Both true; neither is *truth*. A check
> can be about casing, about mechanics, or about a value — but the ones added
> here keep proving that "the check I wrote" is not the same question as "the
> claim the player reads."
>
> **And setting the cap to 14 — a legal edit to a constant — took down the entire
> screenshot gate.** `shot.gd` derives its copy rows by subscripting a literal
> table of number words, `COUNT_WORD`, with the constant:
> `COUNT_WORD[Rules.Enemy.ARMOR_GROW_CAP]`. Godot constant-folds a `const` array
> indexed by a `const`, so that subscript is evaluated **at compile time**. The
> table holds thirteen entries and the cap is 12 — the file compiled by one slot
> of luck. Set it to 14 and `shot.gd` does not load at all:
>
> ```
> SCRIPT ERROR: Parse Error: Cannot get index "14" from
>   ["", "one", ..., "twelve"].   at: GDScript::reload (res://shot.gd:1328)
> ERROR: CHECK FAILED [test.gd]: res://shot.gd fails to parse (error 43)
> ```
>
> Note what that failure is: **not a red row naming the claim that went stale**,
> but a parse error naming nothing, surfaced by a *different* file's suite
> reporting that this one would not load. Every check in the screenshot gate goes
> missing for a reason that has nothing to do with any of them. Six other
> constants subscript the same table — `FINAL_DEPTH + 1`, `POOL_SIZE`,
> `OFFER_COUNT`, `UNLOCK_CAP`, `base_focus`, `base_rerolls` — so this cliff sits
> under the whole copy-claims section, waiting for any of them to grow.
>
> Fixed by routing all eight call sites through `_count_word(n)`, which returns
> the numeral when the table runs out. The function call stops the constant
> folding, so an out-of-range count degrades to `"14"` and *the row turns red
> against copy that still says "twelve"* — the failure this gate exists to
> produce, instead of the one it produced. Verified in both directions: at 14,
> `shot.gd` parses and its eleven checks survive; at 12, everything is green.
>
> ```bash
> xvfb-run -a godot --path . --rendering-driver opengl3 -s shot.gd -- --check
> ```
>
> **`_rects.gd` carried the identical pattern and is now fixed by deleting
> the pattern.** It staged the same way — a fixed
> `/tmp/dice-save-backup2.json`, the real save removed by
> `DirAccess.remove_absolute(SAVE)` and put back by
> `DirAccess.copy_absolute(BACKUP, SAVE)` on the way out — and it was
> **worse** than `shot.gd`'s, on two counts. The path was
> fixed, so two copies at once backed up to the same file: the second
> overwrote the first and one of the two restores could put back the *other*
> player's history. And nothing swept up afterwards, where `shot.gd` at least
> left a per-process backup behind.
>
> The fix is not a per-pid path. It is to stop staging the save at all. The
> tool wants the title screen's *fresh* state — "Begin the run" rather than
> "Play", an empty stats line — because a saved profile renders different text
> and the whole file exists to measure text. `test.gd:22` already solves
> exactly this by redirecting the path, so `_run()` now does the same:
>
> ```gdscript
> RunState.SAVE_PATH = "user://self-test.json"
> ```
>
> One line replacing eight. No copy, no delete, no restore, nothing written
> outside the project, and no window at all rather than a narrower one. It
> reuses `test.gd`'s scratch filename on purpose, so at most one stray file
> exists instead of one per tool. `SAVE` and `BACKUP` are gone; nothing outside
> the file referenced them.
>
> **It is shipped parse-verified and not run-verified**, and the reason that is
> acceptable here rather than the trade this file keeps refusing is worth
> stating plainly: the failure modes are not symmetric. If the redirect failed
> to take, this tool dumps a title screen carrying the player's real stats — a
> wrong measurement, visible, harmless. The old code's version of that same
> failure destroys their save, invisibly. The edit cannot make anything worse
> than the thing it replaced, so the lack of a runtime check is not carrying
> the risk; removing the risk is. `test.gd:15` loads and re-parses the file, so
> a typo here is a one-line headless failure, and that is verified: 9041 checks,
> exit 0.
>
> **The player may need to check their save.** The six-wide run above is the
> event that could have clobbered the real `user://run.json` — the worst
> interleaving ends with the file deleted and never restored. I could not look:
> reading Godot's user-data directory was denied as out-of-project access, and I
> did not route around it. If the mute state is not what it was, that is this.
> Nothing else the harness writes is player-owned.

> **"Eight of the ten call sites" was fight.gd counted on its own.** The
> audio table in `game.gd` mixes eight `SFX` files against the combat bed, and
> the paragraph under it read *"Eight of the ten call sites land over the bed;
> only the two rolls land under it."* The two-rolls half is right. The count is
> not: there are **twelve** call sites, ten of them over the bed.
>
> | file | call sites | over | under |
> |---|---|---|---|
> | `fight.gd` | 10 — `:435` `:452` `:462` `:467` `:478` `:491` `:499` `:515` `:524` `:537` | 8 | 2, both `roll` (`:435`, and `:499` at `vol:-6`) |
> | `game.gd` | 2 — `:608` `win`, `:617` `lose` | 2 | 0 |
>
> Why the undercount was so tidy: `fight.gd` reaches audio through its own
> `_sfx` helper, so a count anchored on the fight returns exactly ten and looks
> finished. The two `play_sfx` calls in `game.gd` were never in the sentence,
> and the sentence was in `game.gd` — the file that owns the dict. Eight-of-ten
> is precisely fight.gd's own split, so the error is invisible from inside the
> file it appears in.
>
> The two omitted ones are genuinely over the bed, and that needed checking
> rather than assuming: `win` and `lose` both fire *before* `show_end` runs, so
> `_swap`'s default `MUSIC_MENU` has not started its 1.2s fade and the combat
> bed is still up. The table's last column is correct for them.
>
> Three neighbouring claims in the same block, measured rather than assumed, and
> **all three hold** — recorded because a paragraph corrected for one false count
> should not be assumed to hold its others:
>
> | claim | measured |
> |---|---|
> | "Procedural costs 46KB for all seven (46,338 bytes…)" | `46,338` across 7 files, exactly |
> | the strip margin "used to be… 'roughly 150px'" | `171`: `540 − 369`, with `87` clear to the button at `456` and the button eating the `84` between (`74` target + `10` offset) |
> | "the strip draws all nine pips including the wide boss one whatever the depth" | `for i in RunState.FINAL_DEPTH + 1`, unconditional, boss pip `30` wide against `16` |
>
> No check added. The count is a comment, and a check for it would be a source
> grep — which is the weaker instrument the class of thing that cannot fail, and
> `_haptics_wired`'s own note says so. The gap this closes is a sentence, and a
> sentence is fixed by writing the true one.

> **`pair_bonus` documents a two-part rule and pinned one half of it.** The
> comment above `pair_bonus` in `dice.gd` is explicit: *"'Showing' is not
> 'resolving': a held die is on the board with its face up, and a spent one
> still pays this turn, so both count as partners."* The hold was pinned — by
> the check reading `"a held die still pairs"`.
> The spend had **no check at all**, on the field or on the resolve, and that is
> the half most likely to be lost.
>
> The edit that loses it is one line and reads like a courtesy:
> `if dice[j].spent: continue` inside `pair_bonus`. `spent` is documented as
> "already re-rolled this turn", and the resolve *does* skip
> the banked die — so the parallel looks exact, and it is not.
> The resolve skips `i == banked` and never `spent`, because spending is an
> action taken this turn, not an absence from the board. The two are different
> things that share a shape, which is exactly why the rule needed writing down
> and why the sentence was the only evidence for it.
>
> Two checks added — the checks reading `"a held die still pairs"` and
> `"a spent partner still pairs"` — same two dice so the flag
> is the only difference, and the resolve is *run* rather than the field read —
> per `_pierce_tests`'s own note, a test on `pair_bonus` alone would pass on a
> build where the resolve stopped consulting it. Both forced red together by
> that one-line mutation, and only those two: 8539 checks, 2 failed, exit 1.
>
> The surrounding claim survives its own check, which is worth saying because
> `pairs` is a *designed* rarity. The checks reading `"Fang's 5 is the paired
> face"` and `"exactly one face in the whole roster pairs"` pin it, and the
> rationale above `Encounter` is that it is "the one face in the roster that
> lands exactly on `EXPOSE_AT` when doubled". `EXPOSE_AT` is 10, Fang's face is
> 5, and the balance of that is asserted through the engine by the check
> reading `"a stacked PIERCE does not apply on top of exposed"`
> rather than asserted about. Hex also carries a `5` face and would double to
> the same 10, so the uniqueness is a property of the `pairs` flag, not of the
> roster's face values — which is what `tagged == 1` actually says, and it is
> the check that would catch a second flag.
>
> One imprecision left standing, because the conclusion is right and the
> comment is about a hypothetical. The note above `Face.pair_bonus` credits the
> no-chaining property to comparing raw `dmg`; it actually comes from
> `pair_bonus` returning the constant `f.dmg` rather than anything scaled by
> the number of partners. With exactly one paired face in the roster the
> distinction is unreachable, and correcting the sentence would be a diff
> against a comment whose conclusion is correct.

> **`icon.gd` states a rule that nothing gates, and the only cheap gate is
> worse than none.** `icon.gd:8` says *"Re-run this after editing theme.gd to
> restyle the launcher too"* — and `icon.png` is the one image inside the APK,
> so a theme change that is not followed by a re-run ships a launcher icon that
> does not match the game. There is no check for it, and the reason is worth
> writing down rather than leaving as an unexplained gap.
>
> The obvious instrument is `theme.gd`'s mtime against `icon.png`'s, and it
> would have fired. It is also wrong: the two are **2026-09-30 12:26** and
> **2026-09-29 12:49** on this tree, a gap that says nothing, because a checkout,
> an editor save and a `git stash` all touch mtime without touching content. A
> floor that is red on a fresh clone is the permanently-red gate this file warns
> against four times over, so it is not written.
>
> The content check I tried first is subtler and also wrong. None of the seven
> current palette hexes — `BG`, `CARD`, `MUTED`, `GOLD`, `GOLD_DARK` — appears
> **exactly** in the 512×512 PNG, which reads as "every colour is stale" and is
> not: the image carries 54,456 distinct colours across 262,144 pixels because it
> is drawn over a gradient with antialiased type, so exact matching finds nothing
> by construction. What settled it was two weaker measurements that are honest
> about their own precision — 5,941 gold-ish pixels (2.27%) and 9,759 bright
> pixels — and then looking at it: a gold die, "DICE FATE" in the muted grey,
> over the dark backdrop, which is `GOLD` over `MUTED` over `BG`. Consistent
> with the current theme, so **not changed**.
>
> Recorded because the failure here was mine and it was one step wide. The
> "every colour absent" reading was the *worst* of the three results available
> to me and it came last, because the instrument that produced it was the
> precise one. A check precise enough to be wrong about a gradient is not more
> trustworthy than a coarse one that says what it measured.

> **The other `icon.gd` axis was destructive, and the warning under-wrote it.**
> The entry above is about *staleness* — a theme change with no re-run. This one
> is about running the tool. `play/LISTING.md` warned that *"running it will
> overwrite the generated `feature.png`"*, which is true and names one of the
> two files. `icon.gd:26` writes `res://icon.png` on the line above, and that is
> the launcher icon — the only image inside the APK, per `icon.gd:5` and
> `LISTING.md:7`. A reader skimming a note whose subject is Play *store art*
> takes the blast radius to be store art only.
>
> Worse, the paragraph's own recovery advice inverts for that file. *"Copy it
> back from `*.bak-flat` if you want the original, not the replacement."* The
> `*.bak-flat` files **are** the originals, so for `feature.png` that sentence
> is a real undo — and for `icon.png` it hands back the 8.4 KiB near-flat fill
> that the very next clause says it was replaced for being. Measured:
> `icon.png` is 315,682 B on disk and in `HEAD` with `icon.png.bak-flat` at
> 8,585 B; `feature.png` is 580,736 B with its bak at 17,753 B — the "8.4 KiB
> and 17.3 KiB" the note cites. Those four figures are KiB, and three
> documents had been labelling them KB; a commit earlier in this audit caught
> the same slip in the audio table and fixed it there, which is what made it
> worth sweeping for here. The generated pair exists only in git history.
>
> **Changed, with a guard rather than a better warning.** A warning is prose
> somebody has to have read before running the tool; `icon.gd:_run` now exits
> without writing unless `--overwrite` is passed, so the documented command
> carries the decision in itself. Measured: run without the flag, both files
> are byte-identical afterwards and the exit is 0; run with `-- --overwrite`,
> `OS.get_cmdline_user_args()` returns `["--overwrite"]` and `has()` is true.
> Both halves, because a flag the accessor cannot see would make `icon.gd`
> unrunnable — the opposite failure, and the one a single negative test misses.
> The `has()` form is the same accessor `_probe.gd:16`, `_pack.gd:112`,
> `_rects.gd:45` and `shot.gd:42` already use, so nothing new was invented.
>
> No automated caller exists to break: `test.gd:14` only `load()`s `icon.gd`,
> which parses without instantiating, so `_init` is unreachable from the suite,
> and `export_presets.cfg:11,43` exclude it from both presets. The only way in
> is a human typing the header's command. `icon.gd:3`'s *"so a fresh checkout
> can produce them"* was a second false claim in the same file and is gone —
> untrue for `icon.png` since 2026-09-29.
>
> Not checked: whether the generated art matches `theme.gd` today. That is the
> entry above, measured and left alone; this one is only about what the tool
> does when it runs.

> **A comment that names a line number is a claim, and it was the false one.**
> The reward-card comments were audited for their *reasoning* — "BULWARK's 49 is
> the longest string here with layout evidence behind it" is false, and it says
> so while quoting PRECISE_STRIKE's 66 in the same breath — and the fix that
> uncovered it ran into the class underneath. Citations are how a comment reaches
> its evidence, and they rot silently: the sentence keeps asserting something
> true about code that has moved on. Resolving all 22 in the repo found 6 dead.
>
> `run.gd` named its own line 49 for `saved_loadout()`'s call, which is 17 lines
> below it. `dice.gd`'s exposure window was cited at 641 and 646; it was 649 and
> 654, and 646 then pointed *inside the comment explaining that very code* — a
> uniform +8 drift. `shot.gd` pointed at `dice.gd:1138` for the line that opens
> the window (654) and at `dice.gd:645` for the line that sets it after damage
> (654 again, and the citation had been off by nine).
>
> And the same pair drifted a second time, by eight, in the course of fixing an
> unrelated log line — 657 and 661 now, because that fix added seven lines above
> them. Small, and found only because the gate was re-run. What it turned up
> alongside it is worth more: the same run asked for line 1559 of `dice.gd`, where
> `PLAN.md` claims a balance check lives, and the check was fifty-six lines away
> at 1615 — stale since long before this audit touched the file. It had been
> passing the whole time, because that line happened to hold something other than
> whitespace, which is the blind spot described above doing precisely what it was
> documented to do. The edit then slid it onto a blank line and the gate caught
> it by accident, which is the only reason it is fixed at all.
>
> **`_balance.gd` had already written the post-mortem, and then the bug happened
> again.** That file carries three lines about a `run.gd` citation that was wrong
> at 268, was "corrected" to 284, which had *also* drifted, and whose wrong
> number then "sat in PLAN.md's sweep table as the *corrected* value, so the
> wrong number was ratified twice by fixing it once." So the third copy — 312 —
> should have been the moment that stopped being a number. It was moved to 331 by
> a `depth_no` helper added nineteen lines higher up **in the same file during
> this very audit**, and the comment recording the first two failures was stale
> before the third was written. Three failures, one shape, every one a hand
> correction.
>
> **Changed: `test.gd`'s `_citations`, not a fourth number.** Two checks per
> citation site — resolves to a real line, and is not blank — plus one more when
> the citation *quotes* its target, checked against that exact line. Measured,
> both ways, by mutation: putting the real bug back (`at run.gd:312`) goes red
> with `_balance.gd line 807 quotes "picks.size() < OFFER_COUNT", and that text
> is not on run.gd:312`, and the plain-form mutation (`run.gd:71` → `:49`) stays
> **green** — which is the gap, stated in the check's own comment rather
> than papered over. `ponytail:` the loose half is only checkable once a claim
> quotes its target, so closing it means rewriting every citation in the repo as
> a quote; that is a diff across five files to cover a gap that has opened once.
>
> The counterexample is the reason the 22 were read by hand rather than trusted
> to the gate: `run.gd:49` is a real, plausible `base_focus` declaration sitting
> seventeen lines from the call it was cited for. A mechanically-checked claim is
> still a claim somebody has to read.
>
> **Also corrected, in the same pass:** `shot.gd` claimed PRECISE_STRIKE's
> description was 69 characters; it is 66, and the 69 was itself already-drift —
> that comment had caught the number once and then not been updated. `run.gd`'s
> "BULWARK's 49 is the longest" is replaced by the bound that is actually right,
> PRECISE_STRIKE's 66, which also covers GAMBLERS_RUSH at 64 — the longest card
> nothing stages, and the one `shot.gd`'s note names as the pool's next longest.
> Two files, one subject, opposite answers.
>
> **Verified and left alone.** All twelve card descriptions against their code:
> BASTION_HOLD's 4 is `BASTION_BLOCK`, paid on the tap (`dice.gd:485`), so "4
> block at once" is exact; GAMBLERS_RUSH's "ignoring armour" is true because the
> payout at `dice.gd:610` sits *after* `enemy.pierce(...)` has already subtracted
> it, and its `RUSH_FLOOR` of 1 only ever exceeds "half the gain"; ADD_DIE's
> ownership filter is already pinned on a temp save at both ends, including the
> case the copy is about; and the `+=` cards are per-pick descriptions the way
> "+8 max health" is, which is not a false claim.

> **`_citations` was extended to the docs in the same pass, and they were the
> worse half.** The `.gd` files hold 22 of these; `PLAN.md` holds 78 and
> `play/LISTING.md` another 13. The docs drift *more*, and for a reason the code
> half cannot have: editing any `.gd` file breaks every document citing it while
> breaking nothing in the file being edited, so nothing about the edit says
> "this moved". Four were dead.
>
> `play/LISTING.md` put the nine-enemy roster at run.gd lines 132 to 144 — it is
> 146 to 158, and 132 is eleven lines above a blank gap. The seven-die catalogue
> was dice.gd lines 341 to 376 against a true 350 to 396, off by nine at both
> ends. And
> it credited `run.gd:566-574` with asserting "four of those names against the
> behaviour each implies", which that range does not do at all: it is the
> doc comment above `_check_fuller_hand_claim`, which asserts hand *width*. The
> assertions that do what the sentence says are at `run.gd:620-628`. That one
> is the honest counterexample to the gate — see below.
>
> `PLAN.md` itself was worse than stale: it described the `COUNT_WORD` cliff in
> the present tense, quoting the literal `COUNT_WORD[Rules.Enemy.ARMOR_GROW_CAP]`
> as if it were still in the count helper, and **that literal no longer exists** — the `_count_word`
> guard written earlier in this same audit removed it, and `shot.gd:1323` is
> now an unrelated line. The block forty lines down correctly says "It is
> guarded"; the paragraph above it still described the hazard. Drift this
> session caused, in the file that records this session's findings.
>
> **Two more fell out of a two-character change to the regex.** The quoting form
> had been written to match `` `code` at file.gd:N ``, but the docs quote a
> citation *inside* backticks — `` `code` at `file.gd:N` `` — so those fell
> through to the plain pass and got only the in-range test. One of them is
> `PLAN.md:1216`, which quotes `_balance.gd`'s corrected sentence back at
> itself, including its line number, on the one site in the repo whose entire
> subject is whether a quoted citation still holds. It had been stale since
> this session's first fix. The other is the `COUNT_WORD` paragraph above.
>
> **Six sites are citations on purpose and are now prose.** `PLAN.md` records
> drift by *naming the wrong line* — a sweep table of six rows whose subject is
> run.gd line 268 holding code it does not hold. Rewriting those as "line 268"
> keeps the record and stops them reading as pointers, which is the same
> treatment `_balance.gd`'s copy of that citation already got.
>
> Measured, both halves. Restoring a doc citation to its original dead value —
> the roster range back to lines 132 to 144 — goes red: *"play/LISTING.md line
> 185 cites run.gd line 132, which is a blank line"*. Pointing it back at the wrong
> *function*, the name-and-behaviour assertions to lines 569 to 577 instead of
> 620 to 628, stays **green** — it lands on a real,
> non-blank doc comment three lines from the truth. That is the same blind spot
> the `.gd` half has, now demonstrated in the second place it applies, and it is
> why all 82 were read by hand and not merely resolved.

> **The mechanism all 9041 checks pass through held up.** `_check.gd` was the
> last major un-audited file and the one every finding in this document
> ultimately rests on, so its doc comments were enumerated rather than skimmed:
> seven claims — six about the gate's behaviour, one recording a measurement of
> its own. Five are true as written. One is historical arithmetic that still
> adds up. One is true only in a narrower scope than its wording admits.
>
> **The headline claim had to be measured rather than read, and measuring it
> exposed a defect in my own method that had been passing all session.**
> Line 50 promises `returns the process exit code: 0 clean, 1 dirty` at `_check.gd:50`,
> and the floor is worthless without it. Forcing the
> floor to 999999 and reading the process's own status gives 1. True. But every
> `EXIT=0` reported in this audit came from `godot ... 2>&1 | tail; echo
> "EXIT=$?"`, and **`$?` after a pipe is the status of `tail`, the last element
> of the pipeline, not of `godot`.** Each of those reports would have printed
> `EXIT=0` for a red suite. They came out right by coincidence — the runs were
> green, and `tail` really does exit 0 — and that is what made the method
> invisible: both readings agree at 0 and diverge only on the run you most want
> to read correctly. `${PIPESTATUS[0]}` is the fix, and every exit code in this
> block is taken that way. The `EXIT=124` further up is unaffected and was never
> affected: 124 is `timeout`'s code for *killed after the deadline*, so it is a
> reading of `timeout`, not of a `godot` that never got to exit at all.
>
> **Three more are verified against the code rather than against the prose.**
> `_check.gd:54` names `_pack.gd` as the one reporter that passes no floor, and
> both its call sites still do — `_pack.gd:87` and `_pack.gd:130`, and those
> two are the only `Check.report(` calls in the repo without a second argument.
> `_check.gd:20` names `_axis_report` as one of the two measured throws; it is
> still `_balance.gd:726`. `_check.gd:74` justifies leaving `Check.failures`
> undeduplicated on the grounds that `dice.gd` and `run.gd` both read its size,
> and those are the only two readers of it anywhere — `dice.gd:1108` and
> `run.gd:1126`, exactly the two named. A census the docstring asserts as
> fact, checked rather than trusted.
>
> **The 8167/8527 incident still adds up, and was a bigger loss than it reads.**
> `dice.gd:21` records a throw on the first line of `dice.gd::_focus_tests`
> costing 360 checks at exit 0, and the subtraction is right. What the comment
> does not say is that `_focus_tests` is not a leaf: its tail dispatches six
> more suites (`dice.gd:1170` onward — `_bank_tests`, `_expose_tests`,
> `_rush_tests`, `_deflect_tests`, `_bastion_tests`, `_bank_budget_tests`), so
> 360 was the cost of the whole subtree, not of one function. Both figures are a
> dated measurement and the suite prints 9041 now. Left alone deliberately: the
> difference from the `8392`/`8469` strings in `BALANCE.md` is that those were
> standing in for a pass condition, and these two stand in for nothing — no
> check reads them, nothing goes red or green on them. A historical note that
> decides nothing does not rot the way a stale pass condition does.
>
> **The one genuine scope error, and why correcting it would buy nothing.**
> Lines 4-9 argue that `assert()` cannot gate this suite because it aborts the
> calling function, "so `test.gd::_init()` never reaches `quit()` and the
> SceneTree hangs". That inference only holds if the abort happens in `_init()`'s
> own frame. It holds for the 22 checks `_init()` runs inline — the UI parse loop
> — and not for the other 8934, which are at least one frame down: `_focus_tests`
> is called as a bare statement and the next line of its caller prints
> unconditionally. An `assert()` in a helper would abort that helper, let
> `_init()` resume at its next statement, reach `quit()`, and exit 1 on the
> floor. **Not a hang** — and the document's own next paragraph states the
> opposite consequence for the same mechanism. Not rewritten, on purpose: the
> mis-stated case is the one the floor catches by construction, so no reachable
> behaviour is wrong, and reworking the rationale in the file that explains why
> this gate has no `assert()` is a large edit to buy symmetry of wording.

> **The gate proves a cited line exists. It cannot prove the line says what the
> citing comment claims, and six of them did not.** `_citations` charges two
> checks for a plain `file.gd:N` — in range, not blank — which is existence, not
> meaning. `PLAN.md` has already recorded what that costs on the documentation
> side: pointing a citation back at the wrong *function* stays green, because it
> lands on a real non-blank line near the truth. This is the same blind spot on
> the **code** side, and there it is one line off.
>
> The census is 159 citation sites, 120 of them in this file and 14 in the Play
> listing, so the code-facing ones are the small remainder: 25 across `run.gd`,
> `shot.gd`, `BALANCE.md`, `_pack.gd`, `test.gd`, `_balance.gd` and `_rects.gd`.
> Every one was read against its target. **Nineteen hold. Six are wrong** — three
> in `run.gd`, two in `shot.gd`, one in `_balance.gd` — and all six are
> *describing something true about the wrong line*.
>
> **The first census undercounted them, and that is the part worth keeping.** The
> expression used to enumerate the sites required a backtick on each side of
> `file.gd:N`. The gate's does not: its plain pattern matches the bare form
> anywhere in a line. So the count came back 17 code-facing where the gate sees
> 25, and the eight it missed were eight nobody had read — which is how a tidy
> three-defect story in one file became four in two. Re-running the census with
> the gate's own two expressions, lifted from `test.gd` rather than rebuilt from
> the prose that describes them, is what found the second file. A hand-built
> approximation of the mechanism you are auditing is the failure this document
> has now recorded six times, and the guard against it costs nothing: read the
> two lines that do the matching.
>
> **The commonest defect is off by one, and it is not confined to one site.**
> `run.gd:253` cited `dice.gd:661` for a comment claiming the expose window is
> "set again" after `dice.gd:657` decrements it. Line 661 is
> `if precision and hardest >= EXPOSE_AT and not over:` — the guard. The
> assignment is 662. A one-character edit turns a pointer at a code line into a
> pointer at the `if` in front of it, and the gate has nothing to say, because
> the line is there and it is not blank. The same wrong line was cited twice
> more, from `shot.gd:699` and `shot.gd:705`, in both cases for the same thing
> — the place exposure is set — so one renumbering was wrong three times over
> and in two files. Of the three, the one in `run.gd` was converted to quote
> form rather than merely renumbered, on the argument that `enemy.exposed = 1`
> and the `if` that admits it are adjacent in wording and adjacent in meaning,
> which makes this the citation most likely to rot again. The other two were
> left plain, because quoting them means rewrapping `shot.gd` and PLAN.md cites
> lines in that file.
>
> **The second pointed at a layout offset and claimed to be about a Label.**
> `run.gd:228` supported "a reward Label has no autowrap" with
> `stack.offset_bottom = -14` at `game.gd:501` — a VBoxContainer margin fourteen
> pixels from the bottom of the card, with nothing to do with wrapping. The claim
> itself is true and trivially so: `autowrap_mode` is set nowhere in the repo,
> in any file, and the Label is built at `game.gd:235` without it, so the
> default `OFF` stands. The citation moved to the factory that omits it. Found
> by grepping for the thing being claimed — zero hits outside comments, which is
> the shape of an answer: a property held by nobody is held by everybody.
>
> **The third had the direction backwards, and only a measurement settled it.**
> `run.gd:710` reported that `_balance.gd:179` "argues ... 'seven of nine'
> armoured and 'two of them' able to grow into the cap -- and both were wrong."
> Line 179 says no such thing. What it reads is
> `the roster carries armour on eight of its nine enemies` at `_balance.gd:179`
> -- all of them but the Grunt -- and two lines on, three growers, not two. So the file under
> suspicion was right and the file accusing it was stale — `_balance.gd:184`
> keeps the old "seven of nine" text in the past tense, correctly, and `run.gd`
> was quoting a dead first draft as current. Counting settled it rather than
> argument: the roster is nine `Enemy.new(title, hp, armor, atk, behaviour)`
> calls at `run.gd:146-158`, and their armour values are 0, 3, 1, 2, 2, 5, 2, 3,
> 5 — eight non-zero, every one but the Grunt. The three growers are Rust
> Golem and Stone Sentinel on `BEH_ARMOR_GROW` and Ironhide on `BEH_BRACE`,
> which shares the cap. Both of `_balance.gd`'s corrected figures are right.
> The claim that they are pinned holds too: `Both counts are pinned` at
> `_balance.gd:186` points at `run.gd:725` and `run.gd:726`, which assert
> `armoured == 8` and `growing == 3` over every depth. Four files agreeing,
> and the one that was wrong was the one making the accusation.
>
> **The fourth is the same off-by-one again, and it is why the census mattered.**
> `_balance.gd:266` records that paired faces ship as "`Face.pairs` on Fang's
> `5`", citing `dice.gd:383`. Line 383 is the `8`, the `11` and the `pierce 6`.
> Fang's `5` is on 382, one line up, on the face row above it. A line that
> begins with three other faces is a perfectly good line for a gate to certify
> as existing and non-blank, and it is the wrong one by exactly the distance
> that matters. Nothing in this audit turned up a *systematic* cause — 661 was
> cited three times and 383 once, and they are unrelated lines in unrelated
> functions. The shape is just what happens when a comment names a line by hand
> and code above it grows by one row.
>
> **Of the nineteen that hold, two were near enough to be worth naming.**
> `game.gd:516` is cited for the fixed 146px card and lands inside the comment
> block that argues exactly that — right paragraph, slightly off sentence.
> `test.gd:613` cites `run.gd:312` for "the three hand corrections", which is a
> region rather than a line, and 312 sits inside the doc block recording them.
> Both are loose in the way a pointer to a paragraph is loose, and both would
> have been called wrong by a stricter rule than the one this repo holds itself
> to — so they are named here rather than fixed, because the rule that would
> flag them would also flag every honest pointer to a paragraph.
>
> **Corrections were same-width token swaps, and that is not laziness.** Converting
> all six to quote form is what makes them self-correcting, but a quote-form
> citation is twenty-two characters longer than the bare form here, and rewrapping
> to fit shifts lines — which moves every citation *into* that file and manufactures
> the exact defect this block is about. `run.gd` is pointed at by `test.gd:613`,
> `run.gd:1084` points at `run.gd:71`, and this file cites lines inside
> `shot.gd`, so a line count change in either is not free. The one conversion
> that was made was done without touching the line count, and all three edited
> files are the same length they were before any of this: `run.gd` at 1127 lines
> and `shot.gd` at 1523, verified by re-counting rather than by the diff, which
> shows this session's whole accumulated change to a file and cannot isolate
> three comments in it.

> ### The second floor's arithmetic is true, and the table above it had drifted
>
> The repo has two floors and `_check.gd:28` holds both to one rule: a floor is
> set "equal to the count the caller expects, not comfortably below it".
> `_balance.gd:714` passes 22025 against a bench that actually runs 167697 — some
> 145,000 of margin, on the one file whose floor is deliberately loose. That is
> not an oversight; the trade is argued in place and the argument is sound. But
> an argued trade is only as good as the arithmetic under it, and that part was
> falsifiable, so it was falsified.
>
> **Every group in the parenthetical maps to a real check, at the multiplicity
> claimed.** Enumerating every `Check.check` in the file with its indent depth
> and enclosing loop puts `_axis_report` and `_plan_cards` together at 20:
> `not axis_name.is_empty()` inside `for u in RunState.UPGRADES` × 12, one
> histogram invariant, one "PLAN.md 1.1 is still findable", one per bullet in
> `### 1.1`…`### 1.2` × 3 (grepped, not inferred), and three prose checks — the
> last of which sits under `if m != null:` and so fires once rather than per
> line. The three verdict checks at one tab are at 579, 587 and 661, and
> `_gate_ratio` adds 2. 20 + 3 + 2 + 22000 = 22025.
>
> **The 22000 is a guarantee rather than a measurement, and both halves hold.**
> `rows.size()` is 22 — twelve upgrades, `<random>`, four die policies, four
> archetype pairings, `nudge` — and `N` is 1000. The loop cannot run short,
> because GDScript's `break` leaves only the innermost loop and all seven
> `break`s in the file sit at five tabs or deeper, inside `while true:`,
> `while not enc.over:`, `for j` or `for o`. None sits at the three-tab body
> level of `for i in N:`. Nor can a run skip its first fight: `r.start_fight()`
> is the first statement of `while true:`, ahead of every guard. The three
> run-ending breaks at five tabs are that loop doing its job, not a leak in the
> bound — which is the distinction the old sentence blurred by saying the trial
> loop has "no `break` in it" without saying which loop it meant.
>
> **The table above the argument had drifted, and one row documents a failure the
> floor can no longer produce.** It read 167694, 167694, and "32 short, EXIT 1".
> Re-measured by moving the seed base and changing nothing else: 167695, 167798,
> 167663 — all three clearing 22023, the last at EXIT 0. The shipped row is
> stable, two runs agreeing to the check, so this is drift and not a flapping
> statistic. The 91000 row was the worse of the two: "32 short, EXIT 1" was
> measured against a floor calibrated on the shipped row's own count, and that
> floor is gone, so as written it teaches the next reader to expect a red run
> that is now green, and calls the green evidence for a trade. Corrected at
> `_balance.gd:684`, with the `quit` at 714. Adding `_gate_ratio` put a line
> below five of these citations, so all five moved and each was re-measured.
>
> **And the block's own pointer was off by one, in the one place the gate cannot
> see.** "The check at line 589" named a line two past the check: the call is at
> 587, and 589 is inside its message. The same shape as `test.gd:613`, and free
> to fix while the paragraph was being rewritten anyway — which is the argument
> for rewriting a paragraph when a number in it is found wrong, rather than
> patching the digit and leaving the reasoning that produced it.

> ### `BALANCE.md` is written to catch its own staleness, and the two claims it got wrong were both *derived* from a number that had already moved
>
> `BALANCE.md` is the most self-aware document in this repo. It carries ten
> blockquotes recording its own staleness, one of which names the exact failure
> this block is about — fixing "a stale number by writing down a fresher one
> moves the staleness, it does not remove it". So auditing it is expected to
> find nothing, and that is the reason to run the audit rather than skip it.
> Audited against a fresh bench (N=1000, seeds 7000..7999, 167697 checks), two
> claims are false, and neither is a number that went stale. Both are numbers
> *derived* from one that did.
>
> **The gate states criterion 1 twice, and the two statements now disagree.**
> `BALANCE.md:490` requires the ratio to strictly widen against `1.49x`;
> `BALANCE.md:553` gives that same criterion as "beating 24.4% wins" and closes
> "**24.4% is the live threshold and it is correct under both**". At the
> measured `<random>` of 18.0%, 24.4% scores **1.36x** — it fails the very
> criterion it is the percentage form of, whose real threshold is **26.8%**.
> And `BALANCE.md:430` already records the live ratio as **1.55x** (27.9% over
> 18.0%, which the bench reproduces to the digit), so the document does not
> merely drift, it contradicts itself in three places at once. This is the one
> class of number `BALANCE.md` itself says is read hardest: a pass condition,
> read on every run.
>
> **"MEND, BLESS, FOCUS and VIGOR are all below random" is false for two of the
> four** (`BALANCE.md:59`). MEND measures 18.5% and BLESS 19.9% against the
> 18.0% control; only FOCUS at 10.5% and VIGOR at 17.7% are still sub-random.
> Item 3 of the same file reached the BLESS half and said so with statistics —
> "only-BLESS-won 308, only-random-won 237, net +71 of 545, exact two-sided
> p = 0.0027" at `BALANCE.md:648` — so the sentence and the entry have
> contradicted each other since that entry was filed, and the entry is the one
> with a distribution behind it. Corrected in place rather than filed as an
> eleventh drift note, because a claim contradicted *inside one document* is
> not drift: one of the two was never true at the moment it was read.
>
> **The generalisable part is about derived claims, and the file already knows
> it.** Ten drift notes recorded the *input* — `16.4% → 18.0%` — and neither
> sentence built on that input was ever revisited. A restamp that updates the
> table and leaves the prose is the failure this document has already
> identified three times, one level up from where it happened. The check that
> would have caught both is cheap and cannot go stale: the ratio and its
> percentage form are one claim written twice, so recompute one from the other
> and fail when they disagree. That belongs in `_balance.gd`, which already
> owns the bench's verdicts, rather than as an eleventh note.
>
> **Two by-line citations into `BALANCE.md` were already pointing at the wrong
> paragraph, and my own edit made them worse before it made them better.**
> `_balance.gd:843` and `PLAN.md:172` both cited `BALANCE.md:593` for
> DISCIPLINED_MIND's criterion-3 drop. Line 593 sits inside the blockquote
> arguing that criterion 1 had become unreachable — a different criterion
> making a different argument — so a false citation of this class was already
> sitting in the tree, in a file the previous block's census could not reach.
> Correcting the two defects above added ten lines above 593 and slid the line
> onto "## Rules", which is the only reason the mistake became visible at all:
> **markdown is uncitable by the gate, whose two expressions both require
> `.gd`, so a by-line pointer into a `.md` is a claim with no verifier
> anywhere.** That is this whole audit's failure mode, one file type out of
> reach. Both now point at `BALANCE.md:659`, and each fix is a digit swap, so
> neither file's line count moved and nothing else shifted under them.

To re-shoot the Play listing (overwrites `play/screenshots/`):
```bash
xvfb-run -a godot --path . --rendering-driver opengl3 -s shot.gd
```
