import 'package:flutter/foundation.dart';

/// Developer sign-in settings from `~/.config/kaneo-app/dev.env`, passed at build time:
///
///     flutter run --dart-define-from-file=$HOME/.config/kaneo-app/dev.env
///
/// Release builds always ignore them, so a key cannot be used in, or ship with, a real build path.
class DevConfig {
  const DevConfig({
    this.serverUrl = '',
    this.apiKey = '',
    this.workspaceId = '',
    this.projectId = '',
  });

  factory DevConfig.fromEnvironment() {
    if (kReleaseMode) return const DevConfig();
    return const DevConfig(
      serverUrl: String.fromEnvironment('KANEO_DEV_SERVER_URL'),
      apiKey: String.fromEnvironment('KANEO_DEV_API_KEY'),
      workspaceId: String.fromEnvironment('KANEO_DEV_WORKSPACE_ID'),
      projectId: String.fromEnvironment('KANEO_DEV_PROJECT_ID'),
    );
  }

  final String serverUrl;
  final String apiKey;

  /// Seeded sample data, for tests that run against the local server.
  final String workspaceId;
  final String projectId;

  bool get isConfigured => serverUrl.isNotEmpty && apiKey.isNotEmpty;
}
