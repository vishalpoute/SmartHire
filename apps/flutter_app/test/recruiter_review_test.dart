import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthire/app.dart';
import 'package:smarthire/features/auth/domain/auth_repository.dart';
import 'package:smarthire/features/profile/data/api_profile_repository.dart';
import 'package:smarthire/features/recruiter_review/data/api_recruiter_review_repository.dart';
import 'package:smarthire/features/recruiter_review/domain/recruiter_review.dart';

import 'auth_state_test.dart' show TestAuthRepository;

Map<String, dynamic> companyJson([String owner = 'target']) => {
  'owner_uid': owner,
  'approval_status': 'pending',
  'updated_at': '2026-10-27T00:00:00Z',
  'name': 'Acme',
  'description': 'Company description',
  'location': 'Pune',
  'website': '',
};

class ReviewAdapter implements HttpClientAdapter {
  Object body = {
    'items': [companyJson()],
    'next_cursor': null,
  };
  int status = 200;
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

class ReviewFake implements RecruiterReviewRepository {
  int writes = 0;
  int reads = 0;
  String? error;
  Completer<ReviewPage>? pending;
  ReviewDecision? decision;
  final submission = ReviewSubmission.fromJson(companyJson());
  @override
  Future<ReviewPage> load({String? cursor}) async {
    reads++;
    return pending?.future ?? ReviewPage([submission], null);
  }

  @override
  Future<void> review(
    ReviewSubmission submission,
    ReviewDecision decision,
    String reason,
  ) async {
    writes++;
    this.decision = decision;
    if (error != null) throw ReviewFailure(error!, reloadRequired: true);
  }
}

void main() {
  group('review API boundaries', () {
    late ReviewAdapter adapter;
    late ApiRecruiterReviewRepository repo;
    String? uid;
    bool verified = true;
    setUp(() {
      uid = 'admin';
      verified = true;
      adapter = ReviewAdapter();
      repo = ApiRecruiterReviewRepository(
        origin: Uri.parse('https://api.example.com'),
        session: () async => ProfileSession(
          uid: 'admin',
          token: 'test-token',
          verified: verified,
        ),
        currentUid: () => uid,
        adapter: adapter,
      );
    });
    tearDown(() => repo.close());

    test('bounded queue uses bearer identity and encodes cursor', () async {
      final page = await repo.load(cursor: 'a/b');
      expect(page.items.single.company.ownerUid, 'target');
      expect(adapter.request!.path, '/api/v1/admin/recruiter-reviews');
      expect(adapter.request!.queryParameters, {
        'page_size': 10,
        'cursor': 'a/b',
      });
      expect(adapter.request!.headers['Authorization'], 'Bearer test-token');
      expect(adapter.request!.followRedirects, isFalse);
    });
    test('unverified or changed identity makes no request', () async {
      verified = false;
      await expectLater(repo.load(), throwsA(isA<ReviewFailure>()));
      expect(adapter.request, isNull);
      verified = true;
      uid = 'other';
      await expectLater(repo.load(), throwsA(isA<ReviewFailure>()));
      expect(adapter.request, isNull);
    });
    test('account change discards private queue response', () async {
      adapter.beforeResponse = () => uid = 'other';
      await expectLater(repo.load(), throwsA(isA<ReviewFailure>()));
    });
    test('server administrator denial has safe error', () async {
      adapter.status = 403;
      adapter.body = {'private': 'secret'};
      await expectLater(
        repo.load(),
        throwsA(
          isA<ReviewFailure>().having(
            (e) => e.message,
            'message',
            'Administrator access is required.',
          ),
        ),
      );
    });
    test(
      'review sends reason and company version with no privilege fields',
      () async {
        adapter.body = {'target_uid': 'target', 'decision': 'approved'};
        await repo.review(
          ReviewSubmission.fromJson(companyJson()),
          ReviewDecision.approved,
          '  Verified company  ',
        );
        expect(adapter.request!.method, 'POST');
        expect(adapter.request!.data, {
          'target_uid': 'target',
          'decision': 'approved',
          'reason': 'Verified company',
          'expected_company_updated_at': '2026-10-27T00:00:00.000Z',
        });
      },
    );
    test('self review and invalid reasons never send a write', () async {
      await expectLater(
        repo.review(
          ReviewSubmission.fromJson(companyJson('admin')),
          ReviewDecision.rejected,
          'Valid reason',
        ),
        throwsA(isA<ReviewFailure>()),
      );
      await expectLater(
        repo.review(
          ReviewSubmission.fromJson(companyJson()),
          ReviewDecision.rejected,
          'a\nb',
        ),
        throwsA(isA<ReviewFailure>()),
      );
      expect(adapter.request, isNull);
    });
    test(
      'conflicts require reload and receipts must match target and decision',
      () async {
        final submission = ReviewSubmission.fromJson(companyJson());
        adapter.status = 409;
        await expectLater(
          repo.review(submission, ReviewDecision.rejected, 'Not valid'),
          throwsA(
            isA<ReviewFailure>().having(
              (e) => e.reloadRequired,
              'reload',
              isTrue,
            ),
          ),
        );
        adapter.status = 200;
        adapter.body = {'target_uid': 'other', 'decision': 'rejected'};
        await expectLater(
          repo.review(submission, ReviewDecision.rejected, 'Not valid'),
          throwsA(isA<ReviewFailure>()),
        );
      },
    );
    test(
      'malformed pages reject duplicates, reviewed rows and bad cursors',
      () {
        for (final json in <Map<String, dynamic>>[
          {
            'items': [companyJson(), companyJson()],
          },
          {
            'items': [
              {...companyJson(), 'approval_status': 'approved'},
            ],
          },
          {'items': [], 'next_cursor': 'bad\ncursor'},
          {'items': List.generate(11, (i) => companyJson('$i'))},
          {
            'items': [
              {...companyJson(), 'updated_at': 'not-a-time'},
            ],
          },
        ]) {
          expect(() => ReviewPage.fromJson(json), throwsFormatException);
        }
      },
    );
    test('pagination cannot repeat its incoming cursor', () async {
      adapter.body = {'items': [], 'next_cursor': 'same'};
      await expectLater(
        repo.load(cursor: 'same'),
        throwsA(isA<ReviewFailure>()),
      );
    });
    test('unsafe API origins rejected', () {
      for (final url in [
        'http://api.example.com',
        'https://a:b@api.example.com',
        'https://api.example.com/path',
        'https://api.example.com?token=x',
      ]) {
        expect(
          () => ApiRecruiterReviewRepository(
            origin: Uri.parse(url),
            session: () async => null,
            currentUid: () => null,
          ),
          throwsArgumentError,
        );
      }
    });
  });

  for (final width in [360.0, 1440.0]) {
    testWidgets(
      'review UI validates decisions and clears on sign-out at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final auth = TestAuthRepository();
        addTearDown(auth.sessions.close);
        final repo = ReviewFake();
        await tester.pumpWidget(
          SmartHireApp(
            authRepository: auth,
            initialRoute: '/admin/recruiter-reviews',
            reviewRepositoryFactory: (_) => repo,
          ),
        );
        await tester.pump();
        auth.sessions.add(
          const AuthUser(
            uid: 'admin',
            email: 'admin@example.com',
            emailVerified: true,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Review submission'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Approve recruiter'));
        await tester.tap(find.text('Approve recruiter'));
        await tester.pumpAndSettle();
        expect(repo.writes, 0);
        expect(find.textContaining('3–500'), findsOneWidget);
        await tester.enterText(
          find.byType(TextField),
          'Verified company registration',
        );
        await tester.ensureVisible(find.text('Approve recruiter'));
        await tester.tap(find.text('Approve recruiter'));
        await tester.pumpAndSettle();
        expect(repo.writes, 1);
        expect(repo.decision, ReviewDecision.approved);
        expect(find.text('Recruiter approved.'), findsOneWidget);
        auth.sessions.add(null);
        await tester.pumpAndSettle();
        expect(find.text('Acme'), findsNothing);
        expect(find.byType(TextField), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('stale review removes rows until explicit reload', (
    tester,
  ) async {
    final auth = TestAuthRepository();
    addTearDown(auth.sessions.close);
    final repo = ReviewFake()
      ..error = 'This submission changed. Reload before reviewing.';
    await tester.pumpWidget(
      SmartHireApp(
        authRepository: auth,
        initialRoute: '/admin/recruiter-reviews',
        reviewRepositoryFactory: (_) => repo,
      ),
    );
    await tester.pump();
    auth.sessions.add(
      const AuthUser(uid: 'admin', email: 'a@example.com', emailVerified: true),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review submission'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Invalid company');
    await tester.ensureVisible(find.text('Reject submission'));
    await tester.tap(find.text('Reject submission'));
    await tester.pumpAndSettle();
    expect(repo.writes, 1);
    expect(find.text('Review submission'), findsNothing);
    expect(find.textContaining('Reload before reviewing'), findsOneWidget);
    await tester.ensureVisible(find.text('Reload queue'));
    await tester.tap(find.text('Reload queue'));
    await tester.pumpAndSettle();
    expect(repo.reads, 2);
    expect(find.text('Review submission'), findsOneWidget);
  });
  testWidgets(
    'signed-out and unverified users do not create review repositories',
    (tester) async {
      final auth = TestAuthRepository();
      addTearDown(auth.sessions.close);
      var creates = 0;
      await tester.pumpWidget(
        SmartHireApp(
          authRepository: auth,
          initialRoute: '/admin/recruiter-reviews',
          reviewRepositoryFactory: (_) {
            creates++;
            return ReviewFake();
          },
        ),
      );
      await tester.pump();
      auth.sessions.add(null);
      await tester.pumpAndSettle();
      expect(creates, 0);
      auth.sessions.add(
        const AuthUser(
          uid: 'admin',
          email: 'a@example.com',
          emailVerified: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(creates, 0);
      expect(find.text('Verify your email before reviewing.'), findsOneWidget);
    },
  );
  testWidgets('late private load is discarded after account change', (
    tester,
  ) async {
    final auth = TestAuthRepository();
    addTearDown(auth.sessions.close);
    final repo = ReviewFake()..pending = Completer<ReviewPage>();
    await tester.pumpWidget(
      SmartHireApp(
        authRepository: auth,
        initialRoute: '/admin/recruiter-reviews',
        reviewRepositoryFactory: (_) => repo,
      ),
    );
    await tester.pump();
    auth.sessions.add(
      const AuthUser(uid: 'admin', email: 'a@example.com', emailVerified: true),
    );
    await tester.pump();
    auth.sessions.add(null);
    await tester.pumpAndSettle();
    repo.pending!.complete(ReviewPage([repo.submission], null));
    await tester.pumpAndSettle();
    expect(find.text('Acme'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
