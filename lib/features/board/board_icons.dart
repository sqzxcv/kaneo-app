import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:kaneo_app/core/core.dart';

IconData boardColumnIcon(BoardColumn column) =>
    switch (column.icon?.toLowerCase().replaceAll('-', '')) {
      'circlecheck' || 'checkcircle' || 'checkcircle2' => LucideIcons.circleCheck,
      'circle' => LucideIcons.circle,
      'circledot' => LucideIcons.circleDot,
      'circledashed' => LucideIcons.circleDashed,
      'search' => LucideIcons.search,
      'circlepause' || 'pausecircle' => LucideIcons.circlePause,
      'clock' => LucideIcons.clock,
      'archive' => LucideIcons.archive,
      'inbox' => LucideIcons.inbox,
      'circleplay' || 'playcircle' => LucideIcons.circlePlay,
      'circlex' || 'xcircle' => LucideIcons.circleX,
      _ =>
        column.isFinal == true
            ? LucideIcons.circleCheck
            : switch (column.slug) {
                'in-progress' => LucideIcons.circleDot,
                'in-review' => LucideIcons.search,
                'planned' => LucideIcons.clock,
                _ => LucideIcons.circle,
              },
    };
