extends SceneTree
## Throwaway balance probe: does the 1-of-3 upgrade choice matter?
## Plays the same bot N times per strategy. If "always take X" lands in the
## same band as "pick at random", the pick is decorative and the game has no
## decision in it.
##   godot --headless --path . -s _balance.gd

const RunState = preload("res://run.gd")
const Rules = preload("res://dice.gd")
const Check = preload("res://_check.gd")
const N := 1000
## Buckets for the per-depth survival line below. A run records the depth it
## stopped at, which is depth+1, and the boss bucket holds both wins and
## boss-deaths -- so slot FINAL_DEPTH+1 is "got to the last fight" and is not
## a win count. The wins% column is the honest one; this is the honest
## condition.
const SLOTS := RunState.FINAL_DEPTH + 2
## PLAN.md 1.2's second bullet -- "every card offered must support a distinct axis
## (Variance/Gamble vs. Focus/Certainty vs. Banking/Stalling)" -- has no code
## behind it. `roll_rewards` draws three cards uniformly at random, so whether
## those three span three different axes is left to chance, and this map is the
## only place that says which axis a card is on.
##
## It is a judgement call and worth arguing with: the plan names three axes and
## maps no card to them, so the five below are mine, drawn from what each card
## actually does. "Focus/Certainty" is the plan's own catch-all and it absorbs
## all nine non-variance, non-stalling cards, which is why the plan's three
## axes cannot be satisfied three times over and the measurement below is run
## on the five instead.
const AXIS := {
	"ADD_DIE": "pool",          ## grows the hand -- its own thing, neither of these
	"SHARPEN": "damage",         ## +1 to a damage face
	"PIERCE": "damage",          ## ignores 1 armour
	"REFORGE": "damage",        ## raises one die's worst face, at random
	"PRECISE_STRIKE": "damage",  ## a 10+ hit applies Exposed
	"BLESS": "defence",          ## +1 to a block face
	"VIGOR": "defence",          ## +8 max health
	"MEND": "defence",           ## heal 14
	"BULWARK": "defence",        ## reflect 4
	"FOCUS": "gamble",           ## +1 re-roll every turn
	"GAMBLERS_RUSH": "gamble",   ## a re-roll that lands higher pays extra
	"BASTION_HOLD": "stall",     ## holding a die pays block at once
}

# PLAN.md 1.2's second bullet, measured over the 8000 offers a run that clears
# all eight depths actually sees (the offer sequence depends only on the picks,
# not on the fights, so walking it is exact rather than an approximation):
#
#   49.0% of offers span three distinct axes, 51.0% carry a repeat,
#   and the repeats are damage 2378 / defence 1236 / gamble 462. Those three
#   sum to 4076 exactly, which is the check that the counter is honest: with
#   three cards an axis can repeat at most once and only one axis can, so the
#   three counts must add to the number of offending offers. They do -- and
#   `_axis_report` now checks that rather than leaving it to the reader, which
#   is what it used to be.
#
# Re-measured 2026-10-01. This said 45.8% / 54.2% over damage 2011 / defence
# 1971 / gamble 357, which was true until the two reward clamps landed -- both
# change which cards an offer is allowed to contain, so the histogram moves
# with them and defence fell 735 while damage rose 367. The run prints the
# histogram above its own table, so this paragraph is where to look rather
# than what to trust: the two disagreed silently for the whole time between
# the clamps and now.
#
# So the rule is a coin flip that nothing enforces: `roll_rewards` draws three
# uniformly at random and whether they span three axes is left to chance. It is
# also unsatisfiable as written. Under the plan's own three axes, "Variance/
# Gamble" holds FOCUS and GAMBLERS_RUSH, "Banking/Stalling" holds BASTION_HOLD,
# and "Focus/Certainty" absorbs the other nine -- a 2/1/9 partition, and since
# there is only one way to take all three, P(span) = 9*2*1 / C(12,3) = 8.2%. The
# plan's rule would then hold in one offer in twelve, where the five-way map
# above holds in nearly half, and that map is what makes the number mean
# anything rather than being a fact about an arbitrary grouping.
#
# Which is the argument for NOT enforcing it, and the reason is in the table
# above rather than in a preference. A repeated-axis offer is still a real
# choice, because cards on the same axis are not interchangeable. Reading the
# per-card wins% off the table (2026-10-01): the damage axis spans 9.3%
# (REFORGE) to 20.6% (PRECISE_STRIKE), an 11.3-point spread that is wider than
# the gap between most pairs of cards on different axes. Defence spans 4.1
# (VIGOR 17.7 to BULWARK 21.8) and gamble 1.2 (FOCUS 10.5 to GAMBLERS_RUSH
# 11.7). Forcing three distinct axes would delete exactly those choices -- in
# 51.0% of offers -- taking one containing PRECISE_STRIKE against REFORGE, a
# real 11-point decision, and handing back one with nothing in it.
#
# The argument is unaffected by the clamps; the numbers above them are not, and
# that is why the card-axis spreads are quoted here rather than asserted. The
# conclusion rests on damage staying much wider than the other two, and it is
# 11.3 against 4.1 and 1.2 -- the shape survived even though three of the five
# figures it was argued from did not.
#
# The rule worth having instead is a dominance rule: no card on offer may be
# strictly worse than another card on offer, so every card the player sees is
# takeable. That is BALANCE.md's "no dead-weight / strictly dominated" and it
# is the right shape for a draft. It cannot be checked from this table, and
# that is the honest limit of this measurement: wins% is a mean over runs, so
# it can rank cards but it can never show that one is *never* better than
# another. Strict dominance needs a paired per-fight comparison, which is what
# the forced-draw arms above are built for and what the ADD_DIE lottery was
# measured with. Not attempted here: it is a check, not a change, but it wants
# its own bench rather than a corner of this one.


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	# A row is [label, card-to-always-take, die policy]. The two axes were fused
	# into one `id` before the reactive enemies existed, which is why no policy
	# could be measured: "which card" and "which die" were the same knob.
	var rows: Array = []
	for u in RunState.UPGRADES:
		rows.append([str(u["id"]), str(u["id"]), "greedy"])
	rows.append(["<random>", "<random>", "greedy"])
	# The control for the two below: identical card picks, greedy dice. Any
	# movement from the `<random>` row is the reactive enemy talking, not the
	# card pool.
	for pol in ["swing", "chip", "read", "reach"]:
		rows.append(["dice:" + pol, "<random>", pol])
	# Phase 2.1's rows. Each archetype card is paired with a bot that actually
	# plays its axis, and with the same bot on `<random>` cards. The pairing is
	# the whole point: a build-defining card measured against a bot that never
	# presses its button is a measurement of the bot, not of the card. Every
	# archetype card measured under `greedy` scores near the bottom of the table,
	# and every one of them is worth more than nothing to a bot that uses it.
	for pair in [["GAMBLERS_RUSH", "gamble"], ["BASTION_HOLD", "bank"]]:
		rows.append([str(pair[0]) + "+" + str(pair[1]), str(pair[0]), str(pair[1])])
		rows.append(["<rand>+" + str(pair[1]), "<random>", str(pair[1])])
	# A third card was measured this way and cut: DISCIPLINED_MIND bought focus
	# with a re-roll and measured 7.8 points below its own control. `nudge` stays
	# on its own here anyway -- the die policy is the only way left to ask
	# whether Phase 0.1's Focus is worth anything now that no card pays for it.
	rows.append(["dice:nudge", "<random>", "nudge"])
	# SUNDER was built and cut here, so the number is kept rather than re-run.
	# It was PLAN.md 0.3's last unbuilt bullet: wounds, one per die that dealt
	# damage, capped at 5, bleeding for their count at the top of the enemy's
	# turn and losing one each time -- a status like Exposed, and it bypassed
	# armour like thorns. Measured under `greedy` at 12.7% wins and 7.68 depth,
	# against the `<random>` row's 15.6% and 7.76 *from the same run*, with
	# SUNDER still in the pool it was drawing from. Read the 15.6% as that row,
	# not as whatever it says today: with the card cut the pool is 12 again and
	# the same row now measures 16.5%, which is a different pool and not a
	# like-for-like control for anything. At 1000 runs the 2.9-point gap is
	# about 2.6 standard errors, so it is a real drop and not a sample.
	# Two reasons, and only the first is about the card:
	#   1. It is a rider, not a decision. Every die that lands wounds on its own,
	#      with nothing for the player to weigh, so it is a small damage upgrade
	#      competing for the same pick against SHARPEN, VIGOR and ADD_DIE -- and
	#      losing, because 5+4+3+2+1 is worth less than one turn of Sunder.
	#   2. The build it was written to serve does not exist. 0.3 asks for bleed
	#      that lets a slow defensive build win, and the `bank` policy -- the one
	#      that banks and turtles -- scores 1.4%. There is no slow build here for
	#      damage over time to reward, so the card has no target to be good for.
	# A version worth keeping needs the wound to be a choice: a die may spend its
	# damage opening a wound instead of dealing it, which is a per-die toggle in
	# fight.gd and a real feature rather than a rule. That is not a smaller patch
	# to this one, so it is not started here.
	# That version was built, since it is the only way to answer the objection
	# above, and it was cut too -- for a different reason, and it is the more
	# interesting of the two. A die spent opening a wound, the wound ignoring
	# armour, draining in Encounter.BLEED_TURNS instalments. 51 checks in
	# dice.gd, and it went in green.
	#
	# It measured at 30.2% wins and 8.86 depth against the `<random>` row's 16.5%
	# and 7.69, on the same cards and greedy dice. At 1000 runs that gap is about
	# 7 standard errors, and 8.86 is deeper than any card row in the table --
	# one extra button, nearly double the win rate.
	#
	# A damage audit was run before believing that, because 7 sigma from one
	# toggle is the shape of a free lunch rather than a good idea. It is not
	# free. 300 paired fights, same seed, sundering and not: the surplus is
	# zero against 0 and 1 armour and rises with it -- +3.3 at 2, +3.8 at 3,
	# +21.6 at 5. So a wound pays back exactly the face it was opened with, and
	# every point of the win-rate gap is the armour bypass. The mechanic does
	# what it was built to do.
	#
	# Which is the problem. It is break-even without armour and dominant with
	# it, and the roster carries armour on eight of its nine enemies -- all of
	# them but the Grunt, whose 0 is the only zero in the table -- with three of
	# those eight able to grow into the 12 cap: Rust Golem and Stone Sentinel by
	# BEH_ARMOR_GROW, Ironhide by BEH_BRACE, which shares the cap. So the answer
	# is "always sunder" nearly every turn of nearly every fight. This said
	# "seven of nine ... with two of them", which was wrong twice: it discounted
	# Bloodletter's armour of 1, which `pierce()` spends like any other, and it
	# counted only the two behaviours whose name grows. Both counts are pinned
	# by `run.gd`'s self_test now. Charging the sundered die its block was the
	# one cost tried, on the theory that a die spent on wounding is not bracing:
	# the bench came back at 31.2%, above the 30.2% it was meant to pull down. Not
	# because the cost is free -- because a policy ranking on both axes picks
	# better targets. (The damage-only policy could not see the cost at all: it
	# skips any die with no damage face, so it never once sundered a Ward and
	# returned 30.2% to the decimal after the rule changed. A policy that cannot
	# reach a rule is not measuring it.)
	#
	# So the cut is not "bleed is a bad idea" -- it is that a mechanic needs a
	# cost the player can feel, and no cost on the spending turn supplies one.
	# The cost has to live somewhere the die cannot reach: a wound the enemy can
	# close, or an armour that tears as it heals, or a bleed that pays the
	# enemy's attack instead of its health. Each of those is a new enemy
	# behaviour rather than a new die rule, which is also why this keeps landing
	# on Phase 0.3's third bullet and not somewhere Phase 3 can polish.
	#
	# The first of those three was then built and priced, because it is the only
	# one of the three the enemy can do on its own initiative, and a paragraph
	# listing three options is not a measurement. Sandbox in /tmp/woundbench
	# (never shipped): a per-die toggle opening a wound at full face value, the
	# wound ignoring armour, and the enemy closing up to `wound_close` of them
	# per turn -- healing for each -- before any wound pays. Close-before-pay,
	# or there is no cost: a wound that has paid cannot be healed back. The
	# control is a sunder toggle no policy ever presses, and it measures 16.5%
	# and 7.69 to the decimal against this table's `<random>` row above, so the
	# copy is faithful and every row below is a delta rather than a new baseline.
	# It is also identical at every close rate, which is the check that the
	# added rule consumes no randomness and leaks nothing between fights.
	#
	# The cost works, and knowing that is the new part. Closing the SMALLEST
	# wound is a smooth monotone dial, and it halves the free lunch:
	#
	#   close/turn    0.0    0.25   0.5    0.75   1.0    2.0
	#   wins%        39.2   36.8   27.9   19.9   13.9    0.1
	#   avg depth     8.90  8.88   8.78   8.69   8.50   2.67
	#
	# Closing the LARGEST is a cliff, and the reason is worth keeping: a rate
	# that matches the player's own opening rate makes the enemy unkillable.
	# 43.8% of fights run to the 50-turn cap at 1.0, 93.1% at 2.0, on 85.7 and
	# 119.2 wounds opened per fight, dealing 13.6 and 2.2 damage across the
	# whole fight. The run dies to the clock rather than to the hit, which is
	# a missing stalemate rule, not a cost that is working. A whole-number rate
	# can only miss the player's rate or match it, which is why the sweep has
	# to be fractional -- 0.5 closes one wound every other turn -- and the
	# smallest-target row above is that sweep.
	#
	# But it prices the wound as a constant rather than as a decision, and that
	# is the finding. `always` (sunder every die with damage on it) beats both
	# counter-policies at all nine paired settings. `burst2` (sunder only the
	# two biggest) is behind by 6.6 points at 0.0 and by 17.0 at 0.5. `armour`
	# -- sunder only faces that already beat the enemy's armour, the exact
	# policy the +21.6 audit above implies a player would read off the table --
	# is worse still: 27.2% against 39.2% uncosted, and 4.0% against 27.9% at
	# 0.5. Conditioning on the enemy is a LOSS, not a play.
	#
	# The reason is structural, and it is the part worth not rediscovering. The
	# cost is charged per wound and is identical for every wound, so the enemy's
	# rule can change how good sundering is but never when to do it. A decision
	# needs a cost that varies with WHICH die or WHEN; this one is the same
	# number every time, so the argmax is "sunder everything" everywhere along
	# the dial. There is no close rate that produces a choice, because there is
	# nothing for the player to choose between.
	#
	# Nor does the dial land the card in the table. The shipped cards run 7.7%
	# (BASTION_HOLD) to 24.5% (ADD_DIE) on wins%, and 0.75 closes the smallest
	# to 19.9% -- inside the band, between SHARPEN and ADD_DIE. Its depth is
	# 8.69, against 8.01 for the deepest card row here, so the win rate can be
	# dialled into the band and the depth never follows it down. Same shape as
	# the cut, from the other end: not a card this game already has.
	#
	# It also cannot ship into the current build. build/android/dicefate.aab is
	# signed, versionCode 5 is committed, and eight screenshots are shot against
	# a roster that a doubling mechanic would re-balance. That is an unrequested
	# balance change at the end of a release, not a bug fix.
	#
	# --- PLAN.md 2.2's other two items, measured with the per-depth line ---
	#
	# Paired faces are already shipped -- `Face.pairs` on Fang's `5`,
	# dice.gd:382, covered by `_pair_tests`. What had never been priced is the
	# flag, because ADD_DIE is a lottery: `apply_upgrade` draws one of the three
	# `Encounter.bonus_dice()` at random, so every ADD_DIE row above is the
	# average of three different dice and cannot say which one is carrying it.
	# Forcing the draw, 3000 runs a row, the same pick scan throughout:
	#
	#   riposte   32.3% wins   91.2 / 88.3 / 98.8 / 97.0   d=5..8
	#   fang      27.0%         92.0 / 94.3 / 97.7 / 94.0
	#   spark     16.5%         89.2 / 92.2 / 96.6 / 90.3
	#   (control, random draw: 25.3%)
	#
	# Two things fall out. The paired face PASSES: fang 27.0% against the same
	# die at 24.0% with the flag cleared, better at every depth from 5 to 8, and
	# firing 2.77 times a turn rather than never -- which is the gate item 6
	# failed and item 8 was moved to Fang to pass, now measured rather than
	# argued. The margin is about a point, so it earns its place and is not
	# worth building the pool around.
	#
	# The bigger one is that the lottery spans 15.8 points. ADD_DIE is the best
	# card in the table and it is not a card, it is a build: a player who draws
	# Spark is 15.8 points worse off than one who draws Riposte, with no
	# information and no choice. The block die wins over both damage dice, and
	# it wins at the boss (97.0 vs 94.0), which fits everything else measured
	# here: `bank` is the only policy that survives its own card, and the
	# BRACE/ARMOR_GROW roster punishes chip.
	#
	# Acquired-die armour pierce -- the third item -- was built and measured, and
	# should not be built. Same scan, rule on vs off:
	#
	#   adddie   25.3%  ->  pierce-on   33.6%   (+8.3)
	#   fang     27.0%  ->  fang-pierce  40.3%   (+13.3)
	#   riposte  32.3%  ->  riposte-pierce 32.4% (+0.1)
	#
	# It is a large buff to the strongest card in the pool, and it pays only on
	# the draw that was already good: Riposte has no damage faces, so it has no
	# armour to pierce and gains nothing. It also does not do what it looks
	# like it was proposed to do. If the point was to make an earned die matter
	# more, the spread between the best and worst draw goes from 5.3 points to
	# 7.9, because the good draw gains three times what the bad one does. The
	# variance is the thing worth fixing and this rule widens it.
	#
	# The lottery itself is not being fixed, and that is a decision rather than an
	# oversight. The lever is agency, not arithmetic: show the three bonus dice on
	# the ADD_DIE card and let the player choose one. That turns the best card in
	# the table from the average of three into a pick between 16.5% and 32.3%,
	# and the block die stops being a build the player happened to be handed and
	# becomes one they chose -- which is what PLAN.md's design principle actually
	# asks for, and the same axis the FOCUS clamp above sits on. Rebalancing the
	# three dice to narrow the spread is the arithmetic fix and it is the worse
	# one: it makes all three draws mediocre rather than one of them chosen.
	#
	# It is not made here because it is a card-pool change and
	# build/android/dicefate.aab is signed at versionCode 5 against the roster
	# these numbers were shot for. The owner chose to ship versionCode 5 as
	# signed and to take both this and the FOCUS clamp at the next build rather
	# than re-cut a release for them, so what is recorded here is the two levers
	# and their measured value, not a pending patch.
	#
	# Measured in a sandbox copy of run.gd/dice.gd with two probe-only hooks
	# (`forced_bonus`, `bonus_pierce`), which is why there are no arms for any
	# of this above: the hooks live in the rules layer and shipping them to
	# measure something decided not to ship is a change nobody asked for. The
	# control arm reproduced the random-draw row to the decimal, so the pairs
	# are tight.
	#
	# --- PLAN.md 0.3, the other half: "an enemy that counters on rolls > 10" --
	#
	# The last bullet of the section, and it was built and cut the same way
	# SUNDER was, for a reason that is a property of the dice rather than of the
	# rule. Nothing in the roster punishes a big single hit: ARMOR_GROW and
	# ENRAGE punish long fights, LIFESTEAL is a damage race, CURSE punishes
	# relying on one die, and BRACE punishes chip. So flat damage has no
	# counter-play anywhere in the game, and SHARPEN -- +1 to *every* damage
	# face, safe against all nine enemies -- measures 19.0%, second best.
	#
	# BEH_GUARD was written as the exact mirror of BRACE: +1 armour per face at
	# or above REACT_HIGH, sharing BRACE's cap and its off-diagonal inertness
	# (8 checks in a sandbox, each behaviour provably blind to the other's
	# trigger). Measured as a conversion of Ironhide 30/2/7 rather than a new
	# roster slot, so the depth ladder and the stats are untouched and one enum
	# field is the only difference. Predicted before running: `reach` chases
	# EXPOSE_AT and must fall, `swing` never shows a big face and must be flat,
	# SHARPEN must be the least hurt damage card. All three were wrong --
	# `reach` +1.6, `swing` +1.5, and SHARPEN +3.0, the single most helped row
	# in the table. Every row rose, `<random>` 16.5% -> 17.8%.
	#
	# The reason is the trigger rate, and it is the whole finding. Over 4000
	# rolls and 10660 damaging hits:
	#
	#   >=10 : 12.4% of hits    (2 of 24 faces in the pool can ever reach it)
	#   >=7  : 24.8%           (4 of 24)
	#   >=3  : 68.1%           (11 of 24)
	#   BRACE's own <6 fires on 69.4%
	#
	# The pool is bottom-heavy: Blade's best face is 9 and cannot clear 10 on
	# any roll, and Ward and Hex have no damaging face at all. Only Sunder
	# reaches the threshold, on 2 of its 6 faces. So GUARD fires 5.6x less
	# often than the BRACE it replaced, and converting Ironhide *deletes*
	# pressure instead of adding it -- which is the entire reason every row
	# rose. Sweeping the threshold confirms it is structural and not a tuning
	# miss: 10 -> 17.8%, 7 -> 16.9%, 5 -> 16.0%, 3 -> 15.8% against a 16.5%
	# control. The only threshold at which the rule bites is one that punishes
	# most hits, and that is not "counters on rolls > 10", it is BRACE again.
	#
	# So the bullet is unbuildable as written rather than badly balanced: no
	# threshold makes "punishes the big hit" *selective* in a pool whose faces
	# cluster low. A version worth keeping would have to read something other
	# than a single face -- a per-resolve total, or a per-die one that Sunder
	# can clear and Blade cannot -- which is a different mechanic, not a
	# threshold, and it would not be the mirror the plan asked for. Not
	# started here.
	#
	# The roster already knew. `run.gd` carries the note at the depth-6 slot: "a
	# reactive mirror of Ironhide was built here and cut, because its only
	# correct play was to stop taking big faces, which is an absence rather than
	# a decision." That cut was recorded as a design judgement and this is the
	# mechanical explanation of it -- the same verdict, reached by measurement
	# rather than by taste, and the reason it was reached. Both agree the bullet
	# does not ship. What the earlier note could not say is *why no threshold
	# would fix it*, and the 12.4% trigger rate is the answer to that.
	#
	# Measured in /tmp/guardbench, a fresh copy of dice.gd/run.gd/_check.gd with
	# BEH_GUARD and react_high added to the rules. Nothing was shipped: the
	# repo's dice.gd is byte-identical to the commit this was written against,
	# which `git show HEAD:dice.gd | diff - dice.gd` is the check for. The
	# first version of that sandbox's sanity check found a face by damage value
	# and returned -1 when the die had none, and GDScript's negative indexing
	# wrapped it to that die's *last* face -- so a Sunder that was supposed to
	# be small was silently rolled as 14 and the check passed anyway. It is
	# recorded here because a green sanity block is worth exactly nothing
	# unless it can fail, and this one could not.

	_axis_report()
	_plan_cards()

	print("strategy        wins%   avg depth   max")
	# Collected for the check at the bottom: the twelve single-card rows and
	# the control they are read against. Both share the `greedy` policy and
	# the same per-trial seeds, so the only thing that differs between a card
	# row and `<random>` is which card the bot prefers. The `dice:*` rows move
	# the die policy and the paired rows bundle a card with a bot that plays
	# it, so neither answers "is the pick decorative" and both are excluded.
	var single_card_avg: Array[float] = []
	var control_avg := 0.0
	var control_wins := 0.0
	var strategy: Array = []
	for row in rows:
		var id: String = row[1]
		var pol: String = row[2]
		var wins := 0
		var depth_sum := 0.0
		var depth_max := 0
		# How many runs stopped at each depth. resize() fills with null, which
		# is a Nil on the first increment, so the array is built by hand.
		var hist: Array = []
		for _i in SLOTS:
			hist.append(0)
		for i in N:
			var rng := RandomNumberGenerator.new()
			rng.seed = 7000 + i
			var r: RunState = RunState.new()
			var run_end := 0
			while true:
				var enc = r.start_fight()
				while not enc.over:
					enc.roll_all(rng)
					# Focus is spent before the re-rolls, and the two fight over
					# the same die: a focused die is spent, so a reroll request
					# on it would be refused. Against a BRACE the charge is
					# worth more than the roll, so the charge goes first.
					if pol == "read":
						_spend_focus(enc)
					elif pol == "nudge":
						_spend_all_focus(enc)
					if pol == "bank":
						_bank_one(enc)
					for j in enc.dice.size():
						if _reroll(enc, j, pol) and not enc.dice[j].spent:
							enc.toggle_pick(j)
					enc.resolve_rerolls(rng)
					enc.resolve_faces()
					if enc.over:
						break
					enc.take_turn(rng)
					if enc.turn > 50:
						break
				r.absorb(enc)
				var reached: int = r.depth + 1
				Check.check(reached <= RunState.FINAL_DEPTH + 1, "a run cannot pass depth 9")
				run_end = reached  ## how far this run got, counted once
				hist[mini(run_end, SLOTS - 1)] += 1
				if not enc.won:
					break
				if r.at_boss():
					wins += 1
					break
				r.depth += 1
				# The run loop's own bound, so the depth check above is a report
				# rather than the only thing standing between a stranded run and
				# a gate that says nothing. Disabling `at_boss()` to find out
				# what that check actually catches was the experiment: the gate
				# stopped completing -- 240s against a 60s baseline, seven lines
				# of output, not one failure -- because `at_boss()` is the only
				# thing limiting `depth`. The bound is `FINAL_DEPTH + 1` and not
				# `FINAL_DEPTH` deliberately: the check reads `r.depth + 1` at
				# the top of the next iteration, so breaking on the overshoot
				# itself skips the one iteration that reports it, and the first
				# version of this line did exactly that and passed green on a
				# build that could never win a fight. One extra pass lets the
				# check go red, and then the loop stops.
				if r.depth > RunState.FINAL_DEPTH + 1:
					break
				var offer = r.roll_rewards(rng)
				if offer.is_empty():
					continue
				# The strategy: take `id` if it is on offer, else the first offer.
				# The fallback is load-bearing, not a confound to correct. Mandating
				# `id` every offer instead was measured and is degenerate -- it
				# strips out the mixing that a real player does, and six of the
				# nine cards measure 0% wins when stacked. See BALANCE.md.
				var pick: Dictionary = offer[0]
				if id != "<random>":
					for o in offer:
						if str(o["id"]) == id:
							pick = o
							break
				r.apply_upgrade(str(pick["id"]), rng)
			depth_sum += run_end
			depth_max = maxi(depth_max, run_end)
		var avg: float = depth_sum / N
		var win_frac: float = float(wins) / N
		if pol == "greedy":
			if id == "<random>":
				control_avg = avg
				control_wins = win_frac
			else:
				single_card_avg.append(avg)
		elif str(row[0]).begins_with("dice:"):
			strategy.append([str(row[0]), win_frac, avg])
		print("%-14s %5.1f%%   %6.2f   %3d" % [row[0], 100.0 * wins / N, avg, depth_max])
		# Per-depth survival, conditioned on having reached that depth. This is
		# the column that can actually see a card, and the reason is the bind
		# between upgrades and depth: a run takes one card per depth cleared
		# and stops at the first death, so its upgrade count IS depth-1,
		# identically, for every run. A wins% gap between two rows is therefore
		# equally a depth gap, and a card that did not get you further reads as
		# a card that did no good. Conditioning on the depth both rows reached
		# holds the build size fixed and leaves only what the card did.
		#
		# Measured on the FOCUS row, which is the clearest case: at wins% it
		# read 8.9% against a 16.5% control and looked broken. Per-depth it is
		# level with the control until d=4 and then sits 5 points below at d=5
		# and d=6 -- the card is real, it is just not worth a pick twice.
		#
		# The re-roll itself is not the problem, and the number for that is
		# worth keeping because it is not recoverable from this table: an arm
		# taking offer[0] exactly as `<random>` does -- same picks, same dice,
		# same rng stream -- and handed a free +1 re-roll per pick reaches
		# 90.7/91.6 at d=5/d=6 against the control's 87.1/87.0. So a re-roll is
		# worth about +4 survival per pick. Forcing the budget to 1/2/3/4
		# instead shows it saturating after the first (d=2 reads 94.8/95.8/
		# 96.0/95.9), which is why the second copy is the worthless one: the
		# bench's control takes FOCUS 0.58 times a run and a player who is
		# told to prefer it takes it 1.62, and the extra ~1 pick is a near-
		# worthless +0.5 spent instead of an average card's ~+4.
		#
		# The fix is ADD_DIE's clamp -- refuse FOCUS once `upgrades` has it --
		# which recovers about two thirds of the gap (d=5 83.1 -> 85.2,
		# d=6 82.6 -> 86.8 against the control's 87.1/87.0). It is one line in
		# `roll_rewards` and it is NOT made here: it re-balances the reward
		# pool, and build/android/dicefate.aab is signed at versionCode 5
		# against the roster these numbers were shot for. Same shipping blocker
		# as the bleed cut below, and it is a card-pool change, not a bug fix.
		var line := ""
		for d in range(1, SLOTS - 1):
			if hist[d] > 0:
				line += "%5.1f%%" % (100.0 * hist[d + 1] / hist[d])
			else:
				line += "   --  "
		print("               %s" % line)
	print("a gap of a few points between the best and random row is the card's edge")
	print("compare `dice:*` against `<random>` -- same cards, so that gap is the")
	print("die policy reading the enemy and not the reward pool")
	print("the unlabelled row under each is survive(d) for d=1..%d. Read THAT"
		% (SLOTS - 2))
	print("line, not wins%: upgrades and depth are the same number here, so wins%")
	print("cannot separate a weak card from a build that simply went further")

	# The verdict, which the docstring at the top of this file has been asking
	# for since it was written: "if 'always take X' lands in the same band as
	# 'pick at random', the pick is decorative and the game has no decision in
	# it." Every run of this probe printed the table and answered nothing, and
	# the bare `quit()` below meant the exit code was 0 either way -- so as
	# gate 2 in PLAN.md this could not fail, and the `_check.gd` docstring's
	# whole argument about `assert()` applies to this file and was never
	# applied to it.
	#
	# The spread, not a level. A rebalance that moves every row together is
	# the rebalance that actually happens, and a threshold on an absolute
	# would turn red for it and teach everyone to ignore the gate. What would
	# turn this red is cards being interchangeable, which is the failure worth
	# catching. Measured: BULWARK 8.09 down to REFORGE 7.10, a spread of 0.99
	# against a floor of 0.5.
	var lo := INF
	var hi := -INF
	for a in single_card_avg:
		lo = minf(lo, a)
		hi = maxf(hi, a)
	print("_balance.gd: %d single-card rows span %.2f avg depth (%.2f to %.2f), control %.2f"
		% [single_card_avg.size(), hi - lo, lo, hi, control_avg])
	# The control is the instrument. Every comparison above is relative to it,
	# so a control that reads near zero means the bot is broken and the twelve
	# rows beside it are measuring nothing.
	Check.check(control_avg > 5.0,
		"the <random> control is a real run, not a broken bot (avg depth %.2f)"
		% control_avg)
	# The parenthesised concatenation is load-bearing: `a + b % x` binds `%` to
	# `b` alone, so the format specifiers have to be applied after the whole
	# message is built. Getting that wrong raised "not all arguments converted"
	# at runtime and the run still exited 0 -- a check that errors instead of
	# failing is the same defect as one that cannot fail, one level deeper.
	Check.check(hi - lo > 0.5,
		("the card pick is not decorative: the single-card rows span %.2f avg "
			+ "depth, and a spread at or under 0.5 means the cards are "
			+ "interchangeable") % (hi - lo))

	# PLAN.md 2.1 asked one question this file never answered: "does the gap
	# between tactical strategies and the random player widen significantly
	# beyond the baseline 2.0x?" There is no 2.0x, no ratio and no baseline
	# anywhere in the repo -- `grep -rn "2\.0x\|skill.to.random" *.gd` returns
	# only "512x512" -- so the phase recorded a target it never measured and
	# every run since has been silent about it. Measured now, and deliberately
	# NOT gated: the best policy lands well under the bar, so a hard check would
	# be red on every run and would teach the reader to ignore this gate
	# entirely. The ratio is printed on the way out instead, which is also why it
	# is not written down here. This paragraph used to say "dice:nudge at 1.55x"
	# and "whether 1.55x is the skill ceiling", and the run has printed 1.46x
	# since the two card clamps landed -- PLAN.md records that move (1.55x ->
	# 1.46x), so the file that prints the number was the one place still
	# asserting the old one. Whether the ratio a run reports is the skill ceiling
	# this design wants is the owner's call, not something to re-tune to fit a
	# sentence in a plan.
	var best := ["", 0.0, 0.0]
	for s in strategy:
		if s[1] > best[1]:
			best = s
	if control_wins > 0.0:
		print("_balance.gd: best policy %s is %.2fx the control's wins (%.1f%% vs %.1f%%), "
			% [best[0], best[1] / control_wins, 100.0 * best[1], 100.0 * control_wins]
			+ "and %.2fx its depth (%.2f vs %.2f). PLAN 2.1's bar is 2.0x."
			% [best[2] / control_avg, best[2], control_avg])

	# The other criterion this file states in prose and measures on every run
	# without ever saying so. `_reroll`'s docstring puts it plainly: "`read` is
	# the row that is meant to carry the weight... `read` above `<random>` and
	# the mechanic is real, `read` level with `<random>` and Ironhide is a stat
	# block with extra words." Nothing gated it -- `grep -n "Check.check" ` over
	# this file returned ten sites and none of them mentioned `read`, `<random>`
	# or wins, so the sentence deciding whether a shipped mechanic is real had
	# no more enforcement than the comment it lived in.
	#
	# Printed rather than gated, for the same reason the 2.0x ratio above is
	# printed rather than gated, and the reason is measured here rather than
	# assumed. Three seed bases, same code, nothing else changed:
	#
	#     7000   read 19.1%   random 18.0%    +1.1
	#     47000  read 22.5%   random 18.4%    +4.1
	#     91000  read 20.5%   random 18.1%    +2.4
	#
	# The sign holds on all three and the gap swings by four points, so the
	# bar is met and is not yet safely met. A floor at +1 point is red roughly
	# half the time for no reason -- the "permanently red, worse than none"
	# this registry's own comment warns about, and the mistake `shot.gd` avoided
	# by running nine times and *measuring* 766/767/767/766 before choosing a
	# lower bound instead of an exact one. A floor at +0.5 would clear all
	# three of today's samples and could go red on the fourth, which is worse
	# than not gating: the output would read as Ironhide having stopped working
	# when the real cause is which seeds the bench drew.
	#
	# The upgrade path is already half-built and is the only form of this
	# number a gate should ever be given. The arms are paired -- `rng.seed =
	# 7000 + i` is the same for every row -- so recording the per-trial win of
	# both arms turns "+1.1 points" into the count of trials where they
	# disagree, which is the signed error bar this lacks. Two independent
	# proportions cannot be compared at N=1000 and a gap this size.
	var read_wins := -1.0
	for s in strategy:
		if str(s[0]) == "dice:read":
			read_wins = s[1]
	# The print below is a measurement a comment above it calls decisive, so it
	# gets the same guard `_axis_report` got: a rename of the row label makes the
	# lookup miss, `read_wins` stays -1, and both prints are skipped with no
	# failure anywhere. That is exactly how the whole PLAN.md 1.2 report once
	# disappeared while the gate stayed green. One structural check, and it is
	# the only new one here -- the verdict's value stays a report.
	Check.check(read_wins >= 0.0,
		"the `dice:read` row is still in the strategy table under that label, so the Ironhide verdict below has something to report")
	if read_wins >= 0.0 and control_wins > 0.0:
		print("_balance.gd: dice:read vs `<random>` is %+.1f points (%.1f%% vs %.1f%%)"
			% [100.0 * (read_wins - control_wins), 100.0 * read_wins, 100.0 * control_wins])
		print("  that is this file's bar for Ironhide being a mechanic and not a stat block: MET. Not gated -- the gap moved +1.1 to +4.1 across three seed bases, so any floor here is a coin flip. Read it, do not gate it.")
	_gate_ratio()
	# The floor is the same one test.gd uses, and it is NOT the live count --
	# that was a bug, and the difference is the whole of this comment.
	#
	# `_axis_report` is called from here and a throw inside it aborts only that
	# function, so this quit() runs and the gate exits 0 with the entire PLAN.md
	# 1.2 report gone -- which is what happened until its AXIS lookups were made
	# total. That is what a floor is for, and it needs to catch it.
	#
	# The live count was 167694, and 167640 of that came from one check that
	# sits inside the run loop on purpose: `reached <= FINAL_DEPTH + 1` is
	# asserted once per *fight*, not once per run, because the bound comment
	# above explains that a per-run check skips the very iteration that reports
	# an overshoot -- the first version passed green on a build that could never
	# win a fight. Correct placement, and it makes the count a simulation
	# statistic: how many fights 22000 runs happen to play.
	#
	# Measured, by moving the seed base and changing nothing else:
	#
	#     7000 (shipped)  ->  167695 checks, floor met (seeded, so stable)
	#     47000           ->  167798
	#     91000           ->  167663
	#
	# The 91000 row once read "32 short, EXIT 1" -- against a floor calibrated
	# on the shipped row's own count. All three clear today's 22025 with room
	# to spare, which is the floor working: the count is a statistic about
	# seeds, not a count of checks that must run. A floor set on it is not a
	# floor; re-roll the seeds and the gate goes red having found nothing. And
	# it is *backwards*, because runs getting shorter is exactly what a balance
	# change looks like, while staying green through every abort it was written
	# to catch. A rebalance is not a broken gate, and the check at line 587 says
	# as much when it refuses to gate on an absolute depth for the same reason.
	#
	# So the floor is the count that is structural on every seed, and nothing
	# else: 20 from `_axis_report` and `_plan_cards` (12 axes, 1 histogram, 1
	# heading, 3 PLAN.md 1.1 bullets, 3 prose checks), 3 from the verdict checks
	# above, 2 from `_gate_ratio` on the two ways the doc states one ratio, and
	# 22000 from the trial loop -- `rows.size() * N`, held up from below by the
	# fact that `for i in N:` has no `break` in it and each run plays at least
	# one fight. 20 + 3 + 2 + 22000 = 22025.
	#
	# That is a real loss of sensitivity and it is not free: a `break` added to
	# the trial loop would shrink the bench without turning this red. It is
	# still the right trade, because the sensitivity it gives up protects a
	# quantity nothing should gate on, while the 20 it keeps are the checks
	# whose loss is silent -- a throw resumes the caller, so the count is the
	# only evidence.
	quit(Check.report("_balance.gd", 22025))


## PLAN.md 1.2's second bullet, measured: how often do the three cards on offer
## actually span three different axes?
##
## The offer sequence is walked directly rather than played. `roll_rewards` reads
## only `dice.size()` and `upgrades`, and a run takes one card per depth cleared
## and stops at the first death, so the sequence of offers a run sees is fixed
## by its picks alone -- there is no fight to simulate and nothing about the dice
## changes the draw. The pick policy is the control's, `offer[0]`, so the pool
## shrinks the same way the `<random>` row above shrinks it.
func _axis_report() -> void:
	# Every card in UPGRADES has a non-empty axis, checked *before* anything
	# below indexes AXIS. The order is not tidiness, it is the whole bug: in
	# GDScript `AXIS[missing]` throws, a throw inside a called function aborts
	# that function only, the caller carries straight on to
	# `quit(Check.report(...))`, and the gate exits 0. Deleting the
	# `"BASTION_HOLD"` line to prove it printed the whole strategy table, no
	# axis report at all, and a passing count of 167674 against a green 167687.
	# The measurement a PLAN.md claim rests on simply stopped existing and
	# nothing said so. A check sitting below the abort point never runs, so
	# this one has to sit above it.
	#
	# `.get(id, "")` + is_empty rather than `has()`: a key present with an
	# empty value is the same failure in different clothes, found by writing it
	# the `has()` way first and mutating `"BASTION_HOLD": "stall"` to `""`,
	# which sailed straight through.
	for u in RunState.UPGRADES:
		var axis_name := str(AXIS.get(str(u["id"]), ""))
		Check.check(not axis_name.is_empty(),
			"%s is mapped to a named axis -- an unmapped card deletes this entire report silently"
				% str(u["id"]))

	# ...and the two index sites below are `.get` too, for the same reason. The
	# check above says *which* card is unmapped; the measurement still has to
	# run to show where it landed. A throw here would take the report with it
	# all over again, which is exactly what it did before this was written.
	var unmapped := "<unmapped>"

	var offers := 0
	var clean := 0
	var dup_of := {}
	var seen_axis := {}
	for a in AXIS.values():
		seen_axis[a] = 0
	for u in RunState.UPGRADES:
		var pooled := str(AXIS.get(str(u["id"]), unmapped))
		seen_axis[pooled] = int(seen_axis.get(pooled, 0)) + 1
	for i in N:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7000 + i
		var r := RunState.new()
		for depth in RunState.FINAL_DEPTH:
			var offer: Array = r.roll_rewards(rng)
			if offer.is_empty():
				continue
			offers += 1
			var axes := {}
			for o in offer:
				var a := str(AXIS.get(str(o["id"]), unmapped))
				axes[a] = int(axes.get(a, 0)) + 1
			if axes.size() == offer.size():
				clean += 1
			for a in axes:
				if int(axes[a]) > 1:
					dup_of[a] = int(dup_of.get(a, 0)) + 1
			r.apply_upgrade(str(offer[0]["id"]), rng)
	print("PLAN.md 1.2 -- do the three offers span three axes?")
	print("  pool axes: %s" % seen_axis)
	print("  %d offers: %d span three distinct axes (%.1f%%), %d carry a repeat (%.1f%%)" % [
		offers, clean, 100.0 * clean / offers, offers - clean, 100.0 * (offers - clean) / offers])
	var parts := PackedStringArray()
	for a in dup_of:
		parts.append("%s %d" % [a, dup_of[a]])
	print("  repeats by axis: %s" % ", ".join(parts))

	# The second of the two things the header asserts in prose and nothing
	# checked; the first is the AXIS completeness loop at the top of this
	# function. Both were found by reading this function against its own
	# comment, and this is the one that had gone stale: the paragraph used to
	# claim the three counts "sum to 4339 exactly, which is the check that the
	# counter is honest", which is not a check at all -- it is a number a reader
	# is asked to verify by hand, and it stayed at 4339 through the reward
	# clamps that moved the total to 4076 without anyone noticing.
	#
	# The invariant is worth having for its own sake. With three cards an axis
	# can repeat at most once and only one axis can, so every offending offer
	# contributes exactly one to the histogram. That is what makes the histogram
	# mean "offers that repeated this axis" rather than "card slots that
	# repeated", and it is also the thing that breaks first if `roll_rewards`
	# ever stops offering three.
	#
	# Tested rather than reasoned, by widening the offer to four: the
	# `picks.size() < OFFER_COUNT` at run.gd:331 becomes `< 4` for the length of
	# a run and is put back afterwards, and the check reports "7189 histogram
	# hits, 6433 offending offers" and exits 1. Four cards can repeat twice in
	# one offer, so the counts sum past the number of offers -- which is the
	# failure this exists to catch, and the printout alone would still have
	# looked entirely plausible, which is why it needed a check rather than a
	# reader.
	#
	# Both halves of that sentence used to be wrong and neither was visible
	# from the comment: it cited run.gd line 268, which had drifted, and it
	# quoted `picks.size() < 4` as if that were the shipped line rather than the
	# mutation. A reader sent to 268 by a `< 4` quote lands on code that has
	# neither, and concludes the experiment was never run. That correction fixed
	# 268 but wrote 284, which had drifted the same way -- and 284 then sat in
	# PLAN.md's sweep table as the *corrected* value, so the wrong number was
	# ratified twice by fixing it once. It then went stale a third time while
	# this audit was running: the line read 312, and a `depth_no` helper added
	# nineteen lines higher up in the same file moved it to 331. Three failures,
	# one shape, and every one of them a hand correction. The fourth is not a
	# number either -- it is `test.gd`'s `_citations`, which fails a gate when a
	# citation stops matching its line, because a number somebody has to choose
	# to go and read is a number that will rot. The line is run.gd:331 and it is
	# named
	# here as `picks.size() < OFFER_COUNT`, because that is the code; `OFFER_COUNT
	# := 3` is the constant, and quoting the literal 3 restates it somewhere that
	# can drift again.
	var dup_total := 0
	for a in dup_of:
		dup_total += int(dup_of[a])
	Check.check(dup_total == offers - clean,
		"every repeated-axis offer lands in the histogram exactly once (%d histogram hits, %d offending offers)"
			% [dup_total, offers - clean])


## PLAN.md 1.1 names the cards Phase 1 promised. Three shipped and one was cut
## (`BALANCE.md:659`), and PLAN.md went on listing all four unstruck, so a
## reader of the plan could not tell which were real. Nothing compared the two
## documents, and this is the check that does.
##
## One direction only. `UPGRADES` carries twelve cards and 1.1 names three, by
## design -- it is the archetype shortlist, not the pool -- so "every card is
## named in the plan" is not true here and must not be asserted. What has to
## hold is that 1.1 does not present a card the game does not have.
##
## Struck bullets are how a cut card is written down, BALANCE.md's own
## convention, and `- ~~**Name**~~` does not begin `- **` so it is skipped here
## for free. That is also the only reason the strikethrough is spelled rather
## than left implicit: a dropped card left in the list is what this catches.
##
## The section is bounded by its own headings rather than the file scanned,
## because `- **Problem**:` and `- **Design**:` use the identical bullet form
## throughout Phase 0 and would all read as card names.
##
## ponytail: `found` only has to be non-zero. Hardcoding it to the number of
## bullets would catch a half-reformat that still leaves one parseable line --
## matching nothing at all is the failure worth catching, since then every
## per-card check silently stops running.
func _plan_cards() -> void:
	if not FileAccess.file_exists("res://PLAN.md"):
		return  ## not in the export, and _balance.gd is not either
	var f := FileAccess.open("res://PLAN.md", FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	var start := text.find("### 1.1")
	var stop := text.find("### 1.2")
	Check.check(start >= 0 and stop > start,
		"PLAN.md 1.1 is still findable by its own ### headings (got %d, %d)" % [start, stop])
	if start < 0 or stop <= start:
		return
	var names := {}
	for u in RunState.UPGRADES:
		names[str(u["name"])] = true
	var found := 0
	for line in text.substr(start, stop - start).split("\n"):
		if not line.begins_with("- **"):
			continue
		var close := line.find("**:")
		if close < 0:
			continue
		found += 1
		# "- **Name**: ..." -- the name starts after `- **`, i.e. index 4, and
		# runs to the `*` that `close` points at.
		var card := line.substr(4, close - 4)
		Check.check(names.has(card),
			"PLAN.md 1.1 presents \"%s\" as a card and it is not in UPGRADES -- struck it, or the pool lost it"
				% card)
	Check.check(found > 0,
		"PLAN.md 1.1 still lists its cards as `- **Name**: ...` bullets -- reformatting them would make every check above stop running without failing")

	# PLAN.md 0.3 names the reactive threshold, and it is the one number in that
	# section a retune can invalidate silently: `REACT_LOW` lives in `dice.gd`
	# and the sentence in the plan has no reason to move with it. Measured rather
	# than assumed -- 0.3 read "small hits < 4" for the whole of Phase 0 while
	# the shipped rule was `< 6`, and nothing would have said so.
	var rx := RegEx.new()
	rx.compile("small hits[^\\n]*?`<\\s*(\\d+)`")
	var m := rx.search(text)
	Check.check(m != null,
		"PLAN.md 0.3 still states the reactive threshold as `small hits ... `<N>`` -- reformatting that sentence makes the check below stop running")
	if m != null:
		Check.check(m.get_string(1).to_int() == Rules.Enemy.REACT_LOW,
			"PLAN.md 0.3's reactive threshold agrees with Enemy.REACT_LOW (%d)"
				% Rules.Enemy.REACT_LOW)


## Which die this policy wants re-rolled. Greedy is "re-roll the worst face",
## which never reads the enemy. `swing` re-rolls anything a BRACE would feed on
## and `chip` does the exact opposite -- throwing away every heavy face -- but
## both are re-roll-only policies, and BRACE's answer is not on the re-roll
## axis, so neither row can settle whether Ironhide forces a choice. `chip` in
## particular is confounded: it discards cleave 12 in every fight, so its 0.0%
## is mostly Hexweaver at depth 3 killing it, not Ironhide at depth 4.
##
## `read` is the row that is meant to carry the weight. It plays greedy and
## spends the focus charge only against a BRACE, on the chip face with the
## biggest gain -- Sunder's `1` into `cleave 12` is +11 and clears the
## threshold at the same time. If reading the enemy is worth anything, that is
## where it shows up: `read` above `<random>` and the mechanic is real, `read`
## level with `<random>` and Ironhide is a stat block with extra words.
func _reroll(enc, i: int, pol: String) -> bool:
	var d = enc.dice[i]
	match pol:
		"swing":
			return d.face().dmg > 0 and d.face().dmg < Rules.Enemy.REACT_LOW
		"chip":
			return d.face().dmg >= 12
		"reach":
			# Re-roll toward EXPOSE_AT, but only on a die that can actually get
			# there -- re-rolling Blade's 4 to try for a 10 is throwing the die
			# away, which is what `chip` does and why it scores nothing.
			return d.face().dmg < Rules.Encounter.EXPOSE_AT and _can_reach(d)
		"gamble":
			# Chases the *swing*, not the die's best face. The first version of this
			# policy re-rolled anything short of the best face, and it scored 0.1% --
			# which was read as "a gamble needs the bonus to break even" and was really
			# a bad control: it re-rolled Sunder's 9 to chase 12 and Blade's 5 to chase
			# 9, both of which gain 3 and pay 1, so it spent the whole budget on
			# two-thirds of its dice and paid for a turn of damage doing it. GAMBLERS_
			# RUSH pays `gain / 2` floored at 1, so a swing has to clear 4 to be worth
			# more than the re-roll it replaces. The threshold below is that arithmetic,
			# not a number found by running the bench until it went green.
			var best := 0
			for f in d.faces:
				best = maxi(best, f.worth())
			return best - d.face().worth() >= Rules.Encounter.RUSH_SHARE * 2
		_:
			return d.up == d.worst_index()


## The charge, spent the way the rules want it: on the die that gains most, and
## only if the gain also carries that die clear of the BRACE threshold. The
## second half is the point -- a focus that lifts a Blade 2 to a Blade 3 gains
## one damage and still arms the enemy, so it is worse than not spending.
## Can this die roll a face at or above EXPOSE_AT at all? Read off the die, so
## the policy and the rule cannot disagree about which dice qualify.
func _can_reach(d) -> bool:
	for f in d.faces:
		if f.dmg >= Rules.Encounter.EXPOSE_AT:
			return true
	return false


## The Focus bot, and the control for the card that was cut for not being worth
## one. Spends every charge the fight has, on the biggest gain available,
## unconditionally -- the same yardstick as `read` with the BRACE clause removed.
## It stays in the bench on its own because Focus is still a mechanic the player
## pays turns for, and this is the only row that presses the button.
func _spend_all_focus(enc) -> void:
	for _i in enc.focus_left:
		var best := -1
		var best_gain := 0
		for i in enc.dice.size():
			var gain: int = enc.focus_gain(i)
			if gain > best_gain:
				best_gain = gain
				best = i
		if best < 0:
			return
		enc.focus_die(best)


## BASTION_HOLD's bot, and the control that decides whether the card is worth
## measuring. Holds the best block face it can, but only on a hold that pays for
## itself twice over. The first version took the best block face whenever the
## enemy telegraphed 6 or more, and scored 1.3% against greedy's 9.2% -- it held
## 2-block faces against 6-damage hits, which is a turn of a die's damage traded
## for a fifth of what is coming. Two conditions now, both from the card's own
## numbers rather than from the bench: the telegraph has to be worth a die
## (`atk >= 5`, roughly the smallest hit that outcosts a die's turn) and the face
## has to be worth holding (`block >= BASTION_BLOCK`, the block the card pays on
## the tap -- below that the hold is a downgrade).
func _bank_one(enc) -> void:
	if enc.enemy.atk < 5:
		return  ## too soft to be worth a turn of that die
	var best := -1
	var best_block := 0
	for i in enc.dice.size():
		var f = enc.dice[i].face()
		if f.block > best_block and not enc.dice[i].spent:
			best_block = f.block
			best = i
	if best >= 0 and best_block >= Rules.Encounter.BASTION_BLOCK:
		enc.toggle_bank(best)


func _spend_focus(enc) -> void:
	if enc.enemy.behavior != Rules.Enemy.BEH_BRACE:
		return
	var best := -1
	var best_gain := 0
	for i in enc.dice.size():
		if not enc.can_focus(i):
			continue
		if enc.focus_face(i).dmg < Rules.Enemy.REACT_LOW:
			continue
		if enc.focus_gain(i) > best_gain:
			best_gain = enc.focus_gain(i)
			best = i
	if best >= 0:
		enc.focus_die(best)



## BALANCE.md states criterion 1 twice -- as a multiple of the control, and as a
## win rate -- and the two forms drifted apart without either being false. It
## read "1.49x widens** vs `<random>`" beside "beating 24.4% wins" in a section
## that also gave the control as 18.0%, and 1.49 x 18.0 is 26.8: the percentage
## form was failing the very criterion it is the percentage of, and nothing said
## so, because each form was separately defensible and both had been restamped
## from the same bench.
##
## All three numbers are read out of the document, and the control is one of them
## rather than this bench's live `control_wins`. That is the whole design, and it
## is not a detail: the first version multiplied the anchor by the live control
## and was green at the shipped seed base and red at 47000 and 91000 -- a gate
## that fails on a re-roll having found nothing, which is the exact thing the
## floor above refuses to be. Reading the control from the document also catches
## the failure this audit kept finding, the one where a restamp moves the input
## and leaves the sentences built on it: that is now a red gate rather than prose
## nobody rereads.
func _gate_ratio() -> void:
	if not FileAccess.file_exists("res://BALANCE.md"):
		return  ## not in the export, and _balance.gd is not either
	var f := FileAccess.open("res://BALANCE.md", FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	var anchor := RegEx.new()
	anchor.compile("widens\\*\\* vs `([0-9.]+)x`")
	var rate := RegEx.new()
	rate.compile("beating ([0-9.]+)% wins")
	var ctrl := RegEx.new()
	ctrl.compile("\\| random win% \\|[^|]*\\| \\*\\*([0-9.]+)%\\*\\*")
	var a := anchor.search(text)
	var p := rate.search(text)
	var c := ctrl.search(text)
	Check.check(a != null and p != null and c != null,
		"BALANCE.md states criterion 1 as a multiple, a win rate, and the control it is a percentage of (got %s, %s, %s) -- reformat any of them and the check below stops running without failing"
			% ["yes" if a != null else "no", "yes" if p != null else "no", "yes" if c != null else "no"])
	if a == null or p == null or c == null:
		return
	var want := a.get_string(1).to_float() * c.get_string(1).to_float()
	Check.check(absf(want - p.get_string(1).to_float()) < 0.05,
		"BALANCE.md's two forms of criterion 1 agree (%.2fx at %.1f%% random is %.1f%% wins, it says %.1f%%)"
			% [a.get_string(1).to_float(), c.get_string(1).to_float(), want, p.get_string(1).to_float()])
