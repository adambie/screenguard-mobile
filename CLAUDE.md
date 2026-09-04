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

Connect probe is `probeScreenGuardServer()` in `api_client.dart`: `GET /api/v1/auth/status`,
falling back to `GET /api/v1/version` on any HTTP error. **Two server generations expose
mirror-image endpoints** and neither has both — verified 2026-09-04:

| endpoint | self-hosted LAN server | api.screenguard.cc (0.2.7) |
|---|---|---|
| `/api/v1/auth/status` | 200 `{"setup_needed":false}` | 404 |
| `/api/v1/version` | 404 | 200 `{"version":"0.2.7"}` |

So never probe with a single endpoint. The 0.2.7 host also 404s `/auth/setup`, so
first-time admin creation is impossible there — the app can only sign in to an existing
account. `login_screen.dart` already degrades correctly (its `/auth/status` failure is
swallowed and `_setupNeeded` stays false).

Manual server entry defaults the port to **8080** when the typed address has none;
an explicit `http://`/`https://` scheme is used verbatim (so `https://host` stays on 443).

## Release / CI

`.github/workflows/release.yml` is the **only** workflow. Trigger: `push` of a tag
matching `v*`. There is no `workflow_dispatch`, no PR/push-to-main CI.

Steps: checkout → JDK 17 (temurin) → `subosito/flutter-action@v2` (`channel: stable`,
no pinned version) → `flutter pub get` → `flutter build apk --release
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
- `applicationId` is still the scaffold placeholder `com.parentalcontrol.mobile`, with
  Flutter's TODO comments intact. Changing it breaks upgrades for existing installs.
- `channel: stable` is unpinned against `sdk: ^3.12.2`, so builds are not reproducible;
  a green build today can break on a Flutter stable release.
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
