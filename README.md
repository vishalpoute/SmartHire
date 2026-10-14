# SmartHire

A Flutter job portal for Android and Web with explainable resume-to-job skill matching.

## Current status

The first milestone delivers a responsive job-discovery preview: search by title, skill, company or city, filter by work mode, save roles for the current session and open job details. All listings are fictional fixtures. Authentication, persistent saved jobs, applications and resume processing are upcoming work.

The account icon opens responsive sign-in, registration and password-reset previews. Forms validate email, name and passwords, including confirmation. Registration offers seeker/recruiter intent; recruiter publishing will require server approval. Account actions currently validate locally and clearly state that no account is created or reset email sent. Firebase connection is the next milestone.

## Run locally

Requires Flutter 3.47.2 / Dart 3.13.2 (the initial tested toolchain).

```sh
cd apps/flutter_app
flutter pub get
flutter run -d chrome
```

For Android, start an emulator or connect a device, then run `flutter run`.

```sh
flutter analyze
flutter test
flutter build web --release
```

## Structure

Firebase initialization and local emulator configuration are scaffolded. See `docs/firebase-setup.md` for build-time client configuration and remaining integration work. Default builds continue to use the sample preview.

`apps/flutter_app/lib/core` holds the shared theme. Each feature has domain, data and presentation layers. The jobs repository interface separates the UI from its current fixtures; a Firestore adapter can replace it without moving data access into widgets. Feature state uses BLoC/Cubit and repository injection.

`services/api` will contain the FastAPI service; `firebase` will hold access rules and indexes as integration is added. See `docs/roadmap.md` for implementation order.

## Design

Warm neutral surfaces, forest-green accents and readable, compact cards. Mobile uses bottom navigation; desktop uses a workspace sidebar. Preview data is labeled and no live applications are accepted yet.

## Development

Implement complete features with appropriate tests. Keep credentials out of Git. Commit messages describe actual changes; timestamps reflect when work was committed.
