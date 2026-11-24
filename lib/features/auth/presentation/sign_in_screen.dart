import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:split_app/app/brand.dart';
import 'package:split_app/app/providers.dart';
import 'package:split_app/features/auth/data/auth_repository.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
      // The router redirects once the auth state changes.
    } on AuthCancelled {
      // User closed the Google sheet: no error message.
    } on Object catch (e) {
      setState(() => _error = 'Sign-in failed. Please try again.\n$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const white = Colors.white;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Brand.seedColor,
              Color.lerp(Brand.seedColor, const Color(0xFF0B2E4A), 0.7)!,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 2),
                Center(
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const Icon(
                      Icons.call_split_rounded,
                      size: 52,
                      color: white,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  Brand.name,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displaySmall?.copyWith(color: white),
                ),
                const SizedBox(height: 10),
                Text(
                  Brand.tagline,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: white.withValues(alpha: 0.85),
                  ),
                ),
                const Spacer(flex: 2),
                for (final (icon, text) in const [
                  (Icons.groups_rounded, 'Track shared expenses in groups'),
                  (
                    Icons.calculate_rounded,
                    'Split equally, by %, or by shares',
                  ),
                  (Icons.handshake_rounded, 'Settle up with fewer payments'),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(icon, color: white.withValues(alpha: 0.9)),
                        const SizedBox(width: 12),
                        Text(
                          text,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: white,
                    foregroundColor: const Color(0xFF1F1F1F),
                  ),
                  onPressed: _busy ? null : _signIn,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login_rounded),
                  label: const Text('Continue with Google'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
