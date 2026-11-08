# Android plugins and the Plugin Lab

M0 proves every Android plugin the game depends on with a test build on a real phone, before any game system relies on it. The test app opens on a home screen with **Sim tests** and **Plugin Lab**; the Lab has one check per plugin.

This file has three parts: the plugins and how they get into the build, the owner's walkthrough (install the APK, then the one-time console setup), and what to do when a check fails. Everything here was checked on 2026-11-08 against the sources linked at the end.

## The plugins

| Need | Plugin, pinned version | License | What the Lab check does | Needs from the owner |
| --- | --- | --- | --- | --- |
| Play Billing | [GodotGooglePlayBilling](https://github.com/godot-sdk-integrations/godot-google-play-billing) 3.3.0 (Play Billing Library 9.1.0) | MIT | Connects to Play, asks for product `m0_test_gems` and the account's subscriptions. Passes when Play returns the product. | Play Console app, one internal-testing upload, an active product |
| Rewarded ads | [Poing Studios AdMob](https://github.com/poingstudios/godot-admob-plugin) v5.1.0 (Google Mobile Ads Next-Gen SDK 1.4.0) | MIT | Starts the SDK, loads Google's demo rewarded ad and shows it. Passes when the SDK grants the reward. | Nothing: it uses Google's sample app ID and demo ad unit |
| Push notifications | [Godotx Firebase](https://github.com/godot-x/firebase) 3.1.0, Core and Messaging | MIT | Starts Firebase, asks for notification permission, fetches the phone's FCM token. Passes on the token; then you send a test message to it. | A Firebase project and its `google-services.json` |
| Google sign-in | [Google Play Games Services for Godot](https://github.com/godot-sdk-integrations/godot-play-game-services) v3.4.0 (games-v2 21.0.0) | MIT | Initializes Play Games, checks sign-in and signs in if needed. Passes when signed in. | Play Games Services project, OAuth credential, tester |
| Play Integrity | Ours: `client/android_plugins/play_integrity` (Java, `com.google.android.play:integrity:1.6.0`) | Ours | Prepares a standard token provider and requests one token. Passes on the token; the server decodes tokens from M4. | A linked Google Cloud project number |

No maintained Godot 4 plugin for Play Integrity turned up, so the repo carries a small one (see D-011 in `docs/DECISIONS.md`).

## How the plugins get into the build

- `tools/fetch_plugins.sh` downloads each pinned release from GitHub, checks it against its SHA-256 and unpacks only the folders the client needs into `client/addons/` (and Firebase's two Android modules into `client/android/`). Those folders are git-ignored. Run it before opening the client in Godot; CI runs it in every job that opens the client. To update a plugin, change its line in the script, run it, export, and commit the new hash only after the Plugin Lab passes.
- AdMob's addon downloads its own binaries, without a hash check, when it starts headless and doesn't find them. The script pins and installs those binaries too, so that never happens.
- Firebase needs Google's Gradle plugin added to the Android build template. Godot reinstalls the template on every CI export, so the small `client/addons/firebase_gradle` addon makes that edit at the start of each Android export, and only when `client/google-services.json` exists.
- Play Games registers an autoload. Keep its line in `client/project.godot` as a `res://` path: the addon rewrites it to a `uid://` value that only works on your machine, and a tool test fails if that gets committed.
- After the export, `tools/ci/check_apk_plugins.sh` fails CI unless every plugin is registered in the APK's manifest. Godot drops a missing plugin without failing the export.

### What CI builds

Every push to `m0-foundations`, and every manual run (Actions tab, **CI**, **Run workflow**), builds:

- `aetd-m0-debug.apk`: the test build you install on the phone.
- `aetd-m0-release.aab`: the bundle you upload to Play. Only built once the upload key secrets exist (step 2 below).

The run's summary page shows which key signed the build, its SHA-1 and SHA-256, and which owner settings the build includes.

### The owner's settings

All of them live in the GitHub repo under **Settings > Secrets and variables > Actions**, so you never edit code. Each is optional; a build without one still works, and the matching Lab check tells you it's missing.

| Name | Kind | What it is | Step |
| --- | --- | --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Secret | Your upload key, as text | 2 |
| `ANDROID_KEYSTORE_PASSWORD` | Secret | Its password | 2 |
| `ANDROID_KEY_ALIAS` | Secret | Its alias, `upload` | 2 |
| `PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER` | Variable | Google Cloud project number (digits) | 5 |
| `PLAY_GAMES_PROJECT_ID` | Variable | Play Games Services project ID (digits) | 6 |
| `GOOGLE_SERVICES_JSON` | Secret | The whole text of Firebase's `google-services.json` | 7 |

`google-services.json` is a secret because the repo is public: Firebase says its config isn't secret, but recommends keeping it out of open-source repos.

## Walkthrough for the owner

Do the steps in order. Steps 1 and 2 need no Google accounts beyond the phone's. After each step that changes a setting, start a new build: Actions tab > **CI** > **Run workflow** > branch `m0-foundations`, and install the new APK when it finishes (about 5 minutes).

### 1. Install the APK and run the sim tests

1. On the phone, sign in to github.com in the browser (artifacts need a signed-in account).
2. Open the repo's **Actions** tab, then the newest green **CI** run on `m0-foundations`.
3. Scroll to **Artifacts** and tap **aetd-m0-debug.apk**. It downloads as an APK.
4. Open the download. Android asks to allow installs from your browser: tap **Settings**, turn on **Allow from this source**, go back and tap **Install**. Play Protect may offer to scan an app it hasn't seen before; that's expected, let it scan.
5. If Android says the app isn't installed because it conflicts with an existing package, uninstall **AETD Plugin Lab** first. Builds signed with different keys can't update each other; this happens once, when you move to your upload key in step 2.
6. Open **AETD Plugin Lab** and tap **Sim tests**. Every line should be green and the top line should read **ALL CHECKS PASS**. Take a screenshot. This is the "same hash on Android" check of M0.
7. Back on the home screen, open **Plugin Lab** and run **AdMob rewarded ad**. A Google test ad plays; watch it to the end. The check passes when the SDK grants the reward.

From a computer with the Android platform tools, `adb install -r aetd-m0-debug.apk` works too.

Android's new developer verification doesn't cover direct sideloads or `adb` installs as of today, so none of this needs a verified developer account.

### 2. Make your upload key

Play only accepts uploads signed with your own key, and the same key keeps every CI build installable over the last one and gives Play Games a stable SHA-1.

1. On github.com, open the repo, tap **Code > Codespaces > Create codespace on m0-foundations**. (Any computer with Java 17 or newer works too.)
2. In the codespace's terminal, run `tools/make_upload_key.sh`.
3. It writes three files to `~/aetd-upload-key/`. For each, run `code ~/aetd-upload-key/<NAME>.txt`, select all, copy, and add a repository secret with that name and the copied text as its value: **Settings > Secrets and variables > Actions > New repository secret**.
4. Save the text of `ANDROID_KEYSTORE_BASE64.txt` and the password together in your password manager. Together they are the key. If it's ever lost, Play Console can reset an upload key, but that takes a support request.
5. Delete the folder (`rm -r ~/aetd-upload-key`) and then the codespace (**Code > Codespaces > ... > Delete**).
6. Start a new build. Its summary should say **upload-key**, and its artifacts now include **aetd-m0-release.aab**. Uninstall the old app and install the new APK as in step 1.

### 3. Create the Play Console app and make the first upload

Billing, Play Games and the Integrity test tools all hang off a Play Console app. The Plugin Lab gets its own app, `com.alienempiretd.pluginlab`, so the real game's package name stays free (D-010).

1. Finish the Play Console account checks early: identity verification, and device verification in the **Play Console** mobile app (it needs an Android 10 or newer phone). Google doesn't say whether internal testing waits for them.
2. **Create app**: app name "AETD Plugin Lab", package name `com.alienempiretd.pluginlab`, your default language, **Game** (Play Games Services needs a game), **Free**, and a contact email. Accept the declarations, including the Play App Signing terms, and tap **Create app**.
3. Download **aetd-m0-release.aab** from the latest CI run on a computer.
4. **Test and release > Testing > Internal testing > Create new release**. If it asks about the app signing key, keep the Google-generated one: Google signs what it delivers, and you keep only the upload key. Upload the AAB, add a release name, **Save**, **Review release**, **Start rollout to Internal testing**. Play may list setup tasks it wants first; internal testing doesn't need the closed-test requirement that production has.
5. On the **Testers** tab, create an email list with your Google account and save.

Each new upload needs a higher version code. CI uses its run number, so a newer AAB always works.

### 4. Billing

1. **Monetize with Play > Products > In-app products > Create product**. Product ID `m0_test_gems`, any name, description and price. **Save**, then **Activate**.
2. Your Play Console account is a license tester automatically. Make sure it's the phone's main Google account, and that the Play Store app is up to date.
3. On the phone, run **Play Billing** in the Lab. A new product can take a while to show up; if Play doesn't return it yet, try again later.

License testers can test billing on the sideloaded debug APK; it doesn't have to come from Play, as long as the package name matches.

### 5. Play Integrity

1. Play Console: **Protected with Play > Play Integrity API > Link Cloud project**. Create a new Google Cloud project or pick one; linking also enables the API.
2. In [Google Cloud console](https://console.cloud.google.com), select that project; its **Project number** is on the dashboard (digits only, not the project ID).
3. GitHub: **Settings > Secrets and variables > Actions > Variables > New repository variable**: name `PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER`, value the number.
4. Start a new build, install it, and run **Play Integrity**. It passes when it gets a token. On a sideloaded build the verdict inside will say the app isn't recognized by Play; that's expected, and the server reads verdicts from M4.

### 6. Play Games sign-in

1. In the Google Cloud project from step 5, enable the **Google Play Games Services API**.
2. Play Console: **Grow users > Play Games Services > Setup and management > Configuration**. Create a Play Games Services project for this app (only the display name is needed for testing). Note the **Project ID** shown under the game's name (digits).
3. Set up the OAuth consent screen when Play Console asks: add the scopes `games`, `games_lite` and `drive.appdata`, and publish it or make it available to test users.
4. **Credentials > Add credential > Android**: package name `com.alienempiretd.pluginlab`, and the **SHA-1** from the build's run summary (the upload key's SHA-1; `tools/make_upload_key.sh` printed it too). If you also install builds from Play, add a second Android credential with the app signing key's SHA-1 from Play Console's app signing page.
5. **Setup and management > Testers**: add your own Google account. Google says the SDK won't work for your account otherwise; it can take a couple of hours to take effect.
6. GitHub: add the variable `PLAY_GAMES_PROJECT_ID` with the Project ID.
7. Start a new build, install it, and run **Google sign-in (Play Games)**.

### 7. Push notifications (Firebase)

1. In the [Firebase console](https://console.firebase.google.com), create a project (you can add Firebase to the Cloud project from step 5).
2. Add an Android app with package name `com.alienempiretd.pluginlab`. Download `google-services.json`.
3. GitHub: add the secret `GOOGLE_SERVICES_JSON` with the file's whole text. CI checks it's valid JSON for our package name and stops with a clear message if not.
4. Start a new build, install it, and run **Push notifications (FCM)**. Allow notifications when Android asks. The check passes when it shows the phone's FCM token. Tap **Copy this check's output** and send the token to yourself.
5. Put the app in the background. In the Firebase console: **DevOps & Engagement > Messaging > Create your first campaign > Firebase Notification messages > Create**. Enter a title and text, choose **Send test message**, paste the token into **Add an FCM registration token**, and tap **Test**. The notification should appear on the phone. With the app open instead, the message shows up in the check's output. The notification icon is a plain square for now; a real icon comes with the game's art.

### 8. Report back

Send screenshots of the **Sim tests** screen and of each Plugin Lab check after its run. M0 is done when the sim hashes match and every check passes; then `m0-foundations` merges into `main`.

## When a check fails

| Message | Likely cause and fix |
| --- | --- |
| "Plugin not installed" or "isn't in this build" | The APK was built without the plugin. Check the CI log's **Check every plugin is in the APK** step. |
| Billing: "didn't return m0_test_gems" | The product isn't **Active** yet, or hasn't propagated, or the phone's main account isn't a license tester. |
| Billing: `BILLING_UNAVAILABLE` or `DEVELOPER_ERROR` | Read Play's message after the code first. Usually there's no internal-testing release with the billing library yet, or the Play Store app is out of date. |
| Sign-in: "didn't finish within 3 minutes" | The Google account picker stayed open; run the check again and pick your account. |
| AdMob: "failed to load" | Network or ad availability. Google's demo units usually fill; run it again. |
| Push: "built without google-services.json" | The `GOOGLE_SERVICES_JSON` secret was missing when this build ran. Add it and rebuild. |
| Push: "permission is off" | Allow notifications for the app in Android settings, then run again. |
| Sign-in: "didn't complete" | Usually the credential's SHA-1 doesn't match the key that signed the APK, the consent screen isn't available to you, or you aren't a Play Games tester yet. A fresh tester entry can take a couple of hours. |
| Sign-in: "placeholder Play Games project ID" | `PLAY_GAMES_PROJECT_ID` wasn't set when this build ran. |
| Integrity: "no Google Cloud project number" | `PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER` wasn't set when this build ran. |
| Integrity: a numeric error | Look it up in Play's [Integrity error codes](https://developer.android.com/google/play/integrity/error-codes). |

## Sources

- Plugins: the release pages and source at each pinned tag, linked in the table above; Godot's [Android plugin](https://docs.godotengine.org/en/4.7/tutorials/platform/android/android_plugin.html) and [in-app purchases](https://docs.godotengine.org/en/4.7/tutorials/platform/android/android_in_app_purchases.html) docs.
- Billing testing: [Test your Play Billing integration](https://developer.android.com/google/play/billing/test), [Getting ready](https://developer.android.com/google/play/billing/getting-ready), [Create an in-app product](https://support.google.com/googleplay/android-developer/answer/1153481), [License testing](https://support.google.com/googleplay/android-developer/answer/6062777), [Billing Library deprecation FAQ](https://developer.android.com/google/play/billing/deprecation-faq).
- Play Console: [Create and set up your app](https://support.google.com/googleplay/android-developer/answer/9859152), [App bundles for new apps](https://support.google.com/googleplay/android-developer/answer/9859348), [Internal testing](https://support.google.com/googleplay/android-developer/answer/9845334), [Play App Signing and upload key reset](https://support.google.com/googleplay/android-developer/answer/9842756), [Testing requirements for new personal accounts](https://support.google.com/googleplay/android-developer/answer/14151465), [Device verification](https://support.google.com/googleplay/android-developer/answer/14316361), [Target API requirement](https://support.google.com/googleplay/android-developer/answer/11926878).
- Play Games Services: [Console setup](https://developer.android.com/games/pgs/console/setup), [Sign-in](https://developer.android.com/games/pgs/android/android-signin).
- Play Integrity: [Setup](https://developer.android.com/google/play/integrity/setup), [Verdicts](https://developer.android.com/google/play/integrity/verdicts), [Testing tools](https://developer.android.com/google/play/integrity/additional-tools).
- AdMob: [Quick start](https://developers.google.com/admob/android/quick-start), [Test ads](https://developers.google.com/admob/android/test-ads), [Next-Gen SDK test ads](https://developers.google.com/admob/android/next-gen/test-ads).
- Firebase: [FCM Android client](https://firebase.google.com/docs/cloud-messaging/android/client), [Config files in open-source projects](https://firebase.google.com/docs/projects/learn-more).
- Sideloading: [Install unknown apps](https://support.google.com/pixelphone/answer/7391672), [Play Protect warnings](https://developers.google.com/android/play-protect/warning-dev-guidance), [Developer verification FAQ](https://developer.android.com/developer-verification/guides/faq).
