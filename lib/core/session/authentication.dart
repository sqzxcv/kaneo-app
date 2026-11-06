import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../i18n/i18n.dart';
import '../providers.dart';
import 'session.dart';

final authenticationProvider = Provider<Authentication>(
  (ref) => Authentication(ref.watch(apiClientProvider), ref.watch(i18nProvider)),
);

/// Self-hosted sign-in. No credentials are persisted until the server confirms the user.
class Authentication {
  Authentication(this._client, this._i18n);

  final ApiClient _client;
  final I18n _i18n;

  String serverAddress(String input) {
    final normalized = normalizeServerUrl(input);
    final uri = Uri.tryParse(normalized);
    if ((input.contains('://') && (Uri.tryParse(input.trim())?.host.isEmpty ?? true)) ||
        (input.contains('://') &&
            !RegExp(r'^https?://', caseSensitive: false).hasMatch(input.trim())) ||
        input.trim().isEmpty ||
        uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        RegExp(r'\s').hasMatch(input.trim()) ||
        uri.host.contains('%') ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ApiError(_i18n.t('app:auth.invalidAddress'));
    }
    return normalized;
  }

  Future<void> probe(String server) async {
    final config = await _client.request('api/config', serverUrl: server);
    if (config is! Map<String, dynamic>) {
      throw ApiError(_i18n.t('mobile:errors.notKaneo', {'url': server}));
    }
  }

  Future<Session> withPassword(String address, String email, String password) async {
    final server = serverAddress(address);
    await probe(server);
    final response = await _client.requestRaw(
      'api/auth/sign-in/email',
      serverUrl: server,
      method: 'POST',
      body: {'email': email.trim(), 'password': password, 'rememberMe': true},
    );
    if (!response.isOk) {
      throw ApiError(_client.httpMessage(response.status, response.body), status: response.status);
    }
    final body = response.body;
    final token = response.header('set-auth-token') ?? (body is Map ? body['token'] : null);
    if (token is! String || token.isEmpty) {
      throw ApiError(_i18n.t('app:auth.noSession'));
    }
    return _identify(server, token, CredentialType.bearer);
  }

  Future<Session> withApiKey(String address, String apiKey) async {
    final server = serverAddress(address);
    await probe(server);
    return _identify(server, apiKey.trim(), CredentialType.apiKey);
  }

  Future<Session> _identify(String server, String token, CredentialType type) async {
    Object? body;
    try {
      body = await _client.request(
        'api/user/me',
        serverUrl: server,
        credentials: ApiCredentials(type, token),
      );
    } on ApiError catch (error) {
      if (error.status == 401 || error.status == 403) {
        throw ApiError(
          _i18n.t(
            type == CredentialType.apiKey
                ? 'mobile:errors.apiKeyRejected'
                : 'mobile:errors.signInRejected',
          ),
          status: error.status,
        );
      }
      rethrow;
    }
    if (body is! Map<String, dynamic> || body['id'] is! String || (body['id'] as String).isEmpty) {
      throw ApiError(_i18n.t('app:errors.badResponse'));
    }
    final user = CurrentUser.fromJson(body);
    return Session(
      serverUrl: server,
      credentialType: type,
      token: token,
      userId: user.id,
      userName: user.name,
      userEmail: user.email,
    );
  }
}
