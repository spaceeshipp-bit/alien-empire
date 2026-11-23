# Art

How the game looks and the rules its art follows. For now the art is **placeholder**: decent vector sprites drawn in code, with final art later (D-031). The preview is [`docs/art/cast_sheet.png`](art/cast_sheet.png).

## The look

- Top-down. Flat, bright shapes on dark ground, with glow (the build prompt's art direction).
- Portrait. Lanes run from the top of the screen to the Core at the bottom.
- Motion comes from code, not frame-by-frame animation: recoil, muzzle flashes, squash and stretch, walk bob, hit flashes, pulses and death pops.
- The hive: all six aliens share violet shells, glowing yellow eyes and glowing spots, with a glow in their class color. Each has its own silhouette, so they stay apart at phone size.
- Your towers: white-and-cyan machines on a dark hexagonal base with a cyan rim.

## Colors

What each color means. Use a color only for its meaning.

| Color | Hex | Means |
| --- | --- | --- |
| Cyan | `#7cf3ff` | You: your towers, your units, your colony |
| Teal | `#2ec4b6` | Your clan |
| Amber | `#f5a524` | Rivals |
| Magenta | `#ff4fd8` | The AI and the hive: alien lanes, AI colonies |
| Violet | `#6b3fe6`, lighter `#9b7dff`, darker `#35208a` and `#22145e` | Alien shells |
| Yellow | `#ffe14d` | Alien eyes |
| Red | `#ff5a5f` | Danger and failures in the interface |
| Ground and panels | `#0b1626`, `#0e1b30`, `#13213a`, `#1b2d4d` | Backgrounds |
| Text | `#e8f1ff`, muted `#9db0c8` | Text |
| Metal, heat and ion | `#dbe7f5`, `#ff8a3d`, `#4aa8ff` | Tower details |

### Class colors

Every class color comes with its icon. Never tell classes apart by color alone (build prompt, accessibility).

| Class | Color | Icon |
| --- | --- | --- |
| Swarm | `#a5ef58` lime | Three dots |
| Armored | `#f04b12` red-orange | Hexagon with two bars |
| Shielded | `#1791c5` blue | Shield |
| Air | `#f6f3eb` white | Double chevron |
| Cloaked | `#edbbfb` lavender | Crossed-out eye |
| Titan | `#f08c8e` coral | Crown |

The colors were chosen with a color-vision check (D-032). `python3 tools/art/color_check.py` simulates the three main kinds of color blindness, and every pair of class colors must stay at least 15 apart (CIEDE2000). The closest pair is 16.3 apart: shielded and cloaked, for someone with protanopia. Two class colors sit near other colors for some players: cloaked near your cyan with deuteranopia, and swarm near the eye yellow with protanopia. Class colors appear only on class icons and on aliens' spots and glow, where the icons tell them apart.

## Sprites

| What | Where |
| --- | --- |
| Source, drawn in code | `tools/art/sprites.py` |
| The sprites the game loads (generated, don't edit) | `client/art/`: `aliens/`, `towers/`, `core/`, `icons/`, `fx/` |
| The palette for game code (generated) | `client/art/palette.gd` |
| The cast sheet preview | `tools/art/sheets.py`, rendered to `docs/art/cast_sheet.png` |

```sh
python3 tools/art/build_art.py            # write client/art/
python3 tools/art/build_art.py --check    # fail if client/art/ is out of date (a tool test runs this)
python3 tools/art/build_art.py --preview  # also render the cast sheet (needs Node and Playwright with Chromium)
```

After adding a sprite, import the client in Godot to create its `.import` file, set the scale below, and commit both. Importing rewrites `client/project.godot`, so revert that file afterwards (D-025).

Rules for every sprite:

- **Units.** 100 units is one tile, and a sprite is centered on (0, 0). Aliens are 100 units across (the Hive Carrier 170), tower heads 140, the tower base 100, the Core 200 and class icons 26.
- **Facing.** Aliens face down, toward the Core. Tower heads face up, toward where the aliens come from.
- **Towers have two parts.** `towers/base.svg` stays still. Each tower's head turns to aim, around (0, 0).
- **Glow is drawn into the sprite** as radial gradients: eyes, spots, nozzles. The game adds each alien's class-colored glow by drawing `fx/halo.svg` under it, tinted with the class color.
- **Only what Godot draws.** Godot turns SVG into textures with its built-in renderer (ThorVG) when it imports them. Sprites use shapes (path, circle, ellipse, rect), groups, linear and radial gradients, opacity and dashed lines. They don't use filters, patterns, masks, clip paths, images or text. A tool test enforces the list.
- **Import scale.** 2 texture pixels per unit (3 for icons), with mipmaps and lossless compression. A tile is 80 px at the 720-px base width and 120 px on a 1080-px-wide phone, so a 200-px tile texture stays sharp. A tool test checks every `.import` file.

Checked on 2026-11-23:

- Godot 4.7.2 drew all 21 sprites the way Chromium draws them, through the same SVG renderer its importer uses.
- In the cast sheet's bottom strip, at 120 px a tile, each alien keeps a distinct silhouette:
  - the Swarmer is a small beetle;
  - the Brute is a wide plated shell;
  - the Shield Drone sits in a ring;
  - the Skimmer is a wide wing;
  - the Phaser is a thin dashed outline;
  - the Hive Carrier is the biggest.

## Final art, later

- **When:** the owner decides (D-031). The build prompt's default is a style test after M2: one tower, one alien and one tile in finished art, checked at phone size. Full production follows by M9.
- **Drop-in replacements:** final art keeps the file names, sizes, centers and facing above, so it replaces the placeholders file by file without code changes.
- **AI-generated art** is fine with a commercial license, from tools such as Scenario or PixelLab. Never prompt with another game's name, characters or art; every alien design is original.
- **Log every asset** in [`docs/ASSET_LOG.md`](ASSET_LOG.md): file, tool, prompt, date and license.
- **The concept boards** belong to the owner and aren't in the repo yet. The style test redoes their map and raid screens in portrait.
