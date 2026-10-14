# Delivery roadmap

## Completed

- [x] Android/Web scaffold and feature-first project structure
- [x] Shared Material theme and adaptive discovery layout
- [x] Repository-backed job search, work-mode filters, session bookmarks and job details
- [x] Initial domain/widget checks and Flutter CI
- [x] Named routes, responsive sign-in/register/reset previews and form validation
- [x] Firebase dependency/bootstrap boundary, example client configuration and restrictive emulator rule scaffold
- [x] Firebase authentication repository and tested session/action state, ready for form integration

## Next milestones

1. Register Firebase clients, complete account integration and verify local emulator/rules behavior.
2. Connect account forms to Firebase with session state and route guards.
3. FastAPI health endpoint, Firebase token verification and permission checks.
4. Seeker profiles, company profiles and server-managed recruiter approval.
5. Firestore job repository, scoped rules, indexes and job publishing.
6. Private resume upload, durable parsing tasks and skill confirmation.
7. Versioned skill-match scoring with evidence and missing skills.
8. Applications, resume snapshots and recruiter status management.
9. Admin moderation, audit events and deletion workflows.
10. Parser evaluation, performance profiling, production deployment and portfolio demo.

Each milestone can span several commits. Prefer a small verified feature over an arbitrary file count. Do not publish unfinished features as completed.

## Integration prerequisites

Firebase development/production project IDs and client configuration, Storage billing setup, and Render deployment access will be needed before live integration. Request them at the appropriate milestone. Never put service-account credentials in a client or repository.
