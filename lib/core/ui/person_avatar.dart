import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../format/style.dart';
import '../providers.dart';
import '../theme/app_theme.dart';

/// A person's picture, as the web shows it, with their initials until it loads and when they have
/// none or it fails. [image] is the user's `image`: a path on the instance such as
/// `/api/user/avatar/<id>`, a URL elsewhere, or a data URL.
class PersonAvatar extends ConsumerWidget {
  const PersonAvatar({
    super.key,
    required this.name,
    required this.image,
    this.radius = 12,
    this.fontSize = 10,
  });

  final String? name;
  final String? image;
  final double radius;
  final double fontSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: colors.avatar,
      foregroundColor: colors.avatarForeground,
      child: Text(initials(name), style: TextStyle(fontSize: fontSize)),
    );
    final server = ref.watch(sessionProvider.select((s) => s?.serverUrl));
    final picture = _picture(server == null ? null : resolveUrl(server, image));
    if (picture == null) return fallback;
    return ClipOval(
      child: Image(
        image: picture,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        frameBuilder: (context, child, frame, loaded) =>
            frame == null && !loaded ? fallback : child,
        errorBuilder: (context, error, stack) => fallback,
      ),
    );
  }

  static ImageProvider? _picture(String? url) {
    if (url == null) return null;
    try {
      final data = Uri.parse(url).data;
      return data == null ? NetworkImage(url) : MemoryImage(data.contentAsBytes());
    } on FormatException {
      return null;
    }
  }
}
