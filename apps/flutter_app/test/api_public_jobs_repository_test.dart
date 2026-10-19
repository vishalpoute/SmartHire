import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthire/features/jobs/data/api_public_jobs_repository.dart';
import 'package:smarthire/features/jobs/domain/public_jobs_repository.dart';

Map<String, Object> job(String id) => {
  'id': id,
  'title': 'Flutter developer',
  'company_name': 'Company',
  'description': 'Build maintained applications.',
  'location': '',
  'work_mode': 'remote',
  'employment_type': 'full_time',
  'required_skills': ['Dart'],
  'preferred_skills': <String>[],
  'published_at': '2026-10-19T09:00:00+00:00',
};

class JobsAdapter implements HttpClientAdapter {
  int status = 200;
  Object? body = {'items': [], 'next_cursor': null};
  RequestOptions? request;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

void main() {
  late JobsAdapter adapter;
  late ApiPublicJobsRepository repo;
  final first = '1' * 32;
  final second = '2' * 32;
  setUp(() {
    adapter = JobsAdapter();
    repo = ApiPublicJobsRepository(
      origin: Uri.parse('https://api.example.com'),
      adapter: adapter,
    );
  });
  tearDown(() => repo.close());
  test(
    'anonymous request uses bounded transport and immutable content',
    () async {
      adapter.body = {
        'items': [job(second)],
        'next_cursor': second,
      };
      final page = await repo.page(pageSize: 2, cursor: first);
      expect(page.items.single.id, second);
      expect(page.items.single.publishedAt.isUtc, isTrue);
      final request = adapter.request!;
      expect(request.uri.path, '/api/v1/public/jobs');
      expect(request.queryParameters, {'page_size': 2, 'cursor': first});
      expect(request.headers.containsKey('Authorization'), isFalse);
      expect(request.followRedirects, isFalse);
      expect(request.connectTimeout, const Duration(seconds: 10));
      expect(() => page.items.clear(), throwsUnsupportedError);
      expect(
        () => page.items.single.requiredSkills.clear(),
        throwsUnsupportedError,
      );
    },
  );
  test('empty sparse page preserves continuation', () async {
    adapter.body = {'items': [], 'next_cursor': second};
    expect((await repo.page(cursor: first)).nextCursor, second);
  });
  test(
    'detail checks requested identity and safely ignores private fields',
    () async {
      adapter.body = {...job(first), 'recruiter_uid': 'private ignored'};
      final result = await repo.detail(first);
      expect(result!.company, 'Company');
      expect(result.employmentType, EmploymentType.fullTime);
      adapter.body = job(second);
      await expectLater(repo.detail(first), throwsA(isA<PublicJobsFailure>()));
    },
  );
  test('only missing details map to absence', () async {
    adapter.status = 404;
    expect(await repo.detail(first), isNull);
    await expectLater(repo.page(), throwsA(isA<PublicJobsFailure>()));
  });
  test('server diagnostics are never surfaced', () async {
    for (final status in [302, 401, 403, 429, 500, 503]) {
      adapter.status = status;
      adapter.body = {'message': 'private credential diagnostics'};
      try {
        await repo.page();
        fail('Expected safe failure');
      } on PublicJobsFailure catch (error) {
        expect(error.message, isNot(contains('credential')));
      }
    }
  });
  test('invalid caller parameters never touch transport', () async {
    await expectLater(repo.page(pageSize: 11), throwsArgumentError);
    await expectLater(repo.page(cursor: '../secret'), throwsArgumentError);
    await expectLater(repo.detail('not-an-id'), throwsArgumentError);
    expect(adapter.request, isNull);
  });
  test('malformed pages and nonprogressing cursors fail closed', () async {
    for (final body in [
      {'items': []},
      {'items': 'bad', 'next_cursor': null},
      {'items': [], 'next_cursor': first},
      {'items': [], 'next_cursor': 'url'},
      {
        'items': [job(first)],
        'next_cursor': null,
      },
      {
        'items': [job(second), job(second)],
        'next_cursor': null,
      },
    ]) {
      adapter.body = body;
      await expectLater(
        repo.page(cursor: first),
        throwsA(isA<PublicJobsFailure>()),
      );
    }
  });
  test('invalid enums dates and skills never become usable details', () async {
    for (final changes in [
      {'work_mode': 'unknown'},
      {'employment_type': 'unknown'},
      {'published_at': '2026-10-19T09:00:00'},
      {
        'required_skills': [12],
      },
      {
        'required_skills': ['Dart', 'dart'],
      },
      {'title': 'x' * 121},
    ]) {
      adapter.body = {...job(first), ...changes};
      await expectLater(repo.detail(first), throwsA(isA<PublicJobsFailure>()));
    }
  });
  test('insecure or credential-bearing origins rejected', () {
    for (final origin in [
      'http://api.example.com',
      'https://user:pass@api.example.com',
      'https://api.example.com/path',
      'https://api.example.com?token=bad',
    ]) {
      expect(
        () => ApiPublicJobsRepository(origin: Uri.parse(origin)),
        throwsArgumentError,
      );
    }
  });
}
