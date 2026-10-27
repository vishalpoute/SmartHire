import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthire/app.dart';
import 'package:smarthire/features/auth/domain/auth_repository.dart';
import 'package:smarthire/features/profile/data/api_profile_repository.dart';
import 'package:smarthire/features/recruiter_jobs/data/api_recruiter_jobs_repository.dart';
import 'package:smarthire/features/recruiter_jobs/domain/recruiter_job.dart';

import 'auth_state_test.dart' show TestAuthRepository;

const jobId = '0123456789abcdef0123456789abcdef';
RecruiterJobFields completeFields() => RecruiterJobFields(
  title: 'Flutter developer',
  description: 'Build and maintain Flutter applications.',
  location: 'Pune',
  requiredSkills: ['Flutter'],
);
Map<String, dynamic> jobJson({String status = 'draft', int version = 1}) => {
  ...completeFields().toJson(),
  'id': jobId,
  'recruiter_uid': 'owner',
  'company_owner_uid': 'owner',
  'status': status,
  'version': version,
  'created_at': '2026-10-27T00:00:00Z',
  'updated_at': '2026-10-27T00:00:00Z',
};
RecruiterJob snapshot({
  String status = 'draft',
  int version = 1,
  RecruiterJobFields? fields,
}) => RecruiterJob(
  id: jobId,
  status: status,
  version: version,
  fields: fields ?? completeFields(),
);

class JobsAdapter implements HttpClientAdapter {
  int status = 200;
  Object body = jobJson();
  RequestOptions? request;
  void Function()? beforeResponse;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    beforeResponse?.call();
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class JobsFake implements RecruiterJobsRepository {
  RecruiterJob current = snapshot();
  int writes = 0, transitions = 0;
  bool failSave = false;
  bool denyList = false;
  Completer<RecruiterJob>? pending;
  @override
  Future<OwnedJobsPage> list({String? cursor}) async {
    if (denyList) {
      throw const RecruiterJobFailure('Access denied.', accessDenied: true);
    }
    return OwnedJobsPage([current], null);
  }

  @override
  Future<RecruiterJob> load(String id) async => current;
  @override
  Future<RecruiterJob> save(
    RecruiterJobFields fields, {
    RecruiterJob? previous,
  }) async {
    writes++;
    if (failSave) {
      throw const RecruiterJobFailure(
        'This job changed. Reload it before making another change.',
      );
    }
    if (pending != null) return pending!.future;
    return current = snapshot(
      fields: fields,
      version: (previous?.version ?? 0) + 1,
    );
  }

  @override
  Future<void> transition(RecruiterJob job, {required bool publish}) async {
    transitions++;
    current = snapshot(
      status: publish ? 'published' : 'closed',
      version: job.version + 1,
      fields: job.fields,
    );
  }
}

Finder input(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

void main() {
  group('owned job boundaries', () {
    late JobsAdapter adapter;
    late ApiRecruiterJobsRepository repo;
    String? uid;
    var verified = true;
    setUp(() {
      adapter = JobsAdapter();
      uid = 'owner';
      verified = true;
      repo = ApiRecruiterJobsRepository(
        origin: Uri.parse('https://api.example.com'),
        session: () async => ProfileSession(
          uid: 'owner',
          token: 'test-token',
          verified: verified,
        ),
        currentUid: () => uid,
        adapter: adapter,
      );
    });
    tearDown(() => repo.close());
    test(
      'create sends only editable fields and requires version one draft',
      () async {
        adapter.status = 201;
        final saved = await repo.save(completeFields());
        expect(saved.status, 'draft');
        expect(adapter.request!.path, '/api/v1/jobs');
        expect(adapter.request!.data, completeFields().toJson());
        expect(adapter.request!.headers['Authorization'], 'Bearer test-token');
        expect(adapter.request!.followRedirects, isFalse);
        adapter.body = jobJson(version: 2);
        await expectLater(
          repo.save(completeFields()),
          throwsA(isA<RecruiterJobFailure>()),
        );
      },
    );
    test(
      'owned list is bounded and rejects foreign owners and repeating cursors',
      () async {
        adapter.body = {
          'items': [jobJson()],
          'next_cursor': null,
        };
        final page = await repo.list();
        expect(page.items.single.id, jobId);
        expect(adapter.request!.queryParameters, {'page_size': 10});
        adapter.body = {
          'items': [
            {...jobJson(), 'recruiter_uid': 'foreign'},
          ],
        };
        await expectLater(repo.list(), throwsFormatException);
        adapter.body = {
          'items': [jobJson()],
          'next_cursor': jobId,
        };
        await expectLater(
          repo.list(cursor: jobId),
          throwsA(isA<RecruiterJobFailure>()),
        );
        expect(
          () => OwnedJobsPage.fromJson({
            'items': [jobJson(), jobJson()],
          }, 'owner'),
          throwsFormatException,
        );
      },
    );
    test('edit pins version and rejects changes to published jobs', () async {
      adapter.body = jobJson(version: 2);
      final saved = await repo.save(completeFields(), previous: snapshot());
      expect(saved.version, 2);
      expect(adapter.request!.method, 'PUT');
      expect((adapter.request!.data as Map)['expected_version'], 1);
      await expectLater(
        repo.save(completeFields(), previous: snapshot(status: 'published')),
        throwsA(isA<RecruiterJobFailure>()),
      );
    });
    test('owner and requested ID are checked on load', () async {
      adapter.body = {...jobJson(), 'recruiter_uid': 'other'};
      await expectLater(repo.load(jobId), throwsFormatException);
      adapter.body = {...jobJson(), 'company_owner_uid': 'other'};
      await expectLater(repo.load(jobId), throwsFormatException);
      adapter.body = {...jobJson(), 'id': 'a' * 32};
      await expectLater(repo.load(jobId), throwsFormatException);
    });
    test('verification and account changes fail closed', () async {
      verified = false;
      await expectLater(repo.load(jobId), throwsA(isA<RecruiterJobFailure>()));
      expect(adapter.request, isNull);
      verified = true;
      adapter.beforeResponse = () => uid = 'other';
      await expectLater(repo.load(jobId), throwsA(isA<RecruiterJobFailure>()));
    });
    test(
      'publication and closure send explicit versions with strict receipts',
      () async {
        adapter.body = {'id': jobId, 'status': 'published', 'version': 2};
        await repo.transition(snapshot(), publish: true);
        expect(adapter.request!.path, '/api/v1/jobs/$jobId/publish');
        expect(adapter.request!.data, {'expected_version': 1});
        adapter.body = {'id': jobId, 'status': 'closed', 'version': 3};
        await repo.transition(
          snapshot(status: 'published', version: 2),
          publish: false,
        );
        expect(adapter.request!.path, '/api/v1/jobs/$jobId/close');
        adapter.body = {'id': jobId, 'status': 'closed', 'version': 3.0};
        await expectLater(
          repo.transition(
            snapshot(status: 'published', version: 2),
            publish: false,
          ),
          throwsA(isA<RecruiterJobFailure>()),
        );
      },
    );
    test(
      'incomplete publication, invalid IDs and versions never request',
      () async {
        await expectLater(
          repo.transition(
            snapshot(fields: RecruiterJobFields(title: 'Draft')),
            publish: true,
          ),
          throwsA(isA<RecruiterJobFailure>()),
        );
        await expectLater(
          repo.load('$jobId\n'),
          throwsA(isA<RecruiterJobFailure>()),
        );
        await expectLater(
          repo.transition(snapshot(version: 0), publish: true),
          throwsA(isA<RecruiterJobFailure>()),
        );
        expect(adapter.request, isNull);
      },
    );
    test(
      'authorization conflict and missing records have safe errors',
      () async {
        for (final code in [401, 403, 404, 409, 422, 429, 500]) {
          adapter.status = code;
          adapter.body = {'message': 'private secret'};
          await expectLater(
            repo.load(jobId),
            throwsA(
              isA<RecruiterJobFailure>().having(
                (e) => e.message.contains('secret'),
                'no private diagnostics',
                isFalse,
              ),
            ),
          );
        }
      },
    );
    test('malformed lifecycle and fields are rejected', () {
      for (final change in <Map<String, Object>>[
        {'version': 1.0},
        {'status': 'approved'},
        {'work_mode': 'teleport'},
        {'updated_at': '2026-10-27T00:00:00'},
        {
          'required_skills': [1],
        },
      ]) {
        expect(
          () => RecruiterJob.fromJson({...jobJson(), ...change}, 'owner'),
          throwsFormatException,
        );
      }
    });
    test(
      'publishing requirements include nonoverlapping skills and location',
      () {
        expect(completeFields().validate(publish: true), isNull);
        expect(
          RecruiterJobFields(
            title: 'Job',
            description: 'A complete job description here',
            requiredSkills: ['Flutter'],
            preferredSkills: ['flutter'],
          ).validate(publish: true),
          isNotNull,
        );
      },
    );
  });
  for (final width in [360.0, 1440.0]) {
    testWidgets(
      'draft publication and closure require explicit actions at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final auth = TestAuthRepository();
        addTearDown(auth.sessions.close);
        final repo = JobsFake();
        await tester.pumpWidget(
          SmartHireApp(
            authRepository: auth,
            initialRoute: '/recruiter/jobs',
            recruiterJobsRepositoryFactory: (_) => repo,
          ),
        );
        await tester.pump();
        auth.sessions.add(
          const AuthUser(
            uid: 'owner',
            email: 'a@example.com',
            emailVerified: true,
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(input('Job title'), 'Flutter developer');
        await tester.enterText(
          input('Job description'),
          'Build and maintain Flutter applications.',
        );
        await tester.enterText(input('Location'), 'Pune');
        await tester.enterText(
          input('Required skills (comma separated)'),
          'Flutter',
        );
        await tester.ensureVisible(find.text('Save private draft'));
        await tester.tap(find.text('Save private draft'));
        await tester.pumpAndSettle();
        expect(repo.writes, 1);
        expect(repo.transitions, 0);
        expect(find.text('Status: draft · Version 1'), findsOneWidget);
        await tester.ensureVisible(find.text('Publish job'));
        await tester.tap(find.text('Publish job'));
        await tester.pumpAndSettle();
        expect(repo.transitions, 0);
        await tester.tap(find.text('Publish now'));
        await tester.pumpAndSettle();
        expect(repo.transitions, 1);
        expect(find.text('Status: published · Version 2'), findsOneWidget);
        await tester.ensureVisible(find.text('Close vacancy'));
        await tester.tap(find.text('Close vacancy'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Close now'));
        await tester.pumpAndSettle();
        expect(repo.transitions, 2);
        expect(find.text('Status: closed · Version 3'), findsOneWidget);
        auth.sessions.add(null);
        await tester.pumpAndSettle();
        expect(find.text('Job ID: $jobId'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'stale save preserves edits and disables duplicate writes until reload',
    (tester) async {
      final auth = TestAuthRepository();
      addTearDown(auth.sessions.close);
      final repo = JobsFake()..failSave = true;
      await tester.pumpWidget(
        SmartHireApp(
          authRepository: auth,
          initialRoute: '/recruiter/jobs',
          recruiterJobsRepositoryFactory: (_) => repo,
        ),
      );
      await tester.pump();
      auth.sessions.add(
        const AuthUser(
          uid: 'owner',
          email: 'a@example.com',
          emailVerified: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(input('Job title'), 'Unsaved title');
      await tester.ensureVisible(find.text('Save private draft'));
      await tester.tap(find.text('Save private draft'));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved title'), findsOneWidget);
      expect(repo.writes, 1);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save private draft'),
            )
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'owned list reopens records and authorization loss clears private state',
    (tester) async {
      final auth = TestAuthRepository();
      addTearDown(auth.sessions.close);
      final repo = JobsFake();
      await tester.pumpWidget(
        SmartHireApp(
          authRepository: auth,
          initialRoute: '/recruiter/jobs',
          recruiterJobsRepositoryFactory: (_) => repo,
        ),
      );
      await tester.pump();
      auth.sessions.add(
        const AuthUser(
          uid: 'owner',
          email: 'a@example.com',
          emailVerified: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load my jobs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Flutter developer'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(input('Job title')).controller!.text,
        'Flutter developer',
      );
      repo.denyList = true;
      await tester.tap(find.text('Load my jobs'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(input('Job title')).controller!.text,
        isEmpty,
      );
      expect(find.byType(ListTile), findsNothing);
      expect(find.text('Access denied.'), findsOneWidget);
    },
  );
  testWidgets('verified session is required before creating a job repository', (
    tester,
  ) async {
    final auth = TestAuthRepository();
    addTearDown(auth.sessions.close);
    var creates = 0;
    await tester.pumpWidget(
      SmartHireApp(
        authRepository: auth,
        initialRoute: '/recruiter/jobs',
        recruiterJobsRepositoryFactory: (_) {
          creates++;
          return JobsFake();
        },
      ),
    );
    await tester.pump();
    auth.sessions.add(null);
    await tester.pumpAndSettle();
    expect(creates, 0);
    auth.sessions.add(
      const AuthUser(
        uid: 'owner',
        email: 'a@example.com',
        emailVerified: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(creates, 0);
  });
  testWidgets('late save cannot restore private job after sign-out', (
    tester,
  ) async {
    final auth = TestAuthRepository();
    addTearDown(auth.sessions.close);
    final repo = JobsFake()..pending = Completer<RecruiterJob>();
    await tester.pumpWidget(
      SmartHireApp(
        authRepository: auth,
        initialRoute: '/recruiter/jobs',
        recruiterJobsRepositoryFactory: (_) => repo,
      ),
    );
    await tester.pump();
    auth.sessions.add(
      const AuthUser(uid: 'owner', email: 'a@example.com', emailVerified: true),
    );
    await tester.pumpAndSettle();
    await tester.enterText(input('Job title'), 'Private job');
    await tester.ensureVisible(find.text('Save private draft'));
    await tester.tap(find.text('Save private draft'));
    await tester.pump();
    auth.sessions.add(null);
    await tester.pumpAndSettle();
    repo.pending!.complete(snapshot());
    await tester.pumpAndSettle();
    expect(find.text('Private job'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
