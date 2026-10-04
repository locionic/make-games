# DICE FATE: REBIRTH — Visual, Thematic & Game Feel Overhaul Plan

> **Goal**: Transform *Dice Fate* from an abstract wireframe math prototype into an addictive, visually captivating, highly tactile roguelike dice builder (in the league of *Slice & Dice*, *Balatro*, and *Dicey Dungeons*) that attracts and retains players on itch.io and mobile.

---

## 1. The Core Problem: Why "Dice Fate" Feels Boring Despite Great Math

1. **Spreadsheet / Wireframe Aesthetic**:
   - The game uses 100% code-drawn flat polygons. Enemies are literal geometric wireframes: a hexagon, pentagon, or triangle.
   - Dice are tall, dark, rectangular flat buttons with plain text numbers (`9`, `14`, `4`). In a dice game, **the dice don't look or feel like dice**.
   - Background is sterile flat navy black (`#0f141c`).
   - There are no character sprites, monster portraits, or fantasy illustrations.

2. **Zero Atmosphere / Worldbuilding**:
   - Players have no idea who they are playing as or what world they are in.
   - Contrast with:
     - *Balatro*: Hypnotic retro CRT casino vibe, groovy synth jazz, tactile card flips.
     - *Slice & Dice*: Charming chunky fantasy heroes, expressive dungeon monsters, chunky 3D-ish dice.
     - *Inscryption*: Atmospheric candle-lit wooden cabin, creepy eyes in the dark, tactile card & bone tokens.

3. **No Tactile "Juice" / Roll Sensation**:
   - Tapping "Roll" merely swaps text numbers on a button. There is no physical tumble, no dice shake, no anticipation, no roll physics sound.
   - Combat impacts lack punch: no floating bouncy damage numbers, no hit flashes, no celebratory feedback on big combos.

4. **Lack of Run Identity & Meta-Progression**:
   - Every run starts identically with the same 4 dice.
   - No character classes (e.g. Rogue with poison/evasion dice, Mage with mana/spell dice, Knight with heavy armor/bash dice).
   - No visual relic shelf to show off items collected during the run.

---

## 2. The Vision: "Arcane Tarot & Obsidian Relic Dice"

Transform the game into an **occult, dark-fantasy tarot dice roguelike**:
- **Setting**: An eldritch gambling den at the end of the world. You wager arcane dice against grotesque cosmic horrors and fallen knights.
- **Visual Tone**: Dark velvet/aged wood surface, gold-leaf filigree borders, glowing ethereal runes, high-contrast jewel-toned dice (Crimson for Damage, Sapphire for Ward, Amethyst for Hex/Curse, Amber for Focus).
- **Core Hook**: Fast, addictive 5-minute runs with immense tactical depth, gorgeous dice animations, and juicy tactile feedback.

---

## 3. Implementation Phases

### Phase 1: The Tactile Dice Overhaul (Dice That Look & Feel Like Real Dice)
*Target: `dice.gd`, `fight.gd`, `theme.gd`*

1. **Bevelled 3D-Look Dice Faces**:
   - Replace the flat card rectangles with chunky, rounded-corner, bevelled dice tiles with drop shadows and jewel-toned border insets.
   - Add embossed tactile symbols alongside the numbers:
     - **Blade / Attack**: Stylized cross-swords ⚔️ + damage value.
     - **Ward / Defense**: Heavy ornate shield 🛡️ + block value.
     - **Sunder / Rend**: Cracked armor / shattering strike 💥.
     - **Hex / Curse**: Eldritch glowing skull ☠️.
     - **Focus**: Glowing mystical flame / all-seeing eye ✨.
2. **Juicy Tumble / Roll Animation**:
   - When tapping **Roll**, dice do not instantly swap numbers. They shake, blur with a fast multi-face tumble tween (cycling random symbols for 0.3s), and slam down with a satisfying wooden/resin clatter.
   - Banked dice stay visually locked in a golden velvet tray (`HELD`).
   - Focused dice emit an amber pulse and particle glow.

---

### Phase 2: Monster & Boss Visual Rebirth
*Target: `fight.gd`, `theme.gd`*

1. **Replace Wireframe Polygons with Stylized Vector/Sprite Silhouettes**:
   - Instead of drawing a bare hexagon or triangle, draw distinct, atmospheric monster silhouettes:
     - **Stone Sentinel / Golem**: Heavy craggy stone titan silhouette with glowing runic cracks that pulse when plating armor.
     - **Hexweaver / Spider-Priestess**: Eldritch hooded spider creature with multiple glowing red eyes and venom tendrils.
     - **Blood Cultist / Vampire**: Shrouded dark figure with crimson blade and glowing fangs.
     - **The Devourer (Final Boss)**: Massive multi-jawed cosmic horror with tentacles framing the top screen.
2. **Combat Animations & Juice**:
   - Idle breathing/floating tweens for enemies.
   - Dramatic flinch / knockback tween + red screen flash when the enemy takes heavy damage.
   - Floating, bouncing comic-style damage numbers (e.g. `-14` pops up in red, `-8 deflected` in blue) with elastic ease-out.
   - Attack animation: When the enemy strikes, the monster silhouette lurches forward toward the player with screen shake.

---

### Phase 3: Thematic Environment & Audio Atmosphere
*Target: `game.gd`, `theme.gd`, `audio/`*

1. **Atmospheric Background & Frame**:
   - Replace flat `#0f141c` with a rich dark wooden or stone altar texture with subtle vignetting and gold filigree UI trim.
   - Run depth indicator transformed into an ornate tarot stage tracker (Stage 1 to 9 marked by glowing gemstones).
2. **Sound Design Polish**:
   - Multi-variation dice roll sounds (random pitch 0.95 - 1.05 so repeated rolling never sounds monotonous).
   - Heavy metal clank for Armor/Ward block.
   - Deep visceral boom for critical hits / Boss defeats.
   - Ambient dungeon/tavern background drone.

---

### Phase 4: Class Archetypes & Relic Shelf
*Target: `run.gd`, `game.gd`*

1. **3 Starting Character Archetypes**:
   - **The Sellsword**: Balanced loadout (Blade, Sunder, Ward, Focus). Special: Extra reroll charge.
   - **The Occultist**: Dark magic specialist (Hex, Spark, Ward, Hex). Special: Enemies start with 1 Curse.
   - **The Bastion**: Heavy juggernaut (Ward, Bastion, Riposte, Blade). Special: Retains 50% block between turns.
2. **Visible Relic / Treasure Shelf**:
   - Collected relics and unlocked perks visually line the top bar of the screen as glowing icons with tooltips.

---

## 4. Execution Guardrails

- **Zero Regression on Balance**: The underlying `dice.gd` mathematical model and `_balance.gd` benchmarks must remain 100% intact.
- **Test Integrity**: `godot --headless -s test.gd` (all 9,041 checks) must remain GREEN after every UI/visual upgrade.
- **Hermetic Web Performance**: The WebAssembly export must load in under 3 seconds on itch.io and maintain solid 60 FPS on mobile.
