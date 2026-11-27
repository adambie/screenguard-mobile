import 'dart:io';
import 'package:flutter/services.dart';

const _channel = MethodChannel('cc.screenguard.mobile/tailnet');

/// IPv4 addresses of the Tailscale peers this phone reaches, read from the
/// routes Tailscale's VPN installs (see `MainActivity.tailnetPeers`). Empty
/// when Tailscale is off or not installed, and on non-Android platforms.
Future<List<String>> tailnetPeers() async {
  if (!Platform.isAndroid) return const [];
  return await _channel.invokeListMethod<String>('peers') ?? const [];
}

/// The peer's MagicDNS machine name ("nas" for `nas.tail1234.ts.net`), or null
/// when the reverse lookup fails or MagicDNS is off.
Future<String?> tailnetName(String ip) async {
  try {
    final host = (await InternetAddress(ip)
            .reverse()
            .timeout(const Duration(seconds: 2)))
        .host;
    return host == ip ? null : host.split('.').first;
  } catch (_) {
    return null;
  }
}
