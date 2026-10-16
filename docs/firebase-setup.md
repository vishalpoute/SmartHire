# Firebase development setup

The Flutter client includes Firebase Core and Authentication dependencies and an explicit startup configuration boundary. Account forms use the authentication repository when Firebase initializes successfully; unconfigured builds retain the local preview. The development project and Web client are registered; configured-build deployment and live service verification remain pending.

The authentication repository implements sign-in, signup, password-reset requests, verification requests, session refresh and sign-out. Session state follows Firebase user changes and clears user data on stream failure. Action state prevents duplicate in-flight requests, supports retries, hides unexpected diagnostics and separates signup from verification-email delivery so a mail failure cannot misreport account creation. Connected forms show loading/error feedback and an account summary with verification and sign-out actions. Controlled test doubles verify these behaviors without touching a live Firebase project. Registered-client configuration and live/emulator integration checks remain pending.

## Verified development project

Created 16 October 2026 under the signed-in Google account on the free Spark plan:

- Project: `smarthire-dev-99f32` (SmartHire Dev)
- Web app: `1:242124745289:web:7322af716f4dfcdd362d98` (SmartHire Web Dev)
- Email/Password provider: enabled; passwordless links remain disabled.
- Authorized preview domain: `smarthire-vishalpoute.antideploy.app`.
- Optional Analytics and Gemini were disabled during creation. Billing was not upgraded.

Console: https://console.firebase.google.com/project/smarthire-dev-99f32/overview

The hosted Web build now uses the registered development client configuration, stored outside Git at `work/firebase/web-dev.json` in the task workspace. The temporary export restriction was resolved. Live browser validation confirmed connected email sign-in and safe rejection of a nonexistent test identity; successful signup and email delivery remain unverified. Google provider is now enabled with the approved support email and app name SmartHire. Web Google sign-in uses a popup; Android remains disabled until app registration and signing fingerprints are configured. No Admin SDK credentials were created or exported. Android registration, live authentication checks, emulator/rules verification and backend credentials remain pending.

## Configuration

Copy `apps/flutter_app/config/firebase.example.json` to `firebase.local.json` in the same folder. Fill values from the actual registered Firebase app's client configuration. Use separate files for Android and Web if their app IDs differ. Never insert an Admin SDK service-account key into a Flutter build.

```sh
cd apps/flutter_app
flutter run -d chrome --dart-define-from-file=config/firebase.local.json
flutter build web --release --dart-define-from-file=config/firebase.local.json
```

Builds with no Firebase configuration keep the sample preview available. Partial configuration or initialization failure shows an account-service setup notice while job discovery remains available. No configuration values are logged. A complete configuration initializes Firebase and enables real account actions, so connect only to the intended project. Name/profile fields and recruiter intent stay in the sample registration preview until profile and approval workflows are implemented; configured signup creates an email account only and grants no application role.

## Emulators and rules

The repository root `firebase.json` reserves local Auth (9099), Firestore (8080), Storage (9199) and UI (4000) ports, bound to loopback. All Firestore and Storage operations are denied by the initial rules; open explicit ownership-scoped paths only alongside their feature and rule tests.

Install Firebase CLI and the Java runtime required by the current Firestore/Storage emulators before running:

```sh
firebase emulators:start --project demo-smarthire
```

The `demo-` project is for local testing and cannot access live resources. This milestone adds configuration only: emulator startup and rule integration tests are still pending. Never put localhost emulator settings into the hosted preview.

## Next integration

Save the registered Web client configuration in an ignored local build file, build and verify real authentication against the development project, then register Android (`com.vishalpoute.smarthire`). The authentication repository and session Cubit are already implemented and tested with controlled doubles. Recruiter selection must remain an approval request, never a client-assigned privileged role. Storage billing and resume uploads are later milestones.

Official references: https://firebase.google.com/docs/flutter/setup and https://firebase.google.com/docs/emulator-suite/install_and_configure

Google Web flow reference: https://firebase.google.com/docs/auth/flutter/federated-auth
