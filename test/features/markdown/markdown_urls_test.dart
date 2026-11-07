import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/features/markdown/markdown_urls.dart';

void main() {
  const server = 'https://kaneo.example.com';

  group('resolveLink', () {
    test('keeps web and mail addresses', () {
      expect(
        resolveLink(server, 'https://a.test/b?c=1&d=2').toString(),
        'https://a.test/b?c=1&d=2',
      );
      expect(resolveLink(server, 'HTTP://a.test').toString(), 'http://a.test');
      expect(resolveLink(server, 'mailto:a@b.test').toString(), 'mailto:a@b.test');
    });

    test('puts server paths on the server', () {
      expect(resolveLink(server, '/api/asset/1').toString(), '$server/api/asset/1');
      expect(resolveLink('$server/', '/api/asset/1').toString(), '$server/api/asset/1');
    });

    test('refuses schemes that could do something else', () {
      for (final href in [
        'javascript:alert(1)',
        'file:///etc/passwd',
        'tel:123',
        'data:text/html,x',
      ]) {
        expect(resolveLink(server, href), isNull, reason: href);
      }
    });

    test('refuses what it cannot place', () {
      expect(resolveLink(server, null), isNull);
      expect(resolveLink(server, '  '), isNull);
      expect(resolveLink(server, 'docs/page'), isNull);
      expect(resolveLink(server, '#top'), isNull);
      expect(resolveLink(null, '/api/asset/1'), isNull);
      expect(resolveLink(server, 'http://[bad'), isNull);
    });
  });

  group('resolveImage', () {
    test('keeps web and data addresses', () {
      expect(resolveImage(server, 'https://a.test/b.png').toString(), 'https://a.test/b.png');
      expect(resolveImage(server, 'data:image/png;base64,AAAA')?.scheme, 'data');
    });

    test('puts server paths on the server', () {
      expect(resolveImage(server, '/api/asset/1').toString(), '$server/api/asset/1');
    });

    test('does not read local files', () {
      expect(resolveImage(server, 'file:///etc/passwd'), isNull);
      expect(resolveImage(server, 'resource:a.png'), isNull);
      expect(resolveImage(server, 'a.png'), isNull);
    });
  });

  group('isOnServer', () {
    bool check(String url, [String on = server]) => isOnServer(Uri.parse(url), on);

    test('accepts the same origin', () {
      expect(check('$server/api/asset/1'), isTrue);
      expect(check('https://KANEO.example.com:443/x'), isTrue);
      expect(check('http://localhost:1337/x', 'http://localhost:1337'), isTrue);
    });

    test('refuses every other origin', () {
      expect(check('https://evil.test/x'), isFalse);
      expect(check('https://kaneo.example.com.evil.test/x'), isFalse);
      expect(check('https://evil.test/https://kaneo.example.com'), isFalse);
      expect(check('https://kaneo.example.com:8443/x'), isFalse);
      expect(check('http://kaneo.example.com/x'), isFalse);
      expect(check('http://localhost:9/x', 'http://localhost:1337'), isFalse);
      expect(check('data:image/png;base64,AAAA'), isFalse);
    });
  });
}
