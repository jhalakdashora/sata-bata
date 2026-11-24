import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:split_app/app/brand.dart';
import 'package:split_app/app/providers.dart';
import 'package:split_app/app/theme.dart';
import 'package:split_app/features/auth/presentation/sign_in_screen.dart';
import 'package:split_app/features/ledger/presentation/add_expense_screen.dart';
import 'package:split_app/features/ledger/presentation/expense_detail_screen.dart';
import 'package:split_app/features/ledger/presentation/group_screen.dart';
import 'package:split_app/features/ledger/presentation/home_screen.dart';
import 'package:split_app/features/ledger/presentation/settle_up_screen.dart';
import 'package:split_app/features/premium/presentation/paywall_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  final signedIn = ValueNotifier<bool>(auth.isSignedIn);
  final sub = auth.signedInChanges.listen((v) => signedIn.value = v);
  ref.onDispose(() {
    unawaited(sub.cancel());
    signedIn.dispose();
  });

  return GoRouter(
    refreshListenable: signedIn,
    redirect: (_, state) {
      final atSignIn = state.matchedLocation == '/sign-in';
      if (!signedIn.value) return atSignIn ? null : '/sign-in';
      return atSignIn ? '/' : null;
    },
    routes: [
      GoRoute(path: '/sign-in', builder: (_, _) => const SignInScreen()),
      GoRoute(
        path: '/',
        builder: (_, _) => const HomeScreen(),
        routes: [
          GoRoute(
            path: 'groups/:groupId',
            builder: (_, state) =>
                GroupScreen(groupId: state.pathParameters['groupId']!),
            routes: [
              GoRoute(
                path: 'settle',
                builder: (_, state) =>
                    SettleUpScreen(groupId: state.pathParameters['groupId']!),
              ),
            ],
          ),
          GoRoute(
            path: 'expenses/new',
            builder: (_, state) =>
                AddExpenseScreen(groupId: state.uri.queryParameters['groupId']),
          ),
          GoRoute(
            path: 'expenses/:expenseId',
            builder: (_, state) => ExpenseDetailScreen(
              expenseId: state.pathParameters['expenseId']!,
            ),
          ),
          GoRoute(
            path: 'pro',
            builder: (_, state) =>
                PaywallScreen(highlight: state.uri.queryParameters['feature']),
          ),
        ],
      ),
    ],
  );
});

class SplitApp extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<SplitApp> createState() => _SplitAppState();
}

class _SplitAppState extends ConsumerState<SplitApp> {
  // Coming back to the app refetches, in case changes were missed while it
  // was in the background.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (ref.read(signedInProvider).value ?? false) {
          unawaited(ref.read(ledgerRepositoryProvider).refresh());
        }
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: Brand.name,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
