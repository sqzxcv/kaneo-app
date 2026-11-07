import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/markdown/markdown_view.dart';

import '../../support/test_app.dart';

/// A 1x1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

/// Loads images over real HTTP. `NetworkImage` keeps one client per isolate, so this has to be in
/// its own file: the other tests' client answers every request with a 400.
void main() {
  testWidgets('an image on the server arrives, with the credentials sent', (tester) async {
    final previous = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previous);

    final requests = <HttpHeaders>[];
    final paths = <String>[];
    // Inside runAsync, so the server's callbacks run on the real clock.
    final server = (await tester.runAsync(() async {
      final bound = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      bound.listen((request) {
        requests.add(request.headers);
        paths.add(request.uri.path);
        request.response
          // A connection kept open would leave the client's idle timer pending when the test ends.
          ..persistentConnection = false
          ..headers.contentType = ContentType('image', 'png')
          ..add(_png);
        request.response.close();
      });
      return bound;
    }))!;
    addTearDown(() => tester.runAsync(() => server.close(force: true)));

    final session = Session(
      serverUrl: 'http://127.0.0.1:${server.port}',
      credentialType: CredentialType.apiKey,
      token: 'secret-key',
      userId: FakeKaneo.userId,
      userName: 'Test User',
      userEmail: FakeKaneo.email,
    );
    await pumpInApp(
      tester,
      const MarkdownView(data: '<img src="/api/asset/1" alt="Shot" width="320" />'),
      session: session,
      settle: false,
    );
    expect(find.byKey(markdownImageLoadingKey), findsOneWidget);

    // Real sockets and a real decode: give them real time, and let the test clock pick up the
    // results.
    for (var i = 0; i < 200 && find.byKey(markdownImageLoadingKey).evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }

    expect(paths, ['/api/asset/1']);
    expect(requests.single.value('x-api-key'), 'secret-key');
    expect(find.byKey(markdownImageLoadingKey), findsNothing);
    expect(tester.getSize(find.byType(Image)).width, 320);
  });
}
