import 'dart:convert';
import 'dart:io';

/// Keeps API responses as JSON, so pages can show the last known data right away.
///
/// [peek] answers synchronously from memory, which lets a page that was open a moment ago skip the
/// loading state entirely.
abstract class CacheStore {
  Object? peek(String key);
  Future<Object?> read(String key);
  Future<void> write(String key, Object? json);
  Future<void> remove(String key);
  Future<void> clear();
}

class MemoryCacheStore implements CacheStore {
  final Map<String, Object?> _memory = {};

  @override
  Object? peek(String key) => _memory[key];

  @override
  Future<Object?> read(String key) async => _memory[key];

  @override
  Future<void> write(String key, Object? json) async => _memory[key] = json;

  @override
  Future<void> remove(String key) async => _memory.remove(key);

  @override
  Future<void> clear() async => _memory.clear();
}

/// Adds one JSON file per key on top of the memory layer. Disk failures only lose the cache.
class FileCacheStore extends MemoryCacheStore {
  FileCacheStore(this.directory);

  final Directory directory;

  File _file(String key) => File('${directory.path}/${Uri.encodeComponent(key)}.json');

  @override
  Future<Object?> read(String key) async {
    final inMemory = peek(key);
    if (inMemory != null) return inMemory;
    try {
      final file = _file(key);
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      await super.write(key, json);
      return json;
    } on Exception {
      return null;
    }
  }

  @override
  Future<void> write(String key, Object? json) async {
    await super.write(key, json);
    try {
      await directory.create(recursive: true);
      await _file(key).writeAsString(jsonEncode(json), flush: false);
    } on Exception {
      // The memory layer still has it.
    }
  }

  @override
  Future<void> remove(String key) async {
    await super.remove(key);
    try {
      await _file(key).delete();
    } on Exception {
      // Already gone.
    }
  }

  @override
  Future<void> clear() async {
    await super.clear();
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } on Exception {
      // Nothing more can be done; the next account gets its own directory anyway.
    }
  }
}
