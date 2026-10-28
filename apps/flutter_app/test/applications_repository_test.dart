import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthire/features/applications/data/api_applications_repository.dart';
import 'package:smarthire/features/applications/domain/application.dart';
import 'package:smarthire/features/profile/data/api_profile_repository.dart';

import 'application_test_fixtures.dart';
import 'resume_test_fixtures.dart';

class ApplicationAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Object? overrideBody;
  int? status;
  void Function()? beforeResponse;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final body =
        overrideBody ??
        (options.path.endsWith('/match')
            ? matchJson()
            : options.path.endsWith('/status')
            ? applicationJson(status: 'withdrawn', revision: 2)
            : options.method == 'POST'
            ? applicationJson()
            : {
                'items': [applicationJson()],
                'next_cursor': null,
              });
    beforeResponse?.call();
    return ResponseBody.fromString(
      jsonEncode(body),
      status ??
          (options.method == 'POST' && options.path.endsWith('/applications')
              ? 201
              : 200),
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late ApplicationAdapter adapter;
  late ApiApplicationsRepository repository;
  String? uid;
  setUp(() {
    uid = 'one';
    adapter = ApplicationAdapter();
    repository = ApiApplicationsRepository(
      origin: Uri.https('api.example.com'),
      ownerUid: 'one',
      currentUid: () => uid,
      session: () async => const ProfileSession(
        uid: 'one',
        token: 'fixture-token',
        verified: true,
      ),
      adapter: adapter,
    );
  });
  tearDown(() => repository.close());
  test(
    'history deletion requires terminal state and validates removal receipt',
    () async {
      expect(
        () => repository.delete(JobApplication(applicationJson())),
        throwsA(isA<ApplicationFailure>()),
      );
      final value = JobApplication(
        applicationJson(status: 'withdrawn', revision: 2),
      );
      adapter.overrideBody = {'id': value.id, 'status': 'deleted'};
      await repository.delete(value);
      expect(adapter.requests.last.data, {'expected_revision': 2});
      adapter.overrideBody = {'id': 'd' * 32, 'status': 'deleted'};
      await expectLater(
        repository.delete(value),
        throwsA(isA<ApplicationFailure>()),
      );
    },
  );
  test(
    'pins reviewed inputs and sends bearer only to the configured HTTPS API',
    () async {
      final match = await repository.match(applicationJobId, confirmedResume());
      final receipt = await repository.apply(match);
      expect(receipt.match.jobVersion, 2);
      expect(adapter.requests.last.data, match.command);
      expect(
        adapter.requests.last.headers['Authorization'],
        'Bearer fixture-token',
      );
      expect(
        adapter.requests.every(
          (row) =>
              row.uri.origin == 'https://api.example.com' &&
              !row.followRedirects,
        ),
        isTrue,
      );
      expect(
        (adapter.requests.first.data as Map).keys,
        unorderedEquals(['resume_id', 'expected_resume_revision']),
      );
      expect(adapter.requests.first.data.toString(), isNot(contains('text')));
    },
  );
  test(
    'rejects unconfirmed resumes and path injection before network',
    () async {
      expect(
        () => repository.match(applicationJobId, fixtureRecord()),
        throwsA(isA<ApplicationFailure>()),
      );
      expect(
        () => repository.match('../other', confirmedResume()),
        throwsA(isA<ApplicationFailure>()),
      );
      expect(adapter.requests, isEmpty);
    },
  );
  test('rejects changed match sources and forged scores', () async {
    for (final changes in [
      {'resume_sha256': 'd' * 64},
      {'resume_revision': 7},
      {'job_id': 'e' * 32},
      {'score': 100.0},
      {'algorithm_version': 'unknown'},
    ]) {
      adapter.overrideBody = matchJson()..addAll(changes);
      await expectLater(
        repository.match(applicationJobId, confirmedResume()),
        throwsA(isA<ApplicationFailure>()),
      );
    }
  });
  test(
    'fences requests before and after account switch and after close',
    () async {
      uid = 'two';
      await expectLater(
        repository.list(recruiter: false),
        throwsA(
          isA<ApplicationFailure>().having(
            (e) => e.accessDenied,
            'denied',
            true,
          ),
        ),
      );
      expect(adapter.requests, isEmpty);
      uid = 'one';
      adapter.beforeResponse = () => uid = 'two';
      await expectLater(
        repository.list(recruiter: false),
        throwsA(
          isA<ApplicationFailure>().having(
            (e) => e.accessDenied,
            'denied',
            true,
          ),
        ),
      );
      repository.close();
      uid = 'one';
      await expectLater(
        repository.list(recruiter: false),
        throwsA(isA<ApplicationFailure>()),
      );
    },
  );
  test('rejects duplicate and stalled pages', () async {
    adapter.overrideBody = {
      'items': [applicationJson(), applicationJson()],
      'next_cursor': null,
    };
    await expectLater(
      repository.list(recruiter: false),
      throwsA(isA<ApplicationFailure>()),
    );
    adapter.overrideBody = {'items': [], 'next_cursor': 'a' * 32};
    await expectLater(
      repository.list(recruiter: true, cursor: 'a' * 32),
      throwsA(isA<ApplicationFailure>()),
    );
  });
  test(
    'preserves reviewed snapshot across transitions and rejects stale receipts',
    () async {
      final record = JobApplication(applicationJson());
      final result = await repository.change(record, 'withdrawn', '');
      expect(result.revision, 2);
      expect(adapter.requests.last.data, {
        'expected_revision': 1,
        'status': 'withdrawn',
        'reason': '',
      });
      adapter.overrideBody = applicationJson(status: 'withdrawn', revision: 3);
      await expectLater(
        repository.change(record, 'withdrawn', ''),
        throwsA(isA<ApplicationFailure>()),
      );
    },
  );
  test('safe conflicts and denial never expose server diagnostics', () async {
    adapter.status = 409;
    adapter.overrideBody = {
      'code': 'already_applied',
      'message': 'private-diagnostic',
    };
    await expectLater(
      repository.apply(ApplicationMatch(matchJson())),
      throwsA(
        isA<ApplicationFailure>()
            .having(
              (e) => e.message,
              'message',
              isNot(contains('private-diagnostic')),
            )
            .having((e) => e.reloadRequired, 'refresh', true),
      ),
    );
    adapter.status = 403;
    await expectLater(
      repository.list(recruiter: true),
      throwsA(
        isA<ApplicationFailure>().having((e) => e.accessDenied, 'denied', true),
      ),
    );
  });
  test('unscored is distinct from zero coverage and invalid source metadata rejected', () {
    final noRequirements = matchJson()
      ..addAll({
        'status': 'unscored',
        'score': null,
        'unscored_reason': 'no_required_skills',
        'required_evidence': [],
        'missing_required': [],
      });
    expect(ApplicationMatch(noRequirements).score, isNull);
    expect(
      ApplicationMatch(
        matchJson()..addAll({
          'score': 0.0,
          'required_evidence': [],
          'missing_required': ['Flutter'],
        }),
      ).score,
      0,
    );
    expect(
      () => ApplicationMatch(matchJson()..['resume_sha256'] = 'bad'),
      throwsFormatException,
    );
  });
}
