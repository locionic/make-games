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
const MAX_DICE := 6
const POOL_SIZE := 4  ## dice in hand at the start of a run

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
	var left: int = mini(int(load_stats().get("unlocked", 0)), 3)
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
	{"id": "ADD_DIE", "name": "New Die", "desc": "Add a wild die to your pool."},
	{"id": "SHARPEN", "name": "Sharpen", "desc": "Every damage face +1."},
	{"id": "BLESS", "name": "Bless", "desc": "Every block face +1."},
	{"id": "FOCUS", "name": "Focus", "desc": "+1 re-roll every turn."},
	{"id": "VIGOR", "name": "Vigor", "desc": "+8 max health, and heal 8."},
	{"id": "PIERCE", "name": "Piercing", "desc": "Your hits ignore 1 armour."},
	{"id": "REFORGE", "name": "Reforge", "desc": "Raise your weakest die-face."},
	{"id": "MEND", "name": "Mend", "desc": "Heal 14. It does not last."},
	{"id": "BULWARK", "name": "Bulwark", "desc": "Reflect 4 damage when struck."},
	{"id": "PRECISE_STRIKE", "name": "Precision Strike", "desc": "A hit of 10+ leaves it exposed: your hits on it count for half again."},
	{"id": "GAMBLERS_RUSH", "name": "Gambler's Rush", "desc": "A re-roll that lands higher adds half the gain, ignoring armour."},
	{"id": "BASTION_HOLD", "name": "Bastion Hold", "desc": "Holding a die gains 4 block at once."},
]


static func upgrade_by_id(id: String) -> Dictionary:
	for u in UPGRADES:
		if u["id"] == id:
			return u
	return UPGRADES[0]


## Three distinct upgrade offers. ADD_DIE stops appearing once the pool is full
## -- and after it has been taken once, which is the bigger of the two clamps.
## Measured over 150 bot runs per strategy, letting it repeat won 48% against
## 15% for picking at random: a whole die beats any flat +1, so an unbounded
## New Die snowballs and the 1-of-3 pick stops being a choice. Once per run it
## is a decision again rather than the only decision.
func roll_rewards(rng: RandomNumberGenerator) -> Array:
	var pool: Array = []
	for u in UPGRADES:
		if u["id"] == "ADD_DIE" and (dice.size() >= MAX_DICE or upgrades.has("ADD_DIE")):
			continue
		pool.append(u)
	var picks: Array = []
	var bag := pool.duplicate()
	while picks.size() < 3 and not bag.is_empty():
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
			# already be in hand; offering a second copy wastes the pick.
			var held: Array = []
			for d in dice:
				held.append(d.title)
			var bonus: Array = []
			for b in Rules.Encounter.bonus_dice():
				if not held.has(b.title):
					bonus.append(b)
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
	stats["unlocked"] = mini(int(stats["unlocked"]) + 1, 3)
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

	var mh1 := r.max_hp
	r.hp = 1
	r.apply_upgrade("MEND", rng)
	Check.check(r.hp == 15 and r.max_hp == mh1, "MEND heals without touching the pool")

	# Every card in the table is applied and recorded. A copy-paste slip that
	# adds a description without an arm shows up here rather than as a dead pick.
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
	Check.check(offers.size() == 3, "always three offers")
	var ids := {}
	for o in offers:
		ids[o["id"]] = true
		Check.check(o["id"] != "ADD_DIE", "ADD_DIE not offered at a full pool")
	Check.check(ids.size() == 3, "offers are distinct")

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
	var hand := new()
	hand.set_loadout(["Blade", "NotADie", "AlsoFake"])
	Check.check(hand.dice.size() == POOL_SIZE, "a bad loadout still fills the hand")
	Check.check(hand.dice[0].title == "Blade", "and keeps the titles it could use")
	hand.set_loadout(owned_titles())  # everything owned, which is more than a hand
	Check.check(hand.dice.size() == POOL_SIZE, "an oversized loadout is trimmed to a hand")
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
