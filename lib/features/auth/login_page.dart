import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kaneo_app/core/core.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _server = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _apiKey = TextEditingController();
  var _type = CredentialType.bearer;
  var _obscure = true;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    _email.dispose();
    _password.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? context.t('app:auth.required') : null;

  Future<void> _signIn() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = ref.read(authenticationProvider);
      final session = _type == CredentialType.apiKey
          ? await auth.withApiKey(_server.text, _apiKey.text)
          : await auth.withPassword(_server.text, _email.text, _password.text);
      if (!mounted) return;
      final storageMessage = context.t('app:auth.storageFailed');
      try {
        await ref.read(sessionProvider.notifier).signInPersistently(session);
      } on Exception {
        throw ApiError(storageMessage);
      }
      TextInput.finishAutofillContext();
    } catch (error) {
      if (mounted) setState(() => _error = userMessage(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final devConfig = ref.watch(devConfigProvider);
    final colors = context.colors;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: EdgeInsets.all(context.isWide ? 40 : 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - (context.isWide ? 80 : 48)).clamp(
                  0,
                  double.infinity,
                ),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: AutofillGroup(
                    child: Form(
                      key: _form,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Kaneo', style: Theme.of(context).textTheme.headlineMedium),
                          const SizedBox(height: 8),
                          Text(
                            context.t('app:auth.selfHosted'),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 28),
                          TextFormField(
                            key: const ValueKey('login-server'),
                            controller: _server,
                            enabled: !_busy,
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: context.t('mobile:signIn.serverAddress'),
                              hintText: 'https://kaneo.example.com',
                              helperText: context.t('mobile:signIn.serverAddressHint'),
                              helperMaxLines: 4,
                            ),
                            validator: (value) {
                              try {
                                ref.read(authenticationProvider).serverAddress(value ?? '');
                                return null;
                              } on ApiError catch (error) {
                                return error.message;
                              }
                            },
                          ),
                          const SizedBox(height: 24),
                          SegmentedButton<CredentialType>(
                            segments: [
                              ButtonSegment(
                                value: CredentialType.bearer,
                                label: Text(context.t('app:auth.passwordLogin')),
                              ),
                              ButtonSegment(
                                value: CredentialType.apiKey,
                                label: Text(context.t('mobile:signIn.apiKey.label')),
                              ),
                            ],
                            selected: {_type},
                            onSelectionChanged: _busy
                                ? null
                                : (value) => setState(() {
                                    _type = value.single;
                                    _error = null;
                                  }),
                          ),
                          const SizedBox(height: 24),
                          if (_type == CredentialType.bearer) ...[
                            TextFormField(
                              key: const ValueKey('login-email'),
                              controller: _email,
                              enabled: !_busy,
                              autofillHints: const [AutofillHints.username, AutofillHints.email],
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              decoration: InputDecoration(
                                labelText: context.t('mobile:signIn.email'),
                              ),
                              validator: _required,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              key: const ValueKey('login-password'),
                              controller: _password,
                              enabled: !_busy,
                              obscureText: _obscure,
                              autocorrect: false,
                              enableSuggestions: false,
                              autofillHints: const [AutofillHints.password],
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _signIn(),
                              decoration: InputDecoration(
                                labelText: context.t('mobile:signIn.password'),
                                suffixIcon: IconButton(
                                  tooltip: context.t('mobile:signIn.togglePassword'),
                                  onPressed: () => setState(() => _obscure = !_obscure),
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              validator: _required,
                            ),
                          ] else ...[
                            TextFormField(
                              key: const ValueKey('login-api-key'),
                              controller: _apiKey,
                              enabled: !_busy,
                              obscureText: true,
                              autocorrect: false,
                              enableSuggestions: false,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _signIn(),
                              decoration: InputDecoration(
                                labelText: context.t('mobile:signIn.apiKey.label'),
                              ),
                              validator: _required,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              context.t('mobile:signIn.apiKey.message'),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                _error!,
                                key: const ValueKey('login-error'),
                                style: TextStyle(color: colors.destructive),
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          FilledButton(
                            key: const ValueKey('login-submit'),
                            onPressed: _busy ? null : _signIn,
                            child: _busy
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      semanticsLabel: context.t('app:auth.signingIn'),
                                    ),
                                  )
                                : Text(context.t('mobile:signIn.signIn')),
                          ),
                          if (devConfig.isConfigured) ...[
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => runAction(
                                      context,
                                      () => ref.read(sessionProvider.notifier).devSignIn(),
                                    ),
                              child: Text(context.t('app:auth.devSignIn')),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
