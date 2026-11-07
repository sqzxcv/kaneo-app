import '../../core/core.dart';

const _linkSchemes = {'http', 'https', 'mailto'};
const _imageSchemes = {'http', 'https', 'data'};

/// Where a link goes, or null when the app should not open it. Descriptions are written by other
/// people, so a link can claim any scheme.
Uri? resolveLink(String? serverUrl, String? href) => _resolve(serverUrl, href, _linkSchemes);

/// Where an image loads from, or null when the app should not load it. That includes local files.
Uri? resolveImage(String? serverUrl, String? source) => _resolve(serverUrl, source, _imageSchemes);

Uri? _resolve(String? serverUrl, String? value, Set<String> schemes) {
  final text = value?.trim() ?? '';
  final uri = Uri.tryParse(text);
  if (text.isEmpty || uri == null) return null;
  if (uri.hasScheme) return schemes.contains(uri.scheme.toLowerCase()) ? uri : null;
  if (serverUrl == null || !text.startsWith('/')) return null;
  return Uri.tryParse(resolveUrl(serverUrl, text)!);
}

/// Whether [target] is on the user's own server. Credentials go nowhere else: a description can
/// point an image at any host.
bool isOnServer(Uri target, String serverUrl) {
  final server = Uri.tryParse(serverUrl);
  if (server == null || !const {'http', 'https'}.contains(server.scheme)) return false;
  if (!const {'http', 'https'}.contains(target.scheme.toLowerCase())) return false;
  return target.origin == server.origin;
}

const _taskLinkScheme = 'kaneo-task';

/// A link the app opens itself, to the task with this id. A task link the web's editor inserted
/// (`kaneo-issue-link`) is read as one, because the address in it is the web's, which need not be
/// the server the app signed in to.
String taskLinkTo(String taskId) => '$_taskLinkScheme:${Uri.encodeComponent(taskId)}';

/// A task's page on the web, as the web's own links and the app's "Copy link" write it.
final _taskPath = RegExp(r'^/dashboard/workspace/[^/]+/project/[^/]+/task/([^/?#]+)/?$');

/// The id of the task a web address of one is for, on whatever host. Null for any other address.
String? taskIdInAddress(String? url) {
  final path = Uri.tryParse(url?.trim() ?? '')?.path;
  return path == null ? null : _taskIdInPath(path);
}

String? _taskIdInPath(String path) => _decoded(_taskPath.firstMatch(path)?[1]);

/// [text] with its escapes undone, or null when there is nothing or they are broken.
String? _decoded(String? text) {
  if (text == null || text.isEmpty) return null;
  try {
    return Uri.decodeComponent(text);
  } on FormatException {
    return null;
  }
}

/// The id of the task a tapped link opens in the app, or null when the link is for the system:
/// a task link from the editor, or the web address of a task on the signed-in server. A task's
/// address on any other server is someone else's task, and opens there.
String? linkedTaskId(String? serverUrl, String? href) {
  final text = href?.trim() ?? '';
  final uri = Uri.tryParse(text);
  if (uri == null) return null;
  if (uri.scheme == _taskLinkScheme) return _decoded(uri.path);
  final target = resolveLink(serverUrl, text);
  if (serverUrl == null || target == null || !isOnServer(target, serverUrl)) return null;
  // A server reached under a path has its pages under that path too.
  final base = Uri.parse(serverUrl).path.replaceFirst(RegExp(r'/+$'), '');
  if (!target.path.startsWith('$base/')) return null;
  return _taskIdInPath(target.path.substring(base.length));
}
