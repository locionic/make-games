# Dice Fate — Google Play listing

Screenshots are regenerable:

    xvfb-run -a godot --path . --rendering-driver opengl3 -s shot.gd   # screenshots/

`res://icon.png` (the launcher icon) ships in the APK; everything in this
folder is store art only, kept out of the build by `.gdignore`.

**`icon.png` and `feature.png` are not regenerable.** Both were replaced on
2026-09-29 with art generated through OmniFlash (`POST /generate/image` on
`localhost:8080`), and the originals are kept beside them as `*.bak-flat` — at
8.4 KiB and 17.3 KiB they were near-flat fills, which is why they were replaced.
`icon.gd` still exists and still draws both of them in code, but it is now the
*fallback* and it will not run without `--overwrite`. Without it, `icon.gd`
exits having written nothing. With it, it replaces the generated `feature.png`
**and `icon.png`** — the launcher icon, the only image inside the APK. Note
that `*.bak-flat` holds the *originals*, not this art: restoring from them
gives you back the near-flat fills that were replaced for being near-flat, not
the generated files. The generated pair lives in git history and nowhere else,
so `git checkout -- icon.png play/feature.png` is the way back.

Note when scripting against that API: `/generate/image?download=true` returns a
JPEG whatever the response filename says, so the 24-bit PNG Play wants has to be
re-encoded from the JPEG.

## Audio

Not a store asset, but it ships and it is the biggest change to the game since
the roguelike loop landed. Two 40s seamless loops in `audio/`, generated through
FlowMusic2API on 2026-09-29 with the `lyria-fast` and `lyria` models:

| file | source | size | plays on |
|---|---|---|---|
| `audio/menu.ogg` | 177s m4a, cut and crossfaded to 40s | 527 KiB (539,931 B) | title, reward, run over |
| `audio/combat.ogg` | 176s m4a, cut and crossfaded to 40s | 549 KiB (561,899 B) | the fight panel |

Both sizes are KiB and are written out in bytes beside it, because the same
table two sections down writes "45 KiB (46,338 bytes)" and a bare "527 KB" beside
a bare "527 KiB" is a 2.4% disagreement that reads as drift — someone checking
539,931 bytes against "527 KB" computes 540 KB and concludes the audio had been
replaced. It has not: measured 2026-09-30 at exactly the figures above, and the
nine `.oggvorbisstr` blobs in both AABs are byte-identical at 1,188,787 bytes
total, which is PLAN.md 4.1's number and still true.

The sizes are deliberately **not** asserted. Regenerating the audio through
`POST /v1/audio/generations` is a documented, legitimate action, and every
regeneration produces a different file size — so a size check would be red the
first time anyone followed the instructions two paragraphs above. The duration
gate already catches the failure that actually loses a sound: a file that was
replaced or truncated.

Both were verified with `ffprobe`, not by ear: this machine's only audio driver
is the dummy one, so **listening is not possible here.** The loop seam was
checked numerically instead — head/tail mean volume differs by 0.7 dB on
`combat` and 3.9 dB on `menu`, so neither clicks at the wrap. Re-generate with
`POST /v1/audio/generations` (Bearer token, the service's own account must be
logged in or it 502s), then re-cut: ffmpeg takes `[0:40]` as the body and
`[40:44]` crossfaded over it, which is what makes the wrap seamless.

`game.gd:_music_to` picks the bed and fades it up over `MUSIC_FADE`. The Godot
OGG importer does not loop, so `_ready` sets `loop` on a duplicate of each
stream rather than mutating the preloaded const. `shot.gd` asserts the fight
screen is actually playing the combat bed.

The mute button is built once on the root in `_build_mute()`, not per screen, so
it survives every `_swap` and no screen builder has to know about it. It sits
top-right: the depth strip's pips are centred and leave ~150px of margin at each
end, which is the one part of the fight screen's top edge nothing else uses.
`_swap` lifts it back to the front afterwards, since each new screen is added
after it. The choice persists through `RunState.set_muted()` as a `"muted"` key
in `run.json`; a save written before the button existed has no key, and
`.get("muted", false)` makes that audible rather than silent. `shot.gd` asserts
the press/unmute round-trip and the bus state, on a staged copy of the save.

## Sound effects

Seven one-shots, **six of them synthesised by `_mksfx.py`** (stdlib Python, seed
20260929) rather than generated. FlowMusic is a music model and ignores
`duration` — a 5s request comes back at two minutes — so it cannot make a
200ms die-clack. 45 KiB (46,338 bytes) for all seven, no licence, and they land
exactly on the event that asked for them. This said 43 KB until 2026-09-30, and
was wrong: the files were regenerated after that number was written — the decay
tightening and the tail fade below both landed in them — and nothing
recalculated it.

**The seventh does not come from that script, and this section used to claim it
did.** `_mksfx.py` builds `roll` from seven impacts and a 50 ms tail. Measured
against its own seed that is **0.509s**, and it cannot exceed **0.520s** under
*any* seed, because the per-impact jitter is 30 ms and there are seven of them.
The shipped `roll.ogg` is **0.711s** — `ffprobe` and the engine's `get_length()`
agree, and the duration gate below pins it there. No hit count from 5 to 14
produces 0.711s either (`range(11)` lands at 0.722s), so the file came from a
generator that is not in the repo.

Both were first committed together in `088a3f1` and neither has been edited
since, so this is **not** drift: the claim was false on arrival, and every
`git log` answer to "which one changed?" is the same commit. Regenerate the
other six with `python3 _mksfx.py` then the ffmpeg loop in its docstring — **but
not `roll`**, which would come out 0.2 s short and turn the duration gate below
red. The other six are not in doubt: `tap`, `strike`, `hurt`, `block`, `win` and
`lose` each equal what the script's own arithmetic produces, to the sample.

Every duration in the table below is now asserted by `shot.gd --check` against
the engine's own `get_length()`, and both beds against 40s, so the table cannot
drift the way that total did. That catches a file that has been replaced or
truncated, which loses a sound silently — the name still resolves. It does
**not** catch the defect described further down, where a file runs its full
length and stops still ringing; that needs decoded samples, not a length.

| file | dur | fires on |
|---|---|---|
| `audio/roll.ogg` | 0.71s | the opening roll, and the re-roll at −6 dB |
| `audio/tap.ogg` | 0.07s | any mode change on a card or a button |
| `audio/strike.ogg` | 0.22s | damage reaching the enemy |
| `audio/hurt.ogg` | 0.30s | damage getting past your block |
| `audio/block.ogg` | 0.34s | a roll that gained block, and a Focus spend |
| `audio/win.ogg` | 1.65s | beating the Devourer |
| `audio/lose.ogg` | 1.90s | the run ending |

Each is a damped ring plus a noise transient, and the ring's pitch *falls* as it
decays — that drop is what makes it read as an impact rather than a beep. The
two hits are deliberately tellable apart with your eyes shut: `strike` is bright
and short, `hurt` is low with a body thud under it. `hurt` fires only on damage
that got **through** block, so a full block does not thud like a killing blow.

**Every row above was checked against the call sites, and two of them were
wrong.** `roll`, `strike`, `hurt`, `win` and `lose` name every place they fire,
exactly. `tap` and `block` did not:

| sound | sites | what the table used to say |
|---|---|---|
| `tap` | 4 | queueing or unqueueing a die — one of the four |
| `block` | 2 | a roll that gained block — one of the two |

`tap` fires on queuing a die, banking a die, **arming** Focus and **arming**
Bank. So it is not a sound about dice at all; it is the interface's click, and
it marks *any* change of mode. That is the right design — one tick for "you have
switched something" — and the old row made it read as a semantic die sound,
which is the opposite. `block` also sounds on a Focus spend —
`_sfx("block", 2.0)` at `fight.gd:580` — which is coherent, since a Focus charge
converts to block, but it is not "a roll that gained block".

Neither was caught by reading, and neither is a typo: both rows were true of one
call site and silent about three. `test.gd`'s `_sfx_names` now walks every
`_sfx`/`play_sfx` call site and checks each name against `game.SFX` — the
direction `shot.gd`'s duration gate does not look, since it walks the keys and
not the callers.

`game.gd:play_sfx()` owns a 6-player pool and round-robins it, because a
clatter and a hit can overlap and one player would eat the other. Every player
stays on the Master bus, which is what the mute button flips — `shot.gd` asserts
that, so moving an effect to a bus of its own cannot silently escape the mute.
An unknown name returns without touching the pool, and is asserted too: a typo
would otherwise steal the next effect's player and cut it off.

**Verified without listening.** This machine's only audio driver is the dummy
one. So the effects were checked two ways: `ffprobe` on every file, and a 10ms
RMS profile over the raw WAV, which caught two real defects. `block` never
reached silence — its RMS fell near-linearly for the whole 0.34s and the file
stopped mid-ring, which is a swell that just cuts off. `win` and `lose` were
decaying through their full 1.65s and 1.90s and also ended still ringing.
Tightening `block`'s decay from 0.13 to 0.075, the finals from 0.34/0.40 to
0.22/0.26, and adding a 6ms tail fade in `_mksfx.py:write()` fixed both; all
seven now end on an exact zero sample. `shot.gd` then asserts the wiring: that
each event fires its own sound, that `block` fires **iff** the roll gained block,
and that the re-roll is quieter than the opening roll.

**Still unverified:** how any of it actually sounds. Everything above is
numerical. The numbers are consistent with correct, and they are not a substitute
for an ear.

## Assets

| File | Spec | Status |
|------|------|--------|
| `../icon.png` | 512×512 PNG with alpha, ≤1024 KB | 512×512 RGBA, 308 KiB |
| `feature.png` | 1024×500 PNG/JPG, no alpha | 1024×500 RGB PNG, 567 KiB |
| `screenshots/*.png` | 2–8, 16:9 or 9:16, ≥320px | 8 shots at 540×960 (9:16) |

The eight are checked against these specs by re-running `shot.gd`; the generator
flattens the alpha channel, because the viewport read-back is RGBA and Play
rejects that. Upload order is `01`…`08` as numbered.

That was the whole of the guarantee until `6539bb2`: it described the
*generator*, and said nothing about the files already in the folder. The table's
three rows were correct by hand and unchecked, so a re-shoot at the wrong size,
a screenshot with an alpha channel, or a ninth file dropped in would have
survived every gate and been rejected at upload. `shot.gd --check` now reads
them and asserts the count, each shot's size and lack of alpha, and both rows
below the screenshots — including that the icon keeps the alpha channel the
Play spec wants, which is the one asset where the answer is yes. It writes
nothing, so it runs in the gate loop above like the rest.

The alpha test is `Image.get_format()`, not `Image.detect_alpha()`. The second
inspects pixel values rather than the channel, so it calls `icon.png` opaque --
all 512×512 of it -- and would equally have passed a screenshot carrying a fully
opaque alpha channel, which is exactly what Play rejects. `FORMAT_RGB8` is no
alpha, `FORMAT_RGBA8` is alpha, and the two assets differ by precisely that.

Play caps screenshots at 8, and there were 9 until 2026-09-29: `01-title-first-
launch` was moved to `screenshots-spare/` and the rest renumbered, on the grounds
that it and `02-title-pick-your-hand` are both title screens at near-identical
file size, and the slot was worth more to the armoured-fight shot. The spare is
there if you disagree.

**Six of the eight screenshots show a UI this repository has never contained.**
Not stale — that word is wrong, and it is the word a reader would stop at. The six
are `01`, `02`, `05`, `06`, `07` and `08`, and they are exactly the six files that
are byte-identical to `088a3f1`. The only genuine renders are `03` and `04`, which
another session re-shot after the code moved on. **Two of the eight images Play
will display are pictures of this game.**

They show three screens the project has never drawn. A title: `A RUN OF NINE
FIGHTS`, `CHOOSE YOUR HAND`, `Unlocks at 1 / 3 finished runs`, `BEGIN THE RUN`, and
a hand of MOUND / SHARD / TALON where the real catalogue is Blade, Sunder, Ward,
Hex, Riposte, Spark, Fang (`dice.gd:350-396`). A fight: `DEPTH 1 OF 9`, `FIGHT 1`,
`GRUNT`, `DEATH ROLL`, `TAP TO ROLL`, `SHUNT`, `11 days left`, `REROLL 1`, `END
TURN`. A reward and an end: `THE OFFER — 1 OF 3`, `TAKE ONE`, `RUN 2/9   DIED TO:
GRUNT`, `RUN OVER`, `DEPTH REACHED 5 OF 9`, `COPY RESULT`.

**`08` is the worst case, because it is almost right.** It shows `DEPTH 4 OF 9`
against `WARDEN`, and the ladder has no Warden anywhere: the nine names are Grunt,
Rust Golem, Bloodletter, Hexweaver, Ironhide, Stone Sentinel, Fungal Bloomer,
Berserker, The Devourer (`run.gd:146-158`). The labels are 1-indexed — `02` pairs
`DEPTH 1 OF 9` with `GRUNT`, which is index 0 — so `DEPTH 4 OF 9` is the
Hexweaver slot and `Ironhide` would read `DEPTH 5 OF 9`. `run.gd:620-628` asserts
four of those names against the behaviour each implies. A plausible screen with the
wrong monster in it is worse than an obviously broken one, because it survives a
skim.

Three findings make this provable rather than suspected. First, none of it can be
assembled at runtime: every button assigns its label verbatim — `b.text = text` at `theme.gd:144` and `fight.gd:421` — so `END TURN` is not `End turn` uppercased
and `TAP TO ROLL` is not `Roll`. `F_DISPLAY` (`theme.gd:36`) is a font *size*, not a
case transform. Every label is a literal, and these literals are absent; the
case-insensitive hits that do exist are prose, e.g. `shot.gd:405` is
`_ergonomics(game, "run over")`, a check name on the check that proves the real
run-over screen is still reachable. Second, the shapes are wrong too, not just the
words: the fight screen's button row is `Roll`, `Focus`, `Bank`, `Re-roll`, `End
turn` — five across, opening at `roll_btn = _mk_button(btns, "Roll", T.GOLD)` at `fight.gd:320` — where `02` and `08` each show two; the
re-roll widens to `Re-roll (%d)` (`fight.gd:1163`), never `REROLL 1`; and the status
line is `block %d     re-rolls %d     focus %d     turn %d` (`fight.gd:1130`), not
`FIGHT 1` or `DEATH ROLL`. Third, the timing rules out "an older render of a screen
that has since changed": `git log --since='2026-09-30 14:51' -- game.gd` is
**empty**, and `git diff` on `game.gd` is 29 insertions of comments plus one
`100`→`146` layout literal.

All six are byte-identical to `088a3f1`, the initial commit (2026-09-30 04:49) —
the same commit that first added `shot.gd`. Their 14:50 mtimes are the checkout's,
not a render's, so the directory already carried these images when the project was
first committed and no run since has replaced them.
`screenshots-spare/01-title-first-launch.png` is byte-identical too;
`09-fight-impact.png` is not.

A forensic check that looked decisive is not, and is recorded here so it is not
re-run: PNG IDAT chunk count tracks compressed size, not encoder, and comes out 4,
5 or 6 across all ten files, so it separates nothing. All ten do share 8192-byte
IDATs and an `sRGB` chunk — one libpng build wrote them all — so encoder identity
is not a discriminator either. Only the strings are.

`_check_store_art` cannot catch this, and the honest reason is worth more than a
patch that pretends otherwise: it asserts count, dimensions and alpha, which are
the things Play rejects an upload *over*. Content freshness is not in that set.
`shot.gd:398/406/420` still call `_grab(5, "reward-pick-one")`, `_grab(6,
"run-over")` and `_grab(7, "share-result")`, so a re-shoot produces correct images
— but a green `_check_store_art` says nothing about whether the bytes on disk are
the ones the generator produced, and that is the gap. A mtime check would not close
it either: it is green on a fresh clone, which is the check that cannot fail.

**Re-shoot before uploading, and treat it as a blocker rather than a chore.**
`_grab` rewrites the whole folder, which is why this was never done per-screen as
things changed: it would overwrite `03` and `04`, which are another session's
uncommitted work. That leaves nothing safe to do from inside this tree, so the
re-shoot is that session's call or yours — not something to route around.

## Short description (80 char limit)

```
Nine fights. One pool of dice. Roll, spend your re-roll, and take what you can.
```

That is 79 characters of the 80 Play allows, so the next reword has one to
spare. Both text blocks are length-checked
by `shot.gd --check` (`_check_listing_text`), which prints each count on every
run and fails on the cap — so rewording either block cannot quietly walk past a
limit that only shows up when the console rejects an upload.

## Full description (4000 char limit)

Play has no keyword field. The title, these two text blocks, the developer name
and your review text are the *entire* indexable surface, so the genre words live
here — placed once each, in the opening where they read as prose rather than as
a list. Repetition is a violation risk, so they are not used twice.

Nine claims in this block have been corrected, all after measuring the code
rather than after reading it. The first two are pinned in `run.gd`'s
`self_test`; the rest are checked where the copy itself lives, in `shot.gd`'s
`_check_copy_claims`, which is the only function holding the text — a check in
`run.gd` would have to re-read the file to say anything about what the file
says.

**"Every player gets the same dice and the same enemies on the same day" was
half wrong.** The daily seeds exactly one thing per run — `game.gd:_start`
seeds the global rng off the day, and `Run._init` shuffles `order` from it — so
two players on one day fight the same nine in the same order. The *hand* is
never seeded: it is the player's own pool, and the rolls come from a separate
rng that `fight.gd` randomises on every fight. The obvious guess is that a
veteran's bonus dice make their daily a different fight, and that guess is
wrong for a more interesting reason: `set_loadout` trims to `POOL_SIZE` taking
the library first, so a player on their fourth run rolls the same four starters
as a fresh install. Only a hand *chosen* at the title screen changes it. The
block now says "The dice are the ones you brought."

**"Every finished run unlocks another die" stopped being true from the fourth
run on.** `record_run` increments `unlocked` with `mini(..., 3)` and
`bonus_dice()` holds exactly three, so the fourth finished run unlocks nothing.
`game.gd` had always said so correctly ("the four starters plus the three a
finished run unlocks"); only the store copy dropped the qualifier. Note that
the test pinning this needed a *fourth* `record_run` to fail against an
uncapped build — three runs leave the counter at 3 either way, so a check
placed at the third is a check that cannot fail.

**"You are reading five numbers" described the upgraded state as the default.**
`POOL_SIZE` is 4 and New Die adds exactly one, so a hand is four until a player
takes a card whose text has no number on it. Measured across 2439 bot fights:
**99.9% were four, and 3 were five** — only 0.7% of runs ever took New Die at
all, because `_weak_pick` chooses on the biggest headline number and "Add one
of your unlocked dice." has none. (That card's text was itself wrong and has
been corrected — see "New Die was offering a die that does not exist" below. It
is still deliberately number-free, so the 0.7% still stands.) The copy
contradicted itself two paragraphs
earlier by correctly saying "Add a fifth die to the pool"; that sentence is what
made four the default and this one disagreed with it.

**"Each face is damage, block, or a bonus re-roll" was false for 3 of the 42
faces.** Sunder carries two faces and Riposte one, all labelled `rust`/`fend`
and all `(0, 0, 0)` — they are the *natural* worst face on those dice, not an
overlay. So 7.1% of the roster is a roll that gives you nothing, and this block
also said "Hexweaver curses one of your dice to nothing." Two sentences, one
section apart, flatly disagreeing.

**And the sentence that replaced it was false too, in the same way.** "A few
faces are nothing at all, which is exactly what Hexweaver reaches for" — no.
`BEH_CURSE` picks a die at random and drops it on *that die's* lowest-`worth()`
face, which is a nothing on Sunder and nowhere else: Blade's is a plain `2`,
Ward's a `2` that blocks instead of striking, Hex's a `1`. Measured by writing
the copy's own claim as a check and letting the gate decide, which failed on
exactly those three. The clause is now "A few faces are nothing at all", and the
enemy's own line says what it does: "drags one of your dice down to its worst
face". The two halves of the earlier fix — the face count, which was right, and
the Hexweaver claim, which was not — had to be separated before either could be
correct. `run.gd`'s `self_test` now asserts the half that can drift.

All three are the same failure and worth naming: **length was checked and
accuracy
was not.** The block now sits at 3153 of Play's 4000 characters — the 2854 in
the first draft of this note was true when written, and each of 3046 and 3121
was left behind by the corrections above, 66 out and then 32 out, which is the
same drift it describes, one level down — and every word of it
is a claim about the game, and nothing read those words back against the code.
The first two are internally consistent — each contradicts a *later* sentence
in the same block — which is the hardest kind of wrong to catch by reading and
the easiest to ship. The third is worse than either: it was the *repair*, and
repaired copy gets read as settled. `_check_copy_claims` now builds each numeric
claim from the
constant that owns it, so moving `POOL_SIZE` or `FINAL_DEPTH` or the boss's
health turns its row red instead of leaving the prose behind.

**The next two were the same mistake a third time: a *starting* value written as
a permanent one.**

*"Each fight gives you one Focus and one Bank"* is true of Focus and false of
Bank, and they are not the same kind of thing. Focus is a per-fight charge —
`roll_all` resets `rerolls_left` but not `focus_left`, and there is a test that
a roll does not refill it. Bank has no per-fight cap at all: a hold survives the
roll it was made for, pays on that resolve, clears `banked`, and `toggle_bank`
refuses only a spent or out-of-range die. `_bank_budget_tests` takes three holds
in a single fight and all three pay. Read as one-per-fight, Bank is the weakest
version of the mechanic, and that is the expensive direction to be wrong in —
the reader stops looking for the option.

*"Rust Golem grows its armour every turn until you break through it"* — it stops
whether or not you break through, at `ARMOR_GROW_CAP` = 12, from a starting
armour of 3. **48.5% of real depth-1 fights reach that ceiling** (400 fights,
avg 16 turns, final armour 9.7). Treat that as an *upper* bound: the bot that
measured it never spends Focus or Bank, so a player who does would break the
Golem sooner and meet the wall less. The claim was still wrong as a statement
of the rule, and the ceiling is the more interesting fact besides — 12 is where
it stops precisely because Sunder's `cleave` 12 sits just above it.

One measurement from this round was thrown away rather than reported. The first
Golem probe set the enemy to 999999 health so fights would last long enough to
time, and all 400 then sat out the full 40-turn limit and "reached the cap" by
construction — 100%, a clean number that measured the probe rather than the
game. A real fight has to be played to its real ending.

**"One re-roll for the whole hand" was false twice over, and the second reason
was a bug in the game rather than in the sentence.** `base_rerolls` is 1, so
the copy was right about the number and wrong about the total, for two
independent reasons. FOCUS ("+1 re-roll every turn") raises the *base*, so a run
holding it opens on two or more — 16.3% of 12048 turns across 300 bot runs. And
the *earned* bonus re-roll was unreachable until this round's fix to `dice.gd`: a
Hex 4/5/6 or one of Spark's two spark faces granted one on the resolve, where
`fight.gd` had already cleared the roll and the next `roll_all` reset the
budget, so it was logged and discarded — 44.6% of turns now open holding one the
run had not bought. Between them, 53.5% of turns open with two or more. The
block now says "You get one re-roll a turn, so spend it or lose it — and rolling
well earns you another for the next one", and `_check_copy_claims` asserts both
halves plus a negation row over the three phrasings it used to claim, because a
check that only asserts the new phrase sits happily over the old ones.

**"New Die was offering a die that does not exist."** The card read "Add a wild
die to your pool." What it adds is one of `bonus_dice()` — Riposte, Spark or
Fang, the three a finished run unlocks — and nothing in the roster is wild. A
player who took it expecting a blank to shape got a named die with fixed faces.
The store copy had independently softened the same card to "Add a fifth die to
the pool", which is *true* and so hid the lie rather than fixing it. The card
now reads "Add one of your unlocked dice."

**"The next one starts with a fuller hand" was the ninth, and the only one where
the false half is not the number.** The count beside it was right — `unlocked`
caps at three, and `_check_copy_claims` pins that half today — and the sentence
then spent eleven words on a consequence that does not happen. `owned_dice()`
really does grow to seven: four starters plus one per finished run. But
`set_loadout` trims whatever it is handed to `POOL_SIZE` and tops it back up,
and `game.gd`'s title picker refuses to add past `POOL_SIZE` as well (it renders
`pool.size() / POOL_SIZE`, so the cap is on screen). **Every run in the game
opens on four dice**, so a die you have earned is one you can *pick* at the
title, not one that is dealt to you.

The reason this one survived eight others is worth writing down, because it is
the same contradiction shape and a *later* sentence gave it away. Four lines
below the false clause the block says "past four, the only way wider is a New
Die taken between fights" — which is only true if unlocking does *not* widen the
hand. Both sentences were sitting in the shipped copy at once, one contradicting
the other, and the file's own method for finding these ("each contradicts a
*later* sentence in the same block") is what caught it. Reading for it alone
would not have: both halves are individually reasonable sentences.

What every other one in this list had in common was that the *number* was the
lie. This one's number was true and the inference drawn from it was not, which
is why `_check_copy_claims` — a check that reads sentences — could pin the other
eight and not this one: the row `["your first three finished runs each", "the
unlock cap is three"]` was green throughout, because it was checking the half
that was true. The invariant now lives in `run.gd::_check_fuller_hand_claim`,
where it is stated against the code rather than against this file, with a
liveness check in front of it so it cannot pass on a build where unlocking is
broken. `_check_copy_claims` gained the replacement phrase and a negation row
over "starts with a fuller hand".

The rest of the block was audited the same way and holds, so it is listed here
once rather than re-derived: `run.gd`'s `self_test` now asserts the four named
enemies' names *and* the behaviour each is described as having, plus the boss's
78 health, 5 armour and enrage — retag Bloodletter or rebalance the Devourer and
the suite goes red. Now checked by `_check_copy_claims` rather than by eye:
"nine fights" (`FINAL_DEPTH + 1`), "four dice" and "four numbers"
(`POOL_SIZE`), "add a fifth die", "one of three upgrades", "your first three
finished runs", the boss's 78 health, the one Focus per fight (`base_focus`),
Bank being uncapped, the Golem's ceiling (`ARMOR_GROW_CAP`), the one re-roll a
turn (`base_rerolls`), the sentence that a good roll earns the next one, and the
unlock phrasing ("unlock a die you can pick at the title") with a negation row
over "starts with a fuller hand". The
re-roll pair also has a negation row over "single re-roll", "re-roll once" and
"one re-roll for the whole hand", and the two categorical roster claims now
walk `library() + bonus_dice()` directly: the copy's "a few faces are nothing
at all" holds only while faces worth nothing still exist, and "rolling well
earns you another" only while faces that hand out a re-roll do. Bank's
cadence is additionally pinned in `dice.gd` by `_bank_budget_tests`, which
takes three holds in one fight, so the copy is not the only thing asserting it.
Still checked by hand only: "playable offline" — there is no `http`, `socket`
or `request` call in any script in this repo, only three hits and all three are
the word inside a comment (two in `_balance.gd`, which does not ship, and one in
`game.gd`'s header) — and the upgrade names "Sharpen"/"Bless"/"New Die", which do match
the `UPGRADES` table word for word. The *descriptions* beside them do not, and
until this round that was recorded as a single claim about all three, which was
false: the store copy says "Sharpen every damage face" where the table says
"Every damage face +1.", and the third turned out to be outright wrong (see
"New Die" above). The names are now separated from the descriptions so the
next drift cannot hide behind one true half.

The "still checked by hand only" list is not a list of things that are fine. It
is the remaining work: every entry is a claim a constant owns and a one-line
row in `_check_copy_claims` would pin. It was a three-entry list, and **two of
the three were false** — the one re-roll, and the word-for-word match. Both had
been read, both had looked right, and "read it and it holds" is exactly the
method that let them through. "playable offline" is what is left, and it is the
only entry that has now been checked against the tree rather than against the
eye — `grep -n 'HTTPRequest\|http\|socket\|request' *.gd main.tscn` is three
lines, all comments, zero calls, so the claim holds. Its own count was wrong
while the claim was right, which is the ninth one's lesson arriving one entry
early: it said two hits and there are three, and it counted a dev tool as a
shipped script. The lesson generalises past this list: the claims that survived were the
ones with a number in them, and every claim that turned out to be false was one
whose number was a *starting* value, a *base* value, or not a number at all.

Two things in the block stay unverifiable from here and are the owner's to set
in the Console, not code claims: the "no ads / no in-app purchases" lines and
the developer's own name and review text.

**The same method then found a false claim on a different surface — the upgrade
cards themselves — and nothing in the repo was checking that surface at all.**
`ADD_DIE` was caught by reading it against the code; the other eleven were not
read that way, and `PRECISE_STRIKE` did not survive it. Its description read
*"A hit of 10+ leaves it exposed: your hits on it count for half again"*, which
describes a standing debuff. `dice.gd` spends the window in the next resolve
(`enemy.exposed = maxi(0, enemy.exposed - 1)`) and the section comment above
those tests puts it in as many words — *"a hit of EXPOSE_AT makes the next
turn's hits worth half again, and no longer"* — so a player picking this card
would have believed the
enemy stayed weak rather than buying one turn of it. The copy now says "for one
turn". It is the wild die again: a card promising something the rules do not do.
The other ten hold on the same pass; `REFORGE` is loose rather than false (it
raises the weakest face of a **random** one of your dice, not your weakest die)
and is left alone, because the code's own comment describes it the same way and
that is a wording call, not a contradiction.

**"The other ten hold on the same pass" did not hold, and checking it the way
that sentence was checked is what proved it.** `BULWARK` read *"Reflect 4 damage
when struck"*, and thorns fire on `hit > 0` — `soaked = mini(block, enemy.atk)`,
so an attack the player fully blocks reflects nothing. The rule is defensible;
there was no strike to reflect. The sentence was not: a player holding a Ward is
doing the one thing that suppresses this card, and the card did not say so. It is
`PRECISE_STRIKE`'s shape exactly, and the game already knew the distinction —
`hurt.ogg` "fires only on damage that got **through** block, so a full block does
not thud like a killing blow", written a screen away. The card now says "Reflect
4 damage when hit. A full block stops it."

The reason ten survived a pass and this one did not is worth recording. Reading a
card against the code is the method, and it worked here — but "reflects when
struck" and "reflects when hit" differ by a word, and both readings are
*supported* by the code until you go looking for what `hit` is computed from.
Nothing about the sentence announced itself as wrong the way "your weakest die"
and "half again, and no longer" did. Those had a contradiction inside them.

And reading it turned up something the copy never had: **a live exploit, on the
same card.** `_bastion_tests` asserted "releasing it does not pay again" and
passed — but "does not pay again" was checked as *the release is not a gain*, and
the release **kept** the payment, which is the same state as a free hold. Ten
on/off taps on one unspent die was **40 block in a single turn**, with nothing
anywhere capping `block`. The test had never re-taken a released die, and
displacement was overpaying from the other side (it kept the first die's 4 *and*
added the second's, so one decision paid twice). A release now gives the block
back, in both places `banked` is cleared.

Two details that were wrong in the fix before they were right in it. The refund
has to read `bank_carried`, because a die held at the end of last turn already
paid into a block the enemy's turn then spent — refunding that one claws 4 out
of block the player earned *this* turn. And the refund has to run *before* that
flag is cleared, so it can still see it. Both are checked; the second by the
ordering of the calls, which is why the comment at the call site says so.

The generalisation is the one this file keeps arriving at, and this time the
evidence is a check that **passed**: a test naming the mechanism it does not
test is worse than no test, because it is the one a reader checks and stops.
"Does not pay again" reads like it covers release; it covered the sign of the
change, not its size.

**And the last one was the *anchor*, one paragraph from a sentence already
repaired.** "You are not managing a timer or a stat bar" made the same promise
this file's own upgrades paragraph had already withdrawn — MEND heals 14, VIGOR
grants +8 max health — thirty lines below the correction, on a screen carrying
two `ProgressBar`s (`enemy_bar` at `fight.gd:243`, `player_bar` at `:298`).
`_store_copy` should have stopped it and did not, because it asserted
`"not a stat bar" not in text` and this sentence reads *"not managing a timer **or
a stat bar**"* — the substring is simply absent. Re-anchored on the noun.

That is the fourth time this sweep has found a second occurrence of something
already repaired once (`capitalize()` on two lines, the article-doubled title on
three, the stat-bar absolute on two). In every case the repair was right and the
**anchor** was what failed, which is the same generalisation as the passage above
one level up: a check names what it was told to look for, and re-reading the
thing that was complained about only ever confirms it is gone.

The method that finds these is enumerating *every* quantitative sentence in the
block and checking each — thirty-one came back this round, against one reported
defect. The rest were verified against code and several by measuring rather than
reading: the audio table's "45 KiB (46,338 bytes)" is the exact sum of the seven
SFX, and both beds match to the byte.

Copy now reads "No timer, and nothing to grind: you are reading four numbers and
choosing which one to bet. Health is the one number that ends the run" — true,
and it keeps the four counters the HUD prints while conceding the one bar the
game really has.

```
Nine fights stand between you and The Devourer. You bring four dice.

That is the whole game. Roll them, read the faces, and decide which ones were
not worth the roll. You get one re-roll a turn, so spend it or lose it — and
rolling well earns you another for the next one. Then end the turn and watch
what the thing across from you does about it.

Between fights you take one of three upgrades, and they change your dice or the
rules you roll them under — only two of the twelve buy hit points back. Sharpen
every damage face. Bless every block face. Add a fifth die to the pool. Most
reshape how the hand plays out, so two runs never feel the same.

A turn-based roguelike, built around a puzzle

Every turn is one decision — which dice were wasted, and which of those you can
afford to roll again. That is the strategy, and it is the whole strategy. No
timer, and nothing to grind: you are reading four numbers and choosing which one
to bet. Health is the one number that ends the run.

How a turn works

You roll every die in your pool at once. Each face is damage, block, or a
bonus re-roll. A few faces are nothing at all. Tap any dice you are unhappy
with to queue them, spend the
turn's re-roll, and then everything you are holding resolves together —
so you commit before you know how it lands. Your damage goes through the
enemy's armour, and what it hits first, you. Enemies answer every turn, and the
ones that survive long enough get worse at what they do.

Two ways out of a bad hand

Each fight gives you one Focus. Bank is not limited like that — you can hold a
die on every turn. They are not the same kind of promise. Focus steps a die up
to the next better face on that die: certain, and it costs you the die for the
rest of the turn, and there is exactly one charge per fight. Bank does not
improve anything: it holds a die back whole, out of this turn and into the
next. One is a single guaranteed step, the other a repeatable bet that next
turn is a better hand than this one.

What is in it

Nine hand-built fights. Rust Golem grows its armour every turn, to a ceiling of
twelve — break through it before it gets there. Bloodletter heals off what it
deals to you. Hexweaver drags one of your dice down to its worst face —
Sunder's is the `rust` that deals nothing, Blade's is a plain 2. Berserker gets angrier
the longer it lives. The Devourer is armoured and enraged and it has 78 health.

A daily run

Every player gets the same nine enemies, in the same order, on the same day.
The dice are the ones you brought. There is nothing to grind toward and nothing
to buy — just the same fight everyone else is having, and a result worth
comparing.

Your best run is saved

Depth reached, runs played, victories kept. Your first three finished runs each
unlock a die you can pick at the title — but a run always opens on four, so past
four the only way wider is a New Die taken between fights. The run ends when your
health does.

One thumb, no menu

Built for one hand in portrait, and playable offline. No tutorial, no currency,
no timers, no ads, no accounts. No in-app purchases. One decision per turn and
you are already playing.
```

## Category and tags

- Category: Games / Casual
- Content rating: everyone
- Contains ads: **no**
- In-app purchases: **no**

## Release checklist

- [ ] Upload the **release**-signed AAB.
      **Check the preset is back on AAB before building this.** PLAN 4.1's
      sideload needs an APK, and the Android preset has exactly one
      `export_path` (line 44) and one `gradle_build/export_format` (line 59), so
      exporting for a device means pointing both at the `.apk` and setting the
      format to `0` first. **The format enum runs backwards — `0` is the APK and
      `1` is the AAB**, so the committed values are already correct for Play and
      a well-meaning "fix" here would produce an APK that Play rejects. After the
      hardware pass, put both lines back to the committed values —
      `export_path="build/android/dicefate.aab"` and `export_format=1` — and
      check that with `git diff export_presets.cfg`, which is the whole check.
      Neither line is a credential, and the keystore block at lines 79–81 is
      shared, not copied. Details and the measurements in PLAN.md 4.1.
      **Both** AABs in `build/android/` are release-signed — checked with
      `keytool -printcert -jarfile`, owner and issuer `CN=Dice Spike,
      OU=Games, O=DiceSpike, L=Unknown, ST=Unknown, C=US`, valid from
      2026-09-28. A debug-signed build would say `CN=Android Debug`, and
      neither does. An earlier version of this checklist said
      `dicefate.aab` was debug-signed and Play would reject it; that was
      wrong, and it was acted on — so do not skip the upload on that basis.
      **They are not the same build**, which this note previously said they
      were — that is how they drifted apart in the first place. Checked by
      unzipping each: `dicefate.aab` (2026-09-30) ships 6 compiled scripts,
      `dicefate-release.aab` (2026-09-29) ships 5 and has no `_check.*`. Not a
      packaging fault: `_check.gd` was written 2026-09-30 04:53, a day *after*
      the older AAB was built, so nothing in it refers to the file and it is
      internally consistent. It is simply the pre-Phase-3 build. **Upload
      `dicefate.aab`.** Re-run `godot --headless --path . -s _pack.gd --
      Android` after any rebuild; it checks the export and boots the pack.
      This is gate 5, and it is now in PLAN.md's gate loop too — run there as
      well, because gates 1–4 run from source and cannot see an export filter
      drop a file at all. It writes `/tmp/_pack_probe.pck`, so it needs a
      writable `/tmp`; nothing in the repo is touched.

      > **But it is seven executable commits behind HEAD (corrected
      > 2026-10-02, was "five" — which was itself corrected 2026-09-30 from
      > "one"), and the upload should be a decision.**
      > `dicefate.aab` was built at **06:54:37**, sixteen minutes after Phase 3
      > landed. Seven commits after that build changed shipped code, across all
      > four gameplay scripts:
      >
      > | commit | what a player would not get |
      > |---|---|
      > | `79de3f5` | the touch-target fix — `custom_minimum_size` goes `0, 54` → larger |
      > | `73238fe` | three controls the ergonomics gate had never looked at |
      > | `d035c37` | the named boss threshold and the boss haptic |
      > | `599baac` | item 7: Fang's top face, `18` → a `15` carrying `pierce 6`, and the BEST HIT preview that was hiding its pierce |
      > | `d6b3073` | the SFX pool size, which had claimed headroom nothing checked |
      > | `3b0d28a` | the ADD_DIE reward, which was inert for every player already holding all three bonus dice |
      > | `87afe50` | the MEND reward, dealt at full health about a quarter of the time and worth nothing |
      >
      > `20fe68a` touches `game.gd` too but is 2 lines and comment-level.
      > The earlier version of this note said "one executable commit" and named
      > only item 7, which was true of `dice.gd` alone and wrong everywhere
      > else: scoping the claim to one file is what hid the other four at the
      > time, and two more player-facing commits have landed since.
      >
      > **Those seven are seven of THIRTEEN, and the other six are counted
      > rather than quietly dropped, because `git log --since=<build> -- game.gd
      > fight.gd dice.gd run.gd theme.gd main.tscn` returns all thirteen and
      > stops you knowing which is which.** Three of the six are comment-only
      > rewrites — `20fe68a`, `acf1da9`, `ffc7d87`, at 2, 0 and 0 code lines.
      > `acf1da9` is the one most likely to be miscounted: its subject reads
      > "item 7's trigger rate was measured blind" and it touches `dice.gd`, but
      > its entire diff (`+14/-7`) is `##` prose. Judging by subject, or by
      > `+N/-M` on a diff that is mostly `##`, is how a note like this drifts —
      > the count of seven is only defensible against a measured split.
      >
      > The next two (`8fdf773`, `642ed5d`) are 47 non-comment lines between
      > them and still change nothing a player loads: every one is inside
      > `RunState.self_test`, and `test.gd:24-25` is its only caller, so the gap
      > held at five across those. The three after them did not. `3b0d28a` and
      > `87afe50` are both inside `roll_rewards` and both player-facing.
      > `992f0a4` reads like a fix and is not one: its subject says the Golem's
      > wall "has a ceiling", but its entire `dice.gd` diff is the new
      > `_bank_budget_tests` plus that function's own comment, and its other two
      > files are `shot.gd` and this note. It *measures* the wall, it does not
      > change it. Counting its diff lines without applying the rule two
      > paragraphs up — test-only commits change nothing a player loads — would
      > have made the count eight.
      >
      > **The gap is a floor, not a total: the working tree is uncommitted.**
      > The checkout's `dice.gd` carries a fix no commit has. Holding and then
      > releasing the same die paid BASTION's 4 block on every tap and nothing
      > anywhere capped `block`, so ten tap-pairs on one unspent die banked 40
      > block inside a single turn. That is a gameplay change, it is player-
      > facing, and it is not in `992f0a4` — so seven is what the committed
      > history proves and the real distance is larger by at least one fix.
      >
      > **The touch-target row is the one that matters for a hardware pass.**
      > The artifact still carries `custom_minimum_size = Vector2(0, 54)`, the
      > size `79de3f5` changed precisely because it "cleared 540dp and failed on
      > every other phone". PLAN 4.1's hardware leg is to validate touch
      > ergonomics for Focus, Bank and Re-roll, so validating that on this
      > bundle tests the known-broken size rather than the fix.
      >
      > On difficulty the gap is genuinely neutral: item 7 moved `<random>`
      > 16.5% → 16.4% with every row within 0.5pp, and the other four do not
      > touch the rules at all. So nothing is *broken* by uploading it — the
      > build and the repo simply no longer agree, and that is what this note
      > is for.
      >
      > **Do not silently rebuild under `versionCode` 5.** Play rejects a
      > second upload reusing a code, *and a rejected upload still counts as
      > uploaded* — so if 5 was ever submitted, rebuilding in place strands
      > the next upload. The order is: bump `version/code` past anything ever
      > submitted, rebuild, then upload. If 5 was never uploaded, rebuilding
      > it as-is is correct and costs nothing.
      >
      > **Method note for whoever re-checks this.** Comparing the two AABs by
      > size and md5 is the check that works — `dice.gdc` 27,865 vs 9,918,
      > `fight.gdc` 20,178 vs 15,007, `run.gdc` 14,830 vs 12,074, and 6
      > scripts vs 5. Do **not** grep the compiled `.gdc` for a known string
      > to decide what is inside: `"Devourer"` is absent from *both* AABs, and
      > so is `"pierce 6"` from the newer, so the search returns "absent" for
      > every needle and proves nothing. An earlier pass in this session
      > reported "no item-7 markers in the shipped bytecode" from exactly that
      > method and would have been a confident wrong answer — the control
      > string is what turned it into a non-answer.
- [ ] `versionCode` must be strictly higher than any version ever uploaded for
      `com.dicespike.game`, including drafts and rejected uploads. It lives in
      `export_presets.cfg` as `version/code` under the Android preset — **not**
      in `project.godot`, which an earlier version of this note claimed. It is
      now 5, bumped 2026-09-30 in the same commit that fixed the export filter,
      because that is the build which first carried the Phase 3 work. 5 is
      correct only if nothing above it has ever been uploaded. Bump it and
      rebuild if in doubt; a rejected upload still counts as uploaded.
- [ ] The listing ID `com.dicespike.game` is permanent once created.
- [ ] **The release keystore password is published, not merely committed.**
      `export_presets.cfg` holds it in plaintext at line 81
      (`keystore/release_password`), and this note said to gitignore the file
      *before* `git init`. `git init` has since happened. The password is in
      history at `088a3f1`, and `088a3f1` is an ancestor of both
      `refs/remotes/origin/main` and `refs/remotes/origin/master`, so **it is
      on GitHub today** — at `github.com/locionic/make-games`.
      An earlier version of this note said "There is no remote, so nothing has
      left the machine". That was wrong, and it was the sentence that made this
      look safe: it is the one a reader would have stopped at. Verified
      2026-10-02 with `git remote -v` and `git merge-base --is-ancestor`.
      **Rotate the key.** That is the only fix that helps — rewriting history
      removes the copy from GitHub's reachable commits but leaves a live
      signing credential in every clone, and any fork or cache keeps it.
      Rotating first makes the published value inert; the history cleanup is
      then just tidying. Reading it from an environment variable afterwards
      stops the next commit re-publishing it.
