import 'dart:async';
import 'dart:io' show Platform;

import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class AuthRepository {
  bool get isSignedIn;
  Stream<bool> get signedInChanges;
  Future<void> signInWithGoogle();
  Future<void> signOut();
}

/// Demo mode: always "signed in" as the seeded user.
class DemoAuthRepository implements AuthRepository {
  @override
  bool get isSignedIn => true;

  @override
  Stream<bool> get signedInChanges => const Stream.empty();

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signOut() async {}
}

class AuthCancelled implements Exception {
  const new();
}

/// Native Google sign-in exchanged for a Supabase session
/// (`signInWithIdToken`), so no browser redirect is needed.
class SupabaseAuthRepository implements AuthRepository {
  new(this._db, {required this.webClientId, this.iosClientId});

  final SupabaseClient _db;

  /// OAuth client of type "Web application". Its ID must also be entered in
  /// Supabase → Authentication → Providers → Google → Client IDs.
  final String webClientId;

  /// OAuth client of type "iOS" (only needed on iOS).
  final String? iosClientId;

  Future<void>? _initialized;

  @override
  bool get isSignedIn => _db.auth.currentSession != null;

  @override
  Stream<bool> get signedInChanges =>
      _db.auth.onAuthStateChange.map((s) => s.session != null);

  @override
  Future<void> signInWithGoogle() async {
    if (webClientId.isEmpty) {
      throw StateError(
        'Google sign-in is not set up yet: GOOGLE_WEB_CLIENT_ID is missing '
        'from config/dev.json.',
      );
    }
    final google = GoogleSignIn.instance;
    await (_initialized ??= google.initialize(
      clientId: Platform.isIOS ? iosClientId : null,
      serverClientId: webClientId,
    ));
    final GoogleSignInAccount account;
    try {
      account = await google.authenticate(scopeHint: const ['email']);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthCancelled();
      }
      rethrow;
    }
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw StateError('Google did not return an ID token');
    }
    await _db.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
    );
  }

  @override
  Future<void> signOut() async {
    await _db.auth.signOut();
    try {
      await GoogleSignIn.instance.signOut();
    } on Object {
      // Google session may already be gone; Supabase sign-out is what matters.
    }
  }
}
