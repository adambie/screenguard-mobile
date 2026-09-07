# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this is

`screenguard-mobile` — a **Flutter** (Dart) Android companion app for
[ScreenGuard](https://github.com/adambie/screenguard), a self-hosted parental-control
system for Linux. Despite living under `~/programy/rust/`, there is no Rust here.

The app talks directly to a ScreenGuard server on the local network (no cloud).
~5.5k lines of Dart under `lib/`.

## Layout

```
lib/
  main.dart            App + AuthGate: serverUrl==null → ServerSetupScreen
                       → !isLoggedIn → LoginScreen → MainShell
  api_client.dart      Thin http wrapper; base = <serverUrl>/api/v1, Bearer token,
                       10s timeout, 401 → UnauthorizedException
  auth_provider.dart   AuthNotifier (StateNotifier). server_url in SharedPreferences;
                       token + username/password in FlutterSecureStorage.
                       relogin() replays stored credentials on 401.
  data_providers.dart  Riverpod FutureProviders (autoDispose) — one per read endpoint
  models.dart          Hand-written fromJson: Profile, Schedule, DailyLimit, Agent,
                       AgentUser, ProfileStatus, UsageEntry, BlockedDomain
  l10n.dart            Hand-rolled 1007-line localization map, 6 locales
                       (en/pl/es/fr/de/pt). NOT gen-l10n — no ARB files.
                       Adding a string = add a getter + entries in every locale map.
  settings_provider.dart  theme mode / language / show-logs, in SharedPreferences
  screens/             dashboard, profile_detail, agents, agent_detail, login,
                       server_setup, settings, about
  widgets/             daily_limits_editor, schedule_editor, usage_chart (fl_chart),
                       screen_guard_logo
test/widget_test.dart  4 model-level unit tests (no widget tests despite the name)
```

Server discovery is mDNS over `_parctrl._tcp.local.` in `server_setup_screen.dart`,
with a custom `rawDatagramSocketFactory` forcing `reusePort: false` (GrapheneOS and
some Android kernels reject reusePort — don't "simplify" that back).

Connect probe is `probeScreenGuardServer()` in `api_client.dart`, which both checks
reachability **and classifies the server**. There are two flavours, on independent
version axes (cloud versions the product, community the wire protocol) — so never
discriminate on the version number, only on which endpoints answer:

| endpoint | community (self-hosted) | cloud (`api.screenguard.cc`) |
|---|---|---|
| `/api/v1/version` | 200, since v0.10.2 | 200 |
| `/api/v1/auth/status` | 200 `{"setup_needed":…}` | **404** |
| `/api/v1/auth/setup` | 200 | **404** |
| `/api/v1/auth/signup` | — | 200 (not called by the app) |

Ask `/version` first (both modern servers have it), fall back to `/auth/status` for
community servers older than v0.10.2. `/auth/status` is community-only *by construction*
— it reads the public admin table, which multi-tenant cloud does not have — so a clean
404 there is the cloud signal. Everything else (dashboard, profiles, agents, usage) is
byte-identical between the two; a response-shape mismatch is not a plausible diagnosis,
so look at auth or tenant resolution instead.

The result is persisted as `server_kind` alongside `server_url` and lives on
`AuthState.serverKind` / `.isCloud`. A null kind (installs from before 0.0.11) means
community — the safe default, since misreading community as cloud would make a fresh
self-hosted server impossible to set up from the app.

**Cloud has no onboarding path in the app.** Accounts are created on the web UI
(`/auth/signup`); mobile only signs in, and `login_screen.dart` skips the setup check
entirely when `isCloud`. Adding mobile signup means calling `/auth/signup`, which returns
the same `{token, expires_at}` shape as `/auth/login`.

Server entry (`server_setup_screen.dart`): a **Use ScreenGuard Cloud** button connects to
the fixed `cloudServerUrl` with `assume: ServerKind.cloud` (kind is known at compile time,
never probed — otherwise a cloud server that ever answered `/auth/status` would start
offering admin creation). Self-hosted keeps mDNS discovery and manual entry; manual entry
defaults the port to **8080** when none is typed, while an explicit `http://`/`https://`
scheme is used verbatim (so `https://host` stays on 443).

## Release / CI

`.github/workflows/release.yml` is the **only** workflow. Trigger: `push` of a tag
matching `v*`. There is no `workflow_dispatch`, no PR/push-to-main CI.

Steps: checkout → JDK 17 (temurin) → `subosito/flutter-action@v2` (`channel: stable`,
`flutter-version: '3.47.2'`) → `flutter pub get` → `flutter build apk --release
--dart-define=APP_VERSION=${GITHUB_REF_NAME#v}` → rename to
`dist/screenguard-android-<version>.apk` → `softprops/action-gh-release@v2` with
`generate_release_notes: true`.

### Two version tracks, nothing reconciles them

| Source | Drives |
|---|---|
| Git tag `vX.Y.Z` | APK filename, and the About screen (`APP_VERSION` dart-define → `String.fromEnvironment` in `about_screen.dart:5`) |
| `pubspec.yaml` `version: X.Y.Z+N` | What's *inside* the APK: `flutter.versionName` / `flutter.versionCode` in `android/app/build.gradle.kts:25-26` |

Tagging without bumping `pubspec.yaml` ships an APK *named* 0.1.0 whose manifest still
says 0.0.9 with an unchanged `versionCode` — the About screen and the package manager
then disagree, and Android will refuse a later downgrade because versionCode never moved.
Always bump both.

### Cutting a release

History pairs the build number with the patch (`0.0.8+8`, `0.0.9+9`), so next is `0.0.10+10`:

```bash
sed -i 's/^version: .*/version: 0.0.10+10/' pubspec.yaml
git commit -am "chore: bump mobile version to 0.0.10"
git push
git tag -a v0.0.10 -m "v0.0.10"
git push origin v0.0.10        # this alone starts the pipeline
gh run watch                   # ~6 min; gh release view v0.0.10 when done
```

Redoing a release: `gh run rerun <id>`, or delete + re-push the tag
(`git push origin :refs/tags/v0.0.10`, then re-tag). `action-gh-release@v2` updates an
existing release rather than failing, so a re-run replaces the asset in place.

Current state: tag `v0.0.9`, one release, one successful run.

## Constraints to respect

- **Release APKs are signed with the Android *debug* key.** `build.gradle.kts:31-33`
  uses `signingConfigs.getByName("debug")`; no keystore, no `key.properties`, no signing
  secrets in the workflow. The debug keystore is auto-generated on the runner, so
  signatures are not guaranteed stable between releases — a user may have to uninstall
  before sideloading the next APK. Fixing this means a real keystore in repo secrets;
  don't do it unsolicited, but flag it if release/distribution comes up.
- **Nothing verifies the code before a tag.** No `flutter analyze`, no `flutter test` in
  CI, and **flutter/dart are not installed on this machine** — `which flutter` fails. So
  `test/widget_test.dart` never actually runs anywhere, and a compile error surfaces only
  when a tag is pushed. Reason carefully about Dart changes; you cannot compile-check them
  here. Say so rather than claiming a change is verified.
- `applicationId` / `namespace` is `cc.screenguard.mobile` (renamed from the scaffold
  placeholder `com.parentalcontrol.mobile` before F-Droid submission; the Kotlin source
  lives at `android/app/src/main/kotlin/cc/screenguard/mobile/`). Changing it again breaks
  upgrades for existing installs, and after an F-Droid publish it is the permanent app
  identity — don't. The unbuilt ios/macos/linux/windows runner dirs still carry the old
  id; harmless, since Android is the only shipped target.
- Flutter is pinned to `3.47.2` in `release.yml` (the version the green v0.0.11 build ran
  on, matching `sdk: ^3.12.2`). Two reasons not to unpin: unpinned `stable` makes builds
  unreproducible, and F-Droid's Flutter recipe `sed`s that exact
  `flutter-version: '…'` line to check out the matching Flutter revision — the recipe
  asserts a non-empty match, so removing or reformatting it fails their build. Keep it
  the *only* such line in the file: their `sed -n …p` prints every match, so a second
  `flutter-version:` (a matrix entry, another job) would break their checkout.
- Android permissions (`android/app/src/main/AndroidManifest.xml`): INTERNET,
  ACCESS_WIFI_STATE, ACCESS_NETWORK_STATE, CHANGE_WIFI_MULTICAST_STATE (the last is what
  makes mDNS discovery work).
- iOS/macOS/Linux/Windows runner dirs exist from `flutter create` but are unused and
  unbuilt — Android is the only shipped target.

## Conventions

- Conventional-commit subjects (`feat:`, `fix:`, `chore:`, `docs:`, `ci:`), sometimes
  scoped (`fix(mobile):`). Server-related commits historically carried the server version
  in parens.
- `flutter_lints` via `analysis_options.yaml`, unmodified.
- State is Riverpod `StateNotifierProvider` / `FutureProvider.autoDispose`; new read
  endpoints go in `data_providers.dart`, writes are called inline from screens.
- Every user-facing string goes through `AppLocalizations` (`l10n.dart`) — check that all
  6 locales get an entry, English is the fallback.
