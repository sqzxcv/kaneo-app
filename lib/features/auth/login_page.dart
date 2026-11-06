import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';

/// Placeholder until KAN-23. Keep the developer sign-in button when replacing it: it only appears
/// when `dev.env` is passed to the build.
class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devConfig = ref.watch(devConfigProvider);
    return Scaffold(
      body: StatusMessage(
        title: context.t('mobile:signIn.signIn'),
        message: context.t('app:auth.signInPending'),
        action: devConfig.isConfigured
            ? FilledButton(
                onPressed: () =>
                    runAction(context, () => ref.read(sessionProvider.notifier).devSignIn()),
                child: Text(context.t('app:auth.devSignIn')),
              )
            : null,
      ),
    );
  }
}
