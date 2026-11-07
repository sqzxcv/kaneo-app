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

  group('linkedTaskId', () {
    const page = '/dashboard/workspace/w1/project/p1/task/t1';

    test('reads a task link from the editor, wherever its page is', () {
      expect(linkedTaskId(server, taskLinkTo('t1')), 't1');
      expect(linkedTaskId(null, taskLinkTo('t1')), 't1');
      expect(linkedTaskId(server, taskLinkTo('a b/c')), 'a b/c');
    });

    test('reads the page of a task on the signed-in server', () {
      expect(linkedTaskId(server, '$server$page'), 't1');
      expect(linkedTaskId(server, '$server$page/'), 't1');
      expect(linkedTaskId(server, '$server$page?tab=activity#c1'), 't1');
      expect(linkedTaskId(server, 'https://KANEO.example.com:443$page'), 't1');
      expect(linkedTaskId(server, page), 't1');
      expect(linkedTaskId('http://localhost:1337', 'http://localhost:1337$page'), 't1');
    });

    test('reads the page under the path the server is reached at', () {
      expect(linkedTaskId('$server/kaneo', '$server/kaneo$page'), 't1');
      expect(linkedTaskId('$server/kaneo', '$server$page'), isNull);
    });

    test('leaves the page of a task on another server to the system', () {
      expect(linkedTaskId(server, 'https://other.test$page'), isNull);
      expect(linkedTaskId(server, 'http://kaneo.example.com$page'), isNull);
      expect(linkedTaskId(server, 'https://kaneo.example.com:5173$page'), isNull);
      expect(linkedTaskId(null, page), isNull);
    });

    test('leaves every other address to the system', () {
      for (final href in [
        null,
        '',
        '$server/dashboard/workspace/w1/project/p1',
        '$server/dashboard/workspace/w1/project/p1/task',
        '$server$page/subtasks',
        '$server/api/task/t1',
        '$server/EBB/task/EBB-1',
        'https://a.test/b',
        'mailto:a@b.test',
        'kaneo-task:',
        'kaneo-task:%E0',
      ]) {
        expect(linkedTaskId(server, href), isNull, reason: href);
      }
    });
  });

  test('taskIdInAddress reads the page of a task on any host', () {
    expect(taskIdInAddress('http://localhost:5173/dashboard/workspace/w/project/p/task/x1'), 'x1');
    expect(taskIdInAddress('https://a.test/dashboard/workspace/w/project/p/task/x1/'), 'x1');
    expect(taskIdInAddress('https://a.test/task/x1'), isNull);
    expect(taskIdInAddress(null), isNull);
    expect(taskIdInAddress('http://[bad'), isNull);
  });
}
