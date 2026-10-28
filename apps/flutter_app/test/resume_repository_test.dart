import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthire/features/profile/data/api_profile_repository.dart';
import 'package:smarthire/features/resumes/data/api_resume_repository.dart';
import 'package:smarthire/features/resumes/domain/resume.dart';

import 'resume_test_fixtures.dart';

class ResumeApiAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  void Function(Map<String, dynamic>)? modifyTicket;
  void Function()? beforeResponse;
  Object? overrideBody;
  int? overrideStatus;
  String? createdId;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    Object body;
    var status = 200;
    if (options.path == '/api/v1/resumes' && options.method == 'POST') {
      final nonce = (options.data as Map)['upload_id'] as String;
      final id = createdId = resumeIdFor('one', nonce);
      final file = fixtureResume();
      final json = <String, dynamic>{
        'resume': resumeJson(id: id, status: 'uploading', revision: 1),
        'upload_url': Uri.https(
          'storage.example.com',
          '/bucket/resumes/${resumeOwnerHash('one')}/$id/source.pdf',
          {
            'X-Amz-Expires': '60',
            'X-Amz-SignedHeaders': 'content-length;content-type;host;if-none-match;x-amz-meta-sha256',
            'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
          },
        ).toString(),
        'upload_headers': <String, dynamic>{
          'Content-Type': 'application/pdf',
          'If-None-Match': '*',
          'x-amz-meta-sha256': file.digest,
        },
        'expires_in': 60,
      };
      modifyTicket?.call(json);
      body = json;
      status = 201;
    } else if (options.path.endsWith('/finalize')) {
      body = resumeJson(id: createdId, status: 'queued', revision: 2);
    } else if (options.path.endsWith('/skills')) {
      body = resumeJson(
        status: 'confirmed',
        revision: 5,
        skillsVersion: 1,
        confirmedSkills: ['Flutter'],
      );
    } else if (options.path.endsWith('/delete')) {
      body = {'id': fixtureRecord().id, 'status': 'deleted'};
    } else if (options.path == '/api/v1/resumes') {
      body = {
        'items': [resumeJson()],
        'next_cursor': null,
      };
    } else {
      body = resumeJson();
    }
    beforeResponse?.call();
    return ResponseBody.fromString(
      jsonEncode(overrideBody ?? body),
      overrideStatus ?? status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class ResumeUploadAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int status = 200;
  void Function()? beforeResponse;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    await stream?.drain<void>();
    beforeResponse?.call();
    return ResponseBody.fromBytes([], status);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late ResumeApiAdapter api;
  late ResumeUploadAdapter upload;
  late ApiResumeRepository repo;
  String? uid;
  var verified = true;
  setUp(() {
    uid = 'one';
    verified = true;
    api = ResumeApiAdapter();
    upload = ResumeUploadAdapter();
    repo = ApiResumeRepository(
      origin: Uri.parse('https://api.example.com'),
      storageOrigin: Uri.parse('https://storage.example.com'),
      ownerUid: 'one',
      session: () async => ProfileSession(
        uid: 'one',
        token: 'test-id-token',
        verified: verified,
      ),
      currentUid: () => uid,
      apiAdapter: api,
      uploadAdapter: upload,
    );
  });
  tearDown(() => repo.close());

  test(
    'private file goes only to pinned storage without a Firebase bearer token',
    () async {
      final file = fixtureResume();
      final result = await repo.upload(file, 'a' * 32, (_, _) {});
      expect(result.status, ResumeStatus.queued);
      expect(api.requests.length, 2);
      expect(upload.requests.length, 1);
      expect(api.requests.first.data, {
        'upload_id': 'a' * 32,
        'extension': 'pdf',
        'size': 4,
        'sha256': file.digest,
      });
      expect(
        api.requests.first.headers['Authorization'],
        'Bearer test-id-token',
      );
      expect(
        upload.requests.single.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
      expect(upload.requests.single.data, file.bytes);
      expect(upload.requests.single.followRedirects, isFalse);
      expect(api.requests.last.path, '/api/v1/resumes/${result.id}/finalize');
      expect(api.requests.any((r) => r.path.endsWith('/skills')), isFalse);
    },
  );
  test('already received create-only upload is finalized without another source record', () async {
    upload.status = 412;
    expect(
      (await repo.upload(fixtureResume(), 'a' * 32, (_, _) {})).status,
      ResumeStatus.queued,
    );
    expect(api.requests.where((r) => r.path == '/api/v1/resumes').length, 1);
  });
  test(
    'unverified or changed sessions cannot issue private requests',
    () async {
      verified = false;
      await expectLater(repo.list(), throwsA(isA<ResumeFailure>()));
      expect(api.requests, isEmpty);
      verified = true;
      uid = 'two';
      await expectLater(repo.list(), throwsA(isA<ResumeFailure>()));
      expect(api.requests, isEmpty);
    },
  );
  test('account change after API response prevents file transfer', () async {
    api.beforeResponse = () => uid = 'two';
    await expectLater(
      repo.upload(fixtureResume(), 'a' * 32, (_, _) {}),
      throwsA(isA<ResumeFailure>()),
    );
    expect(upload.requests, isEmpty);
  });
  test('account change during transfer prevents finalization', () async {
    upload.beforeResponse = () => uid = 'two';
    await expectLater(
      repo.upload(fixtureResume(), 'a' * 32, (_, _) {}),
      throwsA(isA<ResumeFailure>()),
    );
    expect(api.requests.length, 1);
  });
  final badTickets = <String, void Function(Map<String, dynamic>)>{
    'foreign origin': (j) => j['upload_url'] = (Uri.parse(
      j['upload_url'] as String,
    ).replace(host: 'evil.example.com')).toString(),
    'wrong owner path': (j) => j['upload_url'] = (j['upload_url'] as String)
        .replaceFirst(resumeOwnerHash('one'), resumeOwnerHash('two')),
    'insecure origin': (j) => j['upload_url'] = (j['upload_url'] as String)
        .replaceFirst('https:', 'http:'),
    'unexpected credential header': (j) =>
        (j['upload_headers'] as Map)['Authorization'] = 'never-send-this',
    'wrong hash header': (j) =>
        (j['upload_headers'] as Map)['x-amz-meta-sha256'] = '0' * 64,
    'overlong capability': (j) => j['upload_url'] = (j['upload_url'] as String)
        .replaceFirst('X-Amz-Expires=60', 'X-Amz-Expires=600'),
    'floating expiry': (j) => j['expires_in'] = 60.0,
  };
  for (final entry in badTickets.entries) {
    test('rejects ${entry.key} before any file leaves the device', () async {
      api.modifyTicket = entry.value;
      await expectLater(
        repo.upload(fixtureResume(), 'a' * 32, (_, _) {}),
        throwsA(isA<ResumeFailure>()),
      );
      expect(upload.requests, isEmpty);
    });
  }
  test(
    'skills confirmation checks immutable source and increasing versions',
    () async {
      final before = fixtureRecord();
      expect((await repo.confirm(before, ['Flutter'])).skillsVersion, 1);
      expect(api.requests.single.data, {
        'expected_revision': 4,
        'skills': ['Flutter'],
      });
      api.overrideBody = {
        ...resumeJson(
          status: 'confirmed',
          revision: 5,
          skillsVersion: 1,
          confirmedSkills: ['Flutter'],
        ),
        'sha256': 'c' * 64,
      };
      await expectLater(
        repo.confirm(before, ['Flutter']),
        throwsA(isA<ResumeFailure>()),
      );
    },
  );
  test('server diagnostics and malformed deletion receipts do not become user data', () async {
    api.overrideStatus = 503;
    api.overrideBody = {'private': 'document-secret'};
    await expectLater(
      repo.list(),
      throwsA(
        isA<ResumeFailure>().having(
          (e) => e.message.contains('document-secret'),
          'safe',
          isFalse,
        ),
      ),
    );
    api.overrideStatus = 200;
    api.overrideBody = {'id': 'b' * 32, 'status': 'deleted'};
    await expectLater(
      repo.delete(fixtureRecord()),
      throwsA(isA<ResumeFailure>()),
    );
  });
  test('malformed snapshots and duplicate pages are rejected', () {
    for (final change in <Map<String, dynamic>>[
      {'revision': 1.0},
      {'size': true},
      {'parse_status': 'approved'},
      {'parse_status': 'confirmed'},
      {'updated_at': '2026-10-28T00:00:00'},
      {'error_code': 'private diagnostics'},
      {
        'extracted_skills': [1],
      },
    ]) {
      expect(
        () => ResumeRecord.fromJson({...resumeJson(), ...change}),
        throwsFormatException,
      );
    }
    expect(
      () => ResumesPage.fromJson({
        'items': [resumeJson(), resumeJson()],
      }),
      throwsFormatException,
    );
  });
  test('selected bytes cannot change after hashing and oversized inputs are rejected', () {
    final original = Uint8List.fromList([1, 2, 3]);
    final file = PickedResume(
      name: 'fixture.pdf',
      extension: 'pdf',
      bytes: original,
    );
    final digest = file.digest;
    original[0] = 9;
    expect(file.bytes[0], 1);
    expect(file.digest, digest);
    expect(() => file.bytes[0] = 9, throwsUnsupportedError);
    expect(
      () => PickedResume(
        name: 'large.pdf',
        extension: 'pdf',
        bytes: Uint8List(maxResumeBytes + 1),
      ),
      throwsA(isA<ResumeFailure>()),
    );
  });
}
