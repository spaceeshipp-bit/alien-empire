# Licenses

Every library, tool and asset the project uses, with its license, as the build prompt's working rules ask. Checked on 2026-11-11 against the artifacts themselves:
- the LICENSE files of the pinned releases;
- the license each Maven POM declares;
- the notice files inside Google's libraries;
- PyPI's package metadata;
- the NDK's NOTICE files;
- the shipped APK's contents;
- Godot's own guidance.

Rows marked **Credits** need their license text inside the game; for Apache 2.0, that also means the contents of any NOTICE file. M9's credits or licenses screen shows them. Update this file in the same commit as any new dependency or version.

This is not legal advice.

## In the app

The Android build (APK and AAB) contains these.

| Component | Version | License | In the game |
| --- | --- | --- | --- |
| Godot Engine runtime (export templates) | 4.7.2 | MIT, "Copyright (c) 2014-present Godot Engine contributors. Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.", plus the third-party code Godot includes | **Credits**: Godot's license text, and the third-party notices `Engine.get_copyright_info()` and `Engine.get_license_info()` return at runtime ([Complying with licenses](https://docs.godotengine.org/en/4.7/about/complying_with_licenses.html)) |
| LLVM libc++, the C++ runtime (`lib/arm64-v8a/libc++_shared.so`), which Godot ships and the sim library also uses | from NDK 29.0.14206865 | Apache 2.0 with LLVM Exceptions (the NDK's `NOTICE.toolchain`) | **Credits**. Godot's third-party notices don't include it. |
| godot-cpp, compiled into the sim library | 10.0.0-stable (`507ed9d`) | MIT, "Copyright (c) 2017-present Godot Engine contributors." | **Credits** |
| [GodotGooglePlayBilling](https://github.com/godot-sdk-integrations/godot-google-play-billing) | 3.3.0 | MIT, "Copyright (c) 2020 Godot Engine contributors" | **Credits** |
| [Poing Studios AdMob plugin](https://github.com/poingstudios/godot-admob-plugin) | v5.1.0 | MIT, "Copyright (c) 2020-present Poing Studios" | **Credits** |
| [Godotx Firebase](https://github.com/godot-x/firebase), Core and Messaging | 3.1.0 | MIT, "Copyright (c) 2026 Paulo Coutinho". The release archive has no LICENSE file; the text is in the repository's `LICENSE`. | **Credits**, with the repository's text |
| [Google Play Games Services for Godot](https://github.com/godot-sdk-integrations/godot-play-game-services) | v3.4.0 | MIT, "Copyright (c) 2023 Jacob Ibáñez Sánchez" | **Credits** |
| This project's own code and assets: client, sim, the Play Integrity plugin, tools, config, icon | — | No license granted: the repository is public, but all rights are reserved until the owner chooses otherwise (Q9 in `docs/DECISIONS.md`) | — |

### Libraries from Gradle

Godot's Android build template, the plugins and our Play Integrity plugin depend on Android libraries that Gradle resolves at export. The licenses below are the ones each library's POM declares, read from the resolved artifacts of an export of this client. Their versions match the pins in `docs/PLUGINS.md`.

| Libraries | Examples (version) | License | In the game |
| --- | --- | --- | --- |
| Play Billing Library | `com.android.billingclient:billing` 9.1.0 | [Android Software Development Kit License](https://developer.android.com/studio/terms.html), a set of terms. Its package also carries a `third_party_licenses.txt` of open-source code inside it. | **Credits** for the notices in `third_party_licenses.txt` |
| Google Mobile Ads (Next-Gen) SDK, User Messaging Platform | `ads-mobile-sdk` 1.4.0, `user-messaging-platform` 4.0.0 | Android Software Development Kit License, plus `third_party_licenses.txt` in each package | **Credits** for those notices |
| Google Play services | `play-services-games-v2` 21.0.0, `-base`, `-basement`, `-tasks`, `-cloud-messaging`, `-cronet` and others | Android Software Development Kit License, plus `third_party_licenses.txt` in each package | **Credits** for those notices |
| Play Integrity | `com.google.android.play:integrity` 1.6.0 | [Play Integrity API Terms of Service](https://developer.android.com/google/play/integrity/overview#tos), plus `third_party_licenses.txt` | **Credits** for those notices |
| Play Core common | `com.google.android.play:core-common` 2.0.4 | [Play Core Software Development Kit Terms of Service](https://developer.android.com/guide/playcore#license) | Terms of use |
| Firebase | `firebase-messaging` 25.1.1, `firebase-common` 22.1.0, `firebase-installations` 19.1.1 and others | Apache 2.0, except `firebase-iid-interop` and `firebase-measurement-connector` (Android Software Development Kit License) | **Credits** |
| OkHttp, with the Public Suffix List | `com.squareup.okhttp3:okhttp` 4.11.0 | Apache 2.0. Its `publicsuffixes.gz` data is under the Mozilla Public License 2.0, as the NOTICE file shipped in the APK says. | **Credits**: the license, the NOTICE text and the list's source link |
| AndroidX, the Kotlin standard library, Dagger, Error Prone annotations, gRPC, Guava, JSpecify | about 200 artifacts | Apache 2.0 | **Credits** |
| Protocol Buffers | `protobuf-*` | BSD-3-Clause | **Credits** |
| Checker Framework annotations | `checker-qual` | MIT | **Credits** |

Google's [open-source notices guide](https://developers.google.com/android/guides/opensource) says the developer is responsible for showing the notices of the open-source libraries an app uses. It offers the oss-licenses Gradle plugin and SDK to collect and show them. This table groups libraries by license; it isn't the exact list.

**Before release (M9):** generate the exact list from the release build, including every package's `third_party_licenses.txt`. The oss-licenses plugin collects both.

### Assets the AdMob addon brings into the build

The export takes every resource, so the AdMob addon's editor and sample assets end up in the APK: 31 imported files, 2.4 MB, checked in the CI APK. They are in `addons/admob/assets/` and `addons/admob/internal/translations/admob_sample.csv`:
- icons;
- the Patreon, PayPal and Ko-fi donation logos;
- the Google Play and Android logos;
- `NotoSansSC-Regular.otf`;
- `music.ogg`.

The game doesn't use any of them. None comes with its own license file, and the logos are their owners' trademarks. The M0 test build only goes to the owner's phone and internal testing. **Release exports (M9) must exclude them**, for example with the export preset's exclude filter, after checking the plugin still works.

## Tools

These run on developers' machines and in CI. None ships in the app.

| Tool | Version | License |
| --- | --- | --- |
| Godot editor (imports, exports, headless tests) | 4.7.2 | MIT |
| Android SDK and NDK (29.0.14206865), build tools | — | Android Software Development Kit License, accepted in CI through `sdkmanager`. The NDK's clang and libc++ are Apache 2.0 with LLVM Exceptions. |
| OpenJDK (Temurin 17 in CI) | 17 | GPL version 2 with the Classpath Exception |
| Gradle | 8.14.3 | Apache 2.0 |
| Android Gradle Plugin, as Godot's build template asks | 8.6.1 | Apache 2.0 |
| google-services Gradle plugin (D-022) | 4.4.4 | Apache 2.0 |
| SCons (builds the sim library) | 4.11.1 | MIT |
| Python | 3.13 | Python Software Foundation License |
| jsonschema, with referencing, jsonschema-specifications, attrs and rpds-py | 4.26.0 | MIT |
| pytest, with pluggy and iniconfig | 9.1.1 | MIT; its dependencies `packaging` (Apache-2.0 or BSD-2-Clause) and Pygments (BSD-2-Clause) |
| PyYAML | 6.0.3 | MIT |
| g++ and clang++ (the sim core checks) | GCC 13, Clang 18 | GPL version 3 with the GCC Runtime Library Exception; Apache 2.0 with LLVM Exceptions |
| xvfb and Mesa (the desktop test's virtual display) | Ubuntu 24.04 packages | X.Org's MIT-style license; MIT, with some parts GPL-2 or MIT |
| GitHub Actions: checkout, setup-python, setup-java, cache, upload-artifact, download-artifact | v6 to v8 | MIT |
| `gradle/actions` setup-gradle | v6 | MIT, except its optional enhanced cache, which CI doesn't use (D-023) |
