# Licenses

Every library, tool and asset the project uses, with its license, as the build prompt's working rules ask. Checked on 2026-11-11 against the artifacts themselves: the LICENSE files of the pinned releases, the license declared in each Maven POM, and PyPI's package metadata. Rows marked **Credits** need their notice inside the game; M9's credits or licenses screen shows them. Update this file in the same commit as any new dependency or version.

This is not legal advice. Where a license is a set of terms rather than a notice (Google's SDK licenses), the row says so.

## In the app

The Android build (APK and AAB) contains these.

| Component | Version | License | In the game |
| --- | --- | --- | --- |
| Godot Engine runtime (export templates) | 4.7.2 | MIT, "Copyright (c) 2014-present Godot Engine contributors. Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.", plus the third-party code Godot includes | **Credits**: Godot's license text, and the third-party notices `Engine.get_copyright_info()` and `Engine.get_license_info()` return at runtime ([Complying with licenses](https://docs.godotengine.org/en/4.7/about/complying_with_licenses.html)) |
| godot-cpp, compiled into the sim library | 10.0.0-stable (`507ed9d`) | MIT, "Copyright (c) 2017-present Godot Engine contributors." | **Credits** |
| [GodotGooglePlayBilling](https://github.com/godot-sdk-integrations/godot-google-play-billing) | 3.3.0 | MIT, "Copyright (c) 2020 Godot Engine contributors" | **Credits** |
| [Poing Studios AdMob plugin](https://github.com/poingstudios/godot-admob-plugin) | v5.1.0 | MIT, "Copyright (c) 2020-present Poing Studios" | **Credits** |
| [Godotx Firebase](https://github.com/godot-x/firebase), Core and Messaging | 3.1.0 | MIT, "Copyright (c) 2026 Paulo Coutinho". The release archive has no LICENSE file; the text is in the repository's `LICENSE`. | **Credits**, with the repository's text |
| [Google Play Games Services for Godot](https://github.com/godot-sdk-integrations/godot-play-game-services) | v3.4.0 | MIT, "Copyright (c) 2023 Jacob Ibáñez Sánchez" | **Credits** |
| Our Play Integrity plugin (`client/android_plugins/play_integrity`) | — | This project's own code | — |

### Libraries the plugins bring in through Gradle

The plugins and our Play Integrity plugin depend on Google's Android libraries, which Gradle resolves at export. The licenses below are the ones each library's POM declares, read from the resolved artifacts of an export of this client (their versions match the pins in `docs/PLUGINS.md`).

| Libraries | Examples | License the POM declares | In the game |
| --- | --- | --- | --- |
| Play Billing Library | `com.android.billingclient:billing` 9.1.0 | [Android Software Development Kit License](https://developer.android.com/studio/terms.html) | Terms of use, no notice |
| Google Mobile Ads (Next-Gen) SDK, User Messaging Platform | `ads-mobile-sdk` 1.4.0, `user-messaging-platform` 4.0.0 | Android Software Development Kit License | Terms of use |
| Google Play services | `play-services-games-v2` 21.0.0, `-base`, `-basement`, `-tasks`, `-cloud-messaging`, `-location` and others | Android Software Development Kit License | Terms of use |
| Play Integrity | `com.google.android.play:integrity` 1.6.0 | [Play Integrity API Terms of Service](https://developer.android.com/google/play/integrity/overview#tos) | Terms of use |
| Play Core common | `com.google.android.play:core-common` 2.0.4 | [Play Core Software Development Kit Terms of Service](https://developer.android.com/guide/playcore/license) | Terms of use |
| Firebase | `firebase-messaging` 25.1.1, `firebase-common` 22.1.0, `firebase-installations` 19.1.1 and others | Apache 2.0, except `firebase-iid-interop` and `firebase-measurement-connector` (Android Software Development Kit License) | **Credits** for the Apache 2.0 ones |
| AndroidX, the Kotlin standard library, Dagger, Error Prone annotations, gRPC, Guava, JSpecify | about 200 artifacts | Apache 2.0 | **Credits** |
| Protocol Buffers | `protobuf-*` | BSD-3-Clause | **Credits** |
| Checker Framework annotations | `checker-qual` | MIT | **Credits** |

This table groups libraries by license; it's not the exact list. Before release (M9), generate the exact list from the release build's resolved dependencies, and keep it with the credits.

### Assets the AdMob addon brings into the build

The export takes every resource, so the AdMob addon's editor and sample assets end up in the APK: icons, the Patreon, PayPal and Ko-fi donation logos, the Google Play and Android logos, `NotoSansSC-Regular.otf`, `music.ogg` (all in `addons/admob/assets/`) and `addons/admob/internal/translations/admob_sample.csv`. The game doesn't use any of them. None comes with its own license file, and the logos are their owners' trademarks. The M0 test build only goes to the owner's phone and internal testing; **release exports (M9) must exclude them**, for example with the export preset's exclude filter, after checking the plugin still works.

## Tools

These run on developers' machines and in CI. None ships in the app.

| Tool | Version | License |
| --- | --- | --- |
| Godot editor (imports, exports, headless tests) | 4.7.2 | MIT |
| SCons (builds the sim library) | 4.11.1 | MIT |
| jsonschema, with referencing, jsonschema-specifications, attrs and rpds-py | 4.26.0 | MIT |
| pytest, with pluggy and iniconfig | 9.1.1 | MIT; its dependencies `packaging` (Apache-2.0 or BSD-2-Clause) and Pygments (BSD-2-Clause) |
| PyYAML | 6.0.3 | MIT |
| Android SDK, NDK 28.1.13356709 and build tools | — | Android Software Development Kit License, accepted in CI through `sdkmanager` |
| GitHub Actions: checkout, setup-python, setup-java, cache, upload-artifact, download-artifact | v6 to v8 | MIT |
| `gradle/actions` setup-gradle | v6 | MIT, except its optional enhanced cache, which CI doesn't use (D-023) |
