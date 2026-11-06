import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';

import '../support/test_app.dart';

void main() {
  group('tokens match kaneo/apps/web/src/index.css', () {
    // Spot checks of values worked out from the CSS. tokens.dart is compared with the CSS in full
    // when it changes; the submodule is not available here.
    test('light', () {
      const c = KaneoColors.light;
      expect(c.background, const Color(0xFFFFFFFF));
      expect(c.foreground, const Color(0xFF262626)); // neutral-800
      expect(c.primary, const Color(0xFF262626));
      expect(c.primaryForeground, const Color(0xFFFAFAFA)); // neutral-50
      expect(c.border, const Color(0x14000000)); // black 8%
      expect(c.destructive, const Color(0xFFFB2C36)); // red-500
      expect(c.mutedForeground, const Color(0xFF686868));
    });

    test('dark', () {
      const c = KaneoColors.dark;
      expect(c.foreground, const Color(0xFFF5F5F5)); // neutral-100
      expect(c.primary, const Color(0xFFF5F5F5));
      expect(c.primaryForeground, const Color(0xFF262626));
      expect(c.background.computeLuminance(), lessThan(0.02));
    });

    test('radius follows --radius: 0.625rem', () {
      expect(KaneoRadius.lg, 10);
      expect(KaneoRadius.md, 8);
      expect(KaneoRadius.sm, 6);
      expect(KaneoRadius.xl, 14);
    });
  });

  test('both themes use the web font and map the tokens to Material', () {
    for (final (theme, colors) in [
      (kaneoLightTheme, KaneoColors.light),
      (kaneoDarkTheme, KaneoColors.dark),
    ]) {
      expect(theme.textTheme.bodyMedium?.fontFamily, 'Geist');
      expect(theme.textTheme.displayLarge?.fontFamily, 'Geist');
      expect(theme.textTheme.bodyMedium?.fontSize, 14);
      expect(theme.colorScheme.primary, colors.primary);
      expect(theme.colorScheme.surface, colors.background);
      expect(theme.colorScheme.error, colors.destructive);
      expect(theme.scaffoldBackgroundColor, colors.background);
      expect(theme.extension<KaneoColors>(), colors);
    }
    expect(kaneoLightTheme.brightness, Brightness.light);
    expect(kaneoDarkTheme.brightness, Brightness.dark);
    expect(KaneoFonts.mono, 'GeistMono');
  });

  testWidgets('the fonts in pubspec.yaml are the ones the theme names', (tester) async {
    final manifest = await tester.runAsync(
      () => DefaultAssetBundle.of(tester.binding.rootElement!).loadString('FontManifest.json'),
    );
    expect(manifest, contains('"family":"Geist"'));
    expect(manifest, contains('"family":"GeistMono"'));
  });

  group('following the system', () {
    Color background(WidgetTester tester) {
      final context = tester.element(find.byType(Scaffold).first);
      return Theme.of(context).scaffoldBackgroundColor;
    }

    testWidgets('light and dark follow the platform, and change while running', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await pumpKaneoApp(tester);
      expect(background(tester), KaneoColors.light.background);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(background(tester), KaneoColors.dark.background);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(background(tester), KaneoColors.light.background);
    });

    testWidgets('a picked mode wins over the system and is remembered', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      final app = await pumpKaneoApp(tester);
      await app.container.read(themeModeProvider.notifier).select(ThemeMode.dark);
      await tester.pumpAndSettle();
      expect(background(tester), KaneoColors.dark.background);
      expect(app.container.read(prefsProvider).getString('kaneo.themeMode'), 'dark');
    });

    testWidgets('a saved mode applies on the next launch', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await pumpKaneoApp(tester, preferences: {'kaneo.themeMode': 'dark'});
      expect(background(tester), KaneoColors.dark.background);
    });
  });

  testWidgets('context.colors reads the tokens for the current brightness', (tester) async {
    late KaneoColors colors;
    await pumpInApp(
      tester,
      Builder(
        builder: (context) {
          colors = context.colors;
          return const SizedBox();
        },
      ),
    );
    expect(colors, KaneoColors.light);
  });
}
