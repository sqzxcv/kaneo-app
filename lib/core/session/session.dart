import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum CredentialType {
  /// `Authorization: Bearer`, from signing in with email and password.
  bearer,

  /// `x-api-key`, from signing in with an API key.
  apiKey,
}

/// A signed-in account on one server.
class Session {
  const Session({
    required this.serverUrl,
    required this.credentialType,
    required this.token,
    required this.userId,
    required this.userName,
    required this.userEmail,
  });

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    serverUrl: json['serverUrl'] as String,
    credentialType: CredentialType.values.byName(json['credentialType'] as String),
    token: json['token'] as String,
    userId: json['userId'] as String,
    userName: json['userName'] as String,
    userEmail: json['userEmail'] as String,
  );

  final String serverUrl;
  final CredentialType credentialType;
  final String token;
  final String userId;
  final String userName;
  final String userEmail;

  Map<String, dynamic> toJson() => {
    'serverUrl': serverUrl,
    'credentialType': credentialType.name,
    'token': token,
    'userId': userId,
    'userName': userName,
    'userEmail': userEmail,
  };
}

/// Where the session is kept between launches.
abstract class SessionStorage {
  Future<Session?> read();
  Future<void> write(Session session);
  Future<void> clear();
}

/// Keeps the session in the Keychain, Keystore or the desktop's secret service.
class SecureSessionStorage implements SessionStorage {
  SecureSessionStorage({this.key = 'kaneo.session'})
    : _storage = Platform.isMacOS
          // The data protection keychain needs a provisioning profile, which local builds lack.
          ? const FlutterSecureStorage(mOptions: MacOsOptions(usesDataProtectionKeychain: false))
          : const FlutterSecureStorage();

  /// An optional namespace lets integration tests avoid any existing app session.
  final String key;
  final FlutterSecureStorage _storage;

  @override
  Future<Session?> read() async {
    final raw = await _storage.read(key: key);
    if (raw == null) return null;
    try {
      return Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on ArgumentError {
      return null; // Unknown credential type from an older or damaged saved session.
    }
  }

  @override
  Future<void> write(Session session) =>
      _storage.write(key: key, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: key);
}

/// Keeps the session until the app exits.
class MemorySessionStorage implements SessionStorage {
  MemorySessionStorage([this._session]);

  Session? _session;

  @override
  Future<Session?> read() async => _session;

  @override
  Future<void> write(Session session) async => _session = session;

  @override
  Future<void> clear() async => _session = null;
}
