# Decision log

Every design or technical decision, with its date, the options considered and the reason. Newest milestone last. Questions waiting on the owner are at the end.

## Project setup

### D-001 · 2026-11-08 · One repo, one branch per milestone

- **Decision:** a single repo with the layout from the build prompt (`client/`, `sim/`, `server/`, `config/`, `tools/`, `docs/`, plus `worker/` for the headless sim worker). Each milestone is built on its own branch (`m0-foundations`, `m1-pve-slice`, …) and merged into `main` only after its "done when" checks pass on the owner's phone.
- **Options:** commit straight to `main`; separate repos for client and server.
- **Reason:** the build prompt says not to start the next milestone until the current one's tests pass, so `main` always holds the last milestone that passed. One repo keeps the shared sim core in one place.

## M0 Foundations

### D-002 · 2026-11-08 · Godot 4.7.2

- **Decision:** pin Godot 4.7.2-stable for the client, the worker, CI and the Android plugin build.
- **Options:** 4.6.3 (previous branch).
- **Reason:** the build prompt asks for the latest stable. GitHub marks 4.7.2 (18 Aug 2026) as the latest release ([releases](https://github.com/godotengine/godot/releases), [endoflife.date](https://endoflife.date/godot)). The Firebase plugin also needs 4.7 or later.

### D-003 · 2026-11-08 · Compatibility renderer, portrait 720 × 1280

- **Decision:** the client uses the Compatibility (OpenGL ES 3) renderer on every platform, a 720 × 1280 portrait base resolution and `canvas_items` stretching with `expand`.
- **Options:** the Mobile (Vulkan) renderer.
- **Reason:** the build prompt targets cheap 3 GB phones and a 2D top-down look; Compatibility runs on the most devices. Portrait one-handed play is the build prompt's default.

### D-004 · 2026-11-08 · Integer units in config, decimals refused

- **Decision:** every config number is an integer whose field name carries its unit: `_x100`, `_mt` (thousandths of a tile), `_mtps`, `_bp` (basis points), `_ms` (multiple of 50, one tick). `tools/config_tool.py` refuses any file with a decimal number, and the sim's loader refuses non-whole values. Conversions from the build prompt's tables are in `config/README.md`.
- **Options:** decimals in config, converted at load.
- **Reason:** the sim must never touch floating point. Whole numbers in the files make every value exactly what the sim uses.

### D-005 · 2026-11-08 · Random numbers: xoshiro128** seeded by splitmix32

- **Decision:** the sim's generator is xoshiro128** on four 32-bit words held in 64-bit ints, with every multiplication split so no intermediate value exceeds 2^48. Seeds are integers from 0 to 2^53 − 1 so JSON carries them exactly. Python (`tools/gen_vectors.py`) and C (`tools/reference/xoshiro128ss.c`) references agree, and their test vectors run on every platform.
- **Options:** xorshift32 (weaker statistics); PCG32 (needs a wrapping 64-bit multiply, and signed overflow isn't safe to rely on in GDScript).
- **Reason:** it's in the xorshift family the build prompt names, it's high quality, and nothing in it can overflow, so results are identical everywhere.

### D-006 · 2026-11-08 · State hash: SHA-256 over little-endian integers

- **Decision:** battle state is hashed with SHA-256 (Godot's `HashingContext`) over a stream of 64-bit little-endian integers and length-prefixed UTF-8 strings. A 16-character checkpoint hash is kept every 100 ticks (5 seconds).
- **Options:** a hand-written FNV or xxHash in GDScript.
- **Reason:** SHA-256 is identical in every Godot build and in Python, and checkpoints show where two runs first diverged.

### D-007 · 2026-11-08 · Lanes store distance travelled

- **Decision:** a lane's segment lengths are computed once with an integer square root. Each alien stores only its distance along the lane; positions are interpolated with truncating integer division. Speed carries a per-alien remainder, so a speed that doesn't divide by 20 still covers the exact distance over time.
- **Options:** step x and y each tick with a square root per alien per tick.
- **Reason:** cheaper per tick, exact over time, and "closest to the Core" targeting (M1) becomes a comparison of distances.

### D-008 · 2026-11-08 · Golden tests on a frozen config

- **Decision:** golden scenarios run on `sim/tests/golden/config_bundle.json`, a frozen copy of the M0 config, not the live balance files. Hashes are recorded once and verified on the headless worker, the desktop client and the phone. If no hashes are committed, the first CI run records them on Linux (with a warning) so the Android build can be checked against them; once committed they're verified strictly.
- **Options:** run goldens on the live config and re-record after every retune.
- **Reason:** balance changes shouldn't break determinism tests. Only a sim change, with a `SIM_VERSION` bump, means re-recording.

### D-009 · 2026-11-08 · Sim copies and preload-only references

- **Decision:** `tools/sync_sim.py` copies `sim/` into `client/sim/` and `worker/sim/`; the copies are git-ignored and CI checks them. Sim scripts load each other with `preload` paths and never use `class_name`.
- **Options:** symlinks; global class names.
- **Reason:** the build prompt asks for copies at build time, and symlinks break on Windows checkouts. Without `class_name`, a fresh headless run doesn't need the editor's class cache.

### D-010 · 2026-11-08 · Separate package name for the Plugin Lab app

- **Decision:** the M0 test app is `com.alienempiretd.pluginlab`, a Play Console app of its own.
- **Options:** use the real game's package name now.
- **Reason:** a package name can't change once an app is on Play, and the game has no title yet. Testing billing and Play Integrity needs a Play Console app, so the test app gets its own.

### D-011 · 2026-11-08 · Android plugins

- **Decision:** GodotGooglePlayBilling for billing, Poing Studios' AdMob plugin for rewarded ads, Godotx Firebase (Core and Messaging) for push, Google Play Games Services for Godot for sign-in, and our own small Java plugin for Play Integrity. Details, links and setup are in `docs/PLUGINS.md`.
- **Options:** no maintained Godot 4 Play Integrity plugin turned up; Firebase App Check was the other route, but it gives Firebase tokens rather than Play Integrity tokens for our own server to decode.
- **Reason:** each pick is maintained for current Godot 4. The Play Integrity plugin is about 90 lines and follows Google's standard-request API.

### D-012 · 2026-11-08 · Android target SDK 36, min SDK 24, arm64 only

- **Decision:** the export targets API 36 with a minimum of API 24, and ships arm64-v8a only.
- **Options:** also ship 32-bit armeabi-v7a.
- **Reason:** since 31 Aug 2026, new apps and updates must target Android 16 (API 36) ([Google](https://developer.android.com/google/play/requirements/target-sdk)). One architecture keeps the download small; 32-bit-only phones are rare now. Revisit if soft-launch analytics show otherwise.

### D-013 · 2026-11-08 · CI on GitHub Actions

- **Decision:** three jobs: config validation and tool tests; sim tests on the headless worker and on the desktop client under a virtual display; an Android debug APK uploaded as an artifact. Godot downloads are checked against the release's SHA-512 list.
- **Options:** another CI service; building locally only.
- **Reason:** free for a solo project on GitHub, and the Android job hands the owner an APK to install without a local Godot setup.

### D-014 · 2026-11-08 · Own minimal test runner

- **Decision:** sim unit tests use a small runner in `sim/tests/` (about 80 lines with its base class) rather than the GUT addon.
- **Options:** GUT.
- **Reason:** no third-party dependency, and the same runner works headless, on desktop and inside the phone app.

### D-015 · 2026-11-08 · Readings of two field-tower rules

- **Decision:** "range +5% per level" is read as +5% of base range per level, not compounding; "selling refunds 70%" as 70% of all credits spent on the tower. Both are config knobs.
- **Options:** compounding range; refund of the build cost only.
- **Reason:** the plainest reading of the prompt. Flagged for the owner below.

### D-016 · 2026-11-08 · Optional seeded spawn jitter

- **Decision:** a wave group can delay each spawn by a seeded random 0 to `jitter_ms`. The default is 0, which makes no random draw.
- **Options:** fully fixed spawn times.
- **Reason:** golden scenarios need something that uses the generator, and slight jitter makes waves look less mechanical. Real waves keep it at 0 until the owner decides (below).

### D-017 · 2026-11-08 · What M0 could and couldn't verify

- **Decision:** M0 was built in Claude's cloud workspace without Godot, the Android SDK or network access. The Python tools, schema, cross-file rules and reference vectors were run and pass; the Java plugin was compile-checked against stand-in classes. The GDScript has not run under Godot yet: the first CI run or a session with Godot does that.
- **Options:** wait for network access before writing any Godot code.
- **Reason:** everything that could be built and checked was, so the first Godot run only has to confirm it.

## Open questions for the owner

| # | Question | Current default | Needed by |
| --- | --- | --- | --- |
| Q1 | How many lives does a leaking Hive Carrier cost? The prompt only gives the Brute's (3). | 1 | M1 |
| Q2 | How many lives does a PvE stage start with? | Not set | M1 |
| Q3 | Should real waves use spawn jitter (seeded, 0 to a few hundred ms per spawn)? | Off | M1 |
| Q4 | Field tower range: +5% of base per level, or compounding? Sell refund: 70% of everything spent, or of the build cost? | Base, everything spent | M2 |
| Q5 | How long does the Ion Disruptor's slow last, and does the Sensor Beacon mark while in range or per hit? | Not set | M2 |
| Q6 | The game's package name (needs the title). | Test app uses `com.alienempiretd.pluginlab` | First Play upload of the game |
