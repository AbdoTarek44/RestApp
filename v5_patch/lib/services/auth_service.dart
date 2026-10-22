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
    final GoogleSignInAccount googleUser = await GoogleSignIn.instance.authenticate();
    final GoogleSignInAuthentication googleAuth = googleUser.authentication;
    final credential = GoogleAuthProvider.credential(idToken: googleAuth.idToken);
    return FirebaseAuth.instance.signInWithCredential(credential);
  }

  Future<void> sendPhoneCode({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(String message) onError,
  }) async {
    if (!ready) {
      onError('Firebase مش متوصل لسه.');
      return;
    }
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (credential) async {
        await FirebaseAuth.instance.signInWithCredential(credential);
      },
      verificationFailed: (error) => onError(error.message ?? error.code),
      codeSent: (verificationId, _) => onCodeSent(verificationId),
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  Future<UserCredential> confirmPhoneCode({
    required String verificationId,
    required String smsCode,
  }) {
    if (!ready) throw StateError('Firebase is not configured');
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    return FirebaseAuth.instance.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    if (!ready) return;
    await FirebaseAuth.instance.signOut();
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }
}
