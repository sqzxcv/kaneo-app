import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../shell/workspace_gate.dart';

/// Placeholder until KAN-39.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  List<SearchResult>? _results;

  Future<void> _search(String query, String workspaceId) async {
    final response = await runAction(
      context,
      () => ref.read(kaneoApiProvider).search(query, workspaceId),
    );
    if (response != null && mounted) setState(() => _results = response.results);
  }

  @override
  Widget build(BuildContext context) {
    return PlaceholderPage(
      title: context.t('mobile:ui.search'),
      child: ContentWidth(
        child: WorkspaceGate(
          builder: (context, workspace) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  key: const ValueKey('search-field'),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(hintText: context.t('mobile:ui.search')),
                  onSubmitted: (query) => _search(query, workspace.id),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final result in _results ?? const <SearchResult>[])
                      ListTile(title: Text(result.title), subtitle: Text(result.type)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
