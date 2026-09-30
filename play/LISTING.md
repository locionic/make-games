# Dice Fate — Google Play listing

Screenshots are regenerable:

    xvfb-run -a godot --path . --rendering-driver opengl3 -s shot.gd   # screenshots/

`res://icon.png` (the launcher icon) ships in the APK; everything in this
folder is store art only, kept out of the build by `.gdignore`.

**`icon.png` and `feature.png` are not regenerable.** Both were replaced on
2026-09-29 with art generated through OmniFlash (`POST /generate/image` on
`localhost:8080`), and the originals are kept beside them as `*.bak-flat` — at
8.4 KB and 17.3 KB they were near-flat fills, which is why they were replaced.
`icon.gd` still exists and still draws a code-only feature graphic, but it is
now the *fallback*: running it will overwrite the generated `feature.png`. Copy
it back from `*.bak-flat` if you want the original, not the replacement.

Note when scripting against that API: `/generate/image?download=true` returns a
JPEG whatever the response filename says, so the 24-bit PNG Play wants has to be
re-encoded from the JPEG.

## Audio

Not a store asset, but it ships and it is the biggest change to the game since
the roguelike loop landed. Two 40s seamless loops in `audio/`, generated through
FlowMusic2API on 2026-09-29 with the `lyria-fast` and `lyria` models:

| file | source | size | plays on |
|---|---|---|---|
| `audio/menu.ogg` | 177s m4a, cut and crossfaded to 40s | 527 KB | title, reward, run over |
| `audio/combat.ogg` | 176s m4a, cut and crossfaded to 40s | 549 KB | the fight panel |

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

Seven one-shots, **synthesised by `_mksfx.py`** (stdlib Python, seed 20260929)
rather than generated. FlowMusic is a music model and ignores `duration` — a 5s
request comes back at two minutes — so it cannot make a 200ms die-clack. 45 KiB
(46,338 bytes) for all seven, no licence, and they land exactly on the event that
asked for them. Regenerate with `python3 _mksfx.py` then the ffmpeg loop in its
docstring. This said 43 KB until 2026-09-30, and was wrong: the files were
regenerated after that number was written — the decay tightening and the tail
fade below both landed in them — and nothing recalculated it.

Every duration in the table below is now asserted by `shot.gd --check` against
the engine's own `get_length()`, and both beds against 40s, so the table cannot
drift the way that total did. That catches a file that has been replaced or
truncated, which loses a sound silently — the name still resolves. It does
**not** catch the defect described further down, where a file runs its full
length and stops still ringing; that needs decoded samples, not a length.

| file | dur | fires on |
|---|---|---|
| `audio/roll.ogg` | 0.71s | the opening roll, and the re-roll at −6 dB |
| `audio/tap.ogg` | 0.07s | queueing or unqueueing a die |
| `audio/strike.ogg` | 0.22s | damage reaching the enemy |
| `audio/hurt.ogg` | 0.30s | damage getting past your block |
| `audio/block.ogg` | 0.34s | a roll that gained block |
| `audio/win.ogg` | 1.65s | beating the Devourer |
| `audio/lose.ogg` | 1.90s | the run ending |

Each is a damped ring plus a noise transient, and the ring's pitch *falls* as it
decays — that drop is what makes it read as an impact rather than a beep. The
two hits are deliberately tellable apart with your eyes shut: `strike` is bright
and short, `hurt` is low with a body thud under it. `hurt` fires only on damage
that got **through** block, so a full block does not thud like a killing blow.

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
| `../icon.png` | 512×512 PNG with alpha, ≤1024 KB | 512×512 RGBA, 308 KB |
| `feature.png` | 1024×500 PNG/JPG, no alpha | 1024×500 RGB PNG, 567 KB |
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

## Short description (80 char limit)

```
Nine fights. One pool of dice. Roll, re-roll once, and take what you can.
```

That is 73 characters of the 80 Play allows. Both text blocks are length-checked
by `shot.gd --check` (`_check_listing_text`), which prints each count on every
run and fails on the cap — so rewording either block cannot quietly walk past a
limit that only shows up when the console rejects an upload.

## Full description (4000 char limit)

Play has no keyword field. The title, these two text blocks, the developer name
and your review text are the *entire* indexable surface, so the genre words live
here — placed once each, in the opening where they read as prose rather than as
a list. Repetition is a violation risk, so they are not used twice.

```
Nine fights stand between you and The Devourer. You bring four dice.

That is the whole game. Roll them, read the faces, and decide which ones were
not worth the roll. You get one re-roll for the whole hand, so spend it or
lose it. Then end the turn and watch what the thing across from you does about
it.

Between fights you take one of three upgrades, and upgrades change your dice,
not a stat bar. Sharpen every damage face. Bless every block face. Add a fifth
die to the pool. Every choice reshapes the hand you roll next fight, so two
runs never feel the same.

A turn-based roguelike, built around a puzzle

Every turn is one decision — which dice were wasted, and which of those you can
afford to roll again. That is the strategy, and it is the whole strategy. You
are not managing a timer or a stat bar; you are reading five numbers and
choosing which one to bet.

How a turn works

You roll every die in your pool at once. Each face is damage, block, or a
bonus re-roll. Tap any dice you are unhappy with to queue them, spend the
turn's single re-roll, and then everything you are holding resolves together —
so you commit before you know how it lands. Your damage goes through the
enemy's armour, and what it hits first, you. Enemies answer every turn, and the
ones that survive long enough get worse at what they do.

Two ways out of a bad hand

Each fight gives you one Focus and one Bank, and they are not the same kind of
promise. Focus steps a die up to the next better face on that die — certain,
and it costs you the die for the rest of the turn. Bank does not improve
anything: it holds a die back whole, out of this turn and into the next. One
is a trade for a guarantee, the other a bet that next turn is a better hand
than this one.

What is in it

Nine hand-built fights. Rust Golem grows its armour every turn until you break
through it. Bloodletter heals off what it deals to you. Hexweaver curses one of
your dice to nothing. Berserker gets angrier the longer it lives. The Devourer
is armoured and enraged and it has 78 health.

A daily run

Every player gets the same dice and the same enemies on the same day. There is
nothing to grind toward and nothing to buy — just the same fight everyone else
is having, and a result worth comparing.

Your best run is saved

Depth reached, runs played, victories kept. Every finished run unlocks another
die, so the next one starts with a fuller hand. The run ends when your health
does.

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

      > **But it is five executable commits behind HEAD (corrected
      > 2026-09-30, was "one"), and the upload should be a decision.**
      > `dicefate.aab` was built at **06:54:37**, sixteen minutes after Phase 3
      > landed. Five commits after that build changed shipped code, across all
      > three gameplay scripts:
      >
      > | commit | what a player would not get |
      > |---|---|
      > | `79de3f5` | the touch-target fix — `custom_minimum_size` goes `0, 54` → larger |
      > | `73238fe` | three controls the ergonomics gate had never looked at |
      > | `d035c37` | the named boss threshold and the boss haptic |
      > | `599baac` | item 7: Fang's top face, `18` → a `15` carrying `pierce 6` |
      > | `d6b3073` | the SFX pool size, which had claimed headroom nothing checked |
      >
      > `20fe68a` touches `game.gd` too but is 2 lines and comment-level.
      > The earlier version of this note said "one executable commit" and named
      > only item 7, which was true of `dice.gd` alone and wrong everywhere
      > else: scoping the claim to one file is what hid the other four.
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
- [ ] `export_presets.cfg` holds the release keystore password in plaintext,
      and this note said to gitignore it *before* `git init`. `git init` has
      since happened and the password is in history at `088a3f1`. There is no
      remote, so nothing has left the machine, but the fix is no longer "add a
      line to `.gitignore`" — the value is in a commit. Rotate the key or drop
      it to an env-var read before this repo goes anywhere.
