class_name Dice
extends RefCounted
const Check = preload("res://_check.gd")

## Pure rules for the dice-faces game. No UI, no scene tree -- so the
## interesting parts (reroll budget, armour, enemy behaviours, run hooks) can
## be asserted headless with: godot --headless --path . -s test.gd
##
## Consumers preload() this file rather than leaning on the global class
## cache, which a headless run on a fresh checkout has not built yet. For the
## same reason nothing in here calls an outer-scope static: a nested
## class cannot resolve `Outer.helper()` unqualified, and self-reference by
## class_name needs the cache. Helpers therefore live on the class that owns
## the data -- armour is the enemy's, so pierce() is Enemy's method.
##
## An Encounter is built from an enemy and a dice pool passed in by the caller,
## so a run can hand the player whatever dice its upgrades have produced.

# One face of a die. A die has six; rolling picks which one is up.
class Face:
	var label: String
	var dmg: int
	var block: int
	var rerolls: int
	## Doubles while another die in the encounter is showing the same number.
	## Item 8, and the second attempt at item 6's mechanic. Item 6 put this on
	## Blade's `5` and failed the gate, but not because the idea was wrong --
	## because Blade is a *starter*, so +5 damage sat in every run from turn one
	## and the whole table just got stronger. On Fang the same face is only
	## reachable by a player who took ADD_DIE and rolled this die, and only pays
	## when a second die happens to match it, which is a thing to notice on the
	## board and hold onto rather than a stat to read off the card.
	##
	## Compares raw `dmg`, so two paired faces cannot chain into each other.
	var pairs: bool = false
	## Armour this face ignores, per hit. Item 7, and the retry of item 5.
	##
	## Item 5 put 12 on Sunder's `cleave` and 12 is `Enemy.ARMOR_GROW_CAP`, so
	## the face ignored every scrap of armour the game can produce -- and Sunder
	## is a *starter*, so it was that in every fight of every run. This is a
	## swap rather than a buff, and the cost is the point: Fang's `18` became a
	## `15` that pierces 6, which moves what the face deals by
	## `min(armour, 6) - 3` -- three less against an unarmoured enemy, two more
	## against the armoured third of the roster, and better still as ARMOR_GROW
	## carries a fight past 5. It is still not a flat power add: at the cap it
	## lands 9, so the invariant two constants up ("the swingiest faces always
	## still land something") survives.
	##
	## Deliberately not counted by `worth()` below. That ranking is used by
	## REFORGE and CURSE, neither of which has an enemy in hand to score
	## against, and armour is the only thing this field changes.
	##
	## Predicted before the bench ran, so the measurement can falsify it: a wash.
	## The face is scoped to a player who spent a pick on ADD_DIE and then rolled
	## this die, so it cannot be item 5's flat chip in every fight of every run,
	## and it is a swap rather than a buff, so it loses on the unarmoured third of
	## the roster. The `Enemy.pierce` note above is the prior running against it:
	## armour bypass has been measured in this pool once and scored as the worst
	## pick in it. Expect the band and the depth to hold and the wins not to move.
	##
	## Measured, and the prediction was right: `<random>` 16.5% -> 16.4%, depth
	## 7.69 -> 7.69, every row within 0.5pp and the signs mixed. The reason is
	## the rate, and it is the number to read before re-tuning the 6. Over 15,966
	## resolves on the ADD_DIE arm: a Fang is in the pool for 19.7% of fights,
	## this face comes up on **2.31% of all resolves**, and it beats the 18 it
	## replaced on **51.5%** of those -- the `armour >= 4` crossover above,
	## measured rather than assumed. It is live (item 8's pair pays on 0.70%,
	## so this fires 3.3x more often) and it is still too rare to move a run:
	## 0.46 damage per appearance times 2.31% is +0.011 damage per resolve. Keep
	## Both arms now play the real policy -- reroll the worst die, as
	## `_balance.gd`'s `_reroll` does. These were first measured blind, with no
	## `toggle_pick` and no `resolve_rerolls`, and the probe's own control said
	## so: 10.25% wins on the "ADD_DIE arm" against the Baseline's 24.4% for
	## that arm. Re-measured, the rate rose to 2.31% and the gain per fire fell
	## to 0.46, and the product is +0.011 either way -- so the verdict is
	## unchanged, but it now rests on the arm it names.
	## this in mind before raising the 6 to make it matter -- a bigger pierce
	## lands more often without arriving more often, and rate 1 is the ceiling.
	var pierce: int = 0

	func _init(l: String, d: int, b: int, r: int) -> void:
		label = l
		dmg = d
		block = b
		rerolls = r

	func is_junk() -> bool:
		return dmg == 0 and block == 0 and rerolls == 0

	## Rough desirability, used by REFORGE and CURSE to rank faces.
	func worth() -> int:
		return dmg + block + rerolls * 3


class Die:
	var title: String
	var faces: Array[Face]
	var up: int = 0
	var spent: bool = false  ## already re-rolled this turn
	## How much better a re-roll landed, in `Face.worth()`, and not yet paid out.
	## A number rather than a flag, because GAMBLERS_RUSH pays for the size of
	## the gamble: Sunder's `1` into `cleave 12` is worth 11 and Blade's 4 into 5
	## is worth 1, so the card pushes the player at the swingy die instead of at
	# any die at all. Cleared by `roll()`, so the opening roll of a turn can
	## never inherit yesterday's gamble.
	var rushed: int = 0

	func _init(t: String, f: Array[Face]) -> void:
		title = t
		faces = f

	func roll(rng: RandomNumberGenerator) -> void:
		up = rng.randi_range(0, faces.size() - 1)
		spent = false
		rushed = 0  ## set immediately after by resolve_rerolls, which has the old face

	func face() -> Face:
		return faces[up]

	## A fresh die for a new fight. The faces are shared on purpose -- upgrades
	## rewrite them in place on the run's pool -- but `up` and `spent` are
	## per-fight, and aliasing those wrote the last fight's state into the run.
	func copy() -> Die:
		return Die.new(title, faces)

	func worst() -> bool:
		return face().is_junk()

	## Index of the least useful face -- the target for CURSE and REFORGE.
	func worst_index() -> int:
		var worst_i := 0
		for i in faces.size():
			if faces[i].worth() < faces[worst_i].worth():
				worst_i = i
		return worst_i

	## Raise the weakest face by one step. Used by the REFORGE upgrade. `pairs`
	## rides along: this builds a new Face, and a flag that did not would mean
	## REFORGE on Fang's 5 quietly turned the mechanic off -- the one die in the
	## game that has the thing, un-set it by accident.
	func forge() -> void:
		var w := worst_index()
		var f := faces[w]
		faces[w] = Face.new(f.label, f.dmg + 1, f.block, f.rerolls)
		faces[w].pairs = f.pairs


class Enemy:
	# Behaviours, applied at the top of the enemy's turn (or on hit).
	const BEH_NONE := 0
	const BEH_ARMOR_GROW := 1  ## +1 armour each turn
	const BEH_LIFESTEAL := 2  ## heals for half the damage it deals
	const BEH_CURSE := 3  ## drags one of your dice to its worst face
	const BEH_ENRAGE := 4  ## +1 attack each turn
	const BEH_BRACE := 5   ## +1 armour per hit under 6 -- chip is punished
	## Ceiling for BEH_ARMOR_GROW and for BEH_BRACE. Uncapped, armour eventually
	## passes every die in the pool and the fight can only end by the player's
	## death, or not at all. 12 sits under Sunder's 14 and Fang's 18, so the
	## swingiest faces always still land something.
	const ARMOR_GROW_CAP := 12
	## What a BRACE reads a hit against. A face below this arms it. Judged on the
	## face value rather than on what survived armour, because that is the number
	## on the card -- a rule the player has to hold in their head rather than read
	## off the board is not a decision.
	const REACT_LOW := 6

	var title: String
	var hp: int
	var max_hp: int
	var armor: int
	var atk: int
	var behavior: int = BEH_NONE
	## Turns of armour-bypass left on it, granted by the PRECISE_STRIKE upgrade.
	## A status and not a behaviour: the tag line already carries the behaviour,
	## and this is a thing the player did to the enemy rather than a thing the
	## enemy does.
	var exposed: int = 0

	func _init(t: String, h: int, a: int, k: int, beh: int = BEH_NONE) -> void:
		title = t
		hp = h
		max_hp = h
		armor = a
		atk = k
		behavior = beh

	## Armour flattens each damage instance, but swingy dice beat it -- that
	## difference is why Sunder exists alongside Blade. `pierce_bonus` is the
	## run's PIERCE upgrade, which shaves armour off before this.
	##
	## Exposed deals half again as much. It does NOT ignore the armour, which is
	## the other half the design offered, and that swap is measured rather than
	## preferred: see the note in `Encounter.EXPOSE_AT`. Briefly -- every enemy
	## in the roster carries 0-5 armour and Sunder's best face is 12, so armour
	## bypass was worth two to five damage a turn, and the bench scored the card
	## as the worst pick in the pool. The multiplier scales with the dice
	## instead, so it is worth something on an enemy with no armour at all.
	func pierce(dmg: int, pierce_bonus: int = 0) -> int:
		if exposed > 0:
			return dmg * 3 / 2
		return maxi(0, dmg - maxi(0, armor - pierce_bonus))

	## Player-facing description of what this enemy does. Lives here so the UI
	## never has to own the vocabulary.
	func behavior_name() -> String:
		match behavior:
			BEH_ARMOR_GROW: return "hardens each turn"
			BEH_LIFESTEAL: return "drinks your blood"
			BEH_CURSE: return "curses a die"
			BEH_ENRAGE: return "rages each turn"
			BEH_BRACE: return "braces off weak hits"
			_: return ""


class Encounter:
	## A hit at least this hard leaves the enemy Exposed. Picked so the threshold
	## is a die line rather than a number: Sunder (12, 14), Fang (11, 18) and
	## Spark (15) clear it out of the box and Blade tops out one short at 9. So
	## the card pays off the swingy half of the pool on its own, and stacking
	## SHARPEN is what pulls the flat half across -- which is a build path out of
	## one 1-of-3 pick, rather than a flat bonus with a number on it.
	##
	## What Exposed is *worth* is the part that had to be measured, and the
	## answer is that it is not the armour. See `Enemy.pierce`.
	const EXPOSE_AT := 10

	var enemy: Enemy
	var dice: Array[Die] = []
	var picks: Array[bool] = []   ## which dice are queued for a re-roll
	var rerolls_left: int = 1
	## Focus charges for the WHOLE fight, not the turn. Refilling per turn made
	## the spend free: the bench measured gambler 13.3% -> nudger 50.7% wins,
	## because Sunder's faces are bimodal (junk 0-1, jackpots 12-14) so "next
	## better" from a 1 is always a 12. Two or three per fight makes the same
	## button a question about *when*, and stops it being an auto-play.
	var focus_left: int = 0
	## Index of the die held back this turn, or -1. It keeps its face through the
	## next roll and pays out on the next resolve, so the cost is a turn of delay
	## and the point is carrying a block to a bigger hit than this one -- which is
	## only a win against an enemy whose attack is rising. Against a falling one
	## it is strictly worse, and the intent readout is what tells the two apart.
	var banked: int = -1
	## True once the held die has survived a roll, and so on the resolve that pays
	## it. Without this the hold has to be either immediate -- so banking changes
	## nothing -- or never -- so it is a delete -- because the turn it was made
	## for is precisely the turn that has to skip it. `roll_all` is the only
	## thing that moves a held die's `up`, so the roll is what marks it carried.
	var bank_carried := false
	var hp: int = 20
	var max_hp: int = 20
	var block: int = 0
	var turn: int = 0
	var log_lines: Array[String] = []
	## How much armour ate on the last resolve_faces(): the gap between the
	## damage the faces were worth and what actually reached the enemy. Kept
	## here rather than recomputed in the UI, because "what the card said" and
	## "what armour took" are the same loop in resolve_faces() -- duplicating
	## it in fight.gd is how the two drift apart and the number lies. Reset at
	## the top of every resolve, so a stale value from the previous turn can
	## never be shown as this turn's.
	var last_deflected: int = 0
	var over: bool = false
	var won: bool = false
	## Copied from the run so a fight can resolve without knowing about it.
	var pierce: int = 0
	var thorns: int = 0
	var base_rerolls: int = 1
	var base_focus: int = 1  ## charges granted at the START of a fight, not each turn
	## Set by PRECISE_STRIKE. A bool rather than a number because the card is
	## all-or-nothing -- the threshold is `EXPOSE_AT` and there is nothing to
	## scale.
	var precision: bool = false
	## Set by BASTION_HOLD: banking a die pays block on the spot.
	var bastion: bool = false
	## Set by GAMBLERS_RUSH: a re-roll that lands higher adds half of what it
	## gained, ignoring armour.
	var rush: bool = false
	## Half, floored at 1. A flat bonus was measured first and is the reason this
	## is not one: a flat 3 paid out identically for Sunder's `1` to `cleave 12`
	## as for Blade's 4 to 5, which makes it a tax on rolling at all rather than
	## a reward for a swing. Scaling it means the card wants the die with the
	## widest gap, which is the decision the player is already making.
	const RUSH_SHARE := 2
	const RUSH_FLOOR := 1
	## BASTION_HOLD's block, paid on the tap. Four is roughly half a Ward 7, so
	## the card makes holding *cheaper* without making holding *free* -- a hold
	## costs a turn of that die's damage, and 4 block does not come close to
	## covering a Sunder cleave.
	const BASTION_BLOCK := 4


	# `d` is untyped so a run can hand over its pool (which grows with upgrades)
	# without caring about the nested-class type at the call site.
	func _init(e: Enemy, d: Array, run_hp: int = 20, run_max: int = 20) -> void:
		enemy = e
		hp = run_hp
		max_hp = run_max
		for die in d:
			dice.append(die.copy())
		picks.resize(dice.size())
		picks.fill(false)
		log_lines.append("A %s blocks your path." % enemy.title)

	# --- enemy factories (rules-level; the run's table composes from these) ---
	static func grunt() -> Enemy:
		return Enemy.new("Grunt", 22, 0, 3)

	static func warden() -> Enemy:
		return Enemy.new("Warden", 28, 4, 6)

	# The starting hand the player begins every run with.
	static func library() -> Array[Die]:
		var out: Array[Die] = []
		out.append(Die.new("Blade", [
			Face.new("2", 2, 0, 0), Face.new("3", 3, 0, 0), Face.new("4", 4, 0, 0),
			Face.new("5", 5, 0, 0), Face.new("7", 7, 0, 0), Face.new("9", 9, 0, 0),
		]))
		out.append(Die.new("Sunder", [
			Face.new("rust", 0, 0, 0), Face.new("1", 1, 0, 0), Face.new("cleave", 12, 0, 0),
			Face.new("1", 1, 0, 0), Face.new("rust", 0, 0, 0), Face.new("rend", 14, 0, 0),
		]))
		out.append(Die.new("Ward", [
			Face.new("2", 0, 2, 0), Face.new("3", 0, 3, 0), Face.new("4", 0, 4, 0),
			Face.new("5", 0, 5, 0), Face.new("7", 0, 7, 0), Face.new("9", 0, 9, 0),
		]))
		out.append(Die.new("Hex", [
			Face.new("1", 1, 0, 0), Face.new("2", 2, 0, 0), Face.new("3", 3, 0, 0),
			Face.new("4", 4, 0, 1), Face.new("5", 5, 0, 1), Face.new("6", 6, 0, 1),
		]))
		return out

	# Extra dice the ADD_DIE upgrade can grant -- swingier than the starters.
	static func bonus_dice() -> Array[Die]:
		var out: Array[Die] = []
		out.append(Die.new("Riposte", [
			Face.new("fend", 0, 0, 0), Face.new("2 blk", 0, 2, 0), Face.new("4 blk", 0, 4, 0),
			Face.new("7 blk", 0, 7, 0), Face.new("2 blk", 0, 2, 0), Face.new("11 blk", 0, 11, 0),
		]))
		out.append(Die.new("Spark", [
			Face.new("spark", 0, 0, 1), Face.new("spark", 0, 0, 1), Face.new("4", 4, 0, 0),
			Face.new("6", 6, 0, 0), Face.new("9", 9, 0, 0), Face.new("15", 15, 0, 0),
		]))
		out.append(Die.new("Fang", [
			Face.new("1", 1, 0, 0), Face.new("3", 3, 0, 0), Face.new("5", 5, 0, 0),
			Face.new("8", 8, 0, 0), Face.new("11", 11, 0, 0), Face.new("pierce 6", 15, 0, 0),
		]))
		# The `5` and only the `5`. It is the one face in the roster that lands
		# exactly on `EXPOSE_AT` when doubled, so a pair is a second route into
		# Exposed that does not run through SHARPEN -- the flat half of the pool,
		# for a player who spent a pick on this die. `11` would double to 22,
		# which is a flat power add with extra steps: 22 is over every armour in the
		# roster and over the boss.
		out[2].faces[2].pairs = true
		# And the `pierce 6`, the face item 7 re-sized. See `Face.pierce` for why
		# it is 15 and not 18, and for the `min(armour, 6) - 3` that decides it.
		out[2].faces[5].pierce = 6
		return out

	func _picked() -> int:
		return picks.count(true)

	## Extra damage die `i` deals this turn because its face pairs, and 0 for
	## every other die and every other face. `Face.pairs` only means anything in
	## the context of the whole hand, so the rule cannot live on the Face -- the
	## only class that can see the other dice is the one holding them.
	##
	## "Showing" is not "resolving": a held die is on the board with its face up,
	## and a spent one still pays this turn, so both count as partners. That is
	## deliberate, because it makes the hold something to think about rather than
	## a die that stops existing -- banking Fang's 5 next to Blade's 5 is a real
	## line, and the alternative (partners only resolve) is a rule the player has
	## to hold in their head instead of read off two cards.
	func pair_bonus(i: int) -> int:
		var f := dice[i].face()
		if not f.pairs or f.dmg <= 0:
			return 0
		for j in dice.size():
			if j != i and dice[j].face().dmg == f.dmg:
				return f.dmg
		return 0

	## What die `i` actually deals before the enemy's armour. One place, because
	## the number appears four times on the resolve -- the hit, PRECISE_STRIKE's
	## threshold and a BRACE's "was that a weak hit" test all have to agree about
	## it, and a paired Fang reads 10 on its card. If they disagreed, a face could
	## arm an enemy on a card that says it is a heavy hit.
	func face_hit(i: int) -> int:
		return dice[i].face().dmg + pair_bonus(i)

	func can_reroll() -> bool:
		return rerolls_left > 0 and _picked() > 0

	func toggle_pick(i: int) -> void:
		if over or dice[i].spent or i == banked:
			return
		picks[i] = not picks[i]

	## The face this die would move to if focused, or null if it cannot be. The
	## one place the rule lives -- the guards and the search are both here, so the
	## button, the preview and the spend cannot drift apart. A die already showing
	## its best face returns null, so a maxed die cannot eat the charge: that is a
	## real decision rather than a dead button.
	func focus_face(i: int) -> Face:
		if focus_left <= 0 or over or i < 0 or i >= dice.size() or dice[i].spent \
				or i == banked:
			return null
		var d := dice[i]
		var now := d.face().worth()
		var best: Face = null
		for f in d.faces:
			if f.worth() > now and (best == null or f.worth() < best.worth()):
				best = f
		return best

	func can_focus(i: int) -> bool:
		return focus_face(i) != null

	## Bank, or release a die already banked. One slot, and no `spent` flag: the
	## die is not used up, it is deferred, so it is neither re-rolled nor focused
	## while it waits. Release is a second tap on the same card rather than a
	## separate button, because a mis-tap here costs a whole turn.
	func toggle_bank(i: int) -> bool:
		if over or i < 0 or i >= dice.size() or dice[i].spent:
			return false
		if banked == i:
			banked = -1
			bank_carried = false
			log_lines.append("%s released." % dice[i].title)
			return true
		# Only one slot, so a second bank has to displace the first. Silently
		# refusing would read as a dead button, which is what the gold outline on
		# a maxed die already reads as -- one dead affordance is a mistake, two is
		# a design.
		if banked >= 0:
			log_lines.append("%s released." % dice[banked].title)
		banked = i
		bank_carried = false
		# BASTION_HOLD pays on the tap, not on the resolve. The hold itself is
		# what earns it, and the hold is a decision the player makes before they
		# can see what the turn resolves to.
		if bastion:
			block += BASTION_BLOCK
			log_lines.append("%s braces. +%d block." % [dice[i].title, BASTION_BLOCK])
		log_lines.append("%s held for next turn." % dice[i].title)
		return true

	## What a focus would gain on this die, or -1 if it cannot be focused. The
	## gap is wildly uneven -- Sunder's "1" jumps to a cleave for +11 while
	## Blade's "7" gains +2 -- which is why the card previews the face rather
	## than a number, and why the bot ranks its target on this too: comparing
	## the two policies needs the same yardstick the player reads.
	func focus_gain(i: int) -> int:
		var target := focus_face(i)
		if target == null:
			return -1
		return target.worth() - dice[i].face().worth()

	## Step a die to the cheapest face worth more than the one showing, and
	## nothing more.
	##
	## Deterministic on purpose. If Focus also rolled, both spends would be
	## gambles and the choice between them would collapse into "which do I like
	## less" -- the whole tension is gambling a re-roll against taking a certain
	## upgrade, so one of the two has to be certain.
	##
	## Ranked by worth() rather than by array index, because the faces are not
	## ladders. Sunder reads [rust, 1, cleave, 1, rust, rend]: one step along the
	## array from cleave(12) is a 1, so an index rule turns the flagship die's
	## best face into its worst. Worth() is also what REFORGE and CURSE already
	## rank by, so a face that is a good bet and a good focus are the same face.
	##
	## Bounding the step to "worth + N" was tried and is a no-op: every die's faces
	## are spaced further apart than any useful N, so the cheapest face above the
	## current one is also the first one above the target. The gap is a property
	## of the dice, not of the rule -- cap it and Sunder becomes unfocusable from
	## every face worth caring about.
	func focus_die(i: int) -> bool:
		var target := focus_face(i)
		if target == null:
			return false
		var d := dice[i]
		d.up = d.faces.find(target)
		d.spent = true  ## one action per die per turn, same rule as a re-roll
		focus_left -= 1
		log_lines.append("Focused %s to %s." % [d.title, d.face().label])
		return true

	func roll_all(rng: RandomNumberGenerator) -> void:
		rerolls_left = base_rerolls
		for i in dice.size():
			if i == banked:
				# Locked on its face, which is the point -- and the roll it
				# survived is the mark that this resolve is the one it pays on.
				bank_carried = true
				continue
			dice[i].roll(rng)
		picks.fill(false)
		var parts: Array[String] = []
		for d in dice:
			parts.append("%s:%s" % [d.title, d.face().label])
		log_lines.append("Rolled " + ", ".join(parts))

	# Spends one reroll per picked die. A die can only be re-rolled once per
	# turn -- that is the whole tension, so it is enforced here, not in the UI.
	func resolve_rerolls(rng: RandomNumberGenerator) -> void:
		var spent := 0
		var gained := 0
		for i in dice.size():
			if not picks[i] or dice[i].spent or i == banked:
				continue
			if spent >= rerolls_left:
				log_lines.append("No re-rolls left for %s." % dice[i].title)
				continue
			# The old face has to be read before the roll, not after: `rushed` is
			# the whole mechanic and there is no other copy of what it beat.
			var was := dice[i].face().worth()
			dice[i].roll(rng)
			dice[i].spent = true
			spent += 1
			var step := dice[i].face().worth() - was
			if step > 0:
				dice[i].rushed = step
				gained += 1
		rerolls_left -= spent
		picks.fill(false)
		if spent > 0:
			log_lines.append("Re-rolled %d." % spent)
		if gained > 0:
			log_lines.append("%d landed higher." % gained)

	func resolve_faces() -> void:
		var blk := 0
		var gained := 0
		var dealt := 0
		last_deflected = 0
		# Hits a BRACE would feed on. Counted off the face, not off what survived
		# armour: Blade 4 reads as 4 on the card, so it counts as 4.
		var low := 0
		# Hardest single face on this resolve, for PRECISE_STRIKE. Per die and not
		# off `dealt`, because the threshold has to be readable on one card -- five
		# faces of 4 that sum to 20 is not a hit of 10 to anyone holding them.
		var hardest := 0
		for i in dice.size():
			if i == banked:
				continue  ## held: it pays on the next resolve, not this one
			var f := dice[i].face()
			blk += f.block
			gained += f.rerolls
			# Armour applies per die, so one big hit beats two small ones.
			# `face_hit`, not `f.dmg`: a paired face reads its doubled number on
			# the card, and the resolve has to be the card's arithmetic.
			# `f.pierce` is the face's own, added to the run's PIERCE upgrade, so the
			# two stack without either of them being able to see the other. Reading
			# `pierce` alone would have made the face's field dead code on both
			# resolve paths while every test still passed on unarmoured enemies.
			var through := enemy.pierce(face_hit(i), pierce + f.pierce)
			dealt += through
			last_deflected += maxi(0, face_hit(i) - through)
			if dice[i].rushed > 0 and rush:
				dealt += maxi(RUSH_FLOOR, dice[i].rushed / RUSH_SHARE)
			hardest = maxi(hardest, face_hit(i))
			if face_hit(i) > 0 and face_hit(i) < Enemy.REACT_LOW:
				low += 1
		var cashed := ""
		if banked >= 0 and bank_carried:
			# The die kept its face through the roll that skipped it, and this is
			# the resolve that hold was made for. Cashing here and not at the end
			# of the hold is the whole mechanic: paying on the turn it was made
			# would make holding a no-op, and never paying would make it a delete.
			var hf := dice[banked].face()
			blk += hf.block
			gained += hf.rerolls
			var cashed_through := enemy.pierce(face_hit(banked), pierce + hf.pierce)
			dealt += cashed_through
			last_deflected += maxi(0, face_hit(banked) - cashed_through)
			hardest = maxi(hardest, face_hit(banked))
			if face_hit(banked) > 0 and face_hit(banked) < Enemy.REACT_LOW:
				low += 1
			cashed = dice[banked].title
			banked = -1
			bank_carried = false
		enemy.hp -= dealt
		block += blk
		rerolls_left += gained
		# A rush pays exactly once. `roll()` already clears the mark, so the turn
		# flow cannot double-pay it, but nothing stops a second resolve in the
		# same turn and `spent` is the precedent for not trusting that.
		for i in dice.size():
			dice[i].rushed = 0
		log_lines.append("You deal %d (armour %d). You gain %d block.%s" % [
			dealt, enemy.armor, blk, (" +%d re-roll" % gained) if gained else "",
		])
		# Exposed is spent here, by the resolve that uses it, and set again by the
		# same resolve if this turn's hardest face re-earned it. Decrementing it
		# anywhere earlier -- on the roll, or on the enemy's turn -- opened and
		# closed the window before any damage was ever paid through it, which is
		# the failure the bench caught: the card scored identically whether Exposed
		# bypassed armour or added half, because neither version ever fired.
		enemy.exposed = maxi(0, enemy.exposed - 1)
		# Set after the damage, so the hit that earned it lands at face value and
		# the next resolve is the one that collects. Set before it would make the
		# card pay for itself the turn it was taken.
		if precision and hardest >= EXPOSE_AT and not over:
			enemy.exposed = 1
			log_lines.append("%s is exposed -- it takes half again." % enemy.title)
		_react(low)
		if cashed != "":
			log_lines.append("%s cashes from the bank." % cashed)
		if enemy.hp <= 0:
			enemy.hp = 0
			over = true
			won = true
			log_lines.append("The %s falls." % enemy.title)

	func take_turn(rng: RandomNumberGenerator) -> void:
		turn += 1
		# Behaviours that ramp over the fight.
		match enemy.behavior:
			Enemy.BEH_ARMOR_GROW:
				enemy.armor = mini(enemy.armor + 1, Enemy.ARMOR_GROW_CAP)
				log_lines.append("%s hardens. Armour is now %d." % [enemy.title, enemy.armor])
			Enemy.BEH_ENRAGE:
				enemy.atk += 1
				log_lines.append("%s rages. Attack is now %d." % [enemy.title, enemy.atk])
		# Block is spent here, not banked -- a Ward that never drained made
		# every fight a formality.
		var soaked := mini(block, enemy.atk)
		var hit := enemy.atk - soaked
		hp -= hit
		block = 0
		if enemy.behavior == Enemy.BEH_LIFESTEAL and hit > 0:
			var healed := mini(enemy.max_hp - enemy.hp, hit / 2)
			enemy.hp += healed
			if healed > 0:
				log_lines.append("%s drinks %d of your blood." % [enemy.title, healed])
		if thorns > 0 and hit > 0:
			enemy.hp -= thorns
			log_lines.append("Thorns deal %d." % thorns)
			if enemy.hp <= 0:
				enemy.hp = 0
				over = true
				won = true
				log_lines.append("The %s dies to your thorns." % enemy.title)
				return
		log_lines.append("%s hits for %d (%d blocked)." % [enemy.title, hit, soaked])
		if enemy.behavior == Enemy.BEH_CURSE and not over:
			_curse_one(rng)
		if hp <= 0:
			hp = 0
			over = true
			won = false
			log_lines.append("You fall.")

	# Drags a random die down to its least useful face -- CURSE enemies.
	# Never the held one. `roll_all` skips the banked die precisely so its face
	# survives, and a curse that reached past that would break the hold with no
	# word on screen: the card still said HELD, the die had simply been moved
	# under it, and the block the player gave up a turn to bank was gone. Found
	# by shot.gd against a daily fight whose enemy is exactly this behaviour --
	# two runs in six, both times the curse landing on the held die and leaving
	# it on face 0. The hold is the one thing in a turn the player cannot
	# re-decide, so it is the one thing an enemy may not quietly take back.
	func _curse_one(rng: RandomNumberGenerator) -> void:
		if dice.size() <= 1:
			return
		var i := rng.randi_range(0, dice.size() - 1)
		if i == banked:
			i = (i + 1) % dice.size()  ## one die is banned, so one of two is enough
		var d: Die = dice[i]
		d.up = d.worst_index()
		log_lines.append("A curse settles on %s." % d.title)

	# The enemy answers to how it was hit, not just to being hit -- Phase 0.3's
	# reactive half. Per-die and permanent, so one bad turn matters for the rest
	# of the fight rather than being a rounding error on one turn.
	#
	# A mirror of this -- armour for every hit of 10+ -- was built here and cut.
	# The bench killed it: the only policy that beats it is "never take a big
	# face", and nothing the player can press pushes a heavy face back down --
	# focus only ever steps up, and banking only defers. A rule whose correct
	# answer is to not play is an absence, not a decision. See BALANCE.md.
	#
	# What BRACE is worth, measured. A policy that reads the enemy and spends
	# the focus charge on the chip face it can lift clear of the threshold --
	# Sunder's `1` into `cleave 12` -- goes from 7.73 to 7.98 average depth over
	# 1000 seeds, about 5 standard errors, and from 12.3% to 14.5% wins. It is
	# the only policy of the four the bench runs that beats greedy, and it beats
	# it by reading a *single* enemy in a nine-fight run, so the per-fight effect
	# is large.
	#
	# The re-roll-only rows cannot settle this and are kept only as the control:
	# `swing` re-rolls whatever the BRACE would feed on and lands *below* greedy,
	# and `chip`'s 0.0% is confounded -- it discards cleave 12 in every fight, so
	# it dies to Hexweaver at depth 3, not to Ironhide at depth 4. The answer is
	# on the focus and bank axes, not the re-roll axis. See BALANCE.md.
	func _react(low: int) -> void:
		if enemy.behavior != Enemy.BEH_BRACE or low <= 0:
			return
		log_lines.append("%s braces off %d weak %s." % [
			enemy.title, low, "hit" if low == 1 else "hits"])
		var was := enemy.armor
		enemy.armor = mini(enemy.armor + low, Enemy.ARMOR_GROW_CAP)
		if enemy.armor > was:
			log_lines.append("Armour is now %d." % enemy.armor)
		else:
			log_lines.append("Its armour is already at its limit.")

	func spent_count() -> int:
		var n := 0
		for d in dice:
			if d.spent:
				n += 1
		return n


static func self_test() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345

	for d in Encounter.library():
		Check.check(d.faces.size() == 6, "%s must have 6 faces" % d.title)

	for _i in 2000:
		for d in Encounter.library():
			d.roll(rng)
			Check.check(d.up >= 0 and d.up < 6, "roll landed out of range")

	# Armour never yields negative damage, and it rewards swingy dice.
	var w := Encounter.warden()
	Check.check(w.pierce(3) == 0, "armour absorbs a weak hit entirely")
	Check.check(w.pierce(9) == 5)
	Check.check(w.pierce(12) > w.pierce(4), "swing must beat flat under armour")
	Check.check(w.pierce(9, 2) == 7, "run pierce shaves the armour before it bites")

	# Die helpers: worst face and forging.
	var blade := Encounter.library()[0]
	Check.check(blade.worst_index() == 0, "Blade's worst face is its 2")
	blade.forge()
	Check.check(blade.faces[0].dmg == 3, "forge raises the weakest face by one")
	blade.forge()
	Check.check(blade.faces[0].dmg == 4, "forge keeps climbing the same face")

	var e := Encounter.new(Encounter.grunt(), Encounter.library())
	e.base_rerolls = 1
	Check.check(e.rerolls_left == 1)
	Check.check(e.can_reroll() == false, "nothing picked, no reroll")
	e.roll_all(rng)

	# Budget: two picks, one reroll -> only the first is honoured.
	e.toggle_pick(0)
	e.toggle_pick(1)
	Check.check(e.can_reroll())
	e.resolve_rerolls(rng)
	Check.check(e.rerolls_left == 0, "one reroll spent")
	Check.check(e.spent_count() == 1, "only one die should have been re-rolled")
	Check.check(e.can_reroll() == false, "budget exhausted")

	# A spent die cannot be queued and re-rolled again this turn.
	e.toggle_pick(0)
	e.toggle_pick(1)
	e.resolve_rerolls(rng)
	Check.check(e.spent_count() == 1, "no die may be re-rolled twice per turn")

	# Hex high faces grant re-rolls, so the budget can grow mid-turn.
	var before := e.rerolls_left
	e.dice[3].up = 5
	e.resolve_faces()
	Check.check(e.rerolls_left == before + 1, "Hex 6 should grant a re-roll")

	# Ward contributes block, not damage. A fresh Encounter has every die on
	# face 0, and the Grunt has no armour, so all three damaging faces land:
	# Blade 2 + Sunder rust 0 + Hex 1 = 3.
	var g := Encounter.new(Encounter.grunt(), Encounter.library())
	var hp_before := g.enemy.hp
	g.resolve_faces()
	Check.check(g.enemy.hp == hp_before - 3, "Blade 2 + Hex 1 = 3 on a Grunt")
	Check.check(g.block == 2, "Ward 2 should give 2 block and no damage")

	# Block is spent by the hit that absorbs it, never banked across turns.
	g.take_turn(rng)
	Check.check(g.block == 0, "block is consumed by the enemy's swing")
	Check.check(g.hp == 20 - 1, "Grunt atk 3 minus 2 block = 1 through")
	g.take_turn(rng)
	Check.check(g.hp == 20 - 1 - 3, "a later swing with no block lands in full")

	# Armour is per-die, so Sunder's big faces beat Blade against the Warden.
	var wd := Encounter.new(Encounter.warden(), Encounter.library())
	wd.dice[0].up = 0  # Blade 2
	wd.dice[1].up = 2  # Sunder cleave 12
	var hp2 := wd.enemy.hp
	wd.resolve_faces()
	Check.check(wd.enemy.hp == hp2 - 8, "12 - 4 armour = 8, Blade 2 fully absorbed")

	# --- behaviours ---
	# ARMOR_GROW raises armour each enemy turn.
	var ag := Encounter.new(Enemy.new("Golem", 30, 3, 4, Enemy.BEH_ARMOR_GROW), Encounter.library())
	var a0 := ag.enemy.armor
	ag.take_turn(rng)
	Check.check(ag.enemy.armor == a0 + 1, "armour grows every turn")

	# ENRAGE raises attack each enemy turn.
	var en := Encounter.new(Enemy.new("Rage", 30, 0, 4, Enemy.BEH_ENRAGE), Encounter.library())
	var k0 := en.enemy.atk
	en.take_turn(rng)
	Check.check(en.enemy.atk == k0 + 1, "attack rages every turn")

	# LIFESTEAL heals the enemy for half the damage it deals.
	var ls := Encounter.new(Enemy.new("Leech", 20, 0, 6, Enemy.BEH_LIFESTEAL), Encounter.library())
	ls.enemy.hp = 10
	ls.take_turn(rng)
	Check.check(ls.enemy.hp > 10, "lifesteal heals after it hits")

	# CURSE drags a die to its worst face.
	var cu := Encounter.new(Enemy.new("Hexer", 30, 0, 3, Enemy.BEH_CURSE), Encounter.library())
	cu.dice[0].up = 5  # Blade 9, the best face
	cu.take_turn(rng)
	var any_cursed := false
	for d in cu.dice:
		if d.up == d.worst_index():
			any_cursed = true
	Check.check(any_cursed, "curse drags at least one die to its worst face")

	# BRACE: the enemy arms itself on chip. Pool is Blade + Sunder throughout --
	# Blade's faces are 2/3/4/5/7/9 and Sunder's are rust/1/12/1/rust/14 -- so
	# "chip" and "burst" are nameable without inventing a die.
	# rust, cleave 12 -- one junk face, one heavy hit, and nothing between.
	var br := Encounter.new(Enemy.new("Iron", 60, 0, 4, Enemy.BEH_BRACE),
		[Encounter.library()[0], Encounter.library()[1]])
	br.dice[0].up = 2  # Blade 4
	br.dice[1].up = 0  # Sunder rust
	br.resolve_faces()
	Check.check(br.enemy.armor == 1, "a BRACE takes one armour for the one chip")
	br.enemy.armor = 0
	br.dice[0].up = 4  # Blade 7 -- a real hit, but neither chip nor heavy
	br.dice[1].up = 2  # Sunder cleave 12
	br.resolve_faces()
	Check.check(br.enemy.armor == 0, "and none at all for a heavy hit")
	br.dice[1].up = 1  # Sunder 1
	br.resolve_faces()
	Check.check(br.enemy.armor == 1, "rust is not a hit and does not count; 1 is")

	# The cap, or a chip-heavy pool walks the armour past every die it has.
	br.enemy.armor = Enemy.ARMOR_GROW_CAP
	br.resolve_faces()
	Check.check(br.enemy.armor == Enemy.ARMOR_GROW_CAP, "armour never passes the cap")

	# A BRACE is inert against an enemy that never reacts, so the rule cannot
	# quietly apply to everything.
	var nr := Encounter.new(Encounter.grunt(), [Encounter.library()[0]])
	nr.dice[0].up = 2  # Blade 4
	nr.resolve_faces()
	Check.check(nr.enemy.armor == 0, "a plain enemy takes no reactive armour")

	# A banked die that cashes is a hit that landed, so it feeds the reaction too
	# -- otherwise holding a die past a BRACE would be a free cheap hit.
	var rb := Encounter.new(Enemy.new("Iron", 60, 0, 4, Enemy.BEH_BRACE),
		[Encounter.library()[1]])
	rb.roll_all(rng)
	rb.dice[0].up = 2  # cleave 12
	Check.check(rb.toggle_bank(0), "held")
	rb.resolve_faces()  # the hold turn: no hit, so no reaction
	Check.check(rb.enemy.armor == 0, "a held die does not feed the reaction")
	rb.roll_all(rng)  # the roll that carries it
	rb.dice[0].up = 1  # 1, so the next resolve chips
	rb.resolve_faces()
	Check.check(rb.enemy.armor == 1, "but the turn it cashes on does")

	# THORNS damages the enemy that hits you.
	var th := Encounter.new(Encounter.grunt(), Encounter.library())
	th.thorns = 5
	var th_hp := th.enemy.hp
	th.take_turn(rng)
	Check.check(th.enemy.hp == th_hp - 5, "thorns reflect damage back")

	_focus_tests()

	# The pass/fail verdict is Check.report()'s exit code, not this line.
	print("dice.self_test: %d checks, %d failed"
		% [Check.checks, Check.failures.size()])


## Focus: step a die to the next strictly-better face. Split out so the budget
## starts clean, and so the Sunder case gets its own name -- it is the one the
## whole rule exists for.
static func _focus_tests() -> void:
	var lib := Encounter.library()
	var e := Encounter.new(Encounter.grunt(), lib)
	e.base_focus = 2
	e.focus_left = 2  ## hand-set: a run grants these, and this needs a second one
	e.roll_all(RandomNumberGenerator.new())
	# The whole point of the fight-long budget: rolling must not refill it.
	Check.check(e.focus_left == 2, "a roll does not refill the focus charges")

	# Sunder is the reason faces are ranked by worth and not by index. Its faces
	# are [rust, 1, cleave, 1, rust, rend]; one step along the array from cleave
	# is a 1. Under an index rule the flagship die's best face becomes its worst.
	var sunder := e.dice[1]
	sunder.up = 2  # cleave, 12
	var worth_before: int = sunder.face().worth()
	Check.check(e.focus_die(1))
	Check.check(sunder.face().worth() > worth_before, "focus never moves a face down")
	Check.check(sunder.face().label == "rend", "cleave focuses to rend, not to the 1 beside it")
	Check.check(sunder.spent, "a focused die is spent, like a re-rolled one")
	Check.check(e.focus_left == 1, "and one charge is gone")
	Check.check(not e.can_focus(1), "no charge left")
	Check.check(not e.focus_die(1), "a second focus is refused")

	# A die already on its best face cannot be focused, so it cannot eat the
	# charge. Fang's 18 and Blade's 9 are the cases a player will hit first.
	for pool in [lib, Encounter.bonus_dice()]:
		for die in pool:
			var f := Encounter.new(Encounter.grunt(), [die])
			f.base_focus = 1
			f.focus_left = 1
			f.roll_all(RandomNumberGenerator.new())
			var top := 0
			for j in die.faces.size():
				if die.faces[j].worth() > die.faces[top].worth():
					top = j
			f.dice[0].up = top
			Check.check(not f.can_focus(0), "%s on its best face has nowhere to focus" % die.title)
			Check.check(not f.focus_die(0), "%s stays put" % die.title)
			Check.check(f.dice[0].up == top, "%s is not consumed by a refused focus" % die.title)
			Check.check(f.focus_left == 1, "%s keeps the charge" % die.title)

	# Every die, every face: focusing must strictly increase worth, or land on a
	# die that is already maxed. That is the whole safety property.
	for pool in [lib, Encounter.bonus_dice()]:
		for die in pool:
			for j in die.faces.size():
				var g := Encounter.new(Encounter.grunt(), [die])
				g.base_focus = 1
				g.focus_left = 1
				g.roll_all(RandomNumberGenerator.new())
				g.dice[0].up = j
				var w: int = die.faces[j].worth()
				if g.focus_die(0):
					Check.check(die.faces[g.dice[0].up].worth() > w,
						"%s face %d focused up, not sideways" % [die.title, j])

	_bank_tests()
	_expose_tests()
	_rush_tests()
	_deflect_tests()
	_bastion_tests()
	_pair_tests()
	_pierce_tests()


## GAMBLERS_RUSH: a re-roll that lands on a strictly better face adds half of
## what it gained, ignoring armour. The property that is easy to get wrong and
## that a flag-only test would sail past: the bonus is measured against the face
## the re-roll *replaced*, so the opening roll can never earn it and a re-roll
## that lands equal or worse earns nothing. It is the size of the gain and not
## merely its existence, so Sunder's `1` into `cleave 12` is worth five and
## Blade's 4 into 5 is worth one.
static func _rush_tests() -> void:
	var lib := Encounter.library()

	# The false branch, deterministically: Blade 9 is its best face, so no re-roll
	# can beat it and the mark must stay zero whatever the RNG does.
	var top := Encounter.new(Encounter.warden(), [lib[0]])
	top.rush = true
	top.roll_all(RandomNumberGenerator.new())
	top.dice[0].up = 5  ## Blade 9, the maximum
	top.toggle_pick(0)
	top.resolve_rerolls(_seeded(11))
	Check.check(top.dice[0].rushed == 0, "a re-roll from Blade's best face earns nothing")

	# The scaling: the mark is the gain, not a flag. Sunder is 0,1,12,1,0,14, so
	# pinning face 1 and re-rolling to face 2 is a gain of 11 and face 5 is 13.
	var sc := Encounter.new(Encounter.warden(), [lib[1]])  ## Sunder
	sc.rush = true
	sc.roll_all(_seeded(5))
	sc.dice[0].up = 1  ## `1`
	sc.toggle_pick(0)
	sc.resolve_rerolls(_seeded(5))
	var step: int = sc.dice[0].face().worth() - 1
	Check.check(sc.dice[0].rushed == maxi(0, step), "the mark is the size of the gain, not a yes/no")

	# The true branch, as an invariant over many seeds: from Blade 2 the mark is
	# positive if and only if the new face is worth more. Asserted as the rule
	# rather than a fixed expectation, because the die owns the outcome.
	var better := 0
	for s in 40:
		var g := Encounter.new(Encounter.warden(), [lib[0]])
		g.rush = true
		g.roll_all(_seeded(s))
		g.dice[0].up = 0  ## Blade 2
		g.toggle_pick(0)
		g.resolve_rerolls(_seeded(s))
		var landed: int = g.dice[0].face().worth() - 2
		Check.check(g.dice[0].rushed == maxi(0, landed),
			"the mark is set exactly when the re-roll beat the face it replaced")
		if landed > 0:
			better += 1
	Check.check(better > 0, "and the better branch is actually reachable")

	# The money line: the same dice and faces, card off and card on. A Blade 2
	# into a warden's 4 armour deals nothing at all, which is what makes this the
	# clearest read on whether the bonus is being added after the armour.
	var off := Encounter.new(Encounter.warden(), [lib[0]])
	off.roll_all(_seeded(3))
	off.dice[0].up = 0
	var hp0: int = off.enemy.hp
	off.resolve_faces()
	Check.check(off.enemy.hp == hp0, "without the card, a Blade 2 into armour 4 deals nothing")

	var on := Encounter.new(Encounter.warden(), [lib[0]])
	on.rush = true
	on.roll_all(_seeded(3))
	on.dice[0].up = 0
	on.dice[0].rushed = 1  ## 2 -> 3, the smallest gain there is
	on.resolve_faces()
	var want: int = maxi(Encounter.RUSH_FLOOR, 1 / Encounter.RUSH_SHARE)
	Check.check(on.enemy.hp == hp0 - want,
		"and with it, the same face adds %d through the armour that swallowed it" % want)
	# The floor earns its keep: a gain of 1 halves to zero, and a bonus that can
	# round away to nothing is not a bonus.
	Check.check(want == Encounter.RUSH_FLOOR, "a one-point gain still pays the floor")
	Check.check(on.dice[0].rushed == 0, "the mark is paid out once and cleared")


## Armour eats faces, and the fight screen wants to say how much. This is the
## number behind the deflection callout, so it has to be per-die: armour
## applies face by face, so 2 and 3 into armour 4 are both swallowed whole,
## while 9 alone punches 5 through. Summing the faces first and subtracting
## once would report 1 absorbed where the truth is 5.
static func _deflect_tests() -> void:
	var e := Encounter.new(Encounter.warden(),
		[Encounter.library()[0], Encounter.library()[0]])  ## Blade, Blade
	e.dice[0].up = 0   ## "2"
	e.dice[1].up = 1   ## "3"
	var hp_before: int = e.enemy.hp
	e.resolve_faces()
	Check.check(e.enemy.hp == hp_before, "armour 4 swallows a 2 and a 3 whole")
	Check.check(e.last_deflected == 5,
		"and absorbs both, not their sum minus one armour hit (got %d)" % e.last_deflected)

	# A big face still gets through, and only the excess is deflection.
	var b := Encounter.new(Encounter.warden(), [Encounter.library()[0]])
	b.dice[0].up = 5   ## "9"
	b.resolve_faces()
	Check.check(b.enemy.hp == 28 - 5, "a 9 lands 5 through armour 4")
	Check.check(b.last_deflected == 4, "and only the 4 that armour ate is reported")

	# Reset per resolve. A stale value shown as this turn's absorb is worse
	# than showing nothing, so an unarmoured enemy must report a clean zero.
	var g := Encounter.new(Encounter.grunt(), [Encounter.library()[0]])
	g.dice[0].up = 5
	g.resolve_faces()
	Check.check(g.enemy.hp == 22 - 9, "an unarmoured enemy takes the face whole")
	Check.check(g.last_deflected == 0,
		"and reports no deflection rather than last turn's (got %d)" % g.last_deflected)

	# A resolve that hits nothing must still clear it.
	var q := Encounter.new(Encounter.warden(), [Encounter.library()[2]])  ## Ward
	q.resolve_faces()
	Check.check(q.last_deflected == 0, "a block-only resolve deflects nothing")


## A seeded RNG, so the tests that care about *what* was rolled can say so
## without depending on the global one.
static func _seeded(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


## BASTION_HOLD: holding a die pays block immediately, and only for the hold --
## a release, a displace and a rejected tap all leave the counter alone.
static func _bastion_tests() -> void:
	var lib := Encounter.library()
	var k := Encounter.new(Encounter.warden(), [lib[2], lib[0]])  ## Ward, then Blade
	k.bastion = true
	Check.check(k.toggle_bank(0), "the first hold lands")
	Check.check(k.block == Encounter.BASTION_BLOCK, "and pays %d block on the spot" % Encounter.BASTION_BLOCK)
	k.toggle_bank(0)
	Check.check(k.block == Encounter.BASTION_BLOCK, "releasing it does not pay again")
	Check.check(k.toggle_bank(1), "holding a second die displaces the first")
	Check.check(k.block == Encounter.BASTION_BLOCK * 2, "and pays for the new one")
	Check.check(not k.toggle_bank(9), "an out-of-range tap is refused outright")
	Check.check(k.block == Encounter.BASTION_BLOCK * 2, "and a refused tap pays nothing")

	var plain := Encounter.new(Encounter.warden(), [lib[2], lib[0]])
	plain.toggle_bank(0)
	Check.check(plain.block == 0, "without the card, banking is still just deferral")


## Exposed (PRECISE_STRIKE): a hit of EXPOSE_AT makes the next turn's hits worth
## half again, and no longer. The properties that matter, and each has a way to
## pass without the mechanic working: the threshold is a *single face* rather than
## the turn total; the window is opened by the resolve and closed by the
## following roll, so it is never spent on the enemy's turn; and it replaces the
## armour maths rather than compounding with PIERCE.
static func _expose_tests() -> void:
	# Sunder (index 1) is the die that clears the threshold: cleave 12 and rend 14.
	var lib := Encounter.library()
	var x := Encounter.new(Encounter.warden(), [lib[1], lib[0]])  ## Sunder, then Blade
	x.precision = true
	x.roll_all(RandomNumberGenerator.new())
	x.dice[0].up = 2  ## cleave 12
	x.dice[1].up = 5  ## Blade 9
	x.enemy.hp = 30
	x.resolve_faces()
	Check.check(x.enemy.exposed == 1, "a face of 12 exposes the enemy")
	var armour: int = x.enemy.armor
	x.take_turn(RandomNumberGenerator.new())
	x.roll_all(RandomNumberGenerator.new())
	# The window has to still be open here. It is closed by the resolve that
	# spends it, not by the roll or the enemy's turn -- and the version that got
	# it wrong passed every other line of this test while paying out nothing.
	Check.check(x.enemy.exposed == 1, "and the window survives the enemy's turn and the next roll")
	# ...and that it pays. This is the line the never-firing version passed: the
	# flag was set and cleared correctly the whole time, and no damage was ever
	# collected through it, so only the enemy's health tells the truth.
	x.roll_all(RandomNumberGenerator.new())
	x.dice[0].up = 2  ## cleave 12
	x.dice[1].up = 0  ## Blade 2, and a chip for BRACE to eat
	x.enemy.hp = 40  ## alive: an exposed 12 kills a 30hp grunt on its own
	var before: int = x.enemy.hp
	x.resolve_faces()
	# Every face that turn is worth half again, not just the one that earned it --
	# 12 -> 18 and 2 -> 3, so 21. Unexposed it would have been 8 + 0 against a
	# warden's 4. The chip gaining 3 is not a mistake: it is why the window is
	# never a downside, and why the card is worth a slot at all.
	Check.check(x.enemy.hp == before - 21,
		"a 12 and a 2 through armour %d land 21 while exposed, not %d" % [
			armour, maxi(0, 12 - armour) + maxi(0, 2 - armour)])

	# The window actually opened: an exposed hit is worth more than a flat one, and
	# an unexposed one is still flattened by the same armour.
	Check.check(x.enemy.armor == armour, "the armour never left -- only the hit got past it")
	var y := Encounter.new(Encounter.warden(), [lib[1]])
	y.roll_all(RandomNumberGenerator.new())
	y.dice[0].up = 2
	y.resolve_faces()
	Check.check(y.enemy.exposed == 0, "without the upgrade nothing exposes anything")
	y.precision = true
	y.roll_all(RandomNumberGenerator.new())
	y.dice[0].up = 2
	y.enemy.exposed = 0
	y.resolve_faces()
	var through: int = y.enemy.pierce(12, 0)
	Check.check(through == 18, "exposed, a 12 goes through as 18")
	y.enemy.exposed = 0
	Check.check(y.enemy.pierce(12, 0) == maxi(0, 12 - armour), "and is a flat 12 less armour once it lapses")
	# A stacked PIERCE must not apply on top of Exposed, or the card would read as
	# "+1 armour ignored" as well and the two would never be separable.
	y.enemy.exposed = 1
	Check.check(y.enemy.pierce(12, 5) == 18, "a stacked PIERCE does not apply on top of exposed")

	# The threshold is a single face, not the turn total: five faces under it that
	# add up to more must not count, or any wide pool would expose for free.
	var z := Encounter.new(Encounter.warden(), [lib[0], lib[0], lib[0], lib[0]])
	z.precision = true
	z.roll_all(RandomNumberGenerator.new())
	for i in z.dice.size():
		z.dice[i].up = 5  ## Blade 9
	z.resolve_faces()
	Check.check(z.enemy.exposed == 0, "36 damage in five faces is not a hit of 10")
	# Blade at its best is 9, one short -- which is the gap SHARPEN exists to close.
	Check.check(lib[0].faces[5].worth() < Encounter.EXPOSE_AT, "Blade alone cannot reach the threshold")


## A paired face doubles while another die shows the same number. Item 8.
## Three things are easy to get wrong and all three are checked here rather than
## assumed: that the bonus needs a *partner* (a lone 5 is still 5), that the
## partner is read off the whole hand including a held die, and that a pair pays
## once rather than compounding -- two Fang 5s cannot feed each other, because
## the rule compares raw `dmg` and a doubled face has no raw number to match.
static func _pair_tests() -> void:
	var fang: Die = Encounter.bonus_dice()[2]
	Check.check(fang.faces[2].pairs, "Fang's 5 is the paired face")
	Check.check(fang.faces[2].dmg == 5, "and it is the 5, not something else on the die")
	# Nothing else in the roster may carry the flag: a second one is a second flat
	# power add, which is the failure item 6 died of.
	var tagged := 0
	for d in Encounter.library():
		for f in d.faces:
			tagged += 1 if f.pairs else 0
	for d in Encounter.bonus_dice():
		for f in d.faces:
			tagged += 1 if f.pairs else 0
	Check.check(tagged == 1, "exactly one face in the whole roster pairs")

	# Alone: 5, not 10, and not one damage more.
	var solo := Encounter.new(Encounter.grunt(), [fang.copy()])
	solo.dice[0].up = 2
	Check.check(solo.pair_bonus(0) == 0, "a lone 5 has no partner, so it is not doubled")
	solo.enemy.hp = 30
	solo.resolve_faces()
	Check.check(solo.enemy.hp == 25, "and it deals 5 (seed-independent, faces are pinned)")

	# Paired: doubles, and the damage is real rather than a flag.
	var duo := Encounter.new(Encounter.grunt(), [fang.copy(), Encounter.library()[0]])
	duo.dice[0].up = 2  ## Fang 5
	duo.dice[1].up = 3  ## Blade 5, the only partner a starter can offer
	Check.check(duo.pair_bonus(0) == 5, "a matched 5 pays its own value again")
	Check.check(duo.face_hit(0) == 10, "so the die is worth 10 while the pair holds")
	Check.check(duo.pair_bonus(1) == 0, "the partner is not itself a paired face")
	Check.check(duo.face_hit(1) == 5, "and it deals its own 5, undoubled")
	duo.enemy.hp = 30
	duo.resolve_faces()
	Check.check(duo.enemy.hp == 15, "5 + 5 + the doubled 5 is 15 (flag-only tests miss this)")

	# The partner can be a *held* die. The hold is a decision about what is on
	# the board, and a die that is visibly sitting on 5 next to Fang's 5 is a
	# partner whether or not it resolves this turn.
	var held := Encounter.new(Encounter.grunt(), [fang.copy(), Encounter.library()[0]])
	held.dice[0].up = 2
	held.dice[1].up = 3
	Check.check(held.toggle_bank(1), "Blade can be held")
	Check.check(held.pair_bonus(0) == 5, "a held die still pairs -- it is on the board")

	# A second Fang 5 does not feed the first. Compared raw, so the doubling
	# cannot be earned twice off one hand.
	var two := Encounter.new(Encounter.grunt(), [fang.copy(), fang.copy()])
	two.dice[0].up = 2
	two.dice[1].up = 2
	Check.check(two.pair_bonus(0) == 5 and two.pair_bonus(1) == 5,
		"two matched 5s each pair, and neither doubles twice")

	# The reason the face is `5` and not `11`: doubled, it lands exactly on
	# EXPOSE_AT, so a pair is a route into Exposed that does not run through
	# SHARPEN. Asserted rather than asserted-about, because this is the whole
	# argument for the die and `hardest` has to be reading `face_hit` for it to
	# hold -- `hardest` reading `f.dmg` would leave the pairing invisible to
	# PRECISE_STRIKE and this test would be the only thing saying it worked.
	var pe := Encounter.new(Encounter.grunt(), [fang.copy(), Encounter.library()[0]])
	pe.precision = true
	pe.dice[0].up = 2  ## Fang 5
	pe.dice[1].up = 3  ## Blade 5
	pe.enemy.hp = 60
	pe.resolve_faces()
	assert(pe.enemy.exposed == 1, "a doubled 5 reaches EXPOSE_AT and exposes")

	# And it moves with the board: break the pair and the bonus is gone, so this
	# is a thing the player watches rather than a stat on the card.
	var breakable := Encounter.new(Encounter.grunt(), [fang.copy(), Encounter.library()[0]])
	breakable.dice[0].up = 2
	breakable.dice[1].up = 3
	Check.check(breakable.pair_bonus(0) > 0, "paired to start")
	breakable.dice[1].up = 4  ## Blade 7
	Check.check(breakable.pair_bonus(0) == 0, "and unpaired the moment the partner moves")


## A face that ignores armour. Item 7, the retry of item 5.
##
## Every check below runs the *resolve*, not `Enemy.pierce` alone, because the
## whole of item 5's failure is that the number it produced was correct and the
## place it was produced was wrong: a per-face field threaded nowhere reads as a
## flag that is set, and a test on the field alone would pass on a build where
## the resolve never consulted it. So each case pins a die and reads enemy hp.
static func _pierce_tests() -> void:
	var fang: Die = Encounter.bonus_dice()[2]
	var face: Face = fang.faces[5]
	Check.check(face.pierce == 6, "Fang's top face pierces 6")
	Check.check(face.dmg == 15, "and it is the 15, not the 18 it replaced")

	# The invariant `Face.pierce`'s comment claims. At the armour cap the pierced
	# face must still land something, or the game grows an unkillable fight that
	# only ends when the player dies -- which is what `ARMOR_GROW_CAP` exists to
	# prevent, and a piercing face is the most likely way to break it.
	var cap := Enemy.new("Cap", 40, Enemy.ARMOR_GROW_CAP, 0)
	Check.check(cap.pierce(15, 6) == 9, "it still lands 9 at the armour cap")
	Check.check(cap.pierce(15, 6) > 0, "so ARMOR_GROW cannot make the face inert")
	Check.check(face.pierce < Enemy.ARMOR_GROW_CAP,
		"and the pierce is under the cap, so it never fully bypasses (item 5's bug)")

	# The trade itself, which is the argument for the whole item: worse where
	# there is no armour, better where there is. Asserted as the resolve's own
	# arithmetic so a change to either number has to move one of these.
	var dealt := func(armour: int) -> int:
		var e := Encounter.new(Enemy.new("T", 40, armour, 0), [fang.copy()])
		e.dice[0].up = 5
		e.enemy.hp = 40
		e.resolve_faces()
		return 40 - e.enemy.hp
	Check.check(dealt.call(0) == 15, "unarmoured: 15, so three less than the 18 it replaced")
	Check.check(dealt.call(3) == 15, "armour 3 is the crossover, where the swap is exactly neutral")
	Check.check(dealt.call(5) == 15, "armour 5: still 15, two more than the old face landed")
	Check.check(dealt.call(5) == 18 - 5 + 2, "which is the +2 the min(armour, 6) - 3 predicts")

	# Stackable with the run's PIERCE and not shadowed by it. A run holding both
	# must not see one of them, and the two live on different objects on purpose.
	var stacked := Encounter.new(Enemy.new("T", 40, 8, 0), [fang.copy()])
	stacked.pierce = 3
	stacked.dice[0].up = 5
	stacked.enemy.hp = 40
	stacked.resolve_faces()
	Check.check(40 - stacked.enemy.hp == 15, "PIERCE 3 and the face's 6 stack: 8 - 9 clamps to none")
	var face_only := Encounter.new(Enemy.new("T", 40, 8, 0), [fang.copy()])
	face_only.dice[0].up = 5
	face_only.enemy.hp = 40
	face_only.resolve_faces()
	Check.check(40 - face_only.enemy.hp == 15 - (8 - 6),
		"without the run card the same face lands 13, so the stack is not a no-op")

	# The held-die path. Banking cashes through a second `enemy.pierce` call, and
	# a rule threaded onto the first site only is the exact half-implementation
	# this suite exists to catch.
	var banked := Encounter.new(Enemy.new("T", 40, 8, 0), [fang.copy()])
	banked.dice[0].up = 5
	Check.check(banked.toggle_bank(0), "the pierced die can be held")
	# `toggle_bank` leaves `bank_carried` false: the cash is owed to the *next*
	# roll, not this one. Set it so the resolve takes the cashing branch.
	banked.bank_carried = true
	banked.enemy.hp = 40
	banked.resolve_faces()
	Check.check(banked.banked == -1, "the hold was cashed")
	Check.check(40 - banked.enemy.hp == 13, "and the pierced face paid through the hold, not full 15")

	# Nothing else in the roster may carry the flag, for the reason item 6 died of.
	var tagged := 0
	for d in Encounter.library():
		for f in d.faces:
			tagged += 1 if f.pierce > 0 else 0
	for d in Encounter.bonus_dice():
		for f in d.faces:
			tagged += 1 if f.pierce > 0 else 0
	Check.check(tagged == 1, "exactly one face in the whole roster pierces")

	# A starter must not be able to reach it. Item 5's regression was precisely
	# that a starter carried the face, so it applied in every fight of every run.
	var starters := 0
	for d in Encounter.library():
		for f in d.faces:
			starters += 1 if f.pierce > 0 else 0
	Check.check(starters == 0, "and no starter die carries a piercing face")


## Banking: hold one die a turn. The property that makes it a hold rather than a
## delete is that the face survives the next roll, so the block is carried to a
## bigger hit rather than re-rolled away. The second die is the control: if it
## did not move on the second roll, the held die's survival would be the seed
## agreeing with itself rather than the hold working.
static func _bank_tests() -> void:
	var b := Encounter.new(Encounter.warden(),
		[Encounter.library()[2], Encounter.library()[0]])  ## Ward, then Blade
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	b.roll_all(rng)
	# Pin the face so the test is about the hold, not the dice.
	b.dice[0].up = 4  ## 7 block
	Check.check(b.toggle_bank(0), "a die can be held")
	Check.check(b.banked == 0, "and the slot takes it")

	var held_label: String = b.dice[0].face().label
	var held_worth: int = b.dice[0].face().worth()
	var free_worth: int = b.dice[1].face().worth()
	b.resolve_faces()
	Check.check(b.block == b.dice[1].face().block, "a held die resolves nothing this turn")
	Check.check(b.banked == 0, "and the slot keeps it -- paying now would make holding a no-op")

	# ...on the next turn, and only then.
	b.take_turn(rng)
	b.roll_all(rng)
	Check.check(b.dice[0].face().worth() == held_worth,
		"the held die kept its face through the next roll (%s)" % held_label)
	Check.check(b.dice[0].face().label == held_label, "same face, same word")
	Check.check(b.dice[1].face().worth() != free_worth,
		"while the unheld die was re-rolled, so the hold is what held it")
	b.resolve_faces()
	Check.check(b.banked == -1, "cashing empties the slot for the next hold")
	Check.check(b.block >= held_worth, "and the held die paid out in full a turn later")

	# A CURSE enemy must not reach past the hold. It picks a die at random and
	# drags it to its worst face, which silently breaks the one thing the player
	# cannot re-decide -- and does it with the card still reading HELD. Not one
	# unlucky roll: forty seeds, so the guard is proved against the picks that
	# would have landed on it, not against the ones that happen not to.
	var cu2 := Encounter.new(Enemy.new("Hexer", 30, 0, 3, Enemy.BEH_CURSE),
		Encounter.library())
	var cursed := 0
	for s in 40:
		var r2 := RandomNumberGenerator.new()
		r2.seed = 900 + s
		cu2.roll_all(r2)
		# Park the held die on its *best* face, not face 0. A first version of this
		# test parked it on 0, which is Ward's worst face -- so a curse landing on
		# it changed nothing and the test passed with the guard deleted. The best
		# face is the one a curse can never be, so any move at all is visible.
		var top := 0
		for j in cu2.dice[0].faces.size():
			if cu2.dice[0].faces[j].worth() > cu2.dice[0].faces[top].worth():
				top = j
		cu2.dice[0].up = top
		Check.check(cu2.toggle_bank(0), "a die can be held against a curse")
		var want: String = cu2.dice[0].face().label
		var before: Array = cu2.dice.map(func(d): return d.face().label)
		cu2._curse_one(r2)
		# Counted before the assert, so a guard that throws the curse at a
		# different die reads as a redirect rather than a vanished curse.
		if cu2.dice[1].face().label != before[1] or cu2.dice[2].face().label != before[2] \
				or cu2.dice[3].face().label != before[3]:
			cursed += 1
		Check.check(cu2.dice[0].face().label == want,
			"a curse cannot move a held die (seed %d)" % s)
		Check.check(cu2.banked == 0, "and the hold is still holding")
		Check.check(cu2.toggle_bank(0), "and it can still be released")
	Check.check(cursed > 20, "the curse still bites the rest of the hand, not just the hold")

	# A second tap releases, so a mis-tap does not cost the turn.
	var c := Encounter.new(Encounter.grunt(), Encounter.library())
	c.roll_all(RandomNumberGenerator.new())
	Check.check(c.toggle_bank(0))
	Check.check(c.toggle_bank(0), "tapping it again releases it")
	Check.check(c.banked == -1, "and the slot is free again")
	c.resolve_faces()
	Check.check(c.block > 0 or c.enemy.hp < c.enemy.max_hp, "a released die resolves normally")

	# The one-slot rule, and the two things a held die must not also be.
	var d := Encounter.new(Encounter.grunt(), Encounter.library())
	d.roll_all(RandomNumberGenerator.new())
	d.focus_left = 1
	Check.check(d.toggle_bank(0))
	Check.check(d.toggle_bank(1), "a second die displaces the first")
	Check.check(d.banked == 1, "the slot holds the newer die")
	Check.check(not d.can_focus(1), "a held die cannot also be focused")
	d.toggle_pick(1)
	Check.check(not d.picks[1], "a held die cannot also be queued for a re-roll")
	Check.check(not d.toggle_bank(9), "out of range is refused, not a crash")
