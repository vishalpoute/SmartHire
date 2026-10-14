# Firebase development setup

The Flutter client now includes Firebase Core and Authentication dependencies and an explicit startup configuration boundary. Account actions remain previews until their repository/session integration is delivered.

The authentication repository implements sign-in, signup, password-reset requests, verification requests and sign-out. Session state follows Firebase user changes and clears user data on stream failure. Action state prevents duplicate in-flight requests, supports retries, hides unexpected diagnostics and separates signup from verification-email delivery so a mail failure cannot misreport account creation. Controlled test doubles verify these behaviors without touching a live Firebase project. Form wiring, registered-client configuration and live/emulator integration checks remain pending.

## Configuration

Copy `apps/flutter_app/config/firebase.example.json` to `firebase.local.json` in the same folder. Fill values from the actual registered Firebase app's client configuration. Use separate files for Android and Web if their app IDs differ. Never insert an Admin SDK service-account key into a Flutter build.

```sh
cd apps/flutter_app
flutter run -d chrome --dart-define-from-file=config/firebase.local.json
flutter build web --release --dart-define-from-file=config/firebase.local.json
```

Builds with no Firebase configuration keep the sample preview available. Partial configuration or initialization failure shows an account-service setup notice while job discovery remains available. No configuration values are logged. A complete configuration initializes Firebase but does not yet enable the preview forms to submit real account actions.

## Emulators and rules

The repository root `firebase.json` reserves local Auth (9099), Firestore (8080), Storage (9199) and UI (4000) ports, bound to loopback. All Firestore and Storage operations are denied by the initial rules; open explicit ownership-scoped paths only alongside their feature and rule tests.

Install Firebase CLI and the Java runtime required by the current Firestore/Storage emulators before running:

```sh
firebase emulators:start --project demo-smarthire
```

The `demo-` project is for local testing and cannot access live resources. This milestone adds configuration only: emulator startup and rule integration tests are still pending. Never put localhost emulator settings into the hosted preview.

## Next integration

Register Android (`com.vishalpoute.smarthire`) and Web apps, enable Email/Password Authentication, add the preview hostname to authorized domains, and implement the authentication repository and session Cubit. Recruiter selection must remain an approval request, never a client-assigned privileged role. Storage billing and resume uploads are later milestones.

Official references: https://firebase.google.com/docs/flutter/setup and https://firebase.google.com/docs/emulator-suite/install_and_configure
