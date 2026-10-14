import 'package:flutter_test/flutter_test.dart';
import 'package:smarthire/core/firebase/firebase_configuration.dart';
import 'package:smarthire/core/firebase/firebase_bootstrap.dart';

void main() {
  test('unconfigured builds remain in preview mode', () async {
    expect(const FirebaseConfiguration().isEmpty, isTrue);
    expect(await initializeFirebase(), FirebaseAvailability.preview);
  });
  test('partial configuration fails closed', () {
    const config = FirebaseConfiguration(projectId: 'demo-smarthire');
    expect(config.isEmpty, isFalse);
    expect(config.isComplete, isFalse);
    expect(() => config.options, throwsStateError);
  });
  test('complete client configuration maps to Firebase options', () {
    const config = FirebaseConfiguration(
      apiKey: 'test-key',
      appId: 'test-app',
      projectId: 'demo-smarthire',
      messagingSenderId: '1234',
      authDomain: 'example.invalid',
    );
    expect(config.isComplete, isTrue);
    expect(config.options.projectId, 'demo-smarthire');
    expect(config.options.authDomain, 'example.invalid');
  });
}
