import '../../core/core.dart';

/// The result kinds the page shows, in its order. The server also finds workspaces and other
/// activity; those aren't things this page looks for.
const List<({String type, String titleKey})> searchGroups = [
  (type: 'task', titleKey: 'mobile:search.kinds.tasks'),
  (type: 'comment', titleKey: 'mobile:search.kinds.comments'),
  (type: 'project', titleKey: 'mobile:search.kinds.projects'),
];

bool isSearchResultShown(SearchResult result) =>
    searchGroups.any((group) => group.type == result.type);

String _cacheKey(String workspaceId) => 'search/$workspaceId';

const String _textField = 'text';

/// What one search found. Every workspace only keeps its last search, and so a search for anything
/// else finds nothing cached. Search words vary too much to keep an entry for each.
final searchQuery = cachedQueryFamily<SearchResponse, ({String workspaceId, String text})>(
  (arg) => QuerySpec(
    key: _cacheKey(arg.workspaceId),
    fetch: (ref) => ref.read(kaneoApiProvider).search(arg.text, arg.workspaceId),
    encode: (response) => {_textField: arg.text, 'response': response.toJson()},
    decode: (json) {
      final map = (json as Map).cast<String, dynamic>();
      // How `CachedQuery` is told that this isn't what it is looking for.
      if (map[_textField] != arg.text) throw TypeError();
      return SearchResponse.fromJson((map['response'] as Map).cast<String, dynamic>());
    },
  ),
);

/// The words of the last search in [workspaceId] that is still in memory, if there is one.
String? rememberedSearch(CacheStore store, String workspaceId) {
  final cached = store.peek(_cacheKey(workspaceId));
  final text = cached is Map ? cached[_textField] : null;
  return text is String ? text : null;
}

Future<void> forgetSearch(CacheStore store, String workspaceId) =>
    store.remove(_cacheKey(workspaceId));
