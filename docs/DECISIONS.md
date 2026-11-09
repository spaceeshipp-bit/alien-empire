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

- **Decision:** golden scenarios run on `sim/tests/golden/config_bundle.json`, a frozen copy of the M0 config, not the live balance files. Hashes are recorded once and verified on the headless worker, the desktop client and the phone. The M0 hashes were recorded by CI's headless worker on 2026-11-08 and committed as `sim/tests/golden/expected.json`. CI fails if that file is missing; it then records fresh hashes into a `golden-hashes` artifact for review, so a re-record is always a reviewed commit.
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

### D-018 · 2026-11-08 · Pinned plugin releases with checked hashes

- **Decision:** `tools/fetch_plugins.sh` downloads exact releases and refuses any file whose SHA-256 differs from the pinned one: GodotGooglePlayBilling 3.3.0, Poing AdMob v5.1.0 (plus its Android and iOS binaries for Godot 4.7.2), Godotx Firebase 3.1.0 (Core and Messaging only) and Play Games Services for Godot v3.4.0. The downloads are git-ignored; CI fetches them in every job that opens the client. Each hash matched GitHub's published digest and was re-checked by a second download.
- **Options:** commit the plugins to the repo; fetch "latest" releases.
- **Reason:** the build prompt asks for licensed, recorded dependencies, and a pinned hash makes every build use the reviewed files. "Latest" would have picked the Godot 3 billing plugin (1.4.0 is newer than 3.3.0). Pinning AdMob's binaries also stops its addon from downloading them unchecked during headless runs. Sources: each plugin's release page, linked in `docs/PLUGINS.md`.

### D-019 · 2026-11-08 · What each Plugin Lab check counts as a pass

- **Decision:** billing passes when Play returns the test product; ads when Google's demo rewarded ad grants its reward; push when the phone gets an FCM token, followed by a console test message; sign-in when Play Games reports the player signed in; Play Integrity when a token arrives. M0 uses Google's sample AdMob app ID and demo ad unit, so no AdMob account is needed yet.
- **Options:** pass billing on any answer from Play; pass ads on load; require a decoded Integrity verdict.
- **Reason:** each pass proves the plugin works end to end on the phone. A sideloaded build gets an "unrecognized" Integrity verdict by design ([verdicts](https://developer.android.com/google/play/integrity/verdicts)), and decoding is server work in M4. Demo units are the documented way to test ([test ads](https://developers.google.com/admob/android/test-ads)).

### D-020 · 2026-11-08 · The owner's upload key signs every CI build

- **Decision:** when the repo has the upload key as Actions secrets, CI signs both the debug APK and a release AAB with it and uploads both; otherwise it signs the APK with a throwaway key and builds no AAB. The version code is the CI run number times 100 plus the re-run attempt, so re-runs get higher codes too. `tools/make_upload_key.sh` makes the key (RSA 4096, random password) in a Codespace or on any machine with Java.
- **Options:** a throwaway key per run (the M0 start); a separate stable debug key; Play's internal app sharing for debuggable builds.
- **Reason:** new apps must upload a signed App Bundle ([Play](https://support.google.com/googleplay/android-developer/answer/9859348)), each upload needs a higher version code, and Play Games ties sign-in to the signing key's SHA-1 ([PGS setup](https://developer.android.com/games/pgs/console/setup)). One stable key covers all three and lets each build update the last. A lost upload key can be reset through Play Console ([Play App Signing](https://support.google.com/googleplay/android-developer/answer/9842756)).

### D-021 · 2026-11-08 · Owner settings live in the repo's Actions settings

- **Decision:** the Play Integrity cloud project number and the Play Games project ID are Actions variables; `google-services.json` and the upload key are Actions secrets. `tools/ci/apply_owner_config.py` writes them into the client before each export and rejects malformed values.
- **Options:** commit them to `project.godot`; ask the owner to edit files.
- **Reason:** the owner never edits code, and nothing tied to the owner's accounts lands in the public repo. Firebase advises keeping its config file out of open-source repos ([Firebase](https://firebase.google.com/docs/projects/learn-more)).

### D-022 · 2026-11-08 · Firebase's Gradle edit is made by an export plugin

- **Decision:** `client/addons/firebase_gradle` adds Google's `google-services` Gradle plugin (4.4.4, the version the Firebase addon asks for) to the Android build template at the start of each export, only when `res://google-services.json` exists.
- **Options:** edit the template once by hand, as the addon's README says; patch it in a CI script after installing the template ourselves.
- **Reason:** Godot 4.7.2 reinstalls the template on every export that passes `--install-android-build-template`, which would wipe a one-time edit. Without the config file the Gradle plugin fails the build, while an unpatched build still works and the Lab reports Firebase as unconfigured. Tested locally with a placeholder config: the Firebase resources appeared in the APK.

### D-023 · 2026-11-08 · Gradle's open-source CI cache

- **Decision:** CI uses `gradle/actions/setup-gradle@v6` with `cache-provider: basic`, the MIT-licensed cache built on GitHub's cache.
- **Options:** the default "enhanced" cache, a proprietary component; dropping the action.
- **Reason:** upgrading to v6 with the default means accepting the Gradle Technologies Terms of Use ([v6.0.0 release notes](https://github.com/gradle/actions/releases/tag/v6.0.0), [DISTRIBUTION.md](https://github.com/gradle/actions/blob/v6.4.1/DISTRIBUTION.md)), which is the owner's call. The action only installs Gradle for our small Play Integrity plugin, so the basic cache loses little. The owner can switch it (Q8).

### D-024 · 2026-11-08 · Node 24 action versions; builds uploaded unzipped

- **Decision:** CI uses checkout v7, setup-python v7, setup-java v6, cache v6, upload-artifact v7 and setup-gradle v6, all running on Node 24. The APK and AAB are uploaded with `archive: false`, so each artifact is the file itself (`aetd-m0-debug.apk`, `aetd-m0-release.aab`).
- **Options:** stay on the v4/v5 actions, which GitHub now forces onto Node 24 with a warning.
- **Reason:** GitHub removed Node 20 from its runners on 2026-09-23 ([changelog](https://github.blog/changelog/2026-09-23-node-20-is-no-longer-available-in-github-actions)). None of the new majors' breaking changes touch how CI uses them. A phone can open an unzipped APK straight from the download.

### D-025 · 2026-11-08 · Godot's generated files are committed; autoloads keep res:// paths

- **Decision:** the `.uid` and `.import` files Godot writes next to our own scripts and assets are committed. Autoloads in `project.godot` must use `res://` paths; a tool test enforces it.
- **Options:** ignore the generated files.
- **Reason:** Godot 4.7's [version control guide](https://docs.godotengine.org/en/4.7/tutorials/best_practices/version_control_systems.html) ignores only `.godot/` and `*.translation`. The Play Games addon rewrites its autoload to a `uid://` value on every editor start, and fetched addons get different uids on each machine, so a committed `uid://` autoload would break everywhere else.

### D-026 · 2026-11-09 · The battle sim runs as C++ in a GDExtension

- **Decision:** the battle simulation is C++20 in `sim/native/`, built into one GDExtension library that the phone, the desktop client and the server's worker all load. GDScript keeps everything around it: reading and checking configs and battle specs, the API the rest of the game calls (`sim/core/*.gd`) and the tests. The determinism rules are unchanged (integers only, the battle's own seeded generator, ascending-ID order), and the C++ is built with `-fwrapv` so integer overflow behaves the same on every compiler. The core uses only the C++ standard library, so CI also compiles it on its own under UndefinedBehaviorSanitizer and AddressSanitizer and checks it against the reference vectors and golden hashes (`tools/check_sim_native.py`). The generator (D-005) and the state hash (D-006, now our own SHA-256 instead of Godot's `HashingContext`) moved with it and give the same answers. godot-cpp (MIT, Godot Engine contributors) is pinned to 10.0.0-stable by commit. The 100 ms raid-replay target stays. This answers Q7, which the owner left to the builder on 2026-11-09.
- **Options:** keep pure GDScript and relax the target to about 2.5 s per raid; keep pure GDScript and optimize it; a separate native sim on the server with GDScript on the phone, which would be two implementations that must agree bit for bit (the build prompt rules that out).
- **Reason:** measured before deciding. A raid kernel with the hot paths a full raid will have (lane movement, a spatial grid, nearest-enemy targeting re-picked every 5 ticks, counters, shields, armor and splash) ran 180 seconds of battle, 3,600 ticks, on one x86-64 core of the build workspace:

  | Raid size | GDScript, release runtime | GDScript, editor runtime | C++ (-O2) |
  | --- | --- | --- | --- |
  | 70 units and towers | 345 to 360 ms | 479 ms | 9 to 12 ms |
  | 303 units and towers | 2,360 to 2,470 ms | 3,010 ms | 65 to 82 ms |

  Both versions fired exactly the same shots, so they did the same work. GDScript missed the budget by 3.5 to 24 times; C++ meets it with room for the rules M1 and M2 add. The phone gains too: it runs the same battle live, and a fast sim leaves the frame time for drawing. On the golden battles the switch took the desktop client from 1.1 to 25.3 ms per battle down to 0.4 ms or less, with identical hashes.
- **Costs:** the library must be built for each platform. CI builds Linux x86-64 and Android arm64; opening the project on Windows or macOS needs a local build first. CI needs a C++ toolchain, SCons and the Android NDK (28.1.13356709, the one godot-cpp builds with). A GDExtension built for Godot 4.7 should keep working in later 4.x releases but not earlier ones ([About godot-cpp](https://docs.godotengine.org/en/4.7/tutorials/scripting/cpp/about_godot_cpp.html)), so a Godot upgrade doesn't force a rebuild, but godot-cpp should be upgraded with it. godot-cpp's MIT notice goes in the game's credits next to Godot's.
- **Build prompt:** its Sim core line says "pure GDScript battle logic". The proposed wording for the owner's doc: "Sim core: deterministic battle logic in C++, built as a Godot GDExtension, with a thin GDScript layer; no engine physics, no rendering and no floating-point math. The same library runs on the phone and on the server." `docs/BUILD_PROMPT.md` is updated when the doc is.

### D-027 · 2026-11-09 · The sim library is registered before Godot first opens a project

- **Decision:** `tools/sync_sim.py` also writes `res://sim/aetd_sim.gdextension` into each project's `.godot/extension_list.cfg`, so Godot loads the sim library at startup.
- **Options:** let Godot discover the extension while it imports.
- **Reason:** in CI, Godot 4.7.2 crashed on exit (signal 6, then a segfault in its own shutdown under gdb) whenever it found the extension during a project's first import. A second run of the same command passed, and so does every run with the extension listed up front.

## Open questions for the owner

| # | Question | Current default | Needed by |
| --- | --- | --- | --- |
| Q1 | How many lives does a leaking Hive Carrier cost? The prompt only gives the Brute's (3). | 1 | M1 |
| Q2 | How many lives does a PvE stage start with? | Not set | M1 |
| Q3 | Should real waves use spawn jitter (seeded, 0 to a few hundred ms per spawn)? | Off | M1 |
| Q4 | Field tower range: +5% of base per level, or compounding? Sell refund: 70% of everything spent, or of the build cost? | Base, everything spent | M2 |
| Q5 | How long does the Ion Disruptor's slow last, and does the Sensor Beacon mark while in range or per hit? | Not set | M2 |
| Q6 | The game's package name (needs the title). | Test app uses `com.alienempiretd.pluginlab` | First Play upload of the game |
| Q8 | CI's Gradle cache: keep the MIT-licensed basic cache, or accept Gradle's terms for the enhanced one (D-023)? | Basic | Any time |
