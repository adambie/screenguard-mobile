# ScreenGuard Mobile

Android companion app for [ScreenGuard](https://github.com/adambie/screenguard) — the self-hosted parental control system for Linux.

Manage screen time limits, schedules, and devices from your phone. No cloud required — the app connects directly to your ScreenGuard server on the local network.

## Download

Grab `screenguard-android-<version>.apk` from the [latest release](https://github.com/adambie/screenguard-mobile/releases/latest) and sideload it (enable *Install unknown apps* in Android settings first).

## Features

- mDNS auto-discovery — finds the server on your local network automatically, no manual IP needed
- Manage profiles: daily time limits, weekly schedules, lock now, send messages to the user
- Manage devices: approve/pair new agents, rename, assign users to profiles
- Usage charts per profile
- Light/dark theme, 6 UI languages

## Requirements

- Android device
- A running [ScreenGuard server](https://github.com/adambie/screenguard) (v0.10.1 or later) on your local network

## Building from source

```bash
flutter pub get
flutter build apk --release
```

The APK will be at `build/app/outputs/flutter-apk/app-release.apk`.

## Server compatibility

The app calls `GET /api/v1/version` on startup to verify it is talking to a compatible server. If the server is too old, a warning is shown.

## Related

- [screenguard](https://github.com/adambie/screenguard) — the server and agent
