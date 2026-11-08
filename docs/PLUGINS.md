# Android plugins and the Plugin Lab

M0 proves every Android plugin the game depends on with a test build on a real phone, before any game system relies on it. The test app opens on a home screen with **Sim tests** and **Plugin Lab**; the Lab has one check per plugin.

Checked on 2026-11-08 against the sources linked below. Pin exact versions in this file when the plugins are first downloaded.

## The plugins

| Need | Plugin | Requires | GDScript entry points | Status in the repo |
| --- | --- | --- | --- | --- |
| Play Billing | [GodotGooglePlayBilling](https://github.com/godot-sdk-integrations/godot-google-play-billing) (godot-sdk-integrations), [Godot docs](https://docs.godotengine.org/fr/4.5/_sources/tutorials/platform/android/android_in_app_purchases.rst.txt) | Godot 4.2+, Gradle build | `BillingClient.new()`, `start_connection()`, `query_product_details()`, `query_purchases()`; signals `connected`, `connect_error`, `query_product_details_response`, `query_purchases_response`, `on_purchase_updated` | Check written; plugin not downloaded yet |
| Rewarded ads | [AdMob plugin](https://github.com/poingstudios/godot-admob-plugin) (Poing Studios) | Godot 4.5+ | `MobileAds.initialize()`, `RewardedAdLoader.new().load(unit, AdRequest.new(), callback)` | Check written; plugin not downloaded yet |
| Push notifications | [Godotx Firebase](https://github.com/godot-x/firebase) (Core + Messaging) | Godot 4.7+, Gradle build, `google-services.json` | singletons `GodotxFirebaseCore`, `GodotxFirebaseMessaging`; `request_permission()`, `get_token()`; signals `messaging_token_received` and others | Check written; plugin not downloaded yet |
| Google sign-in | [Google Play Games Services for Godot](https://store.godotengine.org/asset/jacob-ibanez-sanchez/google-play-games-services-for-godot/) (godot-sdk-integrations, v3.4.0 listed) | Godot 4.3+ | Unconfirmed: the check expects `PlayGamesSignInClient` with `is_authenticated()`, `sign_in()` and signal `user_authenticated`, and lists the real names if they differ | Check written; plugin not downloaded yet |
| Play Integrity | Our own: `client/android_plugins/play_integrity` (Java, Godot Android plugin v2) using `com.google.android.play:integrity:1.6.0` ([setup](https://developer.android.com/google/play/integrity/setup), [standard requests](https://developer.android.com/google/play/integrity/standard)) | Gradle build | singleton `PlayIntegrity`: `prepare(cloud_project_number)`, `request_token(request_hash)`; signals `prepared`, `prepare_failed`, `token_ready`, `token_failed` | Written; build with `tools/build_android_plugins.sh` |

No maintained Godot 4 plugin for Play Integrity turned up, so the repo carries a small one (about 90 lines of Java). Godot's [Android plugin guide](https://docs.godotengine.org/de/4.4/_sources/tutorials/platform/android/android_plugin.rst.txt) describes the format, and its template lives at [m4gr3d/Godot-Android-Plugin-Template](https://github.com/m4gr3d/Godot-Android-Plugin-Template).

The checks look plugin classes up by name at run time, so the project still opens and exports when a plugin is missing; that check then says "not installed". If a plugin's API differs from what its check expects, the check fails and lists the methods and signals the plugin really has.

## Installing the third-party plugins

Each plugin ships a release zip with an `addons/` folder (Firebase also has `android/`). Unzip into `client/`, enable it under Project > Project Settings > Plugins, and keep **Use Gradle Build** on in the Android export preset. The Firebase plugin also needs `google-services.json` in `client/` and the edits to `android/build/build.gradle` described in its README.

This workspace had no network access during M0, so the plugins aren't downloaded yet. The next session with network access adds `tools/fetch_plugins.sh`, which downloads pinned releases and checks their hashes, and an Android build job in CI.

## What the owner sets up

Most of this is a one-time setup in Google's consoles. The Plugin Lab app uses its own package name, `com.alienempiretd.pluginlab`, so these tests don't lock in the real game's package name (see D-010 in `docs/DECISIONS.md`).

1. **Play Console** (one-time $25 for a personal account, per the build prompt): create an app for `com.alienempiretd.pluginlab`. Upload a build to the internal testing track and add your Google account as a license tester.
2. **Billing:** in that app, create an in-app product with id `m0_test_gems`. The check passes once Play answers the product and subscription queries.
3. **AdMob:** the check uses Google's [demo rewarded unit](https://developers.google.com/admob/android/test-ads), which always serves test ads. The export still needs an AdMob app id in the manifest; set it as the plugin's README describes.
4. **Firebase:** create a project, add an Android app with the package name above, download `google-services.json` into `client/` (it's git-ignored). After the check shows a token, send a test message to that token from the Firebase console.
5. **Play Games Services:** in Play Console, set up Play Games Services for the app and add an OAuth client with the signing certificate's SHA-1. Sideloaded debug builds use the debug key's SHA-1; builds from Play use the app signing key's.
6. **Play Integrity:** in Play Console, open **Protected with Play > Play Integrity API** and link a Google Cloud project. Put that project's number in `client/project.godot` under `[aetd]` as `play_integrity/cloud_project_number`.

## Running the checks on the phone

1. Install the test APK (from CI, or a local export) on the phone.
2. Open **Sim tests**: every line should read PASS. Take a screenshot.
3. Open **Plugin Lab** and run each check. If billing or Play Integrity fails on a sideloaded build, install the app from the internal testing track and run it again.
4. Send the screenshots back. M0 is done when the sim hashes match and every check passes.
