# ScreenGuard Mobile

Android companion app for [ScreenGuard](https://github.com/adambie/screenguard) — the self-hosted parental control system for Linux.

Manage screen time limits, schedules, and devices from your phone. No cloud required — the app connects directly to your ScreenGuard server on the local network.

## Download

Grab `screenguard-android-<version>.apk` from the [latest release](https://github.com/adambie/screenguard-mobile/releases/latest) and sideload it (enable *Install unknown apps* in Android settings first).

## Screenshots

<p align="center">
  <img src="docs/screenshots/mobile-profiles.png" width="30%" alt="Profiles dashboard" />
  &nbsp;&nbsp;
  <img src="docs/screenshots/mobile-profile-detail.png" width="30%" alt="Profile detail with usage chart" />
  &nbsp;&nbsp;
  <img src="docs/screenshots/mobile-devices.png" width="30%" alt="Devices list" />
</p>

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

The app does not check the server's version. On connect it probes `GET /api/v1/auth/status`
to confirm the address is a reachable ScreenGuard server — nothing more. Against an older
server the connection still succeeds and any feature whose endpoint is missing fails only
when you use it, so make sure the server is v0.10.1 or later.

## Related

- [screenguard](https://github.com/adambie/screenguard) — the server and agent

## License

GNU Affero General Public License, version 3 or (at your option) any later version —
`AGPL-3.0-or-later`. See [LICENSE](LICENSE) for the full text.
