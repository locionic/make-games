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
request comes back at two minutes — so it cannot make a 200ms die-clack. 43 KB
for all seven, no licence, and they land exactly on the event that asked for
them. Regenerate with `python3 _mksfx.py` then the ffmpeg loop in its docstring.

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

Play caps screenshots at 8, and there were 9 until 2026-09-29: `01-title-first-
launch` was moved to `screenshots-spare/` and the rest renumbered, on the grounds
that it and `02-title-pick-your-hand` are both title screens at near-identical
file size, and the slot was worth more to the armoured-fight shot. The spare is
there if you disagree.

## Short description (80 char limit)

```
Nine fights. One pool of dice. Roll, re-roll once, and take what you can.
```

That is 73 characters.

## Full description (4000 char limit)

Play has no keyword field. The title, these two text blocks, the developer name
and your review text are the *entire* indexable surface, so the genre words live
here — placed once each, in the opening where they read as prose rather than as
a list. Repetition is a violation risk, so they are not used twice.

```
Nine fights stand between you and The Devourer. You bring four dice.

That is the whole game. Roll them, read the faces, and decide which ones were
not worth the roll. Each die you dislike gets one re-roll — spend it or lose
it. Then end the turn and watch what the thing across from you does about it.

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
bonus re-roll. Tap any dice you are unhappy with to queue them, spend your
re-rolls, and then everything you are holding resolves together — so you commit
before you know how it lands. Your damage goes through the enemy's armour, and
what it hits first, you. Enemies answer every turn, and the ones that survive
long enough get worse at what they do.

What is in it

Nine hand-built fights. Rust Golem grows its armour every turn until you break
through it. Bloodletter heals off what it deals to you. Hexweaver curses one of
your dice to nothing. Berserker gets angrier the longer it lives. The Devourer
does both, and it has 78 health.

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

- [ ] Upload the **release**-signed AAB — `build/android/dicefate-release.aab`.
      `build/android/dicefate.aab` is debug-signed and Play rejects it.
- [ ] `versionCode` must be strictly higher than any version ever uploaded for
      `com.dicespike.game`, including drafts and rejected uploads. `project.godot`
      is at 4 (the note here used to say 3, which was stale) — 4 is correct only
      if nothing above it has ever been uploaded. Bump it and rebuild if in doubt;
      a rejected upload still counts as uploaded.
- [ ] The listing ID `com.dicespike.game` is permanent once created.
- [ ] `export_presets.cfg` holds the release keystore password in plaintext.
      Gitignore it before running `git init` on this project.
