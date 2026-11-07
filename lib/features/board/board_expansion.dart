import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kaneo_app/core/core.dart';

String boardExpansionKey(String projectId) => 'kaneo.board.expanded.$projectId';

final boardExpansionProvider = NotifierProvider.autoDispose
    .family<BoardExpansion, Set<String>, String>(BoardExpansion.new);

class BoardExpansion extends Notifier<Set<String>> {
  BoardExpansion(this.projectId);
  final String projectId;
  @override
  Set<String> build() =>
      ref.read(prefsProvider).getStringList(boardExpansionKey(projectId))?.toSet() ?? {};

  Future<void> toggle(String taskId) async {
    state = state.contains(taskId) ? ({...state}..remove(taskId)) : {...state, taskId};
    await ref
        .read(prefsProvider)
        .setStringList(boardExpansionKey(projectId), state.toList()..sort());
  }
}
