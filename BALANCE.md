# Balance backlog — the memory for unattended work

There is no background me. A scheduled job fires a prompt, that run starts with
whatever context exists, and it ends. The only thing that survives between runs
is this file. Treat it as the memory: read it, do one item, append the result.

## Why this exists

The research that produced the current pool is recorded in `run.gd`. Summary:
card *count* is not the lever, distinct *mechanics* are — and every attempt to
improve the game by adding cards made the measured win rate worse:

| pool | random win% |
|---|---|
| 8 cards | 12.7% |
| 14 cards incl. downsides | 2.7% |
| 12 cards incl. dominated | 7.3% |
| 9 cards (shipped) | 12.0% |

Adding cards without distinct mechanics is a regression. That is the whole
reason a gate exists.

### The offer table is the difficulty dial (measured 2026-09-29)

Retiring REFORGE — the worst card at 4.7% — sent random win% from **12.0% to
29.3%** and collapsed best/random to 1.16x. Removing the single worst card in
the table nearly tripled the win rate of a blind player.

The offer is 1-of-3 drawn uniformly from the whole table, so a weak card is not
"a pick you sometimes regret". It is a slot in the lottery that periodically
hands the random player garbage, and a third of that player's runs are ruined
by it. REFORGE was not dead weight; it was about 11% of all offer slots being a
dud, and that dud density was holding the floor down.

This also explains the table above, and corrects the reading of it. **Downside
density, not card count, is the lever.** The two pools with downsides (14 → 2.7%,
12 → 7.3%) are both far harder than the two without (8 → 12.7%, 9 → 12.0%),
even though the *smaller* pool is one of the easy ones. The shipped 9-card table
is a tuned difficulty setting, and every card in it is load-bearing for that,
including the ones that measure worst.

The corollary that matters: **a below-random card is not evidence that the card
is bad.** It is evidence that the table is at the difficulty it is at. Do not
retire the sub-random cards — MEND, BLESS, FOCUS and VIGOR are all below
random, and the two that were tried behaved as predicted.

The same shape has now been caught twice in `dice.gd`, so read it as the general
law rather than a fact about cards: **any flat bonus to output is a flat bonus
to output**, wherever it lives. Item 1 below handed Sunder's `cleave` a per-face
pierce of 12 and it failed the gate for exactly the reason the 14-card pool did —
random win% nearly doubled (12.0% -> 22.7%) while best/random went *narrower*
(2.0x -> 1.67x). Nothing got more interesting; the whole pool just got stronger.
What widens the ratio is a bonus that creates a decision, not one that removes a
question.

### The ratio does not respond to the card table's composition either (2026-09-29)

Item 1 was run and failed, and the way it failed is worth more than the card
was. Four changes, three different mechanisms, every one below the 2.0x:

| change | table | best/random | random | depth |
|---|---|---|---|---|
| baseline | 9 cards | 2.00x | 12.0% | 7.97 |
| remove REFORGE, the worst card | 8 cards | 1.16x | 29.3% | 8.22 |
| add TEMPER, a deliberate downside | 10 cards | 1.29x | 16.0% | 7.85 |
| add TEMPER with the cost removed (control) | 10 cards | 1.60x | 32.0% | 8.13 |
| swap MEND out, table back to 9 | 9 cards | 1.63x | 16.7% | 7.83 |

The control is the informative one. Strip the 12-health cost off TEMPER and it
measures **51.3%** — the best card in the table, twice the baseline's best. Put
the cost back and it measures **4.0%** — the worst. So the card is genuinely a
sharp trade and the downside does real work, exactly as designed. And the ratio
is 1.60x either way.

The reason is that `roll_rewards` draws every card at an equal rate. An "always
take X" strategy gets X in 1/N of the offer slots and something else in the
rest, so it drifts toward random as N grows. Meanwhile random's own expectation
moves with the new card's quality. **Both terms of the ratio are driven by the
same lottery, so changing the lottery moves them together.** The ratio is not a
dial this class of change can turn.

The corollary is uncomfortable: the 2.0x baseline is a property of that one
9-card table, not a stable target. The top row also swung — BULWARK, ADD_DIE,
VIGOR and TEMPER each came first across these five runs, and with 150 runs a
24%-vs-12% gap is only ~3.4 sigma, so which card is "best" is partly luck.

**Read table size as the difficulty dial and the ratio as a smoke alarm, not a
goal.** Future card work should be judged on random win% and depth, which both
moved as expected here (16.7% is inside the 8–18% band, depth 7.83 holds the 7.6
floor), and on whether the pick is *interesting* — which is what the ratio was
standing in for and cannot measure.

TEMPER is not in the game. All four variants were reverted and the baseline
reproduces to the digit on all ten rows.

#### The fix that did not work, and the finding it produced (2026-09-29)

The obvious repair is to stop letting offer rate leak in: hand the strategy its
card every offer, so the row is the card's edge and not the lottery's. That is
implemented in `_balance.gd:_offer` and it is **wrong**, for a reason worth
recording.

| strategy | old (mix) | new (mandated every offer) |
|---|---|---|
| ADD_DIE | 23.3% | 25.3% |
| SHARPEN | 20.0% | 13.3% |
| BULWARK | 24.0% | 10.7% |
| BLESS | 7.3% | 0.7% |
| VIGOR | 8.7% | 0.0% |
| FOCUS | 8.0% | 0.0% |
| MEND | 7.3% | 0.0% |
| PIERCE | 15.3% | 0.0% |
| REFORGE | 4.7% | 0.0% |
| `<random>` | 12.0% | 12.0% |

Mandating a card does not isolate its edge — it removes the mixing, and the
mixing is the player's actual behaviour. The old `else offer[0]` fallback was
not a confound to be corrected; it was modelling "take X when dealt, otherwise
take something else", which is what anyone does.

Traced to the cause, and the cause is a real design result: **six of the nine
cards are strictly worse than useless when stacked.** A VIGOR-only run reaches
the boss with 84 max health and still loses, because health is not damage. A
FOCUS-only run dies to Stone Sentinel with 28 of its 40 health left, because
extra re-rolls cannot break armour that grows to 12 — re-rolling a 4 into a 4
is not a plan. The armour-gated enemies hard-counter any build that does not
add damage, and only SHARPEN and ADD_DIE do.

So the 1-of-3 offer is carrying more weight than it looks: it is what stops the
player from correctly identifying a strong card and then taking it eight times.
That is an argument for the current design, measured, not an argument against.

`roll_rewards` is also the reason the old ratio is noisy — a mandated instrument
does not exist for "how often may I take the good card", because the answer is
once, by design.

### The ratio cannot be widened by a `dice.gd` change (measured 2026-09-29)

Two independent rules changes, both dropped, both narrowed the ratio:

| change | best/random | random | why |
|---|---|---|---|
| baseline | 2.0x | 12.0% | — |
| item 1, per-face pierce | 1.67x | 22.7% | out of band, trivialised |
| item 2, paired face | 1.75x | 15.3% | in band, still narrowed |

The reason is structural, not bad luck. `best/random` is a *relative* measure and
a `dice.gd` change is *uniform* — it lifts every strategy, because every strategy
plays the same dice. Lifting the floor lifts the denominator. The sooner a run
finishes, the less the card it happened to take mattered, and the narrower the
ratio goes. So a rules change cannot pass criterion 1 unless it happens to flatter
the currently-worst cards, and designing toward that is writing to the test.

**Amendment, adopted 2026-09-29.** Split the criteria by what each file can move:

- **Card changes (`run.gd`)** — keep the gate exactly as it was. Cards are
  non-uniform by construction (you take 1 of 3, and they interact differently),
  so the ratio is the right instrument and it can move either way.
- **Rules changes (`dice.gd`)** — criterion 1 is replaced by: random win% stays
  in the 8–18% band **and does not rise by more than 3 points**. The rules may
  make the game more interesting at neutral difficulty. They may not make it
  easier, and they are not required to sharpen a metric they cannot move.
  Criteria 2 and 3 are unchanged.

This amendment did **not** rescue either result above. Both were reverted under
the gate as it stood when they were measured; the gate was changed afterwards,
so no future run can use it to justify a result it already has.

### Damage over time has no window to occupy (measured 2026-09-30)

**PLAN 0.3's third status — "Sundered / Bleed: damage dealt over time, allowing
slow defensive builds to win" — is not buildable as specified, and the reason is
`dice.gd:602`, not the card pool.** This is the second PLAN 0.3 bullet to close
and the two died for unrelated reasons, which is worth knowing: 0.3's "enemy
that counters on rolls > 10" died in the bottom-heavy face lists (no die but
Sunder can reach 10, and 2 of 24 faces can), and this one dies in the damage
model.

The premise the design rests on is that there is slack to convert — damage the
player has already paid for and the game throws away, which a defensive build
could bank instead of losing. **That slack is real and it is not small. None of
it is reachable.**

Over 4,620 fights on 600 seeds, with the HP clamp lifted in a sandbox copy so
the discarded damage is observable at all:

| | |
|---|---|
| true damage dealt | 169,219 |
| enemy total HP | 159,682 |
| **damage discarded past zero** | **31,400 — 18.6% of everything dealt** |
| fights whose killing blow overshot | 3,432 of 4,620 — 74.3% |
| **excess on a NON-killing resolve** | **0 — in 0 of 4,620 fights** |

Nearly a fifth of every point of damage in this game is deleted at
`if enemy.hp <= 0: enemy.hp = 0`. The probe is not in the repo, because it
cannot run against the shipped rules. To rebuild it: copy `dice.gd` and
`run.gd` to a scratch project and **delete the single line `enemy.hp = 0`
inside the `if enemy.hp <= 0:` block**. That is the whole patch. `run.gd`
stays byte-identical to HEAD, and `dice.gd` differs from HEAD by that one
line plus 12 lines of comment on `Face.pierce` — verified by diff, not
assumed, because a measurement taken against a drifted copy is the one
kind of number here that no sample size can rescue.

Then the reason none of it can be banked, which is definitional rather than
statistical and is why no sample size would have found it: **a resolve can only
overshoot by driving HP to or past zero, and a resolve that does that is the
killing blow.** The fight ends that resolve. All 31,400 sits on the blow that
ends the fight. The bottom row is the direct measurement of that: across 20,127
non-killing resolves dealing 103,107 damage — 60.9% of the total — the excess
is **0 damage in 0 of 4,620 fights**. Not "rarely", *zero*.

> **This section's headline number was wrong by a factor of 2.5, and the
> mistake was the same shape as the bug it went looking for.** The probe
> accumulated `dealt_total` only inside the `enc.over` branch, so "total damage
> dealt" was really *damage dealt on killing blows* — 66,112 against a true
> 169,219. Every percentage in the first version of this table was therefore
> "of all damage" when it was "of the last resolve of every fight", which is
> what turned 18.6% into a headline of 47.5% and the sentence above into "half
> of every point of damage in this game". **A measurement that divides by the
> wrong denominator reports a clean, confident, wrong ratio** — and the honest
> test of it was never a bigger sample, it was checking the denominator against
> the rules. The clamp it was measuring is real; only the accounting around it
> was not.
>
> The conclusion is unchanged and the reason survives the correction: the
> excess is unreachable because the fight ends on the only resolve that can
> produce any. What changes is the size of the prize, from "half the game's
> damage" to under a fifth — which is a smaller prize, and still too much to
> reach.

That kills every version a DoT could have taken:

- **Harvest the excess.** Impossible: the excess exists only on the blow that
  ends the fight, so there is no post-zero window for time-based damage to
  occupy. This was the design, and the size of the surplus is why it looked
  worth reaching for.
- **Re-time the same damage instead.** A tax for rushing and a nothing for
  everyone else, since a deck that kills in 2–3 turns never collects a tick.
  Fights last a mean of 5.20 resolves and only 18.9% are still running after
  five, so the delivery window is narrow as well as the surplus being unusable.
- **Add damage.** Then it is a plain damage increase. Random measures ~16%
  against a band topping out at 18, so there is about 1.6–2.4 points of room
  upward before criterion 2 fails outright — a DoT sized to be worth having
  does not fit in it.

**Do not retry** without first changing `dice.gd:602` so the fight does not end
at zero — let the enemy carry a wound that takes a turn to close, or let bleed
apply before the death check.

### …and the escape hatch does not work either (measured 2026-09-30)

That last paragraph used to end *"that is a real design"*. **It is not, and the
reason is worth more than the design would have been.** Moving the death check
was supposed to open the post-zero window, and the cost it would have charged is
tempo: the player takes K more enemy turns instead of the fight ending. Pricing
that cost is one arithmetic question —

```
affordable(K) = hp_at_kill - K * (atk - block_re_earned_each_turn)
```

Block is spent rather than banked (`block = 0` at the end of every enemy turn),
so an extra turn costs the player `atk - block re-earned`, not a drained stock.
Measured over the 3,894 fights the player won in the same 4,620:

| | |
|---|---|
| mean hp left at the killing blow | 16.11 |
| mean enemy attack | 5.32 |
| mean block earned on the last turn | 1.80 |
| mean fight length | 4.77 resolves |
| **can afford K=1 extra enemy turn** | **97.6% of wins** |
| **K=2** | **95.3%** |
| **K=3** | **93.0%** |
| K=4 | 90.3% |

(Re-measured against no block re-earned at all — the pessimistic end — K=1
survives 90.0%, K=2 76.1%, K=3 57.1%, K=4 32.1%.)

**93% of winners can afford three more enemy turns.** The tempo cost does not
gate anything. The premise of the card was that only a slow defensive build
could wait out the delay, and the measurement says nearly every build can — the
player arrives at the killing blow with three times the enemy's attack in hand,
and spends most of it on block, so the median extra turn costs 0 net damage (586
of 3,894 last turns are free or negative). So the third corner closes as well:

- **Harvest the excess.** No post-zero window exists (§ above).
- **Re-time the same damage.** No upside; a strictly dominated card.
- **Gate it on durability.** The gate does not discriminate — 93% pass.
- **Add damage.** A universal buff, and the band tops out 1.6–2.4 points above
  random.

**Do not add this as a card either.** A 13th card is *predicted* to fail
criterion 1 for the same structural reason item 1 was retired: BALANCE.md records
that growing the pool lifts random faster than it lifts the best card (the 10th
card moved random 12.0% → 16.0%), so the 1.49x ratio narrows by construction.
That is a prediction, not a measurement — it is recorded as the reason the item
is closed rather than the reason it should be retried.

What does survive from this section is the observation underneath all of it:
**difficulty in this game is set by turn count, not by damage totals.** That is
why the two `ARMOR_GROW` enemies are the grind of the roster (Rust Golem 13.2
resolves, Stone Sentinel 10.5) and the other seven die in about three. It is a
real finding and it constrains future design harder than any one card does — but
it is a finding, not a card, and closing 0.3 is what it costs.

## Baseline — measured, not remembered

`godot --headless --path . --quit -s _balance.gd`, 1000 runs per strategy,
seeds 7000..7999, so re-running reproduces these exactly. Re-measured
2026-09-30 at `dc6622c`, and the stamp is the point — see the note under the
table.

```
strategy        wins%   avg depth   max
ADD_DIE         24.4%     8.04     9
PRECISE_STRIKE  20.0%     8.00     9
SHARPEN         18.7%     7.99     9
BULWARK         18.6%     8.09     9
BLESS           17.6%     7.64     9
VIGOR           17.4%     7.63     9
<random>        16.4%     7.69     9
PIERCE          15.3%     7.87     9
MEND            13.5%     7.47     9
GAMBLERS_RUSH    9.9%     7.66     9
FOCUS            9.3%     7.36     9
REFORGE          8.3%     7.10     9
BASTION_HOLD     8.2%     7.13     9

  the die-policy rows, which pick no cards and so are not gated -- read these
  against <random> rather than against each other, same reward pool throughout
dice:reach     20.7%     8.15     9
dice:read      18.3%     7.99     9
dice:swing     13.1%     7.57     9
dice:chip       0.3%     3.11     9
dice:nudge     25.4%     8.27     9
<rand>+gamble  21.9%     7.94     9
GAMBLERS_RUSH+gamble    16.2%     7.88     9
<rand>+bank     1.3%     5.93     9
BASTION_HOLD+bank      1.1%     6.04     9
```

**This table went stale, and it went stale *predictably*, which is the finding.**
Item 7 (pierce on Fang) shipped in `599baac` and recorded its own result in its
own section: *"<random> 16.5% -> 16.4%, every row within 0.5pp, signs mixed."*
Nine of the twelve card rows above then sat at their pre-item-7 wins% anyway
(for a full session), because the item entries and this table are two copies of
one fact and only one of them was updated. The document's own header calls it
"measured, not remembered", and it had been remembered.

The numbers themselves are immaterial — 0.5pp moves no verdict, and the three
gates all still read the same pass/fail they did before (random 16.4% is still
inside 8–18%, depth 7.69 is still above 7.6, and criterion 1's threshold lands
on 24.4% either way). The defect is the process one, and the commit stamp above
is the fix: this table is cheap to re-run and the only thing that made it go
quiet was that nothing said *when* it was last true. **Re-run the bench and
restamp this block in the same commit as any change to the rules.** A row here
that disagrees with an item entry above it is a stale row, not a disagreement.

Three numbers define "better":

- **best/random ratio** — baseline `1.49x` (ADD_DIE over random). How much the
  1-of-3 pick matters. This is the thing the game is actually for.
- **random win%** — baseline `16.4%`. A blind player. Must stay in a band.
- **avg depth** — baseline `7.69`. If a change moves wins but not depth, it
  mostly shifted which fight kills you, not whether you finish.

**The ratio's own baseline moved, and the pool moved it.** This block used to
read `2.0x` off BULWARK over a random at 12.0%, on nine cards. The pool is
twelve cards now and `<random>` is 16.4%, so the same arithmetic reads `1.49x`
off ADD_DIE. That is not a card getting worse and not a regression — it is the
effect named in "The ratio does not respond to the card table's composition"
above, where a bigger table lifts the random draw faster than it lifts the best
card. The old `2.0x` is not a number this game can produce any more, which is
what makes criterion 1 below unreadable rather than merely demanding. Item 7
then moved it a further 0.01x on its own, with no card added — so the ratio
tracks the rules, not only the pool, and the stamp is load-bearing.

Depth is the quieter half of the same story: 7.97 -> 7.69 against a 7.6 floor.
That is the number to watch before the ratio, because the floor is a hard fail
and the ratio is not.

> **How much room the floor actually has, measured (2026-09-30).** This block
> used to say *"a blind run finishes 0.09 into 0.09 of headroom"* — the margin
> restated as if it were the noise, which is a different quantity and the
> reason the floor looked like a hard, deterministic edge. Tallying depth
> per run over the same 1,000 seeds (mean reproduces at **7.6910**, so the
> tally is the bench's own convention, not a new one):
>
> | | |
> |---|---|
> | sd of a run's depth | 1.9711 |
> | **SE at N=1000** | **0.0623** |
> | margin over the 7.6 floor | 0.0910 — **1.5 standard errors** |
> | 95% CI on mean depth | [7.5688, 7.8132] |
>
> Two corrections. The scale is **0.0623**, not 0.09, so the floor has 1.5
> runs of headroom rather than exactly one. And the 95% interval **straddles
> 7.6**, which means a change that alters the rules by *nothing measurable*
> still fails criterion 3 about **7% of the time** (z = -1.46). Criterion 3 is
> a real constraint and it is the tight one — but it is a *statistical* floor
> wearing a hard one, and a lone failed criterion 3 should be re-run before
> it is read as "this change costs depth".
>
> The caveat that keeps this honest: the seeds are fixed, so re-running the
> same build gives bit-identical depth and the SE only bites when the rules or
> the seed set change. It is the right figure for "how far can this move and
> still mean something", not for "will this number wobble on re-run".

## The gate

A change is kept only if **all** of these hold after the full suite passes
(`godot --headless --path . --quit -s test.gd`, which must exit **0** and print
`test.gd: <n> checks passed`; a failure prints
`=== test.gd: <k> of <n> CHECKS FAILED ===` and exits 1):

1. best/random ratio **strictly widens** vs `1.49x`, and
2. random win% stays within **8–18%**, and
3. avg depth does not drop below `7.6`.

> **This gate's own pass condition was three-quarters fiction, checked
> 2026-09-30.** It used to require the suite to print `dice.self_test: OK`,
> `run.self_test: OK`, `9 scripts load`, `reached end`. Three of those four
> strings do not exist and never have for some time: the per-script lines are
> `dice.self_test: 8392 checks, 0 failed` and `run.self_test: 8469 checks,
> 0 failed`, and the script count is **11**, not 9. Only `reached end` still
> appears. So the one place in this document that says what "green" means was
> describing an older `test.gd`, and a person following it literally would grep
> for `OK`, find nothing, and have no way to tell a broken suite from a changed
> output format — which is the exact ambiguity that makes a red build
> shippable.
>
> The fix is deliberately not "correct the three strings". Every one of them is
> a thing that drifts: the two counts change whenever a check is added, and
> `9 scripts load` changes whenever a script is. Hardcoding them again would
> rebuild the same trap one commit later. The condition is now the **exit code**
> — which `_check.gd:report()` already returns 0/1 on, and which `2b07efd`
> added deliberately so a broken suite exits non-zero instead of hanging the
> SceneTree — paired with the one line whose format is stable because it is
> written by that same function.
>
> Same failure class as the Baseline table above, one level up: a second copy
> of a fact with nothing to propagate it. The stamp that fixed the Baseline is
> the fix here too — do not hand-maintain a number the program already prints.
>
> `--quit` is in the command above and not in PLAN.md's copy of it; both were
> run and both exit 0 with identical output, so that difference is cosmetic
> and was left alone rather than tidied.

> **Criterion 1 was left at `2.0x` for four runs after the pool outgrew it,
> and that is the honest reason this block was stale rather than merely old.**
> On the twelve-card pool a 2.0x ratio needs the best card at **33.0%** with
> random at 16.5%. The best card in the table measures 24.4% and the best row
> in the whole bench — `dice:nudge`, which is a die policy and not a card at
> all — measures 25.4%. So criterion 1 as it stood could not be passed by any
> configuration of the shipped game; every run against it failed for a reason
> that had nothing to do with the change under test, and the failures were
> being read as evidence about cards.
>
> The threshold is re-anchored to `1.48x` because that is the best/random the
> pool produced at the time — `24.5/16.5 = 1.4848` — and a comparison has to be
> against something reachable to mean anything. It is deliberately *not*
> re-anchored to "whatever
> the last run scored" — that would make the gate unfailable by a card that does
> nothing. This is a change to what passing means, so it is stated here rather
> than buried: **a card now passes criterion 1 by beating 1.49x, which today
> means beating 24.4% wins.** The number moves every time the pool does, and —
> measured 2026-09-30 — it also moves when a single face is retuned, so the
> 1.49x above and the 1.48x in this paragraph are not a contradiction: the
> re-anchor was made at 16.5% and item 7 then moved random to 16.4%.
> **24.4% is the live threshold and it is correct under both.**

Otherwise revert and record why. The 8–18% band is the part that matters most:
a roguelike that a blind player wins 12% of the time is about right, and
"improve the game" must not quietly become "make it trivial". Widening the ratio
while random sits at 8% is a *harder* game with sharper decisions, which is the
goal; widening it while random sits at 30% is a worse game with sharper
decisions.

**The band is lopsided, and the lopsidedness is invisible until you subtract.**
Random currently measures 16.4% at N=1000 and 15.6% at N=4000 — so somewhere
around **16%**, against a band of 8–18%. That is 1.6–2.4 points of room *up* and
roughly 8 points of room *down*. The band reads as symmetric and is not, and the
asymmetry decides what a change can be for: almost any rebalance that makes the
game easier is one or two cards from failing a hard criterion, while making it
harder has room for several runs' worth of work. Worth knowing before reading a
failed criterion 2 as "this card is too strong" — the failure may be the band
closing, not the card. Criterion 3 has the same shape from below, and it is
tighter: 7.691 against a 7.6 floor is a margin of 0.091 against a standard
error of 0.062, so the floor sits inside the 95% interval. See the measurement
under the Baseline block above.

**Criterion 1 does not apply to `dice.gd`.** See "The ratio cannot be widened by
a `dice.gd` change" above — a rules change is uniform, so it cannot move a
relative metric. For rules changes, replace criterion 1 with: random win% stays
in the band and does not rise by more than **3 points**. Card changes keep the
gate as written.

## Rules

- **One item per run.** Two changes in one measurement cannot be attributed.
- **Never edit `dice.gd` rules and `run.gd` cards in the same run.**
- `dice.gd` and `run.gd` are `RefCounted` and headless-testable. Do not build a
  new system; extend `Face`, or add a die to `DICE`.
- The screenshot harness and store art are **out of scope** for this loop.
- If an item cannot be measured, do not attempt it. Record why, move on.

## Items

Two lists, because the gate now works differently on them. **Cards first** —
`run.gd` is where the ratio can actually move, and three of the four cards
beating random are output-multiplying, so that is where the wins are. **Rules
second** — measured under the amended criterion, on the band alone.

Strike through and note the verdict when tried.

### Cards (`run.gd`) — full gate applies, but see the ratio caveat above

1. **~~[x] Add one deliberate downside card, sized to spend the band.~~ DROP
   2026-09-29, four ways.** The premise was that a card costing the player
   something real would pull random down and leave the strong picks intact. It
   does not: the card pulls random *up* (12.0% → 16.0%), because a 10th card
   dilutes every existing card's offer rate and the whole table shifts. Ratios
   1.29x / 1.60x / 1.63x across add, add-without-cost, and swap. The card itself
   works exactly as designed — 51.3% uncosted, 4.0% costed, the sharpest trade
   in the table. What fails is the premise, and it fails structurally: see
   "The ratio does not respond to the card table's composition". **Do not
   retry** without a different gate.
2. **~~[x] Make MEND scale instead of retiring it.~~ DROP 2026-09-29, on the
   narrowest possible miss.** `hp = mini(hp + 4 + (max_hp - hp) / 2, max_hp)`
   — 4 when whole, 16 when nearly dead, so the card's value became conditional
   instead of a flat 14 that reads as wasted at full health. Measured best/
   random `1.94x` (was `2.00x`), random `12.0%` (**unchanged**), MEND `7.3%`
   (**unchanged**), depth `7.97` (**unchanged**). Failed criterion 1 by `0.06x`.
   That is **one run out of 150** — BULWARK went 24.0% to 23.3% because a
   BULWARK-strategy run that fell back to MEND now heals differently. The change
   was measurably neutral and the card was strictly better-designed, which is
   the one case where the gate's letter and the design's merit diverge. Reverted
   anyway: the gate was written to be trusted by the unattended loop, and
   loosening it the moment a result fails is how a gate stops meaning anything.
   The idea is not lost — it is here, with its numbers, if anyone wants to argue
   it with a bigger run count.
3. **~~[x] BLESS is below random (7.3%). Raise its numbers.~~ DROP 2026-09-30,
   on the premise, before any code.** The instruction and the measurement point
   opposite ways, and it is the measurement that is current. That `7.3%` is a
   **nine-card-pool** number; the pool is twelve cards, where BLESS measures
   17.6% against a random at 16.5% — i.e. above random, not below it. Raising
   its numbers would have made the game *easier*, which is the opposite of what
   the item asked for.
   1.1pp at N=1000 is 0.94 standard errors, so the aggregate cannot settle the
   sign, and "not significantly different" is not the same as "still below".
   Both arms re-run on 4000 **paired** seeds and scored on the discordant pairs,
   which is what the unpaired standard error throws away: **only-BLESS-won 308,
   only-random-won 237, net +71 of 545, exact two-sided p = 0.0027**. BLESS is
   above random. Not a near-miss, and not noise.
   So the card is not mis-sized, and there is nothing to raise. What it is
   instead is a **difficulty load-bearer** — 17.4% against a 15.6% random, near
   the top of the 8–18% band — which is the role this document has spent four
   items calling a bad card, and the one thing `7.3%` had concealed.
   The generalisable part: **every open item in this file was written against
   the 9-card pool, and this is the second one in two days whose premise had to
   be re-measured before it could be worked at all.** Re-measure an item's
   premise against the current pool before building it.

### Rules (`dice.gd`) — band-and-delta applies, ratio does not

4. **~~[x] Retire REFORGE.~~ DROP 2026-09-29.** Listed as a card change and run
   under the full gate, which it failed. `best/random 1.16x`, random `29.3%`,
   depth `8.22`. The worst card in the table was carrying the game's
   difficulty — see "The offer table is the difficulty dial" above. Reverted;
   baseline reproduces to the digit on all ten rows.
5. **~~[x] Per-face armour pierce.~~ DROP 2026-09-29.** `Face.pierce: int`,
   added to the run's pierce in `resolve_faces`; Sunder's `cleave` got 12,
   equal to `Enemy.ARMOR_GROW_CAP`, so it ignored any armour the game makes.
   Measured `best/random 1.67x` (ADD_DIE 38.0% over random 22.7%) and random
   22.7% — over the band, and the ratio *narrowed*. Sunder is a starter die,
   so this was a free 12 chip of damage in every fight of every run, which is
   the 14-card regression wearing a new hat. Reverted. See item 7.
6. **~~[x] A conditional face.~~ DROP 2026-09-29, but the best of the three.**
   `Face.pairs`, doubling the face when another die shows the same number;
   Blade's "5" became "5x2". Measured `best/random 1.75x`, random `15.3%`
   (+3.3), depth `8.17`. Reverted under the gate as it stood — the ratio had
   narrowed, and that is what the rule said. Neither lesson is about the
   mechanic failing: the game did **not** get materially easier (in band, depth
   held), and the ratio narrowed anyway, for the structural reason above. Under
   the amended criterion this would have been a marginal pass on delta. It is
   the mechanic most likely to survive contact with players.
7. **~~[x] Per-face armour pierce, on an *acquired* die.~~ KEEP 2026-09-30.**
   `Face.pierce: int`, threaded into both `enemy.pierce()` call sites in
   `resolve_faces` — the main loop *and* the held-die cash. On Fang, the `18`
   became a `15` that pierces 6. That swap is the whole of item 5's designed-out
   failure mode: the item said a piercing face is only a decision if something
   was given up for it, so the raw number comes down by 3 and the face moves by
   `min(armour, 6) - 3` — three less unarmoured, two more once armour is 4, and
   still 9 at `ARMOR_GROW_CAP`, so the "swingiest faces always land something"
   invariant survives. The pierce is 6, not 12, which is what item 5 got wrong.
   Measured against the Baseline above on the same seeds: **random 16.5% →
   16.4%, depth 7.69 → 7.69**, every row within 0.5pp with mixed signs, suite
   8490/0. Band holds, floor holds, ratio unchanged — the same verdict item 8
   got, for the same reason.
   The number that matters more is the trigger rate, because "neutral" and
   "never fires" look identical in a win% table — which is exactly how PLAN
   0.3's big-hit enemy got built. Over 15,966 resolves on the ADD_DIE arm: a
   Fang is in the pool for 19.7% of fights, **this face comes up on 2.31% of
   all resolves**, and it beats the `18` it replaced on **51.5%** of those —
   the `armour >= 4` crossover, measured rather than assumed. It is live: item
   8's pair pays on 0.70%, so this fires 3.3x more often. It is also too rare
   to matter: 0.46 damage per appearance times 2.31% is +0.011 damage per
   resolve, which is the whole explanation for a 0.1pp move.
   **Kept because it is a decision the player can read off the board, not
   because it makes the game better** — it does not, and the honest reason it
   survives is that half the time it is worse and you chose it anyway. Before
   anyone raises the 6 to make it count: a bigger pierce lands more often
   without arriving more often, and 19.7% of fights is the ceiling.
   > **These four rates were first measured against a blind combat loop and
   > called "the ADD_DIE arm".** The probe had neither `toggle_pick` nor
   > `resolve_rerolls`, so it rolled dice and took whatever came up while
   > filtering only the *rewards* by card — and the tell was in its own output:
   > the control reported 10.25% wins on "the ADD_DIE arm" against the
   > Baseline's 24.4% for that arm. Re-measured under the real policy (reroll
   > the worst die, as `_balance.gd`'s `_reroll` does), the control reads
   > 25.00% and the rates moved: the face arrives **more** often (2.31% not
   > 1.82%) and gains **less** per appearance (0.46 not 0.63), for the same
   > +0.011 per resolve. The verdict stands, and the label is now true. A rate
   > measured under one policy and attributed to another is the same error as
   > dividing by the wrong denominator — the arithmetic is fine and the basis
   > is not.
   **Do not** re-run item 5's version: it is measured, and the numbers are in
   the log.
8. **~~[x] Re-take item 6 (the paired face) on an acquired die.~~ KEEP
   2026-09-30.** `Face.pairs`; Fang's `5` pairs, so it doubles to 10 next to a
   matching die. random `15.9% -> 16.5%` (+0.6, allowance 3), depth `7.68 ->
   7.69` (floor 7.6), suite green. Neutral on difficulty, which is the result:
   the same face on a starter cost 3.3 points. Numbers in the Log.

## Log

Append one line per run. Newest last. `KEEP` means it shipped; `DROP` means it
was reverted.

- (baseline established, 9 shipped cards, random 12.0%, best/random 2.0x)
- 2026-09-29 item 1 per-face armour pierce — **DROP**. best/random `1.67x`
  (was 2.0x), random `22.7%` (band 8–18%), depth `8.85`. Failed 2 of 3; a
  piercing face on a starter die is a flat power add, not a decision. Reverted
  and re-measured — baseline reproduces to the digit on all ten rows.
- 2026-09-29 item 2 paired face (`Face.pairs`, Blade "5x2") — **DROP**. best/
  random `1.75x` (was 2.0x), random `15.3%` (+3.3, in band), depth `8.17`.
  In band and depth held, yet the ratio still narrowed. That is the second
  rules change to move the same way, so the gate was amended afterwards to
  stop asking `dice.gd` to widen a relative metric it cannot move. Reverted
  under the gate as it stood; see item 5 for why it is worth re-taking.
- 2026-09-29 **gate amended**, split by file: cards keep the full gate, rules
  are measured on the band and a 3-point delta. Adopted after both results
  above, not before, so it rescues neither.
- 2026-09-29 retire REFORGE — **DROP**. best/random `1.16x`, random `29.3%`,
  depth `8.22`. Removing the worst card in the table made a blind player
  nearly 2.5x more likely to win. The offer table is the difficulty dial, so
  every sub-random card is load-bearing and none of them should be retired.
  Reverted; baseline reproduces to the digit on all ten rows.
- 2026-09-29 item 1 downside card `TEMPER` ("every damage face +2, max health
  -12") — **DROP**, run four ways. As a 10th card: best/random `1.29x`, random
  `16.0%`, depth `7.85`. With the health cost removed as a control: `1.60x`,
  random `32.0%`, and the card itself at `51.3%`, the best in the table. Swapped
  against MEND to hold the table at 9: `1.63x`, random `16.7%`, depth `7.83`.
  All four below the `2.0x` gate. The card is sound — it is the sharpest trade
  measured, and the cost is worth 47 points of win rate — but a card table draws
  uniformly, so both terms of the ratio move with the lottery and this axis
  cannot be turned. Reverted; baseline reproduces to the digit on all ten rows.
- 2026-09-29 item 2 scaled MEND — **DROP** by `0.06x`. best/random `1.94x` (was
  `2.00x`), random `12.0%`, MEND `7.3%`, depth `7.97` — all three of the latter
  identical to baseline. The miss is one run in 150. Reverted on the principle
  that the gate must be trusted by the unattended loop even when a result is
  close; a gate loosened the moment it fails stops meaning anything.
- 2026-09-29 **music shipped** (`audio/menu.ogg`, `audio/combat.ogg`, 40s
  seamless loops via FlowMusic2API) plus a persistent mute button. Not a balance
  item; recorded because it changed the build size and the AAB contents, which
  every later measurement here is taken against.
- 2026-09-29 **sound effects shipped** — seven synthesised one-shots, 43 KB, via
  `_mksfx.py`. Not a balance item, same reason as the music: the AAB went from
  two audio streams to nine, and that is the surface every later measurement here
  is taken against. Worth one line beyond that: `hurt` fires only on damage that
  got *through* block, so what a turn's block was actually worth is now audible,
  which is the first time any of the arithmetic in this file has been checkable
  by ear rather than only by assertion.
- 2026-09-29 **Focus made fight-long, 1 charge** — Phase 0.1. Refilling the
  charge every turn made the button free, and the bench caught it: gambler
  `13.3%` depth `7.78` against nudger `50.7%` depth `8.93`, a 3.8x swing for a
  button that is never once wrong. The cause is Sunder's faces
  `[rust, 1, cleave, 1, rust, rend]` — bimodal, so "next strictly-better face"
  from a 1 is always a 12 or a 14, and a per-turn budget just cashes that in
  every turn. Swept the budget on the same 150 seeds (`7000+i`); the gambler
  column is identical at every setting, which is the control proving the seeds
  are held fixed:

  | charges / fight | gambler | nudger | ratio |
  |---|---|---|---|
  | 0 | 13.3% | 13.3% | 1.00x |
  | 1 | 13.3% | 20.7% | 1.56x |
  | 2 | 13.3% | 28.7% | 2.16x |
  | 3 | 13.3% | 36.0% | 2.71x |

  Shipped at **1**: the question stops being "which button this turn" and
  becomes "which of the next three or four turns is worth my one charge".
  Capping the step instead was tried and is a no-op — every die's faces are
  spaced further apart than any useful cap, so the cheapest face above the
  current one is also the first one above the target, and Sunder ends up
  unfocusable from every face worth caring about. The gap is a property of the
  dice, not of the rule.
- 2026-09-29 **Focus preview** — while the mode is armed, a focusable card
  shows the face it would become rather than the one it rolled, in gold with a
  3px border. Not a balance item, and not optional: the jump is invisible
  otherwise (Sunder's `1` becomes `cleave 12`, Blade's `7` only a `9`), so
  spending a charge you cannot see the result of is not a decision, it is a
  guess. The bench could only rank targets because `focus_gain` exposes the
  same number the card now shows.
- 2026-09-29 **Banking, and the bug that hid it** — Phase 0.2. One slot: hold
  a die, it resolves nothing this turn, keeps its face through the next roll,
  and pays out a turn later. The important measurement is the one that did
  *not* move: autoplay still clears the boss `6/40` runs, byte-identical to
  the pre-banking baseline. That is the dominance result. The greedy policy
  never banks, because block is zeroed every turn and a re-rolled face is
  free — so a hold is never once correct for a player who is not looking at
  the telegraph, which is exactly the population the Core Diagnosis in
  `PLAN.md` is aimed at. It is a lever, not a default.
  Worth recording because the first implementation passed its own tests while
  being **strictly a delete**. `resolve_faces` emptied the slot at the end of
  the turn the die was held, so the face was re-rolled on the very next roll
  it was supposed to survive, and the "keeps its face" assert passed only
  because seed `4242` happened to re-roll Ward onto the same face. The hold
  also logged "cashes from the bank" on a turn where nothing cashed. Fixed by
  paying the hold on the first resolve *after* a roll has skipped it
  (`bank_carried`), which is the only rule under which the mechanic is neither
  a no-op (pay immediately) nor a deletion (never pay). The test now carries a
  second unheld die as a control: if the unheld die did not move on the second
  roll, the held die's survival would be the seed agreeing with itself again.
  Same shape as the `bimodal faces` note above — the trap is an assert that
  cannot fail, not a rule that is hard to reason about.
- 2026-09-29 **Armed modes are mutually exclusive, and cannot outlive their
  resource** — UI, not balance, but the arithmetic is the reason it is here.
  Focus and Bank are both "spend something on one die", so two armed modes on
  one board is a state machine nobody holds at arm's length; arming either
  closes the other. Focus additionally disarms itself when the charge hits
  zero, because an armed Focus with nothing to spend is a mode that eats the
  next card tap — the same failure a mode leaking across a roll would cause.
  Bank does *not* disarm on an empty charge, since it costs nothing; an early
  draft disarmed both and would have made Bank unusable for the rest of a
  fight. Covered end to end in `shot.gd` rather than only in `dice.self_test`,
  because the rule being protected lives in the button row, not the rules
  layer.
- 2026-09-29 **Bench N raised 150 -> 1000** — every row above was taken at
  N=150, where the standard error on a 12% win rate is 2.65 points. That is
  wide enough that a 2-point difference is 0.75 se, i.e. indistinguishable from
  nothing, and Phase 0.3 was about to make claims on exactly that scale. N=1000
  puts se at ~1.0 points and the whole table costs 20s, so there was no reason
  to keep the cheap number. Prior entries are left at their original N rather
  than silently restated.
- 2026-09-29 **Ironhide, and a mirror of it cut** — Phase 0.3, the reactive
  half. `BEH_BRACE`: every hit below 6 on a die arms the enemy by 1, permanent,
  capped at `ARMOR_GROW_CAP` 12. Depth 4, which was a plain `BEH_NONE` Duelist,
  so the run gained an archetype without gaining a fight.

  The threshold is judged on the **face**, not on what survived armour. cleave 12
  reads as 12 on the card, so it counts as 12. A reactive rule the player has to
  hold in their head rather than read off the board is not a decision, it is a
  memorisation test, and the whole point is that the tag line
  ("braces off weak hits") plus the `Armour is now N` tell is enough to play
  around it.

  Measured, N=1000, same card picks throughout so the gap is the die policy and
  not the reward pool:

  | policy | wins% | avg depth |
  |---|---|---|
  | `<random>` (greedy, never reads the enemy) | 12.3% | 7.73 |
  | `dice:swing` (re-roll whatever BRACE would feed) | 11.2% | 7.68 |
  | `dice:chip` (throw away every heavy face) | 0.0% | 3.19 |
  | `dice:read` (greedy, plus the focus charge on a chip face) | **14.5%** | **7.98** |

  `read` is the load-bearing row and the only one above greedy. Depth `7.73 ->
  7.98` is roughly 5 se; wins `12.3% -> 14.5%` is about 2.1 se, which on its
  own would not carry a claim, so the depth number is what the conclusion rests
  on. And it is worth being clear what that effect is: `read` differs from
  greedy at **exactly one** of nine fights, so a single Ironhide is carrying a
  +0.25 average-depth shift across the whole run.

  **`BEH_GUARD`, the mirror, was built and cut.** Same shape reading the other
  way -- armour for every hit of 10 or more -- and the bench is what killed it.
  Its correct answer is "never take a big face", and the `chip` policy that
  plays that way scores 0.0%: nothing the player can press pushes a heavy face
  back down (focus only ever steps up) and banking only defers the armour a
  turn. A rule whose correct answer is to not play is an absence, not a
  decision, and `dice:both` -- the policy that read the threshold but not which
  side of it the enemy sat on -- also scored 0.0%, which is the same fact seen
  from the other side. The depth-6 slot went back to a harder Fungal Bloomer.

  Two measurement traps in this entry, both worth not repeating:

  - **`dice:chip` at 0.0% is not the number it looks like.** Its average depth
    is 3.19, so it dies at depth 3 -- Hexweaver -- not depth 4. It discards
    cleave 12 in *every* fight, so it is a self-destroying policy, and reading
    it as "Ironhide punishes chipping" is reading a coincidence as a result.
  - **`read` is a policy I designed, so its number is not neutral**, and the
    clause that does the work -- only spend the charge if the gain also carries
    the die clear of 6 -- was chosen with the rule in view. A focus that lifts a
    Blade 2 to a Blade 3 gains one damage and still arms the enemy, so dropping
    the clause would make `read` a worse policy, not a fairer one. The honest
    reading is the narrow one: *a* way of playing Ironhide measurably beats
    greedy. It is not proof that this particular way is optimal, and a bot tuned
    against the same table would find a better one. What it does rule out is
    the pessimistic reading -- that Ironhide has no answer at all and is just a
    stat block with extra words on the card.

## 2026-09-29 — Precision Strike, and how the status condition was nearly cut on a bug

Phase 0.3's other half: a sticky status. The plan named Vulnerable/Exposed and
Sundered/Bleed, and named the upgrade that applies Exposed (`Precision Strike`,
§1.1) but no card for Bleed. So only Exposed got built -- a status with no
source is dead code, and the substrate plus its one card is the smallest unit
that is not dead.

The first design made Exposed **bypass armour**, the plan's first suggestion.
The bench killed it, and not for the reason I expected:

| | wins% | avg depth |
|---|---|---|
| `<random>` | 7.3% | 7.27 |
| `PRECISE_STRIKE` (bypass) | 2.1% | 6.63 |

Worst card in a ten-card pool, 0.6 depth *below* taking nothing. The reason is
in the roster: every enemy carries 0-5 armour and Sunder's best face is 12, so
bypass was worth two to five damage a turn. The mechanic worked; the currency
it was denominated in barely exists in this game.

So I measured the plan's other suggestion -- **+50%** -- which scales with the
dice instead of the armour and is worth something against a Grunt with no
armour at all. And it produced **numbers identical to the byte**, across 1000
seeds, which is not a coincidence a rule change produces. It meant the card was
never firing: `Exposed` was being decremented in `roll_all`, and the roll is
what *starts* the next turn, so the window closed at 0 before the resolve that
was supposed to spend it. Every test in `_expose_tests` passed anyway, because
all of them checked the flag and none of them checked the enemy's health.

Fixed by moving the decrement to the end of `resolve_faces` -- spent by the
resolve that uses it, re-armed by the same resolve if that turn's hardest face
re-earned it. Then:

| | wins% | avg depth |
|---|---|---|
| `<random>` | 24.5% | 7.89 |
| `PRECISE_STRIKE` | 24.5% | 8.19 |
| `dice:reach` | 31.0% | 8.35 |

Every row roughly tripled, because until now they were all measuring a card
that paid nothing. `PRECISE_STRIKE` is tied with random on wins (se is 1.4
points, so that half says nothing) and **+0.30 depth** -- no longer a trap,
no longer the best thing in the pool.

**The lesson worth keeping:** an A/B between two designs that returns an
identical number is a broken experiment, not a result. It cost one bench run to
notice and would have cost the whole mechanic, because "+50% did not help
either" is exactly what the data said and exactly the wrong conclusion.

**What the card is.** `EXPOSE_AT` is 10, chosen so the threshold is a die line
rather than a number: Sunder (12, 14), Fang (11, 18) and Spark (15) clear it
out of the box and Blade tops out one short at 9. So the card pays off the
swingy half of the pool by itself, and stacking SHARPEN is what pulls the flat
half across -- a build path out of one 1-of-3 pick, not a flat bonus.

**Honest caveats.**

- `dice:reach` is a policy I designed, the same caveat as `read` above, and
  unlike `read` its result is nearly tautological: it re-rolls toward big
  damage on dice that can produce it, in a game about damage. It is evidence
  that the pool has exploitable structure, not that `reach` is a good player.
- The window is a *turn*, and I confirmed that by test rather than by reading:
  it survives the enemy's turn and the next roll, and is spent by the resolve.
- Two trap cards predate this work and are now measured rather than suspected:
  `FOCUS` at 12.0% and `REFORGE` at 10.3% against 24.5% random. Untouched
  here; they are a separate fix.

---

## 2026-09-30 — Phase 1.1/2.1: three cards, three measurements, three cuts

The three archetype cards (PRECISE_STRIKE, GAMBLERS_RUSH, BASTION_HOLD) were all
measured first under the `greedy` bot, and all three came out at the bottom of
the table. That reading was wrong, and the reason is structural rather than
statistical: `greedy` re-rolls the worst face and never presses Focus, never
banks, never gambles. Those are the *entire axes* of the cards being measured.
A card measured against a bot that never presses its button is a measurement of
the bot.

So each card got a paired row -- the card with a bot that plays its axis, and
the same bot on `<random>` cards. The delta is the card's edge, uncontaminated
by whether the bot is any good.

n = 1000 per row. Unpaired 95% band is ±2.3 points at these rates, so
"real" below means above about 3 points.

### The card table, greedy bot, 12-card pool

| card | wins% | vs `<random>` 15.9% |
|---|---|---|
| ADD_DIE | 23.3% | **+7.4** |
| PRECISE_STRIKE | 18.8% | **+2.9** |
| BULWARK | 18.3% | +2.4 |
| SHARPEN | 17.9% | +2.0 |
| VIGOR | 17.5% | +1.6 |
| BLESS | 17.1% | +1.2 |
| PIERCE | 14.8% | −1.1 |
| MEND | 12.3% | −3.6 |
| FOCUS | 8.8% | **−7.1** |
| REFORGE | 8.4% | **−7.5** |
| GAMBLERS_RUSH | 9.0% | **−6.9** |
| BASTION_HOLD | 7.0% | **−8.9** |
| `<random>` | 15.9% | — |

The bottom five are the story. Three are cards the player cannot use without
knowing they exist, and one is a currency problem, not a card problem.

### The die policies, same cards throughout

| policy | wins% | vs `<random>` |
|---|---|---|
| `dice:nudge` (spend every Focus charge) | 24.8% | **+8.9** |
| `dice:reach` (re-roll toward EXPOSE_AT) | 20.4% | +4.5 |
| `dice:read` (Focus only into a BRACE) | 18.1% | +2.2 |
| `dice:swing` | 12.8% | −3.1 |
| `dice:chip` | 0.1% | −15.8 |

**Focus is the strongest single mechanic in the game, and there is no card that
grants it.** That is DISCIPLINED_MIND's epitaph: it bought +2 Focus for −1
re-roll, and measured 7.8 points below its own control. My hypothesis was that
the price was wrong, and repricing to +2 Focus for −0.5 rerolls moved it 9.0%
→ 10.6% against an 18.4% control. The real cause is denomination, and no price
fixes it: re-rolls are per-turn and effectively unbounded, Focus is per-fight
and bounded, so the card taxes the plentiful currency to buy the scarce one.
**CUT.** `dice:nudge` above says the mechanic itself is fine; the card was not.

### The paired rows, and why the fix to the controls mattered

| pair | card + its bot | `<random>` + same bot | edge |
|---|---|---|---|
| GAMBLERS_RUSH | 16.3% | 21.9% | **−5.6** |
| BASTION_HOLD | 1.3% | 1.4% | −0.1 |

Both control bots were rebuilt first, because the first versions were bad
enough to hide the card behind them:

- `gamble` re-rolled anything short of a die's best face and scored 0.1%. I had
  read that as "a gamble card needs the bonus to break even". It was a bad
  control: it chased Sunder 9 → 12 and Blade 5 → 9, both +3, both paying 1, so
  it spent the whole budget re-rolling two-thirds of its hand. GAMBLERS_RUSH
  pays `gain / 2` floored at 1, so a swing has to clear 4 to beat the re-roll it
  replaces. With that threshold the policy is competent (21.9% on random cards)
  — **and the card is still 5.6 points worse.** The card is the problem, not the
  bot. **CUT.**
- `bank` held the best block face whenever the enemy telegraphed 6 or more, and
  scored 1.4%. It was holding 2-block faces against 6-damage hits, which is a
  turn of a die's damage traded for a fifth of what is coming. Requiring
  `atk >= 5 and block >= BASTION_BLOCK` barely moved it (1.3% vs 1.4%).

### The finding that is bigger than either card

**Banking is a losing line, and the two `bank` rows say it as loudly as 15.8
points can.** A bot that holds a die when the rules say to clears the boss
1.4% of runs. A bot that never holds clears it 15.9%. Phase 0.2's Die Banking
is an approved, shipped mechanic that is worth *less than nothing* to a player
using it correctly, because deferring a die costs a full turn of its damage and
enemy attacks of 3-9 rarely justify that. The one argument for it -- surviving a
telegraphed big hit -- is answered by taking the block this turn instead, which
is free.

This is a design call and it is not mine to make silently. Three ways out,
roughly in order of how much they cost:

1. **Make the hold cheap.** The held die re-rolled on the turn it was held
   rather than the next one, so banking costs a re-roll and not a face. One
   number, and it is the number `BASTION_HOLD` was already paying.
2. **Make the hold pay.** Hold pays block now *and* next turn, the way
   BASTION_HOLD was reaching for, so the deferral is worth something on its own.
3. **Cut it**, and hand the design back the damage face it was spending.

Option 1 is the smallest and the one I would measure first.

**Honest caveats.**

- `gamble`, `bank`, `reach` and `nudge` are policies I wrote. A cleverer bot
  raises the scores without making the game better; these are evidence that a
  mechanic is reachable and worth something to *something*, not that a player
  would find it.
- The `bank` deltas are measured on top of a policy that dies at depth 6. A
  card cannot be fairly judged there, which is most of why BASTION_HOLD's
  −0.1 says less than it looks like it says. GAMBLERS_RUSH's −5.6 is on a
  healthy 21.9% control and does carry.
- `dice:chip` at 0.1% is not a finding, it is the policy being nonsense: it
  discards cleave 12 in every fight. Kept in the table as a control for how bad
  a re-roll policy has to be to read as a signal.
- FOCUS (8.8%) and REFORGE (8.4%) are still traps and are not fixed by this
  work. They predate it.

---

## 2026-09-30 — A curse was quietly taking held dice back

Not balance. Found by `shot.gd` going red roughly one run in three, on an assert
that has been there since banking shipped: *"and the die kept its face"*.

`_curse_one` picks a die at random and drags it to its worst face. It did not
know about `banked`, so against any CURSE enemy a hold could be erased between
the tap and the resolve -- with the card still reading HELD and nothing on
screen saying so. The player gives up a turn of a die's damage to bank its
block, and the block is gone.

The assert caught it twice in six runs, both times the held die left on face 0,
which is what made it a rule and not a fixture. Fixed in `_curse_one`, which now
skips the held die and takes the next one along. One die is banned, so banning
one of two is still a curse.

The test that pins it down went green the first time it was written, and it was
worth nothing: it parked the held die on face 0, which *is* Ward's worst face, so
a curse landing on it changed nothing. Deleting the guard left the suite green.
It parks the die on its **best** face now, where a curse can never be, and the
guard is load-bearing -- red at seed 4 without it, green with it.

Two other flakes were the harness's own fault, and in both cases the assert was
right and the fixture was wrong:

- The damage pin took the *first* damage face on the first unheld die, which on
  an armoured roll is Blade's 2 and resolves to nothing. It now pins the
  strongest hit that survives the enemy's armour, read through the same
  `Enemy.pierce` the rules use.
- `had_block` was read off the faces *before* the pin while the chime comes from
  the *post*-pin resolve, so the two disagreed whenever the pin moved the only
  die that had block. It is read after the pin now, and skips the held die --
  which pays on the next resolve, not this one.

Ten consecutive runs, all nine screenshots, no asserts.
