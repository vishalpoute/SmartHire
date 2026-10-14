import 'package:firebase_core/firebase_core.dart';

import 'firebase_configuration.dart';

enum FirebaseAvailability { preview, ready, unavailable }

Future<FirebaseAvailability> initializeFirebase() async {
  final configuration = FirebaseConfiguration.fromEnvironment();
  if (configuration.isEmpty) return FirebaseAvailability.preview;
  if (!configuration.isComplete) return FirebaseAvailability.unavailable;
  try {
    await Firebase.initializeApp(options: configuration.options);
    return FirebaseAvailability.ready;
  } catch (_) {
    // Do not log configuration or credentials; expose a recoverable setup state.
    return FirebaseAvailability.unavailable;
  }
}
