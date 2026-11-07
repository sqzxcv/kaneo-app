// The data tool/seed_black_box.dart writes. Running it against a server is checked by hand, on an
// empty local Kaneo, twice: see the comment at the top of the script.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/seed_black_box.dart';

const _targets = TagTargets(
  memberId: 'u1',
  memberName: 'E "Member" <&>',
  taskUrl: 'http://localhost:5173/dashboard/workspace/w/project/p/task/t1',
  taskKey: 'EBB-3',
  taskId: 't1',
);

void main() {
  group('descriptions', () {
    final descriptions = formatDescriptions(_targets);

    test('one task for each of the 17 formats', () {
      expect(descriptions, hasLength(17));
      expect(descriptions.keys.toSet(), hasLength(17));
      for (final (i, title) in descriptions.keys.indexed) {
        expect(title, startsWith('E-格式 ${(i + 1).toString().padLeft(2, '0')} '));
      }
    });

    test('each holds what its title says', () {
      String of(int n) => descriptions.entries.elementAt(n - 1).value;
      expect(of(1), allOf(contains('# 一级'), contains('## 二级'), contains('### 三级')));
      expect(of(2), allOf(contains('**'), contains('~~'), contains('`'), contains('](http')));
      expect(of(3), allOf(contains('  \n'), contains('\\\n')));
      expect(of(4), contains('\n    - '));
      expect(of(5), contains('2. '));
      expect(of(6), allOf(contains('- [ ] '), contains('- [x] ')));
      expect(of(7), contains('\n  - [x] '));
      expect(of(8), contains('> > '));
      expect(of(9), startsWith('```dart\n'));
      expect(of(10), contains('\n---\n'));
      expect(of(11), contains('| :--- |'));
      expect(of(12), startsWith('![应用图标](https://'));
      expect(of(13), allOf(startsWith('<img '), contains('width="120"')));
      expect(of(14), contains('<kaneo-mention id="u1" '));
      expect(of(15), contains('<kaneo-attachment url="https://'));
      expect(of(16), contains('<kaneo-issue-link url="http://localhost:5173/'));
      expect(of(17), contains('<kaneo-embed url="https://www.youtube.com/'));
    });

    test('the Kaneo tags are written as the web editor writes them, attributes escaped', () {
      expect(
        descriptions['E-格式 14 kaneo-mention'],
        contains(
          '<kaneo-mention id="u1" label="E &quot;Member&quot; &lt;&amp;&gt;"></kaneo-mention>',
        ),
      );
      expect(
        descriptions['E-格式 15 kaneo-attachment'],
        '<kaneo-attachment url="$attachmentUrl" filename="OFL.txt" mime-type="text/plain" '
        'size="$attachmentSize" />\n',
      );
      expect(
        descriptions['E-格式 16 kaneo-issue-link'],
        '<kaneo-issue-link url="${_targets.taskUrl}" issue-key="EBB-3" task-id="t1" />\n',
      );
      expect(descriptions['E-格式 17 kaneo-embed'], '<kaneo-embed url="$embedUrl" mode="embed" />\n');
    });

    test('the old description is HTML, as the old editor saved it', () {
      expect(legacyHtml, startsWith('<h2>'));
      expect(legacyHtml, isNot(contains('\n')));
    });

    test('the long description is more than a board sends whole, and says where it ends', () {
      final text = longDescription();
      expect(utf8.encode(text).length, greaterThan(64 * 1024));
      expect(text.trimRight(), endsWith(longEnd));
      expect(RegExp(longEnd).allMatches(text), hasLength(1));
    });
  });

  group('board', () {
    final columnOf = {for (final t in boardTasks) t.title: t.column};
    final parentsOf = <String, List<String>>{};
    for (final (parent, child) in boardRelations) {
      parentsOf.putIfAbsent(child, () => []).add(parent);
    }

    test('relates only tasks it makes', () {
      for (final (parent, child) in boardRelations) {
        expect(columnOf, contains(parent));
        expect(columnOf, contains(child));
      }
    });

    test('has six columns, the backlog and planned ones among them', () {
      expect(boardColumns, hasLength(6));
      expect(boardColumns, containsAll(['需求池', '已计划']));
      expect(boardColumns, contains(fullColumn));
      for (final task in boardTasks) {
        expect(boardColumns, contains(task.column));
      }
    });

    test('fills one column with 100 cards of their own', () {
      final titles = {for (var i = 1; i <= fullColumnSize; i++) fullColumnTitle(i)};
      expect(fullColumnSize, 100);
      expect(titles, hasLength(100));
      expect(titles, containsAll(['E-卡片 001', 'E-卡片 100']));
      expect(titles.intersection(columnOf.keys.toSet()), isEmpty);
      expect(boardTasks.where((t) => t.column == fullColumn), isEmpty);
    });

    test('has three levels of parents', () {
      String? parentOf(String title) => parentsOf[title]?.single;
      expect(parentOf(parentOf('E-三层 子')!), 'E-三层 祖父');
    });

    test('has a child in another column than its parent', () {
      expect(boardRelations.any((r) => columnOf[r.$1] != columnOf[r.$2]), isTrue);
    });

    test('has a child with two parents', () {
      expect(parentsOf.values.where((p) => p.length == 2), hasLength(1));
    });

    test('has parents that go round in a circle', () {
      var title = 'E-成环 甲';
      final seen = <String>[];
      while (!seen.contains(title)) {
        seen.add(title);
        title = parentsOf[title]!.single;
      }
      expect(title, 'E-成环 甲');
      expect(seen, hasLength(3));
    });
  });

  test('the accounts are the three the tests sign in as, and one with no workspace', () {
    expect(Person.values.map((p) => p.email).toSet(), hasLength(4));
    expect(memberRoles, {Person.member: 'member', Person.restricted: 'viewer'});
    expect(memberRoles.keys, isNot(contains(Person.loner)));
    for (final person in Person.values) {
      expect(person.email, endsWith('@kaneo.local'));
    }
  });

  test('the projects are told apart by name', () {
    expect(projects.map((p) => p.name).toSet(), hasLength(projects.length));
    expect(projects.map((p) => p.slug).toSet(), hasLength(projects.length));
    for (final project in projects) {
      expect(project.name, startsWith('E-'));
    }
  });

  test('the env file reads back what was written', () {
    final values = {'KANEO_BB_A': 'x=y', 'KANEO_BB_B': 'E-abc_-'};
    expect(readEnv(writeEnv(values)), values);
    expect(readEnv('# note\nKANEO_BB_A=1\n\n'), {'KANEO_BB_A': '1'});
  });
}
