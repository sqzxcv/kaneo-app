import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';

import '../../support/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('keychain sessions round-trip and clear only their own namespace', () async {
    FlutterSecureStorage.setMockInitialValues({'kaneo.session': jsonEncode(testSession.toJson())});
    final testStorage = SecureSessionStorage(key: 'integration.session');
    expect(await testStorage.read(), isNull);
    await testStorage.write(testSession);
    final restored = await SecureSessionStorage(key: 'integration.session').read();
    expect(restored?.toJson(), testSession.toJson());
    await testStorage.clear();
    expect(await testStorage.read(), isNull);
    expect((await SecureSessionStorage().read())?.toJson(), testSession.toJson());
  });

  test('invalid saved sessions return to login instead of crashing startup', () async {
    for (final raw in [
      'invalid-json',
      '[]',
      '{}',
      jsonEncode({...testSession.toJson(), 'credentialType': 'removed-auth-type'}),
    ]) {
      FlutterSecureStorage.setMockInitialValues({'kaneo.session': raw});
      expect(await SecureSessionStorage().read(), isNull);
    }
  });
}
