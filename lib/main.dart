import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:split_app/app/app.dart';
import 'package:split_app/app/providers.dart';
import 'package:split_app/features/auth/data/auth_repository.dart';
import 'package:split_app/features/ledger/data/supabase_ledger_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pass configuration with --dart-define (see README):
///   SUPABASE_URL, SUPABASE_ANON_KEY, GOOGLE_WEB_CLIENT_ID, GOOGLE_IOS_CLIENT_ID
/// Without the Supabase values the app runs in demo mode with in-memory data
/// and no sign-in.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const _googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
const _googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final overrides = <Override>[];
  if (_supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
      url: _supabaseUrl,
      publishableKey: _supabaseAnonKey,
    );
    final client = Supabase.instance.client;
    overrides.addAll([
      authRepositoryProvider.overrideWithValue(
        SupabaseAuthRepository(
          client,
          webClientId: _googleWebClientId,
          iosClientId: _googleIosClientId.isEmpty ? null : _googleIosClientId,
        ),
      ),
      ledgerRepositoryProvider.overrideWithValue(
        SupabaseLedgerRepository(client),
      ),
    ]);
  }

  runApp(ProviderScope(overrides: overrides, child: const SplitApp()));
}
