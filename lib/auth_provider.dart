import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

class AuthState {
  final String? serverUrl;

  /// Which flavour the stored server is. Null on installs that connected
  /// before the kind was recorded — treated as community, the safe default.
  final ServerKind? serverKind;
  final String? token;
  final bool isLoading;

  const AuthState({this.serverUrl, this.serverKind, this.token, this.isLoading = false});

  bool get isLoggedIn => token != null;

  /// Cloud has no admin-creation endpoint, so the app can only sign in there.
  bool get isCloud => serverKind == ServerKind.cloud;

  AuthState _copy({
    Object? serverUrl = _s,
    Object? serverKind = _s,
    Object? token = _s,
    bool? isLoading,
  }) =>
      AuthState(
        serverUrl: serverUrl == _s ? this.serverUrl : serverUrl as String?,
        serverKind: serverKind == _s ? this.serverKind : serverKind as ServerKind?,
        token: token == _s ? this.token : token as String?,
        isLoading: isLoading ?? this.isLoading,
      );
}

ServerKind? _kindFromName(String? name) {
  for (final kind in ServerKind.values) {
    if (kind.name == name) return kind;
  }
  return null;
}

const _s = Object();

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState(isLoading: true)) {
    _init();
  }

  static const _storage = FlutterSecureStorage();
  bool _relogging = false;

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('server_url');
    final serverKind = _kindFromName(prefs.getString('server_kind'));
    final token = await _storage.read(key: 'auth_token');
    state = AuthState(serverUrl: serverUrl, serverKind: serverKind, token: token);
  }

  Future<void> setServerUrl(String url, ServerKind kind) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', url);
    await prefs.setString('server_kind', kind.name);
    state = state._copy(serverUrl: url, serverKind: kind, token: null);
  }

  Future<void> clearServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('server_url');
    await prefs.remove('server_kind');
    await _storage.deleteAll();
    state = const AuthState();
  }

  Future<void> login(String username, String password, String token) async {
    await _storage.write(key: 'auth_token', value: token);
    await _storage.write(key: 'auth_username', value: username);
    await _storage.write(key: 'auth_password', value: password);
    state = state._copy(token: token);
  }

  Future<void> relogin() async {
    if (_relogging) return;
    _relogging = true;
    try {
      final username = await _storage.read(key: 'auth_username');
      final password = await _storage.read(key: 'auth_password');
      if (username == null || password == null) {
        await logout();
        return;
      }
      final client = ApiClient(baseUrl: state.serverUrl ?? 'http://localhost:8080');
      final data = await client.post('/auth/login', {'username': username, 'password': password})
          as Map<String, dynamic>;
      final token = data['token'] as String;
      await _storage.write(key: 'auth_token', value: token);
      state = state._copy(token: token);
    } catch (_) {
      await logout();
    } finally {
      _relogging = false;
    }
  }

  Future<void> logout() async {
    await _storage.deleteAll();
    state = AuthState(serverUrl: state.serverUrl, serverKind: state.serverKind);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);

final apiClientProvider = Provider<ApiClient>((ref) {
  final auth = ref.watch(authProvider);
  return ApiClient(
    baseUrl: auth.serverUrl ?? 'http://localhost:8080',
    token: auth.token,
  );
});
