import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';

class FirebaseRuntimeConfig {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY', defaultValue: '');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID', defaultValue: '');
  static const messagingSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID', defaultValue: '');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: '');
  static const storageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET', defaultValue: '');
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID', defaultValue: '');

  static bool get configured =>
      apiKey.isNotEmpty && appId.isNotEmpty && messagingSenderId.isNotEmpty && projectId.isNotEmpty;

  static FirebaseOptions get options => FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
        storageBucket: storageBucket.isEmpty ? null : storageBucket,
      );
}

class AuthService {
  static bool _ready = false;
  static bool get ready => _ready;
  static bool get configured => FirebaseRuntimeConfig.configured;

  static Future<void> initialize() async {
    if (!configured) return;
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: FirebaseRuntimeConfig.options);
    }
    if (FirebaseRuntimeConfig.googleWebClientId.isNotEmpty) {
      await GoogleSignIn.instance.initialize(
        serverClientId: FirebaseRuntimeConfig.googleWebClientId,
      );
    }
    _ready = true;
  }

  User? get currentUser => ready ? FirebaseAuth.instance.currentUser : null;
  Stream<User?> get authStateChanges => ready
      ? FirebaseAuth.instance.authStateChanges()
      : const Stream<User?>.empty();

  Future<UserCredential> signInWithGoogle() async {
    if (!ready) throw StateError('Firebase is not configured');
    if (FirebaseRuntimeConfig.googleWebClientId.isEmpty) {
      throw StateError('Google sign-in is not configured');
    }
    final GoogleSignInAccount googleUser = await GoogleSignIn.instance.authenticate();
    final GoogleSignInAuthentication googleAuth = googleUser.authentication;
    final credential = GoogleAuthProvider.credential(idToken: googleAuth.idToken);
    final current = FirebaseAuth.instance.currentUser;
    if (current != null && current.isAnonymous) {
      try { return await current.linkWithCredential(credential); }
      on FirebaseAuthException catch (error) {
        if (error.code != 'credential-already-in-use') rethrow;
      }
    }
    return FirebaseAuth.instance.signInWithCredential(credential);
  }

  Future<User> ensureGuest() async {
    if (!ready) throw StateError('Firebase is not configured');
    return FirebaseAuth.instance.currentUser ??
        (await FirebaseAuth.instance.signInAnonymously()).user!;
  }

  Future<String> idToken({bool forceRefresh = false}) async {
    final user = await ensureGuest();
    final token = await user.getIdToken(forceRefresh);
    if (token == null) throw StateError('Authentication token unavailable');
    return token;
  }
  Future<void> signOut() async {
    if (!ready) return;
    await FirebaseAuth.instance.signOut();
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }
}
