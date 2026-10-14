import 'package:firebase_core/firebase_core.dart';

/// Client identifiers are build configuration, never service-account credentials.
class FirebaseConfiguration {
  const FirebaseConfiguration({
    this.apiKey = '',
    this.appId = '',
    this.projectId = '',
    this.messagingSenderId = '',
    this.authDomain = '',
  });
  factory FirebaseConfiguration.fromEnvironment() =>
      const FirebaseConfiguration(
        apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
        appId: String.fromEnvironment('FIREBASE_APP_ID'),
        projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
        messagingSenderId: String.fromEnvironment(
          'FIREBASE_MESSAGING_SENDER_ID',
        ),
        authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
      );
  final String apiKey, appId, projectId, messagingSenderId, authDomain;
  bool get isEmpty => [
    apiKey,
    appId,
    projectId,
    messagingSenderId,
    authDomain,
  ].every((value) => value.isEmpty);
  bool get isComplete => [
    apiKey,
    appId,
    projectId,
    messagingSenderId,
  ].every((value) => value.trim().isNotEmpty);
  FirebaseOptions get options {
    if (!isComplete) {
      throw StateError('Firebase client configuration is incomplete.');
    }
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      projectId: projectId,
      messagingSenderId: messagingSenderId,
      authDomain: authDomain.isEmpty ? null : authDomain,
    );
  }
}
