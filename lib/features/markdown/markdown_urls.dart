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
