// KAN-45: KAN-2 started every page as a placeholder and every shared component as the simplest thing
// that worked, for later tasks to replace. They all have been. This keeps any from coming back.
//
// That every route opens a real page with real data is in pages_test.dart.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What a stand-in says about itself, in code or in the text it shows.
final _standIn = RegExp(
  r'PlaceholderPage|placeholder\.notice|\bTODO\b|\bFIXME\b|later task|comes with KAN-|'
  r'最简|占位页|佔位頁|后续任务|後續任務|由 KAN-\d+ 实|由 KAN-\d+ 實',
);

Iterable<String> _strings(Object? json) sync* {
  if (json is String) yield json;
  if (json is Map) {
    for (final value in json.values) {
      yield* _strings(value);
    }
  }
}

void main() {
  test('no code in lib says it is a stand-in', () {
    final found = <String>[];
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (_standIn.hasMatch(lines[i])) found.add('${file.path}:${i + 1}: ${lines[i].trim()}');
      }
    }
    expect(found, isEmpty);
  });

  test("no text of the app's own says it is a stand-in", () {
    final found = <String>[];
    for (final file in Directory('assets/i18n/overrides').listSync().whereType<File>()) {
      for (final text in _strings(jsonDecode(file.readAsStringSync()))) {
        if (_standIn.hasMatch(text)) found.add('${file.path}: $text');
      }
    }
    expect(found, isEmpty);
  });
}
