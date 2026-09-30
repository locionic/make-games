extends SceneTree
## Throwaway balance probe: does the 1-of-3 upgrade choice matter?
## Plays the same bot N times per strategy. If "always take X" lands in the
## same band as "pick at random", the pick is decorative and the game has no
## decision in it.
##   godot --headless --path . -s _balance.gd

const RunState = preload("res://run.gd")
const Rules = preload("res://dice.gd")
const N := 1000


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
	# it, and the roster carries armour on seven of nine enemies with two of
	# them growing into the 12 cap, so the answer is "always sunder" nearly every
	# turn of nearly every fight. Charging the sundered die its block was the one
	# cost tried, on the theory that a die spent on wounding is not bracing: the
	# bench came back at 31.2%, above the 30.2% it was meant to pull down. Not
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
	# It also cannot ship into the current build. build/android/dicefate.aab is
	# signed, versionCode 5 is committed, and eight screenshots are shot against
	# a roster that a doubling mechanic would re-balance. That is an unrequested
	# balance change at the end of a release, not a bug fix.

	print("strategy        wins%   avg depth   max")
	for row in rows:
		var id: String = row[1]
		var pol: String = row[2]
		var wins := 0
		var depth_sum := 0.0
		var depth_max := 0
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
				assert(reached <= RunState.FINAL_DEPTH + 1, "a run cannot pass depth 9")
				run_end = reached  ## how far this run got, counted once
				if not enc.won:
					break
				if r.at_boss():
					wins += 1
					break
				r.depth += 1
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
		print("%-14s %5.1f%%   %6.2f   %3d" % [row[0], 100.0 * wins / N, depth_sum / N, depth_max])
	print("a gap of a few points between the best and random row is the card's edge")
	print("compare `dice:*` against `<random>` -- same cards, so that gap is the")
	print("die policy reading the enemy and not the reward pool")
	quit()


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

