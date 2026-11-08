import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';

import '../support/test_app.dart';

Finder picture(String url) => find.byWidgetPredicate(
  (w) => w is Image && w.image is NetworkImage && (w.image as NetworkImage).url == url,
);

/// A one-pixel PNG.
const pixel =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

void main() {
  testWidgets('a picture on the instance loads from the server', (tester) async {
    await pumpInApp(tester, const PersonAvatar(name: 'Test User', image: '/api/user/avatar/a1'));
    expect(picture('${FakeKaneo.serverUrl}/api/user/avatar/a1'), findsOneWidget);
  });

  testWidgets('a picture elsewhere loads from there', (tester) async {
    await pumpInApp(
      tester,
      const PersonAvatar(name: 'Test User', image: 'https://avatars.example.com/u/1'),
    );
    expect(picture('https://avatars.example.com/u/1'), findsOneWidget);
  });

  testWidgets('a data URL is drawn as it is', (tester) async {
    await pumpInApp(tester, const PersonAvatar(name: 'Test User', image: pixel));
    expect(find.byWidgetPredicate((w) => w is Image && w.image is MemoryImage), findsOneWidget);
  });

  testWidgets('without a picture the initials show', (tester) async {
    await pumpInApp(tester, const PersonAvatar(name: 'Test User', image: null));
    expect(find.text('TU'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a picture that does not load leaves the initials', (tester) async {
    await pumpInApp(
      tester,
      const PersonAvatar(name: 'Second User', image: '/api/user/avatar/gone'),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(find.text('SU'), findsOneWidget);
  });

  testWidgets('a malformed data URL leaves the initials', (tester) async {
    await pumpInApp(tester, const PersonAvatar(name: 'Test User', image: 'data:image/png;base64'));
    expect(find.text('TU'), findsOneWidget);
  });
}
