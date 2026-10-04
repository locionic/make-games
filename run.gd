class_name Run
extends RefCounted
## Pure run state: the player's deck and stats, the ascending enemy table, the
## upgrade pool, and best-run persistence. No UI, no scene tree -- so the whole
## run can be simulated headless. Rules that resolve a single fight live in
## dice.gd; this is the layer above it that a session spans.
##
## Consumers preload() this file for the same reason dice.gd says so: a headless
## run on a fresh checkout has not built the global class cache.

const Rules = preload("res://dice.gd")
const Check = preload("res://_check.gd")

## Where the player's run history lives. A static var, not a const, so the
## headless suite can point it at a scratch file: `self_test` calls `record_run`,
## and Godot 4.7 has no `--user-data-dir`, so without this every test run
## inflated the real lifetime run/win counters.
static var SAVE_PATH := "user://run.json"
const FINAL_DEPTH := 8  ## fights at depth 0..7, the boss at FINAL_DEPTH


## The depth as the player reads it: one-based, clamped to the run's length.
##
## `FINAL_DEPTH` is an index and every sentence about it is a number, and the two
## kept drifting apart. The fight HUD said "depth 9 of 9", the death screen's
## own summary said "You reached depth 9 of 9", and the line two below it said
## "The Devourer waits at depth 8" -- the same fight, two numbers, on one
## screen, because five of the six sites added one and the sixth did not. Every
## display goes through here now, so the off-by-one has one definition to live
## in and `self_test` has one value to pin.
static func depth_no(d: int) -> int:
	return clampi(d + 1, 1, FINAL_DEPTH + 1)
const MAX_DICE := 6
const POOL_SIZE := 4  ## dice in hand at the start of a run
# These two are constants now because the store copy quotes both, and
# `shot.gd`'s `_check_copy_claims` derives its rows from the constants that own
# the behaviour. "one of three upgrades" and "your first three finished runs"
# were hand-typed against bare `3`s, so moving either count left that row green
# over a sentence that had quietly become false -- the one thing the gate's own
# comment says it prevents. The unlock cap was a literal in two places and the
# offer count in two more, none of them named.
const OFFER_COUNT := 3  ## upgrades offered between fights
const UNLOCK_CAP := 3  ## finished runs before the title picker widens

var dice: Array = []  ## Array[Rules.Die] -- the pool the player fights with
var hp: int = 20
var max_hp: int = 20
var base_rerolls: int = 1
var base_focus: int = 1  ## focus charges granted per FIGHT
var pierce: int = 0
var thorns: int = 0
var precision: bool = false  ## PRECISE_STRIKE: a hit of EXPOSE_AT exposes the enemy
var bastion: bool = false    ## BASTION_HOLD: holding a die pays block on the tap
var rush: bool = false       ## GAMBLERS_RUSH: a better re-roll adds half its gain
var depth: int = 0
var upgrades: Array[String] = []
var won: bool = false
var seed: int = 0  ## 0 for a normal run, otherwise the day's seed
var order: Array = []  ## daily only: which enemy waits at each depth


func _init(seed_value: int = 0) -> void:
	seed = seed_value
	if seed != 0:
		# A daily is the same run for everyone, so the enemy order is fixed up
		# front from the day's seed rather than left ascending.
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		order = range(FINAL_DEPTH)
		_shuffle(order, rng)
	set_loadout(saved_loadout())


## The UTC day number -- shared worldwide, so the daily does not roll over for
## someone mid-session and every result for that day is comparable.
static func today() -> int:
	return int(Time.get_unix_time_from_system() / 86400.0)


func is_daily() -> bool:
	return seed != 0


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp


## Every die the player has earned: the four starters, plus one bonus die per
## finished run. Owning one is the reason to start the next run.
static func owned_dice() -> Array:
	var out: Array = Rules.Encounter.library()
	var left: int = mini(int(load_stats().get("unlocked", 0)), UNLOCK_CAP)
	for b in Rules.Encounter.bonus_dice():
		if left <= 0:
			break
		left -= 1
		out.append(b)
	return out


## Rebuild the pool from a list of titles. Titles the player does not own are
## skipped and the hand is trimmed to POOL_SIZE, then topped back up to it --
## so no save, stale or oversized, can start a run with the wrong number of
## dice. Past POOL_SIZE the only way to grow is ADD_DIE, up to MAX_DICE.
func set_loadout(titles: Array) -> void:
	dice.clear()
	var owned := owned_dice()
	for t in titles:
		if dice.size() >= POOL_SIZE:
			break
		for d in owned:
			if d.title == str(t):
				dice.append(d)
				break
	for d in owned:
		if dice.size() >= POOL_SIZE:
			break
		if not dice.has(d):
			dice.append(d)


## The hand to start from: whatever the player last chose, else the first
## POOL_SIZE dice they own.
func saved_loadout() -> Array:
	var saved: Array = load_stats().get("loadout", [])
	return saved if not saved.is_empty() else owned_titles()


static func owned_titles() -> Array:
	var out: Array = []
	for d in owned_dice():
		out.append(d.title)
	return out


## The fight at a given depth. Difficulty climbs and the last one is the boss;
## a daily walks the same eight in a seeded order instead.
func enemy_for(d: int) -> Rules.Enemy:
	if not order.is_empty() and d < FINAL_DEPTH:
		d = order[d]
	match d:
		0: return Rules.Enemy.new("Grunt", 22, 0, 3, Rules.Enemy.BEH_NONE)
		1: return Rules.Enemy.new("Rust Golem", 30, 3, 4, Rules.Enemy.BEH_ARMOR_GROW)
		2: return Rules.Enemy.new("Bloodletter", 26, 1, 5, Rules.Enemy.BEH_LIFESTEAL)
		3: return Rules.Enemy.new("Hexweaver", 28, 2, 5, Rules.Enemy.BEH_CURSE)
		4: return Rules.Enemy.new("Ironhide", 30, 2, 7, Rules.Enemy.BEH_BRACE)
		5: return Rules.Enemy.new("Stone Sentinel", 40, 5, 5, Rules.Enemy.BEH_ARMOR_GROW)
		# A second lifesteal, harder than the depth-2 Bloodletter rather than
		# different. The depth-6 slot was one of those already; a reactive mirror
		# of Ironhide was built here and cut, because its only correct play was
		# to stop taking big faces, which is an absence rather than a decision.
		6: return Rules.Enemy.new("Fungal Bloomer", 38, 2, 6, Rules.Enemy.BEH_LIFESTEAL)
		7: return Rules.Enemy.new("Berserker", 38, 3, 6, Rules.Enemy.BEH_ENRAGE)
		_: return Rules.Enemy.new("The Devourer", 78, 5, 9, Rules.Enemy.BEH_ENRAGE)


## Build a fresh encounter for the current depth, carrying the run's stats in.
func start_fight() -> Rules.Encounter:
	var enc := Rules.Encounter.new(enemy_for(depth), dice, hp, max_hp)
	enc.pierce = pierce
	enc.thorns = thorns
	enc.base_rerolls = base_rerolls
	enc.base_focus = base_focus
	enc.focus_left = base_focus  ## granted once per fight; see Encounter.focus_left
	enc.precision = precision
	enc.bastion = bastion
	enc.rush = rush
	return enc


## Pull the player's HP back out of a finished fight.
func absorb(enc: Rules.Encounter) -> void:
	hp = enc.hp


func at_boss() -> bool:
	return depth >= FINAL_DEPTH


## --- upgrades ---
##
## Volume is the retention lever research points at -- Balatro ships 15 decks x
## 150 jokers, Slice & Dice 128 classes -- but the naive way to buy it (pad the
## table with weaker or costlier duplicates) was measured here and it loses.
## Three attempts over 150 bot runs each, win rate for a player who just takes
## whatever is offered:
##
##   8 cards                     12.7%   <- baseline
##   14 cards, 2 with downsides    2.7%   <- a 1-of-3 is drawn blind, so a card
##                                                    with a cost is dead weight
##                                                    twice in fourteen
##   12 cards, all net gains      7.3%   <- still down: the new cards were
##                                                    DOMINATED, not distinct
##
## A single-target HONE is always worse than pool-wide SHARPEN, and BULWARK
## always beats THORNS. A dominated option is never the right pick, so it burns
## an offer slot for nothing -- the same defect as a dominant option, inverted.
## Only MEND and BULWARK earned their place; both are net gains with no
## pool-wide sibling, so neither is ever the wrong pick. BULWARK replaces
## THORNS rather than shadowing it.
##
## Which leaves the real finding: card count is not the lever, distinct
## mechanics are. Growing this table past nine means dice.gd growing with it --
## armour-ignoring damage, conditional effects, curses -- and not more restatements
## of "+1 to a face".

const UPGRADES := [
	{"id": "ADD_DIE", "name": "New Die", "desc": "Add one of your unlocked dice."},
	{"id": "SHARPEN", "name": "Sharpen", "desc": "Every damage face +1."},
	{"id": "BLESS", "name": "Bless", "desc": "Every block face +1."},
	{"id": "FOCUS", "name": "Focus", "desc": "+1 re-roll every turn."},
	{"id": "VIGOR", "name": "Vigor", "desc": "+8 max health, and heal 8."},
	{"id": "PIERCE", "name": "Piercing", "desc": "Your hits ignore 1 armour."},
	# "your weakest die-face" promised the player's worst face across the whole
	# hand. `apply_upgrade` picks a die with `rng.randi_range` and calls
	# `forge()` on it, which raises *that die's* `worst_index()` face by 1 --
	# so with four dice the globally weakest face is the one lifted one time in
	# four, and a strong die can be drawn and have a face it already outclasses
	# bumped instead. Same shape as PRECISE_STRIKE below: the code is right,
	# the copy was promising more. Changed rather than the code, because the
	# 4.7% pick rate BALANCE.md records is a measurement of the *code*, and
	# correcting the text moves no number. "worst face" is `worst_index()`'s
	# own word. Kept short on purpose: a reward Label has no autowrap
	# (`game.gd:235`) and the card is a fixed 146px that will not grow for a
	# longer one (`game.gd:516`), and `shot.gd`'s fit check only measures the
	# three cards it stages -- PRECISE_STRIKE 66, BULWARK 49, ADD_DIE 30.
	# The bound is PRECISE_STRIKE's 66. This comment used to name BULWARK's 49
	# as "the longest string here with layout evidence behind it" while quoting
	# that 66 in the same breath -- the shorter of two staged cards, by seventeen.
	# The 66 also covers GAMBLERS_RUSH at 64, the longest card nothing stages,
	# which `shot.gd`'s note on this same staging does name as the pool's next
	# longest: two files, one subject, opposite answers.
	# A first attempt read "Raise a random die's worst face.", 32 characters --
	# inside the 66, so it fitted, and what it got wrong was never the width.
	# "any die" carries the real correction: it is not *your* die, and it is not
	# your weakest.
	{"id": "REFORGE", "name": "Reforge", "desc": "Raise any die's worst face."},
	{"id": "MEND", "name": "Mend", "desc": "Heal 14. It does not last."},
	# "when struck" read as "when attacked", and thorns fire on `hit > 0` -- so
	# an attack the player fully blocks reflects nothing. That is the right rule
	# (there was no strike to reflect) and the wrong sentence: a player holding a
	# Ward is doing the one thing that suppresses this card, and the card did not
	# say so. Same shape as PRECISE_STRIKE below, and as `hurt.ogg`, whose note
	# already says it fires only on damage that got *through* block. The code was
	# left alone because the rule is defensible; only the promise was wrong.
	{"id": "BULWARK", "name": "Bulwark", "desc": "Reflect 4 damage when hit. A full block stops it."},
	# "for one turn" is not a restatement, it is the whole mechanic. The window is
	# opened by the resolve that earns it and spent by the next one
	# (`dice.gd:657` decrements it, `enemy.exposed = 1` at `dice.gd:662` sets it
	# again), so the copy that said only "leaves it exposed" described a permanent
	# debuff the code does not grant. Same shape as ADD_DIE's wild die: a card
	# promising something the rules do not do.
	{"id": "PRECISE_STRIKE", "name": "Precision Strike", "desc": "A 10+ hit exposes it for one turn; your hits count for half again."},
	{"id": "GAMBLERS_RUSH", "name": "Gambler's Rush", "desc": "A re-roll that lands higher adds half the gain, ignoring armour."},
	{"id": "BASTION_HOLD", "name": "Bastion Hold", "desc": "Holding a die gains 4 block at once."},
]


static func upgrade_by_id(id: String) -> Dictionary:
	for u in UPGRADES:
		if u["id"] == id:
			return u
	return UPGRADES[0]


## An owned bonus die this run is not already holding. ADD_DIE appends one of
## these, so when the list is empty the card has nothing to give. The offer and
## the application have to ask that one question or the card gets dealt to a
## player who can only spend a pick on nothing.
##
## "Owned" is in there because the card's own copy says "your unlocked dice"
## and the title picker draws the ones you have not earned as LOCKED. Asking
## only `held` made this a second, silent source of bonus dice: a player on
## their first run owns none at all, and was still dealt one -- from the same
## list their own title screen was showing them as locked. The pick was spent
## on a die they could not carry into the next run, because ownership is what
## `set_loadout` reads and not what the fight reads.
func unheld_bonus_dice() -> Array:
	var held: Array = []
	for d in dice:
		held.append(d.title)
	var owned: Array = []
	for d in owned_dice():
		owned.append(d.title)
	var out: Array = []
	for b in Rules.Encounter.bonus_dice():
		if owned.has(b.title) and not held.has(b.title):
			out.append(b)
	return out

## Three distinct upgrade offers. ADD_DIE stops appearing once the pool is full
## -- and after it has been taken once, which is the bigger of the two clamps.
## Measured over 150 bot runs per strategy, letting it repeat won 48% against
## 15% for picking at random: a whole die beats any flat +1, so an unbounded
## New Die snowballs and the 1-of-3 pick stops being a choice. Once per run it
## is a decision again rather than the only decision.
##
## The third clamp is the one that was missing. A player who has unlocked all
## three bonus dice and plays them is holding every one, and their pool is 4 of
## MAX_DICE 6 -- so neither existing clamp fires and New Die is dealt as a pick
## that does nothing. Measured at 14 appearances in 60 draws of three. That is
## worse than a dominated option, which at least announces that it lost.
##
## MEND is the same defect wearing different clothes, and it is the commoner
## one: it carries no clamp at all, and it is dealt immediately after absorb,
## so a perfectly blocked fight hands Heal 14 to a full-health player. A
## quarter of all reward rolls happen at full health -- 169 dead picks in 717
## measured deals. The difference from ADD_DIE is that this one is transient,
## which is why it is a clamp on the offer rather than on the card.
func roll_rewards(rng: RandomNumberGenerator) -> Array:
	var pool: Array = []
	for u in UPGRADES:
		# Heal 14 at full health is 0, and the card is consumed either way, so
		# at full HP the pick is strictly dominated -- measured inert in 169 of
		# 717 deals, because 24% of reward rolls follow a perfectly blocked
		# fight. SHARPEN and BLESS have no such case: Ward and Riposte are the
		# only all-block dice and a hand is four, so a hand always holds
		# something of both kinds.
		if u["id"] == "MEND" and hp >= max_hp:
			continue
		if u["id"] == "ADD_DIE" and (dice.size() >= MAX_DICE
				or upgrades.has("ADD_DIE") or unheld_bonus_dice().is_empty()):
			continue
		pool.append(u)
	var picks: Array = []
	var bag := pool.duplicate()
	while picks.size() < OFFER_COUNT and not bag.is_empty():
		var i := rng.randi_range(0, bag.size() - 1)
		picks.append(bag[i])
		bag.remove_at(i)
	return picks


## Apply a chosen upgrade to this run. `id` comes from an UPGRADES entry.
func apply_upgrade(id: String, rng: RandomNumberGenerator) -> void:
	upgrades.append(id)
	match id:
		"ADD_DIE":
			if dice.size() >= MAX_DICE:
				return  ## pool is full -- roll_rewards filters this out, guard anyway
			# Now that the bonus dice can also be starters, one of them may
			# already be in hand; offering a second copy wastes the pick. The
			# same question roll_rewards asked before dealing it, so a New Die
			# that reaches here has something left to give.
			var bonus := unheld_bonus_dice()
			if not bonus.is_empty():
				dice.append(bonus[rng.randi_range(0, bonus.size() - 1)])
		"SHARPEN":
			for d in dice:
				for f in d.faces:
					if f.dmg > 0:
						f.dmg += 1
		"BLESS":
			for d in dice:
				for f in d.faces:
					if f.block > 0:
						f.block += 1
		"FOCUS":
			base_rerolls += 1
		"VIGOR":
			max_hp += 8
			hp += 8
		"PIERCE":
			pierce += 1
		"REFORGE":
			if not dice.is_empty():
				dice[rng.randi_range(0, dice.size() - 1)].forge()
		"MEND":
			hp = mini(hp + 14, max_hp)  ## capped: a full-health take would be a wasted pick
		"BULWARK":
			thorns += 4
		"PRECISE_STRIKE":
			precision = true
		"GAMBLERS_RUSH":
			rush = true
		"BASTION_HOLD":
			bastion = true


# --- persistence (best run + unlocks; stdlib FileAccess + JSON) ---

static func load_stats() -> Dictionary:
	var stats := {"best_depth": 0, "runs": 0, "wins": 0, "unlocked": 0, "loadout": [], "muted": false}
	if not FileAccess.file_exists(SAVE_PATH):
		return stats
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return stats
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		stats["best_depth"] = int(parsed.get("best_depth", 0))
		stats["runs"] = int(parsed.get("runs", 0))
		stats["wins"] = int(parsed.get("wins", 0))
		stats["unlocked"] = int(parsed.get("unlocked", 0))
		stats["loadout"] = parsed.get("loadout", [])
		# A save written before the mute button existed has no key, and .get
		# defaults it to false -- "make noise", which is right for a player who
		# has never been asked.
		stats["muted"] = bool(parsed.get("muted", false))
	return stats


## Remember the mute choice across launches. Without this a player who turned
## the music off has to do it again every time they open the game, which reads
## as the game ignoring them.
static func set_muted(on: bool) -> void:
	var stats := load_stats()
	stats["muted"] = on
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(stats))
	f.close()


## Record the outcome of a finished run. Returns true if it beat the best depth.
## A finished run -- won or lost -- unlocks the next bonus die, so there is
## always something new in hand on the next title screen.
static func record_run(depth_reached: int, victory: bool, loadout: Array = []) -> bool:
	var stats := load_stats()
	var beat := depth_reached > int(stats["best_depth"])
	stats["best_depth"] = maxi(int(stats["best_depth"]), depth_reached)
	stats["runs"] = int(stats["runs"]) + 1
	if victory:
		stats["wins"] = int(stats["wins"]) + 1
	stats["unlocked"] = mini(int(stats["unlocked"]) + 1, UNLOCK_CAP)
	if not loadout.is_empty():
		stats["loadout"] = loadout
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(stats))
		f.close()
	return beat


## The line a player pastes. Three short lines: what was played, how far it
## got, and what ended it.
func share_text(reached: int, victory: bool) -> String:
	var tag := ("daily #%d" % seed) if is_daily() else "free run"
	var end := "The Devourer has fallen." if victory else \
		"Fell to %s." % enemy_for(mini(depth, FINAL_DEPTH)).title
	return "DICE FATE — %s\nDepth %d of %d · %d upgrades · %d dice\n%s" % [
		tag, reached, FINAL_DEPTH + 1, upgrades.size(), dice.size(), end,
	]


# --- a crude bot, used only to keep the difficulty honest ---

## Plays one full run with a simple "re-roll my worst face" policy.
## Returns true if the boss fell. Used by self_test to catch balance cliffs.
const BOT_PATIENCE := 50  ## turns before the bot gives up on a fight it cannot finish


## Plays one full run with a simple "re-roll my worst face" policy.
## Returns true if the boss fell. Used by self_test to catch balance cliffs.
##
## `policy` picks what the bot spends the turn on. Both are the same shape -- read
## the roll, spend something, commit -- so any difference in win rate is
## attributable to the spend rather than to a different game. "gambler" is the
## original and queues re-rolls; "nudger" spends the focus charge on the die with
## the biggest certain gain and then still re-rolls what is left.
##
## Read a difference between these two as "the mechanic is reachable and
## matters", NOT as "a player could have found this". A bot playing a policy is
## a heuristic I wrote, and a cleverer one raises the score without making the
## game better. The human-facing claim needs a device, not a simulation.
func autoplay(rng: RandomNumberGenerator, policy: String = "gambler") -> bool:
	while true:
		var enc := start_fight()
		while not enc.over:
			enc.roll_all(rng)
			if policy == "nudger":
				_focus_biggest_gap(enc)
			# Queue whichever dice are showing their least useful faces.
			for i in enc.dice.size():
				var d: Rules.Die = enc.dice[i]
				if d.up == d.worst_index():
					enc.toggle_pick(i)
			enc.resolve_rerolls(rng)
			enc.resolve_faces()
			if enc.over:
				break
			enc.take_turn(rng)
			if enc.turn > BOT_PATIENCE:
				break  ## unwinnable from here; a player would walk away
		absorb(enc)
		if not enc.won:
			return false
		if at_boss():
			return true
		depth += 1
		var offer := roll_rewards(rng)
		if not offer.is_empty():
			apply_upgrade(str(_weak_pick(offer)["id"]), rng)
	return false  ## unreachable; `while true` is not a flow-proof loop to GDScript


## Which of three offers a weak player takes, and the reason the bot no longer
## picks at random: a uniform chooser is not a weak player, it is an adversary.
## Random draws dilute the pool at exactly the rate that most lowers the win
## rate, and it did -- the old bot cleared the boss 0 times in 40 runs, which
## reads as "the run is unbeatable" when it means "this bot is the worst case,
## not a bad one". A weak player reads the three cards and takes the one with
## the biggest number on it: "Heal 14" over "Every damage face +1", and both over
## a card whose text has no number at all. It never prices a card's effect over
## the whole run, which is what makes it weak, and it is the one judgement here
## that is a real habit rather than a rule I tuned until the gate went green.
func _weak_pick(offer: Array) -> Dictionary:
	var best: Dictionary = offer[0]
	var best_n := -1
	for o in offer:
		var n := _headline_number(str(o["desc"]))
		if n > best_n:
			best_n = n
			best = o
	return best


## The first run of digits in a card description, or -1 if it has none. A plain
## scan rather than a RegEx: eleven cards do not need a pattern language, and the
## "10+" in Precision Strike stopping at the plus is the behaviour we want
## anyway -- every number in the pool is either a flat amount or a threshold.
func _headline_number(s: String) -> int:
	var digits := ""
	for i in s.length():
		if s[i] >= "0" and s[i] <= "9":
			digits += s[i]
		elif not digits.is_empty():
			break
	return int(digits) if not digits.is_empty() else -1


## Spend the charge where it buys the most, not merely on the first thing that
## can be focused. Without this the nudge is a rounding on Blade and a payoff on
## Sunder, and a policy that takes whichever die is cheapest to focus would make
## the two look identical.
func _focus_biggest_gap(enc: Rules.Encounter) -> void:
	var best := -1
	var best_gain := 0
	for i in enc.dice.size():
		var gain: int = enc.focus_gain(i)
		if gain > best_gain:
			best_gain = gain
			best = i
	if best >= 0:
		enc.focus_die(best)


## The store copy's "your first three finished runs each unlock a die". Read as
## a sentence about the *hand*, it is false, and it was false in the block until
## this round: the copy said the unlock meant "the next one starts with a fuller
## hand", while four lines later the same block said the only way past four is
## a New Die taken mid-run. Both cannot hold. The one that was wrong is the first.
##
## What unlocking actually does is widen `owned_dice()`, and `set_loadout` trims
## whatever it is handed to POOL_SIZE and tops it back up from the library -- so
## the starting hand is four on every run, forever, and a die you have earned is
## a die you can *pick* at the title screen, not one that is dealt to you. The
## picker agrees: `game.gd` refuses to add past POOL_SIZE and renders
## `pool.size() / POOL_SIZE`, so no path through the game opens a run wider than
## four. Widened mid-run is a different thing and is exactly what a New Die
## does, up to MAX_DICE -- so the clause needs "opens ... than four" to be true,
## and the bare "wider" was not: it is the reading this block exists to refute.
##
## Two checks, and the order matters. The first is liveness: at the point this
## runs, four `record_run` calls have already taken `unlocked` to its cap, so
## `owned_dice()` really is longer than a hand. Without it the second check
## passes on a build where unlocking is broken outright -- seven dice owned
## failing to become six would still open on four -- which is the
## check-that-cannot-fail this repo keeps refusing to write.
static func _check_fuller_hand_claim() -> void:
	Check.check(owned_dice().size() > POOL_SIZE,
		"the three unlocks did land, so the hand-width check below is not vacuous")
	Check.check(new().dice.size() == POOL_SIZE,
		"and a fresh run still opens on exactly POOL_SIZE dice, unlocks or not")


static func self_test() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99

	var r := new()
	Check.check(r.dice.size() == 4, "a run starts with the four library dice")
	Check.check(r.depth == 0 and r.hp == 20)

	# The table escalates and ends in a boss.
	Check.check(r.enemy_for(0).title == "Grunt")
	Check.check(r.enemy_for(FINAL_DEPTH).title == "The Devourer", "last fight is the boss")
	for d in FINAL_DEPTH + 1:
		var e := r.enemy_for(d)
		Check.check(e.hp > 0, "every enemy has health")

	# The depth the player reads, which is not the depth the game indexes. Six
	# sites in `game.gd` printed a depth and five of them added one -- so the
	# death screen said "You reached depth 9 of 9" and, two lines below,
	# "The Devourer waits at depth 8", for the same fight. Both halves pinned:
	# the mapping is one-based, and it cannot run past the end of the run.
	Check.check(depth_no(0) == 1, "the first fight reads as depth 1, not depth 0")
	Check.check(depth_no(FINAL_DEPTH) == FINAL_DEPTH + 1,
		"the boss reads as the ninth fight, not as its index (%d)" % FINAL_DEPTH)
	for d in FINAL_DEPTH + 1:
		Check.check(depth_no(d) == d + 1,
			"depth %d reads as %d" % [d, d + 1])
	Check.check(depth_no(FINAL_DEPTH + 1) == FINAL_DEPTH + 1,
		"and a run past the boss still reads as the ninth, not a tenth")

	# The roster as play/LISTING.md describes it, clause by clause. The store
	# copy is the one surface Play indexes and none of it was checkable, which
	# is how it came to sell a daily that seeded the wrong thing. These are the
	# enemy claims, so they are asserted here: if a behaviour is retagged or the
	# boss is rebalanced the description goes stale and this goes red.
	for claim in [
		[1, "Rust Golem", Rules.Enemy.BEH_ARMOR_GROW, "grows its armour every turn"],
		[2, "Bloodletter", Rules.Enemy.BEH_LIFESTEAL, "heals off what it deals to you"],
		[3, "Hexweaver", Rules.Enemy.BEH_CURSE, "drags one of your dice down to its worst face"],
		[7, "Berserker", Rules.Enemy.BEH_ENRAGE, "gets angrier the longer it lives"],
	]:
		var depth: int = claim[0]
		var who: Rules.Enemy = r.enemy_for(depth)
		Check.check(who.title == claim[1], "depth %d is the %s the description names" % [depth, claim[1]])
		Check.check(who.behavior == claim[2],
			"and it %s (behaviour %d, want %d)" % [claim[3], who.behavior, claim[2]])
	var boss := r.enemy_for(FINAL_DEPTH)
	Check.check(boss.hp == 78, "the boss has the 78 health the description gives it (%d)" % boss.hp)
	Check.check(boss.armor > 0 and boss.behavior == Rules.Enemy.BEH_ENRAGE,
		"and it is armoured and enraged, as described")

	# The store's Hexweaver clause was "curses one of your dice to nothing", and
	# it was false for three of the four library dice. `Dice.Encounter._curse_one`
	# picks a die at random and drops it on *that die's* lowest-`worth()` face --
	# Blade's is a 2, Ward's a 2 that blocks instead of striking, Hex's a 1 -- and
	# only Sunder's is a nothing, because Sunder is the one die carrying `rust`.
	# Measured rather than read: the version of this check that asserted the
	# clause as written failed on exactly those three.
	#
	# The copy now says the true thing, and this is the line that goes red if a
	# rebalance ever made the overclaim true -- which is the signal to change the
	# sentence, not the dice.
	var junk := 0
	for die in Rules.Encounter.library():
		if die.faces[die.worst_index()].is_junk():
			junk += 1
	Check.check(junk < Rules.Encounter.library().size(),
		"the Hexweaver clause must not say \"curses one of your dice to nothing\": "
			+ "the curse lands on a die's own worst face and only %d of the %d library "
			% [junk, Rules.Encounter.library().size()]
			+ "dice have one that is nothing")

	# "upgrades change your dice, not a stat bar" was the store's sentence, and two
	# of the twelve contradict it: VIGOR writes `max_hp += 8; hp += 8` and MEND
	# writes `hp = mini(hp + 14, max_hp)`. Counted by applying every card to a
	# fresh run rather than by reading the arms, because the arms are twelve
	# `match` cases and the copy's claim is about all twelve at once -- and
	# reading them is how the sentence survived.
	var hp_cards := 0
	for card in UPGRADES:
		var c := new()
		## Wounded on purpose: a full-health MEND is capped at `max_hp` and would
		## look identical to a card that does nothing.
		c.hp = 10
		c.max_hp = 20
		c.apply_upgrade(card["id"], RandomNumberGenerator.new())
		if c.hp > 10 or c.max_hp > 20:
			hp_cards += 1
	Check.check(hp_cards == 2,
		"the store copy may not claim upgrades never touch a stat bar: %d of the twelve "
			% hp_cards + "cards move hit points (MEND and VIGOR)")

	# The boss's title already carries its own article -- "The Devourer" -- and
	# three log lines added one of their own, so a run's last fight opened with
	# "A The Devourer blocks your path." and could end with "The The Devourer
	# falls." Every other line in `resolve_faces` and `take_turn` prints the bare
	# title, which is why these three only showed up on re-reading.
	#
	# Driven over the whole roster rather than at the boss, because what makes it
	# reachable is a *title* that starts with an article and that is a property
	# any of the nine could pick up. Three sites, because a fight has one opening
	# and two endings -- the resolve that lands the killing blow, and the thorns
	# on the enemy's own turn. Both endings were reachable: thorns is a card, and
	# the boss enrages to an attack past any block a first run has.
	for d in FINAL_DEPTH + 1:
		var rd := new()
		rd.depth = d
		var enc := rd.start_fight()
		Check.check(enc.log_lines[0] == "%s blocks your path." % enc.enemy.title,
			"depth %d opens with \"%s\" -- every other line in the fight prints the bare "
				% [d, enc.log_lines[0]] + "title, and one that already carries an "
				+ "article must not be given another")
		enc.enemy.hp = 1
		enc.roll_all(RandomNumberGenerator.new())
		enc.dice[0].up = 5  ## Blade 9, which is through every armour in the table
		enc.resolve_faces()
		Check.check(enc.log_lines[-1] == "%s falls." % enc.enemy.title,
			"depth %d ends with \"%s\" -- the same doubling, on the killing blow"
				% [d, enc.log_lines[-1]])
		var rd2 := new()
		rd2.depth = d
		var te := rd2.start_fight()
		te.thorns = 999  ## every enemy answers, so this line is the last one it writes
		te.take_turn(RandomNumberGenerator.new())
		Check.check(te.log_lines[-1] == "%s dies to your thorns." % te.enemy.title,
			"depth %d ends with \"%s\" on the thorns kill -- the third site"
				% [d, te.log_lines[-1]])

	# The roster's armour shape, which nothing pinned. `_balance.gd:184` argued
	# the roster is what makes sunder near-universal, and it did that on two
	# counts -- "seven of nine" armoured and "two of them" able to grow into the
	# cap -- and both were wrong. Counted over every depth rather than asserted
	# per enemy so a daily's shuffle cannot move them: `order` permutes the same
	# nine, so the totals are the totals whichever order the run took.
	var armoured := 0
	var growing := 0
	for d in FINAL_DEPTH + 1:
		var foe := r.enemy_for(d)
		if foe.armor > 0:
			armoured += 1
		if foe.behavior == Rules.Enemy.BEH_ARMOR_GROW \
				or foe.behavior == Rules.Enemy.BEH_BRACE:
			growing += 1
	Check.check(armoured == 8, "eight of the nine enemies carry armour, measured %d" % armoured)
	Check.check(growing == 3, "and three can grow into the %d armour cap, measured %d"
		% [Rules.Enemy.ARMOR_GROW_CAP, growing])

	# A daily is the same run for everyone on that day, and never lets the boss
	# out early. Same seed, same enemy order, opener included.
	var daily_a := new(12345)
	var daily_b := new(12345)
	Check.check(daily_a.order == daily_b.order, "the same seed gives the same daily")
	Check.check(daily_a.order.size() == FINAL_DEPTH, "all eight non-boss fights are ordered")
	var placed := {}
	for d in daily_a.order:
		placed[d] = true
	Check.check(placed.size() == FINAL_DEPTH, "each enemy appears exactly once")
	Check.check(daily_a.enemy_for(0).title == daily_b.enemy_for(0).title, "same opener")
	Check.check(daily_a.enemy_for(FINAL_DEPTH).title == "The Devourer", "the boss is still last")
	Check.check(not new().is_daily(), "a run with no seed is not a daily")
	Check.check(daily_a.share_text(3, false).contains("daily #12345"), "a daily says so")
	Check.check(new().share_text(3, false).contains("free run"), "a free run says so")

	# What a daily fixes, and what it does not. The enemy order is seeded, so
	# two players on one day fight the same nine in the same order. The HAND is
	# not seeded -- it is the player's own pool -- and that distinction is the
	# whole of it, so it is pinned here. play/LISTING.md sold the daily as "the
	# same dice and the same enemies"; only the second half is true, and it is
	# true of a hand nobody has touched, not of one picked at the title screen.
	var stocked := new(12345)
	var picked := new(12345)
	picked.set_loadout(["Spark", "Fang", "Riposte", "Blade"])
	Check.check(stocked.order == picked.order,
		"two players pick their own dice and still fight the same daily")
	var stocked_titles: Array = []
	var picked_titles: Array = []
	for d in stocked.dice:
		stocked_titles.append(d.title)
	for d in picked.dice:
		picked_titles.append(d.title)
	Check.check(stocked_titles != picked_titles,
		"but a hand chosen at the title screen is a different set of dice that day")

	# The surprising half, and the reason the copy is only half wrong: owning
	# bonus dice does NOT change the default hand. `set_loadout` trims to
	# POOL_SIZE library-first, so a player on their fourth run rolls the same
	# four starters as a fresh install. Both ends are pinned below, because
	# "the hand is unaffected by unlocks" is not true of an arbitrary change
	# here -- bonus-first would hand every veteran a different daily.
	var was_path := SAVE_PATH
	SAVE_PATH = "user://self-test-daily.json"
	for case in [[0, "no bonus dice owned"], [3, "every bonus die owned"]]:
		var cf := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		cf.store_string(JSON.stringify({"unlocked": int(case[0])}))
		cf.close()
		var titles: Array = []
		for d in new(12345).dice:
			titles.append(d.title)
		Check.check(titles == ["Blade", "Sunder", "Ward", "Hex"],
			"the unchosen daily hand is the four starters with %s (got %s)"
			% [case[1], titles])
	SAVE_PATH = was_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://self-test-daily.json"))

	# start_fight carries the run's stats into the encounter.
	var f0 := r.start_fight()
	Check.check(f0.enemy.title == "Grunt")
	Check.check(f0.pierce == r.pierce and f0.thorns == r.thorns)
	Check.check(f0.base_rerolls == r.base_rerolls)
	Check.check(f0.base_focus == r.base_focus)
	# ...and the card's flag has to be carried with them. Every Exposed test in
	# dice.gd sets `precision` on the encounter by hand, so a start_fight that
	# forgot this line would leave the card inert in a real run with the whole
	# suite still green -- which is the failure mode the bench found once already.
	Check.check(not f0.precision, "a run without the card exposes nothing")
	r.apply_upgrade("PRECISE_STRIKE", RandomNumberGenerator.new())
	Check.check(r.start_fight().precision, "and a run that took it carries it into the fight")
	Check.check(upgrade_by_id("PRECISE_STRIKE")["id"] == "PRECISE_STRIKE",
		"the card is in the offer pool, not just in this test")
	f0 = r.start_fight()

	for id in ["BASTION_HOLD", "GAMBLERS_RUSH"]:
		var c_run := new()
		c_run.apply_upgrade(id, RandomNumberGenerator.new())
		var c: Rules.Encounter = c_run.start_fight()
		Check.check(c.bastion == (id == "BASTION_HOLD"), "%s carries its flag" % id)
		Check.check(c.rush == (id == "GAMBLERS_RUSH"), "%s carries its flag" % id)
	# A fresh encounter must not inherit the previous fight's unspent charge.
	# Park the die on face 0 first: Blade can roll a 9, which is already its best
	# face, and a refused focus would make this assert depend on the roll.
	f0.roll_all(RandomNumberGenerator.new())
	f0.dice[0].up = 0
	f0.focus_die(0)
	Check.check(f0.focus_left == r.base_focus - 1, "spending a focus uses one charge")
	var f_next := r.start_fight()
	f_next.roll_all(RandomNumberGenerator.new())
	Check.check(f_next.focus_left == r.base_focus, "and the next fight starts with a full charge")

	# Fight state must not survive into the next fight. Before this, `Encounter`
	# aliased the run's Die objects, so a die re-rolled in one fight came into
	# the next still marked spent -- and the cards drew dimmed before the roll.
	f0.roll_all(rng)
	f0.picks[0] = true
	f0.resolve_rerolls(rng)
	Check.check(f0.dice[0].spent, "the re-rolled die is spent this fight")
	var f1 := r.start_fight()
	for d in f1.dice:
		Check.check(not d.spent, "a new fight starts with no die already spent")
	Check.check(r.dice[0].spent == false, "the run's pool is never marked spent")

	# Upgrades each do what they claim.
	var before_dice := r.dice.size()
	r.apply_upgrade("ADD_DIE", rng)
	Check.check(r.dice.size() == before_dice + 1, "ADD_DIE grows the pool")

	var blade: Rules.Die = r.dice[0]
	var blade_min := 999
	for f in blade.faces:
		blade_min = mini(blade_min, f.dmg)
	r.apply_upgrade("SHARPEN", rng)
	var blade_min2 := 999
	for f in blade.faces:
		blade_min2 = mini(blade_min2, f.dmg)
	Check.check(blade_min2 == blade_min + 1, "SHARPEN lifts every damage face")

	var ward: Rules.Die = r.dice[2]
	var blk0 := 0
	for f in ward.faces:
		blk0 += f.block
	r.apply_upgrade("BLESS", rng)
	var blk1 := 0
	for f in ward.faces:
		blk1 += f.block
	Check.check(blk1 == blk0 + 6, "BLESS lifts all six block faces")

	var rr0 := r.base_rerolls
	r.apply_upgrade("FOCUS", rng)
	Check.check(r.base_rerolls == rr0 + 1, "FOCUS adds a re-roll")

	var mh0 := r.max_hp
	r.apply_upgrade("VIGOR", rng)
	Check.check(r.max_hp == mh0 + 8, "VIGOR adds max health")

	var pi0 := r.pierce
	r.apply_upgrade("PIERCE", rng)
	Check.check(r.pierce == pi0 + 1, "PIERCE adds armour penetration")

	var th0 := r.thorns
	r.apply_upgrade("BULWARK", rng)
	Check.check(r.thorns == th0 + 4, "BULWARK reflects damage")

	r.apply_upgrade("REFORGE", rng)
	Check.check(r.upgrades.has("REFORGE"), "REFORGE is recorded")
	# ...and that is all the line above asserted: the id was recorded, not that a
	# die changed. `forge()` is tested on a bare die in `dice.gd` ("forge raises
	# the weakest face by one"), so what was untested is the wiring -- that the
	# arm reaches a face of a die in *this*
	# hand. Measuring a delta across a second application pins the effect and
	# the "one face, by one" the card text now promises at the same time, and
	# it is a delta because the arm draws a random die: the arm can only pass by
	# forging exactly one face of exactly one die, so passing by forging none, or
	# by forging two, both go red.
	var forged0 := 0
	for d in r.dice:
		for f in d.faces:
			forged0 += f.dmg
	r.apply_upgrade("REFORGE", rng)
	var forged1 := 0
	for d in r.dice:
		for f in d.faces:
			forged1 += f.dmg
	Check.check(forged1 == forged0 + 1,
		"REFORGE raises exactly one face of one die by one")

	var mh1 := r.max_hp
	r.hp = 1
	r.apply_upgrade("MEND", rng)
	Check.check(r.hp == 15 and r.max_hp == mh1, "MEND heals without touching the pool")

	# The card copy quotes three magnitudes that live in constants, and **nothing
	# bound them.** The checks above pin the *effects* — `thorns` is four more, a
	# die's face rose by one — but not one check anywhere read a `desc`, so moving
	# a constant left the sentence on screen quietly untrue and every gate green.
	# REFORGE was this same defect found by reading: "your weakest die-face"
	# promised a global worst face the code does not pick.
	#
	# Only the magnitudes whose number is *derivable* are listed. The other seven —
	# SHARPEN's +1, BLESS's +1, VIGOR's 8, MEND's 14, BULWARK's 4, FOCUS's +1,
	# PIERCE's 1 — are each the same literal typed twice, once in `apply_upgrade`
	# and once in the card, so there is nothing for a check to read the value out
	# *of*. (ADD_DIE and REFORGE are the other two and quote no tunable number.)
	# A check that hardcoded the number instead would be a second copy with
	# nothing to propagate it, which is the defect wearing a check's clothes.
	# Binding those means hoisting each literal into a constant and adding it to
	# `derived` below; that is a code change, so it is named rather than made.
	var derived := {
		"BASTION_HOLD": "gains %d block at once" % Rules.Encounter.BASTION_BLOCK,
		"PRECISE_STRIKE": "A %d+ hit" % Rules.Encounter.EXPOSE_AT,
	}
	for id in derived:
		Check.check(upgrade_by_id(id)["desc"].contains(derived[id]),
			"the %s card quotes the constant that implements it (%s)" % [id, derived[id]])
	# "half" is not a number in the copy, so this row asserts the promise instead
	# of restating it: RUSH_SHARE is what "half" means, and the card reads
	# `rushed / RUSH_SHARE`.
	Check.check(Rules.Encounter.RUSH_SHARE == 2,
		"GAMBLERS_RUSH says \"half the gain\", and half is 2")

	# Every card in the table is applied and recorded. This loop cannot be what
	# catches a copy-paste slip that adds a description without an arm, and the
	# comment here used to say it was: `apply_upgrade` appends the id on its
	# first line, before the `match`, and the `match` has no default arm, so a
	# card with no arm is recorded and does nothing and this check still passes.
	# Deleting BULWARK's arm and BASTION_HOLD's arm in turn leaves this loop
	# green both times; what goes red is the per-card checks above and below
	# ("BULWARK reflects damage", "%s carries its flag"). Those are the backstop.
	for u in UPGRADES:
		var probe := new()
		probe.apply_upgrade(str(u["id"]), rng)
		Check.check(probe.upgrades.has(str(u["id"])), "%s is applied and recorded" % u["id"])

	# Rewards are three distinct offers, and ADD_DIE drops out when the pool is full.
	var full := new()
	for _i in 5:
		full.apply_upgrade("ADD_DIE", rng)
	Check.check(full.dice.size() == MAX_DICE, "pool caps at MAX_DICE")
	var offers := full.roll_rewards(rng)
	Check.check(offers.size() == OFFER_COUNT,
		"always %d offers, which is what the store copy quotes" % OFFER_COUNT)
	var ids := {}
	for o in offers:
		ids[o["id"]] = true
		Check.check(o["id"] != "ADD_DIE", "ADD_DIE not offered at a full pool")

	# ...and drops out when it has nothing left to give either. A player who has
	# unlocked all three bonus dice and plays them is holding every one of them,
	# so ADD_DIE has nothing to append -- but the pool is 4 of MAX_DICE 6, so the
	# size clamp does not catch it and the card is offered as a pick that does
	# nothing. The card is then consumed by `apply_upgrade`, so it is a 1-of-3
	# slot spent on nothing, which is worse than a dominated option: a dominated
	# one at least tells you it lost. Reachable from the state the store
	# description advertises -- three finished runs, hand chosen.
	#
	# The "nothing left to give" precondition below is recomputed here rather
	# than read off `unheld_bonus_dice()`, even though that is the helper the
	# fix calls. Asserting the helper against itself would pass on a helper
	# that returns the wrong thing, and the helper is the thing that was wrong.
	var done := new()
	done.set_loadout(["Riposte", "Spark", "Fang", "Blade"])
	Check.check(done.dice.size() == 4, "the all-bonus hand fills to four dice")
	Check.check(done.dice.size() < MAX_DICE,
		"and the pool is not full, so the size clamp cannot be what stops ADD_DIE")
	var held: Array = []
	for d in done.dice:
		held.append(d.title)
	var unheld := 0
	for b in Rules.Encounter.bonus_dice():
		if not held.has(b.title):
			unheld += 1
	Check.check(unheld == 0,
		"every bonus die is already in hand, so ADD_DIE has nothing to give")
	var nadd := 0
	for _i in 60:
		for o in done.roll_rewards(rng):
			if o["id"] == "ADD_DIE":
				nadd += 1
	Check.check(nadd == 0,
		"so ADD_DIE is never offered -- 60 draws of three, and it appeared %d times"
		% nadd)

	# ...and the copy, which is a different question. "Add one of your unlocked
	# dice" claims *which* dice the card may hand over, and nothing asserted it:
	# the block above asks whether the card is offered when there is nothing to
	# give, and never asks what it gives. Both ends are pinned on a temp save
	# rather than reasoned about, because the ambient save already has every
	# bonus die unlocked -- a check built on `r` passes whether or not the
	# ownership filter exists, which is how this stayed invisible. The temp save
	# is the only way to reach the case the sentence is about: a player who owns
	# none of them.
	var own_path := SAVE_PATH
	SAVE_PATH = "user://self-test-new-die.json"
	for case in [[0, "a first run, which owns no bonus die"],
			[UNLOCK_CAP, "every bonus die owned"]]:
		var cf := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		cf.store_string(JSON.stringify({"unlocked": int(case[0])}))
		cf.close()
		var owned: Array = []
		for d in owned_dice():
			owned.append(d.title)
		var nd := new()
		nd.set_loadout(["Blade", "Sunder", "Ward", "Hex"])
		var before: int = nd.dice.size()
		nd.apply_upgrade("ADD_DIE", rng)
		var strays: Array = []
		for d in nd.dice:
			if not owned.has(d.title):
				strays.append(d.title)
		Check.check(strays.is_empty(),
			"New Die hands over nothing the player does not own (%s)" % case[1])
		Check.check(nd.dice.size() == before + (0 if int(case[0]) == 0 else 1),
			"and grows the pool only when an unlocked die is left to add (%s)"
			% case[1])
	SAVE_PATH = own_path
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path("user://self-test-new-die.json"))

	# MEND is the same defect in different clothes, and more common: a card with
	# no clamp, offered right after absorb, so a perfectly blocked fight deals
	# Heal 14 to a full-health player who can only spend the pick on it. 24% of
	# reward rolls happen at full health, which is 169 dead picks in 717 deals.
	# Two runs differing in exactly one variable -- `hp`, by 1 -- so the pair
	# cannot both pass on a build that simply never offers MEND at all.
	var hurt := new()
	hurt.hp = hurt.max_hp - 1
	var m_hurt := 0
	for _i in 60:
		for o in hurt.roll_rewards(rng):
			if o["id"] == "MEND":
				m_hurt += 1
	Check.check(m_hurt > 0,
		"MEND is offered with one point of health to give (%d in 60 draws)" % m_hurt)
	var whole := new()
	whole.hp = whole.max_hp
	var m_full := 0
	for _i in 60:
		for o in whole.roll_rewards(rng):
			if o["id"] == "MEND":
				m_full += 1
	Check.check(m_full == 0,
		"and never at full health, where Heal 14 is worth nothing -- it appeared %d times"
		% m_full)
	Check.check(ids.size() == OFFER_COUNT, "offers are distinct")

	# Persistence round-trips through user://run.json.
	record_run(3, false)
	record_run(5, true)
	var stats := load_stats()
	Check.check(int(stats["best_depth"]) == 5, "best depth is the max reached")
	Check.check(int(stats["wins"]) >= 1, "victories are counted")

	# A finished run unlocks the next bonus die, and the hand always fills.
	record_run(2, false)
	var owned := owned_dice().size()
	Check.check(owned >= 5, "a bonus die is owned after a run")
	Check.check(owned <= 7, "never more than the three bonus dice")
	# The cap is three, so "a finished run unlocks another die" stops being
	# true from the fourth one on. Pinned because the store description said it
	# without the qualifier; only `bonus_dice().size()` ever bounded it before.
	# This needs a FOURTH record_run to mean anything: three runs leave the
	# counter at 3 whether the cap exists or not, so a check placed here would
	# pass on a build with no cap at all -- the one sort of check that is worse
	# than none, because it looks like the cap is covered.
	record_run(1, false)
	Check.check(int(load_stats()["unlocked"]) == UNLOCK_CAP,
		"a fourth finished run unlocks nothing -- the count is still %d" % UNLOCK_CAP)
	Check.check(Rules.Encounter.bonus_dice().size() == 3,
		"and there are only three to unlock in the first place")

	# The last two fields of the save, and the only two with a reader and no
	# assertion: `runs` is the number the title screen prints and what flips
	# the Play button from "Begin the run" to "Play" (the `"%d runs   ·   %d
	# victories"` label, and the `primary_button("Play" if ...)` beside it),
	# and `loadout` is what `saved_loadout()` hands every run at `run.gd:71`
	# -- inside `_init`, so it is read on every single RunState, not on some
	# opt-in path. A delta, not a count: five `record_run` calls now sit in
	# this function and an absolute total goes stale the moment a sixth is
	# added, which is the drift this audit keeps finding.
	var runs_before := int(load_stats()["runs"])
	record_run(1, false, ["Blade"])
	var replayed := load_stats()
	Check.check(int(replayed["runs"]) == runs_before + 1,
		"a finished run is counted exactly once")
	Check.check(replayed.get("loadout", []) == ["Blade"],
		"and the hand it was played with survives the round trip")
	Check.check(new().saved_loadout() == ["Blade"],
		"and comes back out as the next run's starting hand")

	var hand := new()
	hand.set_loadout(["Blade", "NotADie", "AlsoFake"])
	Check.check(hand.dice.size() == POOL_SIZE, "a bad loadout still fills the hand")
	Check.check(hand.dice[0].title == "Blade", "and keeps the titles it could use")
	hand.set_loadout(owned_titles())  # everything owned, which is more than a hand
	Check.check(hand.dice.size() == POOL_SIZE, "an oversized loadout is trimmed to a hand")
	_check_fuller_hand_claim()
	Check.check(hand.share_text(4, true).contains("Depth 4 of 9"), "a free run reports depth")

	# Difficulty: a dumb bot clears the run sometimes and never trivially.
	# The depth line is here because "0/40" on its own cannot tell a game that is
	# too hard from a bot that is too bad, and those want opposite fixes.
	var wins := 0
	var depth_sum := 0
	const TRIALS := 40
	for _i in TRIALS:
		var bot := new()
		if bot.autoplay(rng):
			wins += 1
		depth_sum += bot.depth + 1
	print("  autoplay cleared the boss %d/%d runs, avg depth %.1f of %d"
		% [wins, TRIALS, float(depth_sum) / TRIALS, FINAL_DEPTH + 1])
	Check.check(wins > 0, "the run is beatable by a simple bot")
	Check.check(wins < TRIALS, "but not a given")

	# The pass/fail verdict is Check.report()'s exit code, not this line.
	print("run.self_test: %d checks, %d failed"
		% [Check.checks, Check.failures.size()])
