import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthire/features/company/data/api_company_repository.dart';
import 'package:smarthire/features/company/domain/company.dart';
import 'package:smarthire/features/company/domain/company_repository.dart';
import 'package:smarthire/features/profile/data/api_profile_repository.dart';

class CompanyAdapter implements HttpClientAdapter {
  int status = 200;
  Object body = {
    'owner_uid': 'owner',
    'approval_status': 'pending',
    'updated_at': '2026-10-22T00:00:00Z',
    'name': 'Company',
    'description': '',
    'location': '',
    'website': '',
  };
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

void main() {
  late CompanyAdapter adapter;
  late ApiCompanyRepository repo;
  String? uid;
  bool verified = true;
  bool signedIn = true;
  setUp(() {
    uid = 'owner';
    verified = true;
    signedIn = true;
    adapter = CompanyAdapter();
    repo = ApiCompanyRepository(
      origin: Uri.parse('https://api.example.com'),
      adapter: adapter,
      currentUid: () => uid,
      session: () async => signedIn
          ? ProfileSession(
              uid: 'owner',
              token: 'test-token',
              verified: verified,
            )
          : null,
    );
  });
  tearDown(() => repo.close());

  test(
    'fixed ownerless path, request-only token and bounded HTTPS transport',
    () async {
      expect((await repo.load())!.ownerUid, 'owner');
      final request = adapter.request!;
      expect(request.uri.toString(), 'https://api.example.com/api/v1/company');
      expect(request.headers['Authorization'], 'Bearer test-token');
      expect(request.followRedirects, isFalse);
      expect(request.connectTimeout, const Duration(seconds: 10));
    },
  );
  test(
    'write excludes ownership/approval and requires pending server receipt',
    () async {
      await repo.save(const CompanyDraft(name: ' Company '));
      expect(adapter.request!.method, 'PUT');
      expect(adapter.request!.data, {
        'name': 'Company',
        'description': '',
        'location': '',
        'website': '',
      });
      (adapter.body as Map)['approval_status'] = 'approved';
      await expectLater(
        repo.save(const CompanyDraft(name: 'Company')),
        throwsA(isA<CompanyFailure>()),
      );
    },
  );
  test('unverified or absent sessions never send requests', () async {
    verified = false;
    await expectLater(repo.load(), throwsA(isA<CompanyFailure>()));
    expect(adapter.request, isNull);
    signedIn = false;
    await expectLater(repo.load(), throwsA(isA<CompanyFailure>()));
    expect(adapter.request, isNull);
  });
  test('rejects account switches before and during transport', () async {
    uid = 'other';
    await expectLater(repo.load(), throwsA(isA<CompanyFailure>()));
    expect(adapter.request, isNull);
    uid = 'owner';
    adapter.beforeResponse = () => uid = null;
    await expectLater(repo.load(), throwsA(isA<CompanyFailure>()));
  });
  test('foreign response owner is never returned', () async {
    (adapter.body as Map)['owner_uid'] = 'other';
    await expectLater(repo.load(), throwsA(isA<CompanyFailure>()));
  });
  test(
    '404 is absence only for load; unsafe statuses have fixed errors',
    () async {
      adapter.status = 404;
      expect(await repo.load(), isNull);
      await expectLater(
        repo.save(const CompanyDraft(name: 'Company')),
        throwsA(isA<CompanyFailure>()),
      );
      for (final status in [302, 401, 403, 422, 429, 500]) {
        adapter.status = status;
        adapter.body = {'message': 'private diagnostic'};
        await expectLater(
          repo.load(),
          throwsA(
            isA<CompanyFailure>().having(
              (e) => e.message,
              'safe error',
              isNot(contains('private diagnostic')),
            ),
          ),
        );
      }
    },
  );
  test('invalid drafts do not send requests', () async {
    await expectLater(
      repo.save(const CompanyDraft(name: 'A')),
      throwsA(isA<CompanyFailure>()),
    );
    expect(adapter.request, isNull);
  });
  test('rejects origins that could redirect credentials', () {
    for (final origin in [
      'http://api.example.com',
      'https://u:p@api.example.com',
      'https://api.example.com/path',
      'https://api.example.com?x=1',
    ]) {
      expect(
        () => ApiCompanyRepository(
          origin: Uri.parse(origin),
          session: () async => null,
          currentUid: () => null,
        ),
        throwsArgumentError,
      );
    }
  });
}
